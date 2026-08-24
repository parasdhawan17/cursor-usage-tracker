import SwiftUI

struct CompactMenuContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider().opacity(0.6)
            VStack(alignment: .leading, spacing: 12) {
                Picker("Service", selection: $viewModel.selectedService) {
                    ForEach(TrackedService.allCases) { service in
                        Label(service.title, systemImage: service.icon).tag(service)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                selectedSummary
                quickInsights
            }
            .padding(14)
            Divider().opacity(0.6)
            panelFooter
        }
        .frame(width: 320)
        .glassPanelBackground()
        .animation(.easeOut(duration: 0.2), value: viewModel.selectedService)
    }

    private var panelHeader: some View {
        HStack(spacing: 10) {
            ServiceIcon(service: viewModel.selectedService, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(viewModel.selectedService.title) Usage")
                    .font(.system(size: 13, weight: .semibold))
                Text(headerStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if viewModel.isSelectedServiceLoading { ProgressView().controlSize(.small) }
            Button {
                Task { await viewModel.refresh(viewModel.selectedService) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .disabled(viewModel.isSelectedServiceLoading)
            .help("Refresh now (⌘R)")
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var panelFooter: some View {
        HStack(spacing: 8) {
            Button(action: openDashboard) {
                Label("Open Dashboard", systemImage: "rectangle.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(",", modifiers: [.command])
            Spacer()
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(ToolbarIconButtonStyle())
                .help("Quit AI Usage (⌘Q)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var selectedSummary: some View {
        switch viewModel.selectedService {
        case .cursor:
            if let snapshot = viewModel.cursorSnapshot {
                CompactUsageSummary(
                    plan: snapshot.planName,
                    percent: snapshot.primaryPercent,
                    pacePercent: snapshot.evenPacePercent,
                    resetText: snapshot.daysLeftInCycle.map { $0 == 0 ? "Resets today" : "Resets in \($0) days" },
                    isAllowed: true
                )
            } else {
                compactEmpty(service: .cursor, connected: SessionTokenStore.hasToken, error: viewModel.cursorError)
            }
        case .codex:
            if let snapshot = viewModel.codexSnapshot, let percent = snapshot.primaryPercent {
                CompactUsageSummary(
                    plan: snapshot.planName,
                    percent: percent,
                    pacePercent: snapshot.primaryWindow?.evenPacePercent(),
                    resetText: snapshot.primaryWindow?.resetDescription.map { "Resets \($0)" },
                    isAllowed: snapshot.isAllowed
                )
            } else {
                compactEmpty(service: .codex, connected: CodexTokenStore.hasCredentials, error: viewModel.codexError)
            }
        }
    }

    @ViewBuilder private var quickInsights: some View {
        switch viewModel.selectedService {
        case .cursor:
            if let snapshot = viewModel.cursorSnapshot {
                VStack(alignment: .leading, spacing: 7) {
                    SectionHeaderLabel(title: "At a glance")
                    HStack(spacing: 8) {
                        InsightPill(icon: "speedometer", title: "Pace", value: paceDifference(used: snapshot.primaryPercent, pace: snapshot.evenPacePercent))
                        InsightPill(icon: "number", title: "Requests today", value: snapshot.todayEventCount.map { $0.formatted() } ?? "—")
                        InsightPill(icon: "creditcard", title: "Value today", value: snapshot.todayCostsLoaded ? UsageSnapshot.formatDollarsFull(snapshot.todayIncludedUsageValueCents ?? 0) : "—")
                    }
                    freshnessRow(snapshot.fetchedAt)
                }
            }
        case .codex:
            if let snapshot = viewModel.codexSnapshot {
                VStack(alignment: .leading, spacing: 7) {
                    SectionHeaderLabel(title: "At a glance")
                    if let window = snapshot.primaryWindow {
                        HStack(spacing: 8) {
                            InsightPill(icon: "gauge.with.dots.needle.33percent", title: "Allowance left", value: UsageSnapshot.formatPercent(window.remainingPercent))
                            InsightPill(icon: "calendar", title: "Window", value: window.windowDescription ?? "—")
                            InsightPill(icon: "clock.arrow.circlepath", title: "Resets in", value: window.resetCountdown() ?? "—")
                        }
                    }
                    if let today = viewModel.codexTodayUsage {
                        CodexTodayRow(usage: today)
                    }
                    if let optionalDetail = optionalCodexDetail(snapshot) {
                        HStack(spacing: 6) {
                            Image(systemName: optionalDetail.icon).foregroundStyle(Theme.autoModels)
                            Text(optionalDetail.label).foregroundStyle(.secondary)
                            Spacer()
                            Text(optionalDetail.value).fontWeight(.semibold)
                        }
                        .font(.system(size: 10))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Theme.contentSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    freshnessRow(snapshot.fetchedAt)
                }
            }
        }
    }

    private var headerStatus: String {
        if viewModel.isSelectedServiceLoading { return "Updating usage…" }
        switch viewModel.selectedService {
        case .cursor:
            if viewModel.cursorError != nil { return "Last refresh failed" }
            return SessionTokenStore.hasToken ? "Connected" : "Not connected"
        case .codex:
            if viewModel.codexError != nil { return "Last refresh failed" }
            return CodexTokenStore.hasCredentials ? "Connected" : "Not connected"
        }
    }

    private func freshnessRow(_ date: Date) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
            Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
            Spacer()
            Text("Auto-refresh · \(viewModel.refreshInterval.label)")
        }
        .font(.system(size: 9))
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 2)
    }

    private func paceDifference(used: Double, pace: Double?) -> String {
        guard let pace else { return "—" }
        let difference = used - pace
        if abs(difference) < 1 { return "On pace" }
        return difference > 0 ? "+\(Int(difference.rounded()))%" : "\(Int(difference.rounded()))%"
    }

    private func optionalCodexDetail(_ snapshot: CodexUsageSnapshot) -> (icon: String, label: String, value: String)? {
        if snapshot.creditsUnlimited {
            return ("infinity", "Credits", "Unlimited")
        }
        if let credits = snapshot.creditsRemaining, credits > 0 {
            return ("creditcard", "Credits remaining", credits.formatted())
        }
        if let resets = snapshot.resetCreditsAvailable, resets > 0 {
            return ("arrow.counterclockwise.circle", "Quota resets available", resets.formatted())
        }
        if let messages = snapshot.approximateLocalMessages, messages.upperBound > 0 {
            let value = messages.lowerBound == messages.upperBound
                ? messages.lowerBound.formatted()
                : "\(messages.lowerBound.formatted())–\(messages.upperBound.formatted())"
            return ("message", "Approx. local messages", value)
        }
        return nil
    }

    private func compactEmpty(service: TrackedService, connected: Bool, error: String?) -> some View {
        VStack(spacing: 9) {
            Image(systemName: connected ? "exclamationmark.triangle" : "link.badge.plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(connected ? Theme.warning : Theme.accent)
            Text(connected ? "Usage unavailable" : "Connect \(service.title)")
                .font(.system(size: 13, weight: .semibold))
            Text(error ?? "Open the dashboard to finish connecting this service.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 116)
        .padding(12)
        .background(Theme.contentSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct CompactUsageSummary: View {
    let plan: String
    let percent: Double
    let pacePercent: Double?
    let resetText: String?
    let isAllowed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(plan, systemImage: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(text: statusText, color: statusColor)
            }
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(UsageSnapshot.formatPercent(percent))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.usageColor(percent: percent))
                Text("used")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                UsageProgressBar(progress: percent, pacePercent: pacePercent, tint: Theme.usageColor(percent: percent))
                HStack {
                    if let pacePercent { Text(paceText(pacePercent)) }
                    Spacer()
                    if let resetText { Text(resetText) }
                }
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .background(Theme.contentSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.2), lineWidth: 0.5)
        }
    }

    private var statusText: String {
        if !isAllowed { return "Limited" }
        if percent >= 90 { return "Near limit" }
        if percent >= 70 { return "Watch usage" }
        return "On track"
    }

    private var statusColor: Color {
        isAllowed ? Theme.usageColor(percent: percent) : Theme.destructive
    }

    private func paceText(_ pace: Double) -> String {
        let difference = percent - pace
        if abs(difference) < 1 { return "On even pace" }
        return difference > 0 ? "\(Int(difference.rounded()))% ahead of pace" : "\(Int(abs(difference).rounded()))% behind pace"
    }
}

struct ServiceIcon: View {
    let service: TrackedService
    var size: CGFloat = 32

    var body: some View {
        let color = service == .cursor ? Theme.apiModels : Theme.autoModels
        Image(systemName: service.icon)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct InsightPill: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(Theme.contentSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CodexTodayRow: View {
    let usage: CodexDailyUsage

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.warning)
                .frame(width: 26, height: 26)
                .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Observed today").font(.system(size: 10, weight: .medium))
                Text("Tracking since \(usage.firstObservedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 8)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text(observedValue)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("of window")
                .font(.system(size: 8)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Theme.contentSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Locally observed change in Codex quota usage since the first app refresh today; not an official daily total.")
    }

    private var observedValue: String {
        usage.displayValue
    }
}
