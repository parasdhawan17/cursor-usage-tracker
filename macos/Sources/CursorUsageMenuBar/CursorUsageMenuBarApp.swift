import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            SessionTokenStore.migrateFromLegacyEnvIfNeeded()
            let viewModel = UsageViewModel()
            let controller = StatusBarController(viewModel: viewModel)
            controller.install()
            statusBar = controller
            viewModel.startAutoRefresh()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

extension Notification.Name {
    static let menuBarAppearanceDidChange = Notification.Name("MenuBarAppearanceDidChange")
}

@main
struct CursorUsageMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
                .frame(width: 0, height: 0)
        }
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
    @Published private(set) var sessionSaveError: String?
    @Published private(set) var isSavingSession = false
    @Published var refreshInterval: RefreshInterval = .stored {
        didSet {
            guard refreshInterval != oldValue else { return }
            RefreshInterval.stored = refreshInterval
            startAutoRefresh()
        }
    }

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

    var showsSetupPanel: Bool {
        needsSetup || isEditingSession
    }

    init() {
        needsSetup = !SessionTokenStore.hasToken
        if !needsSetup {
            Task { await refresh() }
        }
    }

    func beginEditingSession() {
        sessionTokenInput = SessionTokenStore.load() ?? ""
        sessionSaveError = nil
        isEditingSession = true
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
                let data = try await UsageFetcher.fetch()
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
}
