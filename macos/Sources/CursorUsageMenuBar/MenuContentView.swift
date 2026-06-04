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
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.sectionBorder, lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack {
            Text(showsSetup ? "Setup" : "Cursor Usage")
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
            if let msg = s.statusMessage {
                statusBanner(msg)
            }
            sectionCard(title: "Plan & pool") {
                planAndPoolSection(s)
            }
            if hasExtraDetails(s) {
                sectionCard(title: "Details") {
                    extraDetailsSection(s)
                }
            }
            compactFooter(updatedAt: s.fetchedAt)
        }
    }

    private func hasExtraDetails(_ s: UsageSnapshot) -> Bool {
        s.breakdownIncluded != nil
            || s.breakdownBonus != nil
            || s.apiPercentUsed != nil
            || s.autoPercentUsed != nil
            || s.onDemandEnabled
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
            Text("Total included usage")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

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

    private func planAndPoolSection(_ s: UsageSnapshot) -> some View {
        VStack(spacing: 0) {
            row("Consumed", value: "\(s.used) / \(s.limit)")
            rowDivider
            row("Pool used", value: UsageSnapshot.formatPercent(s.includedPercent))
            rowDivider
            row("Remaining", value: "\(s.remaining)")
            if s.remaining <= 0 && s.used >= s.limit {
                Text("Pool full — see dashboard.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4)
            }
            rowDivider
            row("Plan", value: s.planName)
            rowDivider
            row("Billing", value: formatBilling(s.billingStart, s.billingEnd))
            if let days = s.daysLeftInCycle {
                rowDivider
                row("Resets in", value: days == 0 ? "Today" : "\(days) d")
            }
        }
    }

    private func extraDetailsSection(_ s: UsageSnapshot) -> some View {
        VStack(spacing: 0) {
            detailRows(s.breakdownIncluded, s.breakdownBonus, s.breakdownTotal)
            if s.apiPercentUsed != nil || s.autoPercentUsed != nil {
                if s.breakdownIncluded != nil || s.breakdownBonus != nil || s.breakdownTotal != nil {
                    rowDivider
                }
                splitRows(s)
            }
            if s.onDemandEnabled {
                rowDivider
                row("On-demand", value: formatOnDemand(s.onDemandUsed))
            }
        }
    }

    @ViewBuilder
    private func detailRows(_ included: Int?, _ bonus: Int?, _ total: Int?) -> some View {
        if let v = included {
            row("Included pool", value: "\(v)")
            if bonus != nil || total != nil { rowDivider }
        }
        if let v = bonus {
            row("Bonus", value: "\(v)")
            if total != nil { rowDivider }
        }
        if let v = total {
            row("Total pool", value: "\(v)")
        }
    }

    private func splitRows(_ s: UsageSnapshot) -> some View {
        Group {
            if let api = s.apiPercentUsed {
                row("API models", value: "\(Int(api.rounded()))%")
                if s.autoPercentUsed != nil { rowDivider }
            }
            if let auto = s.autoPercentUsed {
                row("Auto models", value: "\(Int(auto.rounded()))%")
            }
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
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

    private var sectionBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Theme.sectionBorder, lineWidth: 0.5)
    }

    private var rowDivider: some View {
        Divider().opacity(0.3).padding(.vertical, 4)
    }

    private func statusBanner(_ text: String) -> some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.system(size: 10))
            .foregroundStyle(Theme.textSecondary)
            .padding(8)
            .background(Theme.accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func compactFooter(updatedAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.35)
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                Text("Refresh")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Picker("Auto-refresh", selection: $refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 72)
            }
            HStack(alignment: .firstTextBaseline) {
                if let updatedAt {
                    Text("Updated \(Self.updatedFormatter.string(from: updatedAt))")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Session", action: onEditSession)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                Link("Dashboard", destination: URL(string: "https://cursor.com/dashboard/usage")!)
                    .font(.system(size: 11))
            }
            Button("Quit Cursor Usage") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 2)
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

    private func formatOnDemand(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)"
    }

    private func formatBilling(_ start: String, _ end: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let short = DateFormatter()
        short.dateStyle = .medium
        short.timeStyle = .none

        if let d1 = f.date(from: start) ?? ISO8601DateFormatter().date(from: start),
           let d2 = f.date(from: end) ?? ISO8601DateFormatter().date(from: end) {
            return "\(short.string(from: d1)) – \(short.string(from: d2))"
        }
        return "\(start.prefix(10)) – \(end.prefix(10))"
    }
}
