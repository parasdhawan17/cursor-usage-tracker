import SwiftUI

// MARK: - Usage costs

struct UsageCostsPanel: View {
    enum Period: String, CaseIterable, Identifiable {
        case today = "Today"
        case cycle = "This cycle"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .today: return "sun.max.fill"
            case .cycle: return "calendar.circle.fill"
            }
        }
    }

    @Binding var period: Period
    let billedCents: Double
    let includedCents: Double
    let requestCount: Int?
    let isLoaded: Bool
    let unavailableTitle: String
    let unavailableIcon: String
    let unavailableInfo: String

    var body: some View {
        VStack(spacing: 12) {
            periodPicker

            if isLoaded {
                loadedContent
            } else {
                unavailableContent
            }
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(Period.allCases) { option in
                Label(option.rawValue, systemImage: option.icon).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var loadedContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                CostMetricTile(
                    title: "Billed",
                    value: UsageSnapshot.formatDollarsFull(billedCents),
                    icon: "creditcard.fill",
                    tint: billedCents >= 0.5 ? Theme.warning : Theme.textSecondary,
                    info: period == .today
                        ? "Extra usage charged to your account today."
                        : "Extra usage charged to your account this cycle."
                )
                CostMetricTile(
                    title: "Included",
                    value: UsageSnapshot.formatDollarsFull(includedCents),
                    icon: "checkmark.seal.fill",
                    tint: Theme.includedValue,
                    info: period == .today
                        ? "Notional token cost of plan-covered requests today."
                        : "Notional token cost of plan-covered requests—not an extra charge."
                )
            }

            if billedCents > 0 || includedCents > 0 {
                costMixBar
            }

            if let count = requestCount {
                requestBanner(count: count)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: period)
    }

    private var costMixBar: some View {
        let total = max(billedCents + includedCents, 0.001)
        let billedShare = billedCents / total
        let includedShare = includedCents / total

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if billedShare > 0 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Theme.warning.opacity(0.85), Theme.warning],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * billedShare - 1))
                    }
                    if includedShare > 0 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Theme.includedValue.opacity(0.85), Theme.includedValue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * includedShare - 1))
                    }
                }
            }
            .frame(height: 6)

            HStack(spacing: 12) {
                mixLegendDot(color: Theme.warning, label: "Billed", share: billedShare)
                mixLegendDot(color: Theme.includedValue, label: "Included", share: includedShare)
            }
        }
    }

    private func mixLegendDot(color: Color, label: String, share: Double) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("\(Int((share * 100).rounded()))%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
        }
    }

    private func requestBanner(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .background(Theme.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("\(count.formatted()) requests")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text(period == .today ? "Since midnight" : "This billing cycle")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.chipBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var unavailableContent: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.textTertiary.opacity(0.12))
                Image(systemName: unavailableIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 36, height: 36)

            Text(unavailableTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            InfoPopoverButton(text: unavailableInfo)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct CostMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    let info: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20, height: 20)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                InfoPopoverButton(text: info)
            }

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint == Theme.textSecondary ? Theme.textPrimary : tint)
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.08))
        }
    }
}

// MARK: - Model split

struct ModelSplitPanel: View {
    let apiPercent: Double?
    let autoPercent: Double?

    private var segments: [ModelSegment] {
        var result: [ModelSegment] = []
        if let api = apiPercent {
            result.append(ModelSegment(
                label: "API models",
                icon: "cpu.fill",
                color: Theme.apiModels,
                percent: api,
                info: "Models you pick yourself (e.g. Claude, GPT)."
            ))
        }
        if let auto = autoPercent {
            result.append(ModelSegment(
                label: "Auto models",
                icon: "wand.and.stars",
                color: Theme.autoModels,
                percent: auto,
                info: "Cursor-routed models (e.g. Composer, Auto)."
            ))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if segments.count > 1 {
                compositionBar
            }

            VStack(spacing: 6) {
                ForEach(segments) { segment in
                    ModelSplitRow(segment: segment)
                }
            }
        }
    }

    private var compositionBar: some View {
        let weights = segments.map(\.percent)
        let total = max(weights.reduce(0, +), 0.001)

        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    let width = max(4, geo.size.width * (segment.percent / total) - 1)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [segment.color.opacity(0.8), segment.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width)
                }
            }
        }
        .frame(height: 5)
    }
}

private struct ModelSegment: Identifiable {
    let label: String
    let icon: String
    let color: Color
    let percent: Double
    let info: String

    var id: String { label }
}

private struct ModelSplitRow: View {
    let segment: ModelSegment

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: segment.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(segment.color)
                .frame(width: 18, height: 18)
                .background(segment.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            HStack(spacing: 3) {
                Text(segment.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                InfoPopoverButton(text: segment.info)
            }
            .frame(width: 88, alignment: .leading)

            ModelUsageBar(progress: segment.percent, tint: segment.color)

            Text("\(Int(segment.percent.rounded()))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(segment.color)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(segment.color.opacity(0.06))
        }
    }
}

private struct ModelUsageBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.progressTrack)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.75), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 100) / 100))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Shared info button

struct InfoPopoverButton: View {
    let text: String
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $isShowing, arrowEdge: .top) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: 240, alignment: .leading)
        }
    }
}
