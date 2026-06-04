import AppKit
import Combine
import SwiftUI

/// Owns the NSStatusItem — menu bar shows usage % as plain text.
@MainActor
final class StatusBarController: NSObject {
    private let viewModel: UsageViewModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()
    private var themeObserver: NSObjectProtocol?

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()
    }

    func install() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuPanelHost(viewModel: viewModel)
        )

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp])

        let quitMenu = NSMenu()
        quitMenu.addItem(
            withTitle: "Quit Cursor Usage",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        button.menu = quitMenu

        bindViewModel()
        observeAppearance()
        updateButton()
    }

    private func bindViewModel() {
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateButton()
            }
            .store(in: &cancellables)
    }

    private func observeAppearance() {
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateButton() }
        }
    }

    func updateButton() {
        guard let button = statusItem.button else { return }

        if viewModel.menuBarShowsSetupIcon {
            let symbol = NSImage(
                systemSymbolName: "gearshape.fill",
                accessibilityDescription: "Setup Cursor Usage"
            )
            symbol?.isTemplate = true
            button.image = symbol
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = "Cursor Usage — Set up session token"
            statusItem.length = NSStatusItem.squareLength
            return
        }

        let label = viewModel.menuBarLabel
        button.toolTip = "Cursor Usage — \(label)"
        button.image = nil
        button.imagePosition = .noImage
        button.title = label
        statusItem.length = NSStatusItem.variableLength
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        togglePopover(on: sender)
    }

    private func togglePopover(on button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        Task { await viewModel.refreshOnMenuOpen() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

private struct MenuPanelHost: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        MenuContentView(
            showsSetup: viewModel.showsSetupPanel,
            sessionTokenInput: $viewModel.sessionTokenInput,
            sessionSaveError: viewModel.sessionSaveError,
            isSavingSession: viewModel.isSavingSession,
            onSaveSession: { Task { await viewModel.saveSessionToken() } },
            onCancelSessionEdit: viewModel.needsSetup
                ? nil
                : { viewModel.cancelEditingSession() },
            onEditSession: { viewModel.beginEditingSession() },
            onSignOutSession: { viewModel.signOutSession() },
            snapshot: viewModel.snapshot,
            error: viewModel.error,
            isLoading: viewModel.isLoading,
            isStale: viewModel.isShowingStaleData,
            refreshInterval: $viewModel.refreshInterval,
            onRefresh: { Task { await viewModel.refresh() } }
        )
    }
}
