import AppKit
import Combine
import SwiftUI

/// Borderless panel that can take keyboard focus when setup needs text input.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the NSStatusItem — menu bar shows "C 32%" text.
@MainActor
final class StatusBarController: NSObject {
    private static let panelWidth: CGFloat = 320
    private static let setupPanelWidth: CGFloat = 320

    private let viewModel: UsageViewModel
    private let statusItem: NSStatusItem
    private let panel: KeyablePanel
    private let hosting: NSHostingController<MenuPanelHost>
    private var cancellables = Set<AnyCancellable>()
    private var themeObserver: NSObjectProtocol?
    private var outsideClickMonitor: Any?
    private var isPanelOpen = false
    /// Avoids repeated makeKey/resignKey calls that can freeze SwiftUI hosting on every keystroke.
    private var panelAcceptsKeyboard = false

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.hosting = NSHostingController(rootView: MenuPanelHost(viewModel: viewModel))
        self.panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 400),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()
    }

    func install() {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Keep the panel open while the user types in setup; usage-only mode still dismisses on outside click.
        panel.hidesOnDeactivate = false
        panel.contentViewController = hosting

        configureStatusButton()
        bindViewModel()
        observeAppearance()
        updateButton()
    }

    /// Opens the setup panel on first launch so users see something after install (menu bar only).
    func presentSetupPanelIfNeeded() {
        guard viewModel.needsSetup else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            if !self.isPanelOpen {
                self.showPanel(anchoredTo: button)
            }
        }
    }

    private func configureStatusButton(attempt: Int = 0) {
        guard let button = statusItem.button else {
            guard attempt < 30 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.configureStatusButton(attempt: attempt + 1)
            }
            return
        }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateButton()
    }

    private func bindViewModel() {
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)

        // Do not tie these to objectWillChange — sessionTokenInput updates every keystroke and
        // remeasuring the panel + makeKeyAndOrderFront there freezes the UI on some Macs.
        Publishers.CombineLatest(viewModel.$needsSetup, viewModel.$isEditingSession)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.syncPanelKeyboardFocus()
                self?.resizePanelIfVisible()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            viewModel.$snapshot,
            viewModel.$isLoading,
            viewModel.$error,
            viewModel.$isSavingSession
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in self?.resizePanelIfVisible() }
        .store(in: &cancellables)

        viewModel.$sessionSaveError
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizePanelIfVisible() }
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
        button.toolTip = viewModel.menuBarToolTip
        button.image = nil
        button.imagePosition = .noImage
        button.title = label
        statusItem.length = NSStatusItem.variableLength
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.type == .rightMouseDown {
            showStatusItemMenu(on: sender)
            return
        }
        togglePanel(on: sender)
    }

    private func showStatusItemMenu(on button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit Cursor Usage",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func togglePanel(on button: NSStatusBarButton) {
        if isPanelOpen {
            hidePanel()
            return
        }
        Task { await viewModel.refreshOnMenuOpen() }
        showPanel(anchoredTo: button)
    }

    private func showPanel(anchoredTo button: NSStatusBarButton) {
        let frame = panelFrame(anchoredTo: button)
        hosting.view.frame = NSRect(origin: .zero, size: frame.size)
        panel.setFrame(frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        if viewModel.showsSetupPanel {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        syncPanelKeyboardFocus()
        if viewModel.showsSetupPanel {
            viewModel.requestTokenFieldFocus()
        }
        installOutsideClickMonitor()
        isPanelOpen = true
    }

    private func hidePanel() {
        panel.resignKey()
        panel.orderOut(nil)
        panelAcceptsKeyboard = false
        isPanelOpen = false
        removeOutsideClickMonitor()
    }

    /// `.nonactivatingPanel` blocks SecureField/TextField input; enable key window only for setup.
    private func syncPanelKeyboardFocus() {
        guard isPanelOpen else { return }
        let wantsKeyboard = viewModel.showsSetupPanel
        guard wantsKeyboard != panelAcceptsKeyboard else { return }
        panelAcceptsKeyboard = wantsKeyboard

        if wantsKeyboard {
            if panel.styleMask.contains(.nonactivatingPanel) {
                panel.styleMask.remove(.nonactivatingPanel)
            }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.resignKey()
            if !panel.styleMask.contains(.nonactivatingPanel) {
                panel.styleMask.insert(.nonactivatingPanel)
            }
        }
    }

    private func resizePanelIfVisible() {
        guard isPanelOpen, let button = statusItem.button else { return }
        let frame = panelFrame(anchoredTo: button)
        hosting.view.frame = NSRect(origin: .zero, size: frame.size)
        panel.setFrame(frame, display: true)
    }

    private func measuredContentHeight(width: CGFloat) -> CGFloat {
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.sizeThatFits(in: NSSize(width: width, height: 10_000))
        return max(120, ceil(size.height))
    }

    /// Places the panel just below the status item; height follows SwiftUI content.
    private func panelFrame(anchoredTo button: NSStatusBarButton) -> NSRect {
        let screen = button.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let anchor = screenFrame(of: button, on: screen)

        let width = viewModel.showsSetupPanel ? Self.setupPanelWidth : Self.panelWidth
        let gap: CGFloat = 8
        let height = measuredContentHeight(width: width)

        var x = anchor.midX - width / 2
        var y = anchor.minY - height - gap

        x = max(visible.minX + 10, min(x, visible.maxX - width - 10))
        // Keep the panel on screen; prefer hanging below the menu bar.
        if y + height > visible.maxY - 8 {
            y = visible.maxY - height - 8
        }
        if y < visible.minY + 8 {
            y = visible.minY + 8
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func screenFrame(of button: NSStatusBarButton, on screen: NSScreen) -> NSRect {
        if let window = button.window {
            let inWindow = button.convert(button.bounds, to: nil)
            return window.convertToScreen(inWindow)
        }
        // Fallback when the status button has no window (rare): anchor below menu bar on that screen.
        let visible = screen.visibleFrame
        return NSRect(x: visible.maxX - 60, y: visible.maxY - 4, width: 48, height: 1)
    }

    private func statusBarButtonScreenFrame() -> NSRect? {
        guard let button = statusItem.button else { return nil }
        let screen = button.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return nil }
        return screenFrame(of: button, on: screen)
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            guard let self, self.isPanelOpen else { return }
            let click = NSEvent.mouseLocation
            if self.panel.frame.contains(click) { return }
            // Status bar click is handled by togglePanel on mouse up; ignore it here.
            if let buttonFrame = self.statusBarButtonScreenFrame(), buttonFrame.contains(click) {
                return
            }
            self.hidePanel()
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
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
            tokenFieldFocusToken: viewModel.tokenFieldFocusToken,
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
