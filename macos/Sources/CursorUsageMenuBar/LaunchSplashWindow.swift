import AppKit
import SwiftUI

@MainActor
final class LaunchSplashModel: ObservableObject {
    @Published var status: String = "Starting Cursor Usage…"
    @Published var detail: String = "Please wait while the app prepares your menu bar."
}

@MainActor
final class LaunchSplashController {
    private let model = LaunchSplashModel()
    private var window: NSWindow?
    private var hosting: NSHostingController<LaunchSplashView>?
    private let shownAt = Date()
    private static let minimumVisible: TimeInterval = 0.9

    func show() {
        guard window == nil else { return }

        let view = LaunchSplashView(model: model)
        let host = NSHostingController(rootView: view)
        hosting = host

        let size = NSSize(width: 400, height: 248)
        let frame = centeredFrame(size: size)
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Cursor Usage"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isReleasedWhenClosed = false
        win.contentViewController = host
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.standardWindowButton(.zoomButton)?.isHidden = true
        win.standardWindowButton(.closeButton)?.isHidden = true

        window = win
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func setStatus(_ status: String, detail: String? = nil) {
        model.status = status
        if let detail { model.detail = detail }
    }

    func dismiss(completion: @escaping () -> Void) {
        let elapsed = Date().timeIntervalSince(shownAt)
        let delay = max(0, Self.minimumVisible - elapsed)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let window = self.window else {
                completion()
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                window.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    window.orderOut(nil)
                    self.window = nil
                    self.hosting = nil
                    completion()
                }
            }
        }
    }

    private func centeredFrame(size: NSSize) -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let x = screen.midX - size.width / 2
        let y = screen.midY - size.height / 2
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

private struct LaunchSplashView: View {
    @ObservedObject var model: LaunchSplashModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Theme.accent)
                .symbolRenderingMode(.hierarchical)
                .padding(.top, 8)

            Text("Cursor Usage")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            ProgressView()
                .controlSize(.regular)
                .scaleEffect(1.05)
                .padding(.vertical, 4)

            Text(model.status)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(model.detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(width: 400, height: 248)
        .background(.regularMaterial)
    }
}
