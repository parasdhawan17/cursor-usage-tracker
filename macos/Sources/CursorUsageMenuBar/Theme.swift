import AppKit
import SwiftUI

/// macOS-native color tokens (macos-design visual-design reference).
enum Theme {
    static let textPrimary = Color(light: "#1D1D1F", dark: "#F5F5F7")
    static let textSecondary = Color(light: "#6E6E73", dark: "#98989D")
    static let textTertiary = Color(light: "#AEAEB2", dark: "#636366")
    static let accent = Color(light: "#007AFF", dark: "#0A84FF")
    static let paceMarker = Color(light: "#8E8E93", dark: "#AEAEB2")
    static let progressTrack = Color(light: "#E5E5EA", dark: "#3A3A3C")
    static let sectionBackground = Color(light: "#FFFFFF", dark: "#2C2C2E").opacity(0.72)
    static let sectionBorder = Color(light: "#000000", dark: "#FFFFFF").opacity(0.08)
    static let headerBackground = Color(light: "#F5F5F7", dark: "#1C1C1E").opacity(0.55)
    static let chipBackground = Color(light: "#000000", dark: "#FFFFFF").opacity(0.06)
    static let surfaceHover = Color(light: "#000000", dark: "#FFFFFF").opacity(0.05)
    static let surfacePressed = Color(light: "#000000", dark: "#FFFFFF").opacity(0.08)
    static let separator = Color(light: "#000000", dark: "#FFFFFF").opacity(0.08)
    static let warning = Color(light: "#FF9500", dark: "#FF9F0A")
    static let warningBackground = Color(light: "#FF9500", dark: "#FF9F0A").opacity(0.12)
    static let destructive = Color(light: "#FF3B30", dark: "#FF453A")
    static let includedValue = Color(light: "#34C759", dark: "#30D158")
    static let apiModels = Color(light: "#007AFF", dark: "#0A84FF")
    static let autoModels = Color(light: "#AF52DE", dark: "#BF5AF2")

    static func usageColor(percent: Double) -> Color {
        if percent >= 90 { return destructive }
        if percent >= 70 { return warning }
        return Color(light: "#34C759", dark: "#30D158")
    }

    static func heroTint(percent: Double) -> Color {
        usageColor(percent: percent).opacity(0.12)
    }
}

// MARK: - Reusable styles

struct SectionHeaderLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .tracking(0.45)
    }
}

struct ToolbarIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { isHovered = $0 }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed { return Theme.surfacePressed }
        if isHovered { return Theme.surfaceHover }
        return .clear
    }
}

struct HoverRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowBackground(isPressed: configuration.isPressed))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { isHovered = $0 }
    }

    private func rowBackground(isPressed: Bool) -> Color {
        if isPressed { return Theme.surfacePressed }
        if isHovered { return Theme.surfaceHover }
        return .clear
    }
}

struct InsetGroupedCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sectionBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.sectionBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension Color {
    init(light: String, dark: String) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(hex: hex) ?? .labelColor
        })
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if s.count == 6 { s = "FF" + s }
        guard s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255,
            alpha: CGFloat((v >> 24) & 0xff) / 255
        )
    }
}
