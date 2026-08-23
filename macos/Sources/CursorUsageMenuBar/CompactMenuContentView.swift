import SwiftUI

struct CompactMenuContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI Usage").font(.system(size: 13, weight: .semibold))
                    Text("Plan monitor").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await viewModel.refresh(viewModel.selectedService) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(ToolbarIconButtonStyle())
                    .help("Refresh selected service")
            }
            Picker("Service", selection: $viewModel.selectedService) {
                ForEach(TrackedService.allCases) { service in Label(service.title, systemImage: service.icon).tag(service) }
            }
            .pickerStyle(.segmented)
            selectedSummary
            quickInsights
            Button(action: openDashboard) {
                Label("Open Dashboard", systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            Divider()
            Button("Quit AI Usage") { NSApp.terminate(nil) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 300)
        .glassPanelBackground()
    }

    @ViewBuilder private var selectedSummary: some View {
        switch viewModel.selectedService {
        case .cursor:
            if let snapshot = viewModel.cursorSnapshot {
                UsageHeroCard(
                    title: snapshot.planName,
                    percent: snapshot.primaryPercent,
                    pacePercent: snapshot.evenPacePercent,
                    resetText: snapshot.daysLeftInCycle.map { $0 == 0 ? "Resets today" : "\($0) days left" }
                )
            } else { compactEmpty(service: .cursor, connected: SessionTokenStore.hasToken, error: viewModel.cursorError) }
        case .codex:
            if let snapshot = viewModel.codexSnapshot, let percent = snapshot.primaryPercent {
                UsageHeroCard(
                    title: snapshot.planName,
                    percent: percent,
                    pacePercent: snapshot.primaryWindow?.evenPacePercent(),
                    resetText: snapshot.primaryWindow?.resetDescription.map { "Resets \($0)" }
                )
            } else { compactEmpty(service: .codex, connected: CodexTokenStore.hasCredentials, error: viewModel.codexError) }
        }
    }

    @ViewBuilder private var quickInsights: some View {
        switch viewModel.selectedService {
        case .cursor:
            if let snapshot = viewModel.cursorSnapshot {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeaderLabel(title: "At a glance")
                    HStack(spacing: 8) {
                        InsightPill(
                            icon: "speedometer",
                            title: "Pace",
                            value: cursorPace(snapshot)
                        )
                        if let days = snapshot.daysLeftInCycle {
                            InsightPill(
                                icon: "calendar",
                                title: "Cycle",
                                value: days == 0 ? "Today" : "\(days)d left"
                            )
                        }
                    }
                    if snapshot.todayCostsLoaded {
                        InsightRow(
                            icon: "creditcard",
                            label: "Today’s usage value",
                            value: UsageSnapshot.formatDollarsFull(snapshot.todayIncludedUsageValueCents ?? 0)
                        )
                    }
                }
            }
        case .codex:
            if let snapshot = viewModel.codexSnapshot {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeaderLabel(title: "At a glance")
                    HStack(spacing: 8) {
                        InsightPill(
                            icon: snapshot.isAllowed ? "checkmark.circle" : "exclamationmark.triangle",
                            title: "Status",
                            value: snapshot.isAllowed ? "Available" : "Limited"
                        )
                        if let reset = snapshot.primaryWindow?.resetDescription {
                            InsightPill(icon: "clock", title: "Reset", value: reset)
                        }
                    }
                    if let credits = snapshot.creditsRemaining {
                        InsightRow(icon: "creditcard", label: "Credits remaining", value: credits.formatted())
                    }
                    if let pace = snapshot.primaryWindow?.evenPacePercent(), let used = snapshot.primaryPercent {
                        InsightRow(
                            icon: "speedometer",
                            label: "Window pace",
                            value: paceDifference(used: used, pace: pace)
                        )
                    }
                }
            }
        }
    }

    private func cursorPace(_ snapshot: UsageSnapshot) -> String {
        guard let pace = snapshot.evenPacePercent else { return "—" }
        let difference = snapshot.primaryPercent - pace
        if abs(difference) < 1 { return "On pace" }
        return difference > 0 ? "+\(Int(difference.rounded()))%" : "\(Int(difference.rounded()))%"
    }

    private func paceDifference(used: Double, pace: Double) -> String {
        let difference = used - pace
        if abs(difference) < 1 { return "On pace" }
        return difference > 0 ? "+\(Int(difference.rounded()))%" : "\(Int(difference.rounded()))%"
    }

    private func compactEmpty(service: TrackedService, connected: Bool, error: String?) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 6) {
                Label(connected ? "Usage unavailable" : "\(service.title) not connected", systemImage: connected ? "exclamationmark.triangle" : "link.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
            Text(error ?? "Open Dashboard to connect \(service.title).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InsightPill: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chipBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InsightRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(Theme.chipBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
