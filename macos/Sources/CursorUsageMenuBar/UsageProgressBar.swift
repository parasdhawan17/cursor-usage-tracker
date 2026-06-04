import SwiftUI

/// Usage fill plus an arrow marking even daily pace across the billing cycle.
struct UsageProgressBar: View {
    let progress: Double
    let pacePercent: Double?
    var tint: Color

    private let barHeight: CGFloat = 5
    private let arrowRowHeight: CGFloat = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if pacePercent != nil {
                paceArrowLayer
                    .frame(height: arrowRowHeight)
            }
            progressBarLayer
                .frame(height: barHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var paceArrowLayer: some View {
        GeometryReader { geo in
            if let pace = pacePercent {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(Theme.paceMarker)
                    .position(x: markerX(pace: pace, width: geo.size.width), y: arrowRowHeight / 2)
                    .help("Even pace for today (\(UsageSnapshot.formatPercent(pace)) of cycle)")
            }
        }
    }

    private var progressBarLayer: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.progressTrack)
                    .frame(height: barHeight)

                Capsule()
                    .fill(tint)
                    .frame(width: width * CGFloat(min(max(progress, 0), 100) / 100), height: barHeight)

                if let pace = pacePercent {
                    Rectangle()
                        .fill(Theme.paceMarker.opacity(0.55))
                        .frame(width: 1.5, height: barHeight + 2)
                        .position(x: markerX(pace: pace, width: width), y: barHeight / 2)
                }
            }
        }
    }

    private func markerX(pace: Double, width: CGFloat) -> CGFloat {
        let clamped = min(max(pace, 0), 100)
        let raw = width * CGFloat(clamped / 100)
        return min(max(6, raw), max(6, width - 6))
    }

    private var accessibilityText: String {
        var parts = ["Usage \(UsageSnapshot.formatPercent(progress))"]
        if let pace = pacePercent {
            parts.append("even pace \(UsageSnapshot.formatPercent(pace))")
        }
        return parts.joined(separator: ", ")
    }
}
