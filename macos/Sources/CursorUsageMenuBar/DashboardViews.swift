import AppKit
import SwiftUI

enum DashboardPage: String, CaseIterable, Identifiable {
    case overview
    case cursor
    case codex
    case settings

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .overview: return "rectangle.grid.2x2"
        case .cursor: return "cursorarrow.rays"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .settings: return "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .overview: return Theme.accent
        case .cursor: return Theme.apiModels
        case .codex: return Theme.autoModels
        case .settings: return Theme.textSecondary
        }
    }
}

struct DashboardRootView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var navigation: DashboardNavigation

    init(viewModel: UsageViewModel, navigation: DashboardNavigation) {
        self.viewModel = viewModel
        self.navigation = navigation
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AI Usage").font(.system(size: 13, weight: .semibold))
                        Text("Plan monitor").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)

                List(selection: $navigation.page) {
                    Section("Usage") {
                        ForEach([DashboardPage.overview, .cursor, .codex]) { page in
                            Label(page.title, systemImage: page.icon).tag(page)
                        }
                    }
                    Section("App") {
                        Label(DashboardPage.settings.title, systemImage: DashboardPage.settings.icon)
                            .tag(DashboardPage.settings)
                    }
                }
                .listStyle(.sidebar)

                VStack(alignment: .leading, spacing: 7) {
                    connectionRow(.cursor, connected: SessionTokenStore.hasToken)
                    connectionRow(.codex, connected: CodexTokenStore.hasCredentials)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 215)
        } detail: {
            Group {
                switch navigation.page {
                case .overview: OverviewDashboardView(viewModel: viewModel)
                case .cursor: CursorDashboardView(viewModel: viewModel)
                case .codex: CodexDashboardView(viewModel: viewModel)
                case .settings: SettingsDashboardView(viewModel: viewModel)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: navigation.page)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await viewModel.refreshAll() } } label: {
                    Label("Refresh all", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func connectionRow(_ service: TrackedService, connected: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(connected ? Theme.includedValue : Theme.textTertiary).frame(width: 6, height: 6)
            Text(service.title).font(.system(size: 10, weight: .medium))
            Spacer()
            Text(connected ? "Connected" : "Not set")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

private struct DashboardPageContainer<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 14) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                        .overlay(Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(Theme.accent))
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 25, weight: .bold, design: .rounded))
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                content
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }
}

struct DashboardCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .background(Theme.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.28), lineWidth: 0.5)
            }
    }
}

private struct DashboardSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeaderLabel(title: title)
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            DashboardCard { content }
        }
    }
}

struct OverviewDashboardView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        DashboardPageContainer(title: "Overview", subtitle: "Your AI coding usage at a glance.") {
            HStack(alignment: .top, spacing: 16) {
                OverviewServiceCard(service: .cursor, isConnected: SessionTokenStore.hasToken, snapshotText: cursorSummary, error: viewModel.cursorError) {
                    Task { await viewModel.refreshCursor() }
                }
                OverviewServiceCard(service: .codex, isConnected: CodexTokenStore.hasCredentials, snapshotText: codexSummary, error: viewModel.codexError) {
                    Task { await viewModel.refreshCodex() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.hasAnyConnection {
                DashboardEmptyState(
                    title: "Connect an account",
                    message: "Open Settings to connect Cursor or the experimental Codex integration.",
                    icon: "link.badge.plus"
                )
            }
        }
    }

    private var cursorSummary: String? {
        guard let snapshot = viewModel.cursorSnapshot else { return nil }
        return "\(UsageSnapshot.formatPercent(snapshot.primaryPercent)) used · \(snapshot.planName)"
    }

    private var codexSummary: String? {
        guard let snapshot = viewModel.codexSnapshot else { return nil }
        let usage = snapshot.primaryPercent.map { "\(Int($0.rounded()))% used" } ?? "Usage unavailable"
        return "\(usage) · \(snapshot.planName)"
    }
}

private struct OverviewServiceCard: View {
    let service: TrackedService
    let isConnected: Bool
    let snapshotText: String?
    let error: String?
    let refresh: () -> Void

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(service.title, systemImage: service.icon).font(.headline)
                    Spacer()
                    Circle().fill(isConnected ? Theme.includedValue : Theme.textTertiary).frame(width: 7, height: 7)
                }
            if let snapshotText {
                    Text(snapshotText).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
            } else if isConnected {
                Text(error ?? "Loading usage…").foregroundStyle(error == nil ? Color.secondary : Color.red)
            } else {
                Text("Not connected").foregroundStyle(.secondary)
            }
                HStack {
                    Text(isConnected ? "Live account" : "Connect in Settings")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if isConnected { Button("Refresh", action: refresh).controlSize(.small) }
                }
            }
        }
        .frame(maxWidth: 330, minHeight: 150, alignment: .leading)
    }
}

struct CursorDashboardView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var costPeriod: UsageCostsPanel.Period = .today

    var body: some View {
        DashboardPageContainer(title: "Cursor", subtitle: "Plan usage and billing details from your Cursor dashboard.") {
            if let snapshot = viewModel.cursorSnapshot {
                UsageHeroCard(
                    title: snapshot.planName,
                    percent: snapshot.primaryPercent,
                    pacePercent: snapshot.evenPacePercent,
                    resetText: snapshot.daysLeftInCycle.map { $0 == 0 ? "Resets today" : "\($0) days left" }
                )
                HStack(alignment: .top, spacing: 16) {
                    DashboardSection(title: "Usage costs", subtitle: "Billed and included value") {
                        UsageCostsPanel(
                            period: $costPeriod,
                            billedCents: costPeriod == .today ? (snapshot.todayChargeableCents ?? 0) : (snapshot.chargeableCents ?? 0),
                            includedCents: costPeriod == .today ? (snapshot.todayIncludedUsageValueCents ?? 0) : (snapshot.includedUsageValueCents ?? 0),
                            requestCount: costPeriod == .today ? snapshot.todayEventCount : snapshot.cycleCostEventCount,
                            isLoaded: costPeriod == .today ? snapshot.todayCostsLoaded : snapshot.cycleCostsLoaded,
                            unavailableTitle: "Usage costs unavailable",
                            unavailableIcon: "chart.bar.xaxis",
                            unavailableInfo: "Refresh to retry loading event costs."
                        ).padding(.top, 2)
                    }
                    if snapshot.apiPercentUsed != nil || snapshot.autoPercentUsed != nil {
                        DashboardSection(title: "Model split", subtitle: "Usage by routing mode") {
                            ModelSplitPanel(apiPercent: snapshot.apiPercentUsed, autoPercent: snapshot.autoPercentUsed).padding(.top, 2)
                        }
                    }
                }
            } else {
                ServiceEmptyState(service: .cursor, connected: SessionTokenStore.hasToken, error: viewModel.cursorError) { Task { await viewModel.refreshCursor() } }
            }
        }
    }
}

struct CodexDashboardView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        DashboardPageContainer(title: "Codex", subtitle: "Experimental usage data from your ChatGPT-authenticated Codex account.") {
            if let snapshot = viewModel.codexSnapshot {
                if let percent = snapshot.primaryPercent {
                    UsageHeroCard(
                        title: snapshot.planName,
                        percent: percent,
                        pacePercent: snapshot.primaryWindow?.evenPacePercent(),
                        resetText: snapshot.primaryWindow?.resetDescription.map { "Resets \($0)" }
                    )
                }
                HStack(spacing: 16) {
                    CodexMetricCard(title: "Primary window", value: snapshot.primaryPercent.map { "\(Int($0.rounded()))% used" } ?? "Unavailable", icon: "gauge.with.dots.needle.67percent")
                    CodexMetricCard(title: "Secondary window", value: snapshot.secondaryWindow.map { "\(Int($0.usedPercent.rounded()))% used" } ?? "Not reported", icon: "calendar")
                    CodexMetricCard(title: "Credits", value: snapshot.creditsRemaining.map { $0.formatted() } ?? "Not reported", icon: "creditcard")
                }
                if !snapshot.isAllowed {
                    Label("Codex reports that this account is currently limited.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } else {
                ServiceEmptyState(service: .codex, connected: CodexTokenStore.hasCredentials, error: viewModel.codexError) { Task { await viewModel.refreshCodex() } }
            }
        }
    }
}

struct UsageHeroCard: View {
    let title: String
    let percent: Double
    var pacePercent: Double? = nil
    let resetText: String?

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label(title, systemImage: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(percent >= 90 ? "Near limit" : percent >= 70 ? "Watch usage" : "On track")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.usageColor(percent: percent))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.usageColor(percent: percent).opacity(0.12), in: Capsule())
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(UsageSnapshot.formatPercent(percent)).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("used").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 7) {
                    if pacePercent != nil {
                        UsageProgressBar(progress: percent, pacePercent: pacePercent, tint: Theme.usageColor(percent: percent))
                    } else {
                        ProgressView(value: min(max(percent, 0), 100), total: 100).tint(Theme.usageColor(percent: percent))
                    }
                    HStack {
                        Text("0%").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                        Spacer()
                        if let pacePercent { Text(paceLabel(pacePercent)).font(.system(size: 11)).foregroundStyle(.secondary) }
                        else if let resetText { Text(resetText).font(.system(size: 11)).foregroundStyle(.secondary) }
                        Spacer()
                        Text("100%").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                    }
                    if pacePercent != nil, let resetText {
                        Text(resetText).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paceLabel(_ pace: Double) -> String {
        let difference = percent - pace
        if abs(difference) < 1 { return "On even pace" }
        return difference > 0
            ? "\(UsageSnapshot.formatPercent(difference)) ahead of pace"
            : "\(UsageSnapshot.formatPercent(abs(difference))) behind pace"
    }
}

private struct CodexMetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        DashboardCard {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30).background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline).monospacedDigit()
            }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ServiceEmptyState: View {
    let service: TrackedService
    let connected: Bool
    let error: String?
    let refresh: () -> Void

    var body: some View {
        DashboardEmptyState(
            title: connected ? "Usage unavailable" : "Connect \(service.title)",
            message: error ?? "Connect this service in Settings to see its usage.",
            icon: connected ? "exclamationmark.triangle" : "link.badge.plus",
            actionTitle: connected ? "Try again" : nil,
            action: connected ? refresh : nil
        )
    }
}

private struct DashboardEmptyState: View {
    let title: String
    let message: String
    let icon: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Theme.accent)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.bordered) }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct SettingsDashboardView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        DashboardPageContainer(title: "Settings", subtitle: "Connections and app preferences.") {
            DashboardSection(title: "Menu bar", subtitle: "Choose the service shown in the menu bar") {
                Picker("Display", selection: $viewModel.selectedService) {
                    ForEach(TrackedService.allCases) { service in Text(service.title).tag(service) }
                }
                .pickerStyle(.segmented)
            }
            DashboardSection(title: "Cursor", subtitle: "Dashboard session connection") { cursorSettings }
            DashboardSection(title: "Codex", subtitle: "Experimental ChatGPT account connection") { codexSettings }
            DashboardSection(title: "App", subtitle: "Background behavior and launch preferences") { appSettings }
            DashboardSection(title: "Updates", subtitle: "Version and release installation") { updateSettings }
        }
    }

    private var cursorSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            CredentialGuide(service: .cursor)
            SecureField("WorkosCursorSessionToken", text: $viewModel.cursorTokenInput)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                Button(SessionTokenStore.hasToken ? "Replace Cursor token" : "Save Cursor token") { Task { await viewModel.saveCursorToken() } }
                    .buttonStyle(.borderedProminent)
                if SessionTokenStore.hasToken { Button("Remove", role: .destructive) { viewModel.removeCursorConnection() }.buttonStyle(.bordered) }
                if let error = viewModel.cursorSaveError { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Text("Saved locally with owner-only permissions.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var codexSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            CredentialGuide(service: .codex)
            SecureField("OAuth access token", text: $viewModel.codexAccessTokenInput)
                .textFieldStyle(.roundedBorder)
            TextField("ChatGPT account/workspace ID (optional)", text: $viewModel.codexAccountIDInput)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                Button(CodexTokenStore.hasCredentials ? "Replace Codex credentials" : "Save Codex credentials") { Task { await viewModel.saveCodexCredentials() } }
                    .buttonStyle(.borderedProminent)
                if CodexTokenStore.hasCredentials { Button("Remove", role: .destructive) { viewModel.removeCodexConnection() }.buttonStyle(.bordered) }
                if let error = viewModel.codexSaveError { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Text("This is an unsupported integration and may stop working if ChatGPT changes its internal endpoint.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var appSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Auto-refresh", selection: $viewModel.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in Text("Every \(interval.label)").tag(interval) }
            }
            Toggle("Start at Login", isOn: Binding(get: { viewModel.launchAtLoginEnabled }, set: { viewModel.setLaunchAtLoginEnabled($0) }))
            Toggle("Keep Mac awake while running", isOn: Binding(get: { viewModel.caffeinateEnabled }, set: { viewModel.setCaffeinateEnabled($0) }))
            Text("Version \(AppVersion.current)").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var updateSettings: some View {
        switch viewModel.updateViewModel.phase {
        case .available(let update):
            HStack {
                Text("Version \(update.version) is available.")
                Spacer()
                Button("Install Update") { Task { await viewModel.updateViewModel.installUpdate() } }
                    .buttonStyle(.borderedProminent)
            }
        case .downloading:
            Label("Downloading update…", systemImage: "arrow.down.circle")
        case .installing:
            Label("Installing update…", systemImage: "arrow.triangle.2.circlepath")
        case .failed(let error):
            VStack(alignment: .leading, spacing: 8) {
                Text(error).foregroundStyle(.red)
                Button("Check Again") { Task { await viewModel.updateViewModel.checkForUpdates(force: true) } }
            }
        case .idle, .checking:
            HStack {
                Text("You’re running version \(AppVersion.current).").foregroundStyle(.secondary)
                Spacer()
                Button("Check for Updates") { Task { await viewModel.updateViewModel.checkForUpdates(force: true) } }
            }
        }
    }
}

private struct CredentialGuide: View {
    let service: TrackedService

    private static let cursorDashboardURL = URL(string: "https://cursor.com/dashboard/usage")!
    private static let codexURL = URL(string: "https://chatgpt.com/codex")!

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                switch service {
                case .cursor: cursorSteps
                case .codex: codexSteps
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        } label: {
            Label("How to connect \(service.title)", systemImage: "list.number")
                .font(.system(size: 12, weight: .semibold))
        }
        .tint(Theme.accent)
    }

    private var cursorSteps: some View {
        Group {
            credentialStep(1, "Open Cursor’s usage dashboard", "Sign in to Cursor in your browser.") {
                Button("Open Cursor Dashboard") { NSWorkspace.shared.open(Self.cursorDashboardURL) }
                    .controlSize(.small)
            }
            credentialStep(2, "Open Developer Tools", "Press ⌥⌘I in Chrome, then choose Application → Storage → Cookies → cursor.com.")
            credentialStep(3, "Copy the cookie value", "Copy the value named WorkosCursorSessionToken, then paste it below.")
        }
    }

    private var codexSteps: some View {
        Group {
            credentialStep(1, "Sign in to Codex", "Use your ChatGPT account in Codex first, so it creates a local OAuth session.") {
                Button("Open Codex") { NSWorkspace.shared.open(Self.codexURL) }
                    .controlSize(.small)
            }
            credentialStep(2, "Locate your Codex OAuth record", "For Codex CLI, open ~/.codex/auth.json. This app never reads that file automatically.")
            credentialStep(3, "Copy your access token", "Paste tokens.access_token below. If tokens.account_id is present, add it to the optional Account ID field.")
            Label("Use an OAuth access token—not a browser cookie.", systemImage: "lock.shield")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.warning)
                .padding(.leading, 30)
        }
    }

    private func credentialStep<Accessory: View>(
        _ number: Int,
        _ title: String,
        _ detail: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Theme.accent, in: Circle())
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                accessory()
            }
        }
    }
}
