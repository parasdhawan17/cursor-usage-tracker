import AppKit
import SwiftUI

/// Semantic color tokens aligned with macOS Liquid Glass on 26+, with fallbacks on earlier releases.
enum Theme {
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let accent = Color.accentColor
    static let paceMarker = Color(nsColor: .secondaryLabelColor)
    static let progressTrack = Color(nsColor: .quaternaryLabelColor).opacity(0.45)
    static let chipBackground = systemFillColor
    static let separator = Color(nsColor: .separatorColor)
    static let warning = Color(nsColor: .systemOrange)
    static let warningBackground = Color(nsColor: .systemOrange).opacity(0.14)
    static let destructive = Color(nsColor: .systemRed)
    static let includedValue = Color(nsColor: .systemGreen)
    static let apiModels = Color(nsColor: .systemBlue)
    static let autoModels = Color(nsColor: .systemPurple)

    private static var systemFillColor: Color {
        if #available(macOS 14.0, *) {
            return Color(nsColor: .quaternarySystemFill)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.55)
    }

    static func usageColor(percent: Double) -> Color {
        if percent >= 90 { return destructive }
        if percent >= 70 { return warning }
        return includedValue
    }

    static func heroTint(percent: Double) -> Color {
        usageColor(percent: percent).opacity(0.12)
    }
}

// MARK: - Liquid Glass surfaces

enum GlassMetrics {
    static let panelRadius: CGFloat = 10
    static let sectionRadius: CGFloat = 8
    static let controlRadius: CGFloat = 6

    static var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
    }
}

private struct LegacyPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: GlassMetrics.panelShape)
            .overlay(GlassMetrics.panelShape.strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5))
            .clipShape(GlassMetrics.panelShape)
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .shadow(color: .black.opacity(0.04), radius: 1, y: 0)
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                GlassMetrics.panelShape
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: GlassMetrics.panelRadius, style: .continuous))
            }
            .clipShape(GlassMetrics.panelShape)
    }
}

private struct SectionCardBackground: ViewModifier {
    let roundsBottom: Bool

    func body(content: Content) -> some View {
        if roundsBottom {
            content.background(
                Theme.chipBackground,
                in: RoundedRectangle(cornerRadius: GlassMetrics.sectionRadius, style: .continuous)
            )
        } else {
            content.background(
                Theme.chipBackground,
                in: UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: GlassMetrics.sectionRadius,
                        bottomLeading: 0,
                        bottomTrailing: 0,
                        topTrailing: GlassMetrics.sectionRadius
                    ),
                    style: .continuous
                )
            )
        }
    }
}

struct GlassPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.modifier(LiquidGlassPanelBackground())
        } else {
            content.modifier(LegacyPanelBackground())
        }
    }
}

extension View {
    func glassPanelBackground() -> some View {
        modifier(GlassPanelBackground())
    }

    func sectionCardBackground(roundsBottom: Bool = true) -> some View {
        modifier(SectionCardBackground(roundsBottom: roundsBottom))
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .contentShape(RoundedRectangle(cornerRadius: GlassMetrics.controlRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct HoverRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isHovered || configuration.isPressed {
                    RoundedRectangle(cornerRadius: GlassMetrics.controlRadius, style: .continuous)
                        .fill(Theme.chipBackground)
                        .opacity(configuration.isPressed ? 1 : 0.85)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: GlassMetrics.controlRadius, style: .continuous))
            .onHover { isHovered = $0 }
    }
}

struct InsetGroupedCard<Content: View>: View {
    private let roundsBottom: Bool
    private let content: Content

    init(roundsBottom: Bool = true, @ViewBuilder content: () -> Content) {
        self.roundsBottom = roundsBottom
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sectionCardBackground(roundsBottom: roundsBottom)
    }
}
