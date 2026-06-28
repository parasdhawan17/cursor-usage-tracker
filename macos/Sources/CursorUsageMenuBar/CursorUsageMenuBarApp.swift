import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var splash: LaunchSplashController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMainMenu.install()
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
        let controller = StatusBarController(viewModel: viewModel)
        controller.install()
        statusBar = controller
        viewModel.startAutoRefresh()

        if viewModel.needsSetup {
            markFirstLaunchHintSeen()
            splash?.setStatus(
                "Opening setup…",
                detail: "Paste your WorkosCursorSessionToken next. On MacBook Air, use › in the menu bar if the gear is hidden."
            )
        } else {
            splash?.setStatus("Connecting to Cursor…", detail: "Fetching your usage summary.")
            await viewModel.waitForInitialLoadIfNeeded()
            splash?.setStatus("Ready", detail: "Find your cycle usage % in the menu bar.")
        }

        await Task.yield()
        splash?.dismiss { [weak self] in
            NSApp.setActivationPolicy(.accessory)
            if viewModel.needsSetup {
                controller.presentSetupPanelIfNeeded()
            }
            self?.splash = nil
        }
    }

    private func markFirstLaunchHintSeen() {
        UserDefaults.standard.set(true, forKey: "didShowMenuBarSetupHint")
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
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var needsSetup: Bool
    @Published var isEditingSession = false
    @Published var sessionTokenInput = ""
    @Published private(set) var tokenFieldFocusToken = 0
    @Published private(set) var sessionSaveError: String?
    @Published private(set) var isSavingSession = false
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
    private var fetchTask: Task<Void, Never>?
    private var lastFetchAttempt: Date?

    var isShowingStaleData: Bool {
        error != nil && snapshot != nil
    }

    var menuBarShowsSetupIcon: Bool {
        needsSetup
    }

    var menuBarLabel: String {
        if menuBarShowsSetupIcon { return "" }
        if isLoading && snapshot == nil { return "…" }
        if error != nil, snapshot == nil { return "!" }
        if let s = snapshot { return s.menuBarLabel }
        return "—"
    }

    var menuBarToolTip: String {
        if menuBarShowsSetupIcon { return "Cursor Usage — Set up session token" }
        if let s = snapshot { return s.menuBarToolTip }
        if isLoading { return "Cursor Usage — Loading…" }
        if error != nil { return "Cursor Usage — Could not load" }
        return "Cursor Usage"
    }

    var showsSetupPanel: Bool {
        needsSetup || isEditingSession
    }

    init() {
        needsSetup = !SessionTokenStore.hasToken
        restoreCaffeinateIfNeeded()
        if !needsSetup {
            Task { await refresh() }
        }
    }

    func beginEditingSession() {
        sessionTokenInput = SessionTokenStore.load() ?? ""
        sessionSaveError = nil
        isEditingSession = true
        requestTokenFieldFocus()
    }

    func requestTokenFieldFocus() {
        tokenFieldFocusToken += 1
    }

    func cancelEditingSession() {
        isEditingSession = false
        sessionTokenInput = ""
        sessionSaveError = nil
    }

    func saveSessionToken() async {
        let trimmed = sessionTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sessionSaveError = SessionTokenStore.StoreError.emptyToken.localizedDescription
            return
        }

        isSavingSession = true
        sessionSaveError = nil
        defer { isSavingSession = false }

        do {
            _ = try SessionTokenStore.save(trimmed)
            needsSetup = false
            isEditingSession = false
            sessionTokenInput = ""
            startAutoRefresh()
            await refresh()
        } catch {
            sessionSaveError = error.localizedDescription
        }
    }

    func signOutSession() {
        refreshTask?.cancel()
        SessionTokenStore.delete()
        needsSetup = true
        isEditingSession = false
        sessionTokenInput = ""
        snapshot = nil
        error = nil
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
                guard !needsSetup else { continue }
                await refresh()
            }
        }
    }

    /// Refresh when the panel opens, but not more than once per 30s (avoids duplicate in-flight calls).
    func refreshOnMenuOpen() async {
        if let last = lastFetchAttempt, Date().timeIntervalSince(last) < 30 {
            return
        }
        await refresh()
    }

    func refresh() async {
        guard !needsSetup else {
            isLoading = false
            return
        }

        if let existing = fetchTask {
            await existing.value
            return
        }

        let showLoading = snapshot == nil
        if showLoading {
            isLoading = true
            error = nil
        }

        lastFetchAttempt = Date()

        fetchTask = Task {
            defer {
                fetchTask = nil
                if showLoading { isLoading = false }
            }

            do {
                let data = try await UsageFetcher.fetchOffMainActor()
                snapshot = data
                error = nil
            } catch let err {
                if snapshot == nil {
                    error = err.localizedDescription
                } else {
                    error = err.localizedDescription
                }
            }
        }

        await fetchTask?.value
    }

    /// Keeps the launch splash visible until the first usage fetch finishes or times out.
    func waitForInitialLoadIfNeeded() async {
        guard !needsSetup else { return }
        let deadline = Date().addingTimeInterval(45)

        for _ in 0..<30 {
            if isLoading || fetchTask != nil || snapshot != nil || error != nil { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        while Date() < deadline {
            if snapshot != nil || error != nil { return }
            if !isLoading && fetchTask == nil { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
