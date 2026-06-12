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

    @State private var usageCostPeriod: UsageCostPeriod = .today

    private enum UsageCostPeriod: String, CaseIterable, Identifiable {
        case today = "Today"
        case cycle = "This cycle"

        var id: String { rawValue }
    }

    private static let updatedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .frame(width: showsSetup ? 320 : 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.sectionBorder, lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            if showsSetup {
                Image(systemName: "key.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text(showsSetup ? "Connect" : "Cursor Usage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if !showsSetup, isLoading, snapshot != nil {
                ProgressView().controlSize(.small)
            }
            if !showsSetup {
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .disabled(isLoading && snapshot == nil)
            .help("Refresh now")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Could not load usage", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(light: "#FF3B30", dark: "#FF453A"))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: onRefresh)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            compactFooter(updatedAt: nil)
        }
    }

    private func usageView(_ s: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
                    modelSplitSection(s)
                }
            }
            compactFooter(updatedAt: s.fetchedAt)
        }
    }

    private func hasModelSplitDetails(_ s: UsageSnapshot) -> Bool {
        s.apiPercentUsed != nil || s.autoPercentUsed != nil
    }

    private func staleBanner(_ message: String) -> some View {
        Label("Cached — \(message)", systemImage: "wifi.exclamationmark")
            .font(.system(size: 10))
            .foregroundStyle(Color(light: "#FF9500", dark: "#FF9F0A"))
            .padding(8)
            .background(Color(light: "#FF9500", dark: "#FF9F0A").opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Top usage % — flat, no card background.
    private func heroSection(_ s: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(planSummaryLine(s))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if s.isUnlimited {
                    Text("∞")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text(UsageSnapshot.formatPercent(s.primaryPercent))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.usageColor(percent: s.primaryPercent))
                }
                if !s.isUnlimited {
                    Text("of plan")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if !s.isUnlimited {
                UsageProgressBar(
                    progress: s.primaryPercent,
                    pacePercent: s.evenPacePercent,
                    tint: Theme.usageColor(percent: s.primaryPercent)
                )
            }
        }
    }

    private func planSummaryLine(_ s: UsageSnapshot) -> String {
        var parts = [s.planName]

        if s.isUnlimited {
            parts.append("Unlimited")
        } else {
            parts.append("\(s.used)/\(s.limit) used")
        }

        if let days = s.daysLeftInCycle {
            parts.append(days == 0 ? "Resets today" : "Resets in \(days) d")
        }

        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func usageCostsTabbedSection(_ s: UsageSnapshot) -> some View {
        sectionCard(
            title: "Usage costs",
            infoText: usageCostsInfoText(s, period: usageCostPeriod)
        ) {
            VStack(spacing: 10) {
                Picker("Period", selection: $usageCostPeriod) {
                    ForEach(UsageCostPeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.regular)

                Group {
                    switch usageCostPeriod {
                    case .today:
                        todayCostsContent(s)
                    case .cycle:
                        cycleCostsContent(s)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: usageCostPeriod)
            }
        }
    }

    @ViewBuilder
    private func todayCostsContent(_ s: UsageSnapshot) -> some View {
        if s.todayCostsLoaded {
            costMetricsContent(
                billedCents: s.todayChargeableCents ?? 0,
                includedCents: s.todayIncludedUsageValueCents ?? 0,
                requestCount: s.todayEventCount,
                billedInfo: "Extra usage charged to your account today.",
                includedInfo: "Notional token cost of plan-covered requests today."
            )
        } else {
            costsUnavailableRow(
                title: "Today unavailable",
                systemImage: "calendar.badge.exclamationmark",
                retryInfo: "Tap ↻ in the header to retry loading today's usage."
            )
        }
    }

    @ViewBuilder
    private func cycleCostsContent(_ s: UsageSnapshot) -> some View {
        if s.cycleCostsLoaded {
            costMetricsContent(
                billedCents: s.chargeableCents ?? 0,
                includedCents: s.includedUsageValueCents ?? 0,
                requestCount: s.cycleCostEventCount,
                billedInfo: "Extra usage charged to your account this cycle.",
                includedInfo: "Notional token cost of plan-covered requests—not an extra charge."
            )
        } else {
            costsUnavailableRow(
                title: "Cycle totals unavailable",
                systemImage: "chart.bar.xaxis",
                retryInfo: "Usage % is still accurate. Tap ↻ in the header to retry."
            )
        }
    }

    private func costMetricsContent(
        billedCents: Double,
        includedCents: Double,
        requestCount: Int?,
        billedInfo: String,
        includedInfo: String
    ) -> some View {
        VStack(spacing: 0) {
            costRow(
                label: "Billed (on-demand)",
                info: billedInfo,
                value: UsageSnapshot.formatDollarsFull(billedCents),
                valueColor: billedCents >= 0.5
                    ? Color(light: "#FF9500", dark: "#FF9F0A")
                    : Theme.textPrimary
            )
            rowDivider
            costRow(
                label: "Included usage value",
                info: includedInfo,
                value: UsageSnapshot.formatDollarsFull(includedCents),
                valueColor: Theme.textPrimary
            )
            if let count = requestCount {
                rowDivider
                row("Requests", value: "\(count)")
            }
        }
    }

    private func costsUnavailableRow(
        title: String,
        systemImage: String,
        retryInfo: String
    ) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            infoPopoverButton(retryInfo)
        }
    }

    private func usageCostsInfoText(_ s: UsageSnapshot, period: UsageCostPeriod) -> String {
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

    private func costRow(
        label: String,
        info: String,
        value: String,
        valueColor: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                infoPopoverButton(info)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private func modelSplitSection(_ s: UsageSnapshot) -> some View {
        VStack(spacing: 0) {
            if let api = s.apiPercentUsed {
                modelSplitRow(
                    label: "API models",
                    info: "Models you pick yourself (e.g. Claude, GPT).",
                    value: "\(Int(api.rounded()))%"
                )
                if s.autoPercentUsed != nil { rowDivider }
            }
            if let auto = s.autoPercentUsed {
                modelSplitRow(
                    label: "Auto models",
                    info: "Cursor-routed models (e.g. Composer, Auto).",
                    value: "\(Int(auto.rounded()))%"
                )
            }
        }
    }

    private func modelSplitRow(label: String, info: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                infoPopoverButton(info)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        infoText: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if let infoText {
                    infoPopoverButton(infoText)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sectionBackground)
            .overlay(sectionBorder)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func infoPopoverButton(_ text: String) -> some View {
        InfoPopoverButton(text: text)
    }

    private var sectionBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Theme.sectionBorder, lineWidth: 0.5)
    }

    private var rowDivider: some View {
        Divider().opacity(0.3).padding(.vertical, 4)
    }

    private static let dashboardURL = URL(string: "https://cursor.com/dashboard/usage")!

    private func compactFooter(updatedAt: Date?) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
                .padding(.bottom, 10)

            refreshSettingsRow
                .padding(.bottom, updatedAt == nil ? 10 : 6)

            if let updatedAt {
                Text("Updated \(Self.updatedFormatter.string(from: updatedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }

            footerActions
        }
        .padding(.top, 2)
    }

    private var refreshSettingsRow: some View {
        HStack(spacing: 8) {
            Label {
                Text("Auto-refresh")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textPrimary)
            } icon: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
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
    }

    private var footerActions: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.25)

            footerActionRow(title: "Session", systemImage: "person.badge.key", action: onEditSession)

            Divider().opacity(0.15)
                .padding(.leading, 36)

            footerLinkRow(
                title: "Open Dashboard",
                systemImage: "safari",
                destination: Self.dashboardURL
            )

            Divider().opacity(0.25)

            footerActionRow(
                title: "Quit Cursor Usage",
                systemImage: "power",
                action: { NSApp.terminate(nil) },
                showsChevron: false,
                titleColor: Theme.textSecondary
            )
        }
        .padding(.horizontal, -14)
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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.55))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.55))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct InfoPopoverButton: View {
    let text: String
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $isShowing, arrowEdge: .top) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: 240, alignment: .leading)
        }
    }
}
