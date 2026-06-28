import AppKit
import Combine
import SwiftUI

/// Owns the NSStatusItem — menu bar shows "C 32%" text.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private static let panelWidth: CGFloat = 320

    private let viewModel: UsageViewModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let hosting: NSHostingController<MenuPanelHost>
    private var cancellables = Set<AnyCancellable>()
    private var themeObserver: NSObjectProtocol?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.hosting = NSHostingController(rootView: MenuPanelHost(viewModel: viewModel))
        self.popover = NSPopover()
        super.init()
    }

    func install() {
        popover.contentViewController = hosting
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: Self.panelWidth, height: 400)
        syncPopoverBehavior()

        configureStatusButton()
        bindViewModel()
        observeAppearance()
        updateButton()
    }

    /// Opens the setup popover on first launch so users see something after install (menu bar only).
    func presentSetupPanelIfNeeded() {
        guard viewModel.needsSetup else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            if !self.popover.isShown {
                self.showPopover(relativeTo: button)
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
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
        updateButton()
    }

    private func bindViewModel() {
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)

        // Do not tie these to objectWillChange — sessionTokenInput updates every keystroke and
        // remeasuring the popover there freezes the UI on some Macs.
        Publishers.CombineLatest(viewModel.$needsSetup, viewModel.$isEditingSession)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.syncPopoverBehavior()
                self?.resizePopoverIfVisible()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            viewModel.$snapshot,
            viewModel.$isLoading,
            viewModel.$error,
            viewModel.$isSavingSession
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in self?.resizePopoverIfVisible() }
        .store(in: &cancellables)

        viewModel.$sessionSaveError
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizePopoverIfVisible() }
            .store(in: &cancellables)

        viewModel.$launchAtLoginError
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizePopoverIfVisible() }
            .store(in: &cancellables)

        viewModel.$caffeinateError
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizePopoverIfVisible() }
            .store(in: &cancellables)

        viewModel.updateViewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizePopoverIfVisible() }
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
        togglePopover(on: sender)
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

    private func togglePopover(on button: NSStatusBarButton) {
        if popover.isShown {
            hidePopover()
            return
        }
        Task {
            await viewModel.refreshOnMenuOpen()
            await viewModel.updateViewModel.checkForUpdates()
        }
        showPopover(relativeTo: button)
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        syncPopoverBehavior()
        updatePopoverContentSize()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        configurePopoverChrome()
        activatePopoverWindow()
    }

    private func hidePopover() {
        popover.performClose(nil)
    }

    /// Setup keeps the popover open for typing; usage uses semitransient so it can become key immediately.
    private func syncPopoverBehavior() {
        popover.behavior = viewModel.showsSetupPanel ? .applicationDefined : .semitransient
    }

    /// Transient popovers stay inactive and look dimmed until clicked; activate on open like system extras.
    private func activatePopoverWindow() {
        guard let window = popover.contentViewController?.view.window else { return }
        window.makeKey()
        if viewModel.showsSetupPanel {
            viewModel.requestTokenFieldFocus()
        }
    }

    private func resizePopoverIfVisible() {
        guard popover.isShown else { return }
        syncPopoverBehavior()
        updatePopoverContentSize()
        configurePopoverChrome()
    }

    private func updatePopoverContentSize() {
        let height = measuredContentHeight(width: Self.panelWidth)
        popover.contentSize = NSSize(width: Self.panelWidth, height: height)
    }

    private func measuredContentHeight(width: CGFloat) -> CGFloat {
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.sizeThatFits(in: NSSize(width: width, height: 10_000))
        return max(120, ceil(size.height))
    }

    /// Lets the SwiftUI glass background provide the panel chrome instead of the default popover fill.
    private func configurePopoverChrome() {
        guard let contentView = popover.contentViewController?.view,
              let window = contentView.window else { return }

        window.isOpaque = false
        window.backgroundColor = .clear

        if let frameView = window.contentView?.superview {
            frameView.wantsLayer = true
            frameView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        activatePopoverWindow()
    }

    func popoverDidShow(_ notification: Notification) {
        configurePopoverChrome()
        statusItem.button?.highlight(true)
        installOutsideClickMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
        removeOutsideClickMonitor()
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()

        let handleOutsideClick = { [weak self] in
            guard let self, self.popover.isShown else { return }
            let click = NSEvent.mouseLocation
            if let popoverFrame = self.popover.contentViewController?.view.window?.frame,
               popoverFrame.contains(click) {
                return
            }
            // Status bar click is handled by togglePopover on mouse down; ignore it here.
            if let buttonFrame = self.statusBarButtonScreenFrame(), buttonFrame.contains(click) {
                return
            }
            self.hidePopover()
        }

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            handleOutsideClick()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            handleOutsideClick()
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func statusBarButtonScreenFrame() -> NSRect? {
        guard let button = statusItem.button else { return nil }
        let screen = button.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return nil }
        return screenFrame(of: button, on: screen)
    }

    private func screenFrame(of button: NSStatusBarButton, on screen: NSScreen) -> NSRect {
        if let window = button.window {
            let inWindow = button.convert(button.bounds, to: nil)
            return window.convertToScreen(inWindow)
        }
        let visible = screen.visibleFrame
        return NSRect(x: visible.maxX - 60, y: visible.maxY - 4, width: 48, height: 1)
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
            launchAtLoginEnabled: Binding(
                get: { viewModel.launchAtLoginEnabled },
                set: { viewModel.setLaunchAtLoginEnabled($0) }
            ),
            launchAtLoginError: viewModel.launchAtLoginError,
            onSetLaunchAtLoginEnabled: { viewModel.setLaunchAtLoginEnabled($0) },
            caffeinateEnabled: Binding(
                get: { viewModel.caffeinateEnabled },
                set: { viewModel.setCaffeinateEnabled($0) }
            ),
            caffeinateError: viewModel.caffeinateError,
            onSetCaffeinateEnabled: { viewModel.setCaffeinateEnabled($0) },
            refreshInterval: $viewModel.refreshInterval,
            onRefresh: { Task { await viewModel.refresh() } },
            updatePhase: viewModel.updateViewModel.phase,
            onInstallUpdate: { Task { await viewModel.updateViewModel.installUpdate() } },
            onDismissUpdateError: { viewModel.updateViewModel.dismissFailure() }
        )
    }
}
