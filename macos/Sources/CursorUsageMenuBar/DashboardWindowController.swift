import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSWindowController {
    private let navigation = DashboardNavigation()

    init(viewModel: UsageViewModel) {
        let hosting = NSHostingController(rootView: DashboardRootView(viewModel: viewModel, navigation: navigation))
        let window = NSWindow(contentViewController: hosting)
        window.title = "AI Usage"
        window.setContentSize(NSSize(width: 900, height: 620))
        window.minSize = NSSize(width: 720, height: 500)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show(page: DashboardPage? = nil) {
        if let page { navigation.page = page }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class DashboardNavigation: ObservableObject {
    @Published var page: DashboardPage = .overview
}
