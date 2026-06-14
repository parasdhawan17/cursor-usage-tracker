import SwiftUI

struct MenuContentView: View {
    let showsSetup: Bool
    @Binding var sessionTokenInput: String
    let tokenFieldFocusToken: Int
    let sessionSaveError: String?
    let isSavingSession: Bool
    let onSaveSession: () -> Void
    let onCancelSessionEdit: (() -> Void)?
    let onEditSession: () -> Void
    let onSignOutSession: () -> Void

    let snapshot: UsageSnapshot?
    let error: String?
    let isLoading: Bool
    let isStale: Bool
    @Binding var refreshInterval: RefreshInterval
    let onRefresh: () -> Void

    let updatePhase: UpdateViewModel.Phase
    let onInstallUpdate: () -> Void
    let onDismissUpdateError: () -> Void

    @State private var usageCostPeriod: UsageCostsPanel.Period = .today

    private static let updatedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
        }
        .frame(width: showsSetup ? 320 : 320)
        .fixedSize(horizontal: false, vertical: true)
        .glassPanelBackground()
    }

    private var header: some View {
        HStack(spacing: 10) {
            headerIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(showsSetup ? "Connect" : "Cursor Usage")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !showsSetup {
                    Text("Plan & billing")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 8)
            if !showsSetup, isLoading, snapshot != nil {
                ProgressView().controlSize(.small)
            }
            if !showsSetup {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .disabled(isLoading && snapshot == nil)
                .help("Refresh now")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var headerIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(showsSetup ? Theme.accent.opacity(0.14) : Theme.accent.opacity(0.12))
            Image(systemName: showsSetup ? "key.fill" : "gauge.with.dots.needle.67percent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 28, height: 28)
    }

    @ViewBuilder
    private var content: some View {
        if showsSetup {
            SetupContentView(
                tokenInput: $sessionTokenInput,
                tokenFieldFocusToken: tokenFieldFocusToken,
                saveError: sessionSaveError,
                isSaving: isSavingSession,
                onSave: onSaveSession,
                onCancel: onCancelSessionEdit,
                onRemoveToken: onCancelSessionEdit == nil ? nil : onSignOutSession
            )
        } else if let snapshot {
            usageView(snapshot)
        } else if isLoading {
            loadingView
        } else if let error {
            errorView(error)
        } else {
            loadingView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.regular)
            Text("Loading usage…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.destructive.opacity(0.12))
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.destructive)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Could not load usage")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Try Again", action: onRefresh)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .frame(maxWidth: .infinity, alignment: .center)

            compactFooter(updatedAt: nil)
        }
    }

    private func usageView(_ s: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if isStale, let error {
                staleBanner(error)
            }
            heroSection(s)
            usageCostsTabbedSection(s)
            if hasModelSplitDetails(s) {
                sectionCard(
                    title: "Model split",
                    infoText: "Each category shows how much of your included plan it has used this cycle, and together they explain your total usage %."
                ) {
                    ModelSplitPanel(
                        apiPercent: s.apiPercentUsed,
                        autoPercent: s.autoPercentUsed
                    )
                }
            }
            compactFooter(updatedAt: s.fetchedAt)
        }
    }

    private func hasModelSplitDetails(_ s: UsageSnapshot) -> Bool {
        s.apiPercentUsed != nil || s.autoPercentUsed != nil
    }

    private func staleBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 11, weight: .semibold))
            Text("Showing cached data — \(message)")
                .font(.system(size: 10, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warningBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func heroSection(_ s: UsageSnapshot) -> some View {
        let tint = s.isUnlimited ? Theme.accent : Theme.usageColor(percent: s.primaryPercent)

        return VStack(alignment: .leading, spacing: 8) {
            metadataChips(s)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if s.isUnlimited {
                    Text("∞")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                } else {
                    Text(UsageSnapshot.formatPercent(s.primaryPercent))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                }
                if !s.isUnlimited {
                    Text("used")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if !s.isUnlimited {
                UsageProgressBar(
                    progress: s.primaryPercent,
                    pacePercent: s.evenPacePercent,
                    tint: tint
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: s.primaryPercent)
    }

    private func metadataChips(_ s: UsageSnapshot) -> some View {
        FlowLayout(spacing: 6) {
            metadataChip(s.planName, icon: "sparkles")
            if s.isUnlimited {
                metadataChip("Unlimited", icon: "infinity")
            }
            if let days = s.daysLeftInCycle {
                metadataChip(
                    days == 0 ? "Resets today" : "\(days) days left",
                    icon: "calendar"
                )
            }
        }
    }

    private func metadataChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.chipBackground)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func usageCostsTabbedSection(_ s: UsageSnapshot) -> some View {
        sectionCard(
            title: "Usage costs",
            infoText: usageCostsInfoText(s, period: usageCostPeriod)
        ) {
            UsageCostsPanel(
                period: $usageCostPeriod,
                billedCents: usageCostPeriod == .today
                    ? (s.todayChargeableCents ?? 0)
                    : (s.chargeableCents ?? 0),
                includedCents: usageCostPeriod == .today
                    ? (s.todayIncludedUsageValueCents ?? 0)
                    : (s.includedUsageValueCents ?? 0),
                requestCount: usageCostPeriod == .today ? s.todayEventCount : s.cycleCostEventCount,
                isLoaded: usageCostPeriod == .today ? s.todayCostsLoaded : s.cycleCostsLoaded,
                unavailableTitle: usageCostPeriod == .today
                    ? "Today unavailable"
                    : "Cycle totals unavailable",
                unavailableIcon: usageCostPeriod == .today
                    ? "calendar.badge.exclamationmark"
                    : "chart.bar.xaxis",
                unavailableInfo: usageCostPeriod == .today
                    ? "Tap ↻ in the header to retry loading today's usage."
                    : "Usage % is still accurate. Tap ↻ in the header to retry."
            )
        }
    }

    private func usageCostsInfoText(_ s: UsageSnapshot, period: UsageCostsPanel.Period) -> String {
        switch period {
        case .today:
            return
                "Totals for today in your local timezone (midnight through now). "
                + "Billed is on-demand spend; included usage value is notional token cost—not an extra charge."
        case .cycle:
            return cycleCostsInfoText(s)
        }
    }

    private func cycleCostsInfoText(_ s: UsageSnapshot) -> String {
        var parts: [String] = []
        if s.cycleCostsLoaded {
            let short = DateFormatter()
            short.dateStyle = .medium
            short.timeStyle = .none
            if let start = UsageSnapshot.parseISO8601(s.billingStart) {
                parts.append("Totals since \(short.string(from: start)) through today.")
            } else {
                parts.append("Totals for this billing period through today.")
            }
            parts.append(
                "Billed is what you pay on-demand. Included usage value is the notional token cost of plan-covered requests—not an extra charge."
            )
        }
        return parts.joined(separator: " ")
    }

    private func sectionCard<Content: View>(
        title: String,
        infoText: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                SectionHeaderLabel(title: title)
                if let infoText {
                    infoPopoverButton(infoText)
                }
            }

            InsetGroupedCard {
                content()
                    .padding(.vertical, 6)
            }
        }
    }

    private func infoPopoverButton(_ text: String) -> some View {
        InfoPopoverButton(text: text)
    }

    private static let dashboardURL = URL(string: "https://cursor.com/dashboard/usage")!

    private func compactFooter(updatedAt: Date?) -> some View {
        VStack(spacing: 10) {
            if !showsSetup {
                updateBanner
            }
            refreshSettingsRow

            if let updatedAt {
                Text("Updated \(Self.updatedFormatter.string(from: updatedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            footerActions
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var updateBanner: some View {
        switch updatePhase {
        case .available(let update):
            updateBannerRow(background: Theme.accent.opacity(0.12)) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Update available — v\(update.version)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button("Update", action: onInstallUpdate)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

        case .downloading:
            updateBannerRow {
                ProgressView().controlSize(.mini)
                Text("Downloading update…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

        case .installing:
            updateBannerRow {
                ProgressView().controlSize(.mini)
                Text("Installing update…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

        case .failed(let message):
            updateBannerRow(background: Theme.destructive.opacity(0.08)) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.destructive)
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Button("Dismiss", action: onDismissUpdateError)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.destructive)
            }

        case .idle, .checking:
            EmptyView()
        }
    }

    private func updateBannerRow<Content: View>(
        background: Color = Theme.chipBackground,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var refreshSettingsRow: some View {
        HStack(spacing: 8) {
            Label {
                Text("Auto-refresh")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold))
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 8)

            Picker("Auto-refresh", selection: $refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text("Every \(interval.label)").tag(interval)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.chipBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footerActions: some View {
        InsetGroupedCard(roundsBottom: false) {
            VStack(spacing: 0) {
                footerActionRow(title: "Session", systemImage: "person.badge.key", action: onEditSession)
                footerDivider
                footerLinkRow(
                    title: "Open Dashboard",
                    systemImage: "safari",
                    destination: Self.dashboardURL
                )
                footerDivider
                footerActionRow(
                    title: "Quit Cursor Usage",
                    systemImage: "power",
                    action: { NSApp.terminate(nil) },
                    showsChevron: false,
                    titleColor: Theme.textSecondary
                )
            }
        }
    }

    private var footerDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 0.5)
            .padding(.leading, 34)
    }

    private func footerActionRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void,
        showsChevron: Bool = true,
        titleColor: Color = Theme.textPrimary
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 16, alignment: .center)

                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(titleColor)

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowButtonStyle())
    }

    private func footerLinkRow(
        title: String,
        systemImage: String,
        destination: URL
    ) -> some View {
        Link(destination: destination) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 16, alignment: .center)

                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowButtonStyle())
    }
}

// MARK: - Flow layout for metadata chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
