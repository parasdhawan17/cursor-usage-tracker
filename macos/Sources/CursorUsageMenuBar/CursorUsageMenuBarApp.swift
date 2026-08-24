import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var splash: LaunchSplashController?
    private var dashboard: DashboardWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMainMenu.install(target: self, openDashboardAction: #selector(openDashboard))
        splash = LaunchSplashController()
        splash?.show()
        Task { @MainActor in
            await self.finishLaunchingOnMainActor()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    private func finishLaunchingOnMainActor() async {
        let splash = self.splash

        splash?.setStatus("Checking saved session…", detail: "Looking for an existing token on this Mac.")
        await Task.yield()
        SessionTokenStore.migrateFromLegacyEnvIfNeeded()

        splash?.setStatus("Preparing menu bar…", detail: "This app runs from the menu bar, not the Dock.")
        await Task.yield()
        let viewModel = UsageViewModel()
        Task { await viewModel.updateViewModel.checkForUpdates() }

        splash?.setStatus("Starting menu bar icon…")
        await Task.yield()
        let dashboard = DashboardWindowController(viewModel: viewModel)
        let controller = StatusBarController(viewModel: viewModel) { [weak dashboard] in
            dashboard?.show()
        }
        controller.install()
        statusBar = controller
        self.dashboard = dashboard
        viewModel.startAutoRefresh()

        if !viewModel.hasAnyConnection {
            markFirstLaunchHintSeen()
            splash?.setStatus(
                "Opening dashboard…",
                detail: "Connect Cursor or Codex to start tracking usage."
            )
        } else {
            splash?.setStatus("Connecting to Cursor…", detail: "Fetching your usage summary.")
            await viewModel.waitForInitialLoadIfNeeded()
            splash?.setStatus("Ready", detail: "Find your cycle usage % in the menu bar.")
        }

        await Task.yield()
        splash?.dismiss { [weak self] in
            NSApp.setActivationPolicy(.accessory)
            if !viewModel.hasAnyConnection {
                dashboard.show(page: .settings)
            }
            self?.splash = nil
        }
    }

    private func markFirstLaunchHintSeen() {
        UserDefaults.standard.set(true, forKey: "didShowMenuBarSetupHint")
    }

    @objc private func openDashboard() {
        dashboard?.show()
    }
}

extension Notification.Name {
    static let menuBarAppearanceDidChange = Notification.Name("MenuBarAppearanceDidChange")
}

/// Pure AppKit entry — avoids SwiftUI `Settings` scene hangs on other Macs.
@main
enum CursorUsageMenuBarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var cursorSnapshot: UsageSnapshot?
    @Published private(set) var cursorError: String?
    @Published private(set) var isCursorLoading = false
    @Published private(set) var codexSnapshot: CodexUsageSnapshot?
    @Published private(set) var codexTodayUsage: CodexDailyUsage?
    @Published private(set) var codexError: String?
    @Published private(set) var isCodexLoading = false
    @Published var selectedService: TrackedService = .selected {
        didSet { TrackedService.selected = selectedService }
    }
    @Published var cursorTokenInput = ""
    @Published var codexAccessTokenInput = ""
    @Published var codexAccountIDInput = ""
    @Published private(set) var cursorSaveError: String?
    @Published private(set) var codexSaveError: String?
    @Published private(set) var isSavingCursor = false
    @Published private(set) var isSavingCodex = false
    @Published private(set) var launchAtLoginEnabled = LaunchAtLoginSettings.isEnabled
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var caffeinateEnabled = CaffeinateSettings.isEnabled
    @Published private(set) var caffeinateError: String?
    @Published var refreshInterval: RefreshInterval = .stored {
        didSet {
            guard refreshInterval != oldValue else { return }
            RefreshInterval.stored = refreshInterval
            startAutoRefresh()
        }
    }

    let updateViewModel = UpdateViewModel()

    private var refreshTask: Task<Void, Never>?
    private var cursorFetchTask: Task<Void, Never>?
    private var codexFetchTask: Task<Void, Never>?
    private var lastFetchAttempt: [TrackedService: Date] = [:]

    var hasAnyConnection: Bool { SessionTokenStore.hasToken || CodexTokenStore.hasCredentials }

    var menuBarLabel: String {
        switch selectedService {
        case .cursor:
            if let snapshot = cursorSnapshot { return "Cursor \(UsageSnapshot.formatPercent(snapshot.primaryPercent))" }
            return SessionTokenStore.hasToken ? "Cursor …" : "Cursor"
        case .codex:
            if let snapshot = codexSnapshot { return snapshot.menuBarLabel }
            return CodexTokenStore.hasCredentials ? "Codex …" : "Codex"
        }
    }

    var menuBarValueLabel: String {
        switch selectedService {
        case .cursor:
            if let snapshot = cursorSnapshot {
                return snapshot.isUnlimited ? "∞" : UsageSnapshot.formatPercent(snapshot.primaryPercent)
            }
            return SessionTokenStore.hasToken ? "…" : "—"
        case .codex:
            if let percent = codexSnapshot?.primaryPercent { return "\(Int(percent.rounded()))%" }
            return CodexTokenStore.hasCredentials ? "…" : "—"
        }
    }

    var isSelectedServiceLoading: Bool {
        selectedService == .cursor ? isCursorLoading : isCodexLoading
    }

    var menuBarToolTip: String {
        switch selectedService {
        case .cursor: return cursorSnapshot?.menuBarToolTip ?? "Cursor usage"
        case .codex:
            guard let snapshot = codexSnapshot else { return "Codex usage" }
            if let reset = snapshot.primaryWindow?.resetDescription {
                return "Codex \(snapshot.primaryPercent.map { Int($0.rounded()).description + "% used" } ?? "usage") — resets \(reset)"
            }
            return "Codex usage"
        }
    }

    init() {
        restoreCaffeinateIfNeeded()
        if hasAnyConnection { Task { await refreshAll() } }
    }

    func saveCursorToken() async {
        let trimmed = cursorTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cursorSaveError = SessionTokenStore.StoreError.emptyToken.localizedDescription
            return
        }
        isSavingCursor = true
        cursorSaveError = nil
        defer { isSavingCursor = false }

        do {
            _ = try SessionTokenStore.save(trimmed)
            cursorTokenInput = ""
            startAutoRefresh()
            await refreshCursor()
        } catch {
            cursorSaveError = error.localizedDescription
        }
    }

    func saveCodexCredentials() async {
        let token = codexAccessTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            codexSaveError = CodexTokenStore.StoreError.emptyToken.localizedDescription
            return
        }
        isSavingCodex = true
        codexSaveError = nil
        defer { isSavingCodex = false }
        do {
            try CodexTokenStore.save(accessToken: token, accountID: codexAccountIDInput)
            codexAccessTokenInput = ""
            startAutoRefresh()
            await refreshCodex()
        } catch {
            codexSaveError = error.localizedDescription
        }
    }

    func removeCursorConnection() {
        SessionTokenStore.delete()
        cursorSnapshot = nil
        cursorError = nil
    }

    func removeCodexConnection() {
        CodexTokenStore.delete()
        codexSnapshot = nil
        codexTodayUsage = nil
        codexError = nil
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try LaunchAtLoginSettings.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLoginEnabled = LaunchAtLoginSettings.isEnabled
    }

    func setCaffeinateEnabled(_ enabled: Bool) {
        do {
            try CaffeinateSettings.setEnabled(enabled)
            caffeinateError = nil
        } catch {
            caffeinateError = error.localizedDescription
        }
        caffeinateEnabled = CaffeinateSettings.isEnabled
    }

    private func restoreCaffeinateIfNeeded() {
        do {
            try CaffeinateSettings.restoreStoredPreference()
            caffeinateError = nil
        } catch {
            caffeinateError = error.localizedDescription
        }
        caffeinateEnabled = CaffeinateSettings.isEnabled
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: refreshInterval.nanoseconds)
                guard hasAnyConnection else { continue }
                await refreshAll()
            }
        }
    }

    func refreshOnMenuOpen() async {
        if let last = lastFetchAttempt[selectedService], Date().timeIntervalSince(last) < 30 {
            return
        }
        await refresh(selectedService)
    }

    func refreshAll() async {
        async let cursor: Void = refreshCursor()
        async let codex: Void = refreshCodex()
        _ = await (cursor, codex)
    }

    func refresh(_ service: TrackedService) async {
        switch service {
        case .cursor: await refreshCursor()
        case .codex: await refreshCodex()
        }
    }

    func refreshCursor() async {
        guard SessionTokenStore.hasToken else { return }
        if let existing = cursorFetchTask {
            await existing.value
            return
        }
        let showLoading = cursorSnapshot == nil
        if showLoading { isCursorLoading = true; cursorError = nil }
        lastFetchAttempt[.cursor] = Date()
        cursorFetchTask = Task {
            defer {
                cursorFetchTask = nil
                if showLoading { isCursorLoading = false }
            }
            do {
                let data = try await UsageFetcher.fetchOffMainActor()
                cursorSnapshot = data
                cursorError = nil
            } catch {
                cursorError = error.localizedDescription
            }
        }
        await cursorFetchTask?.value
    }

    func refreshCodex() async {
        guard CodexTokenStore.hasCredentials else { return }
        if let existing = codexFetchTask {
            await existing.value
            return
        }
        let showLoading = codexSnapshot == nil
        if showLoading { isCodexLoading = true; codexError = nil }
        lastFetchAttempt[.codex] = Date()
        codexFetchTask = Task {
            defer {
                codexFetchTask = nil
                if showLoading { isCodexLoading = false }
            }
            do {
                let snapshot = try await CodexUsageFetcher.fetch()
                codexSnapshot = snapshot
                codexTodayUsage = CodexDailyUsageTracker.record(snapshot)
                codexError = nil
            } catch {
                codexError = error.localizedDescription
            }
        }
        await codexFetchTask?.value
    }

    /// Keeps the launch splash visible until the first usage fetch finishes or times out.
    func waitForInitialLoadIfNeeded() async {
        guard hasAnyConnection else { return }
        let deadline = Date().addingTimeInterval(45)

        for _ in 0..<30 {
            if isCursorLoading || isCodexLoading || cursorFetchTask != nil || codexFetchTask != nil || cursorSnapshot != nil || codexSnapshot != nil || cursorError != nil || codexError != nil { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        while Date() < deadline {
            if cursorSnapshot != nil || codexSnapshot != nil || cursorError != nil || codexError != nil { return }
            if !isCursorLoading && !isCodexLoading && cursorFetchTask == nil && codexFetchTask == nil { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
