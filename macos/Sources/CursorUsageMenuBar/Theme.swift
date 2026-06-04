import AppKit
import SwiftUI

/// macOS-native color tokens (macos-design visual-design reference).
enum Theme {
    static let textPrimary = Color(light: "#1D1D1F", dark: "#F5F5F7")
    static let textSecondary = Color(light: "#6E6E73", dark: "#98989D")
    static let accent = Color(light: "#007AFF", dark: "#0A84FF")
    static let paceMarker = Color(light: "#8E8E93", dark: "#AEAEB2")
    static let progressTrack = Color(light: "#E5E5EA", dark: "#3A3A3C")
    static let sectionBackground = Color(light: "#FFFFFF", dark: "#2C2C2E").opacity(0.55)
    static let sectionBorder = Color(light: "#000000", dark: "#FFFFFF").opacity(0.08)

    static func usageColor(percent: Double) -> Color {
        if percent >= 90 { return Color(light: "#FF3B30", dark: "#FF453A") }
        if percent >= 70 { return Color(light: "#FF9500", dark: "#FF9F0A") }
        return Color(light: "#34C759", dark: "#30D158")
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
