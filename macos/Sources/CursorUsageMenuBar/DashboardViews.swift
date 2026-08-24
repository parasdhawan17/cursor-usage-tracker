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
                List(selection: $navigation.page) {
                    Section("Monitor") {
                        ForEach([DashboardPage.overview, .cursor, .codex]) { page in
                            Label {
                                Text(page.title)
                            } icon: {
                                Image(systemName: page.icon).foregroundStyle(page.tint)
                            }
                            .tag(page)
                        }
                    }
                    Section("Configuration") {
                        Label(DashboardPage.settings.title, systemImage: DashboardPage.settings.icon)
                            .tag(DashboardPage.settings)
                    }
                }
                .listStyle(.sidebar)

                VStack(alignment: .leading, spacing: 9) {
                    Text("CONNECTIONS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .tracking(0.5)
                    connectionRow(.cursor, connected: SessionTokenStore.hasToken)
                    connectionRow(.codex, connected: CodexTokenStore.hasCredentials)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) { Divider().opacity(0.55) }
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
                .disabled(viewModel.isCursorLoading || viewModel.isCodexLoading)
                .keyboardShortcut("r", modifiers: [.command])
                .help("Refresh all services (⌘R)")
            }
        }
        .background(Theme.dashboardBackground)
    }

    private func connectionRow(_ service: TrackedService, connected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: connected ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(connected ? Theme.includedValue : Theme.textTertiary)
            Text(service.title).font(.system(size: 10, weight: .medium))
            Spacer()
            Text(connected ? "Connected" : "Set up")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

private struct DashboardPageContainer<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        icon: String = "chart.line.uptrend.xyaxis",
        tint: Color = Theme.accent,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 14) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .overlay(Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint))
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
        .background(Theme.dashboardBackground)
    }
}

struct DashboardCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .background(Theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.24), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.035), radius: 1.5, y: 1)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OverviewDashboardView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        DashboardPageContainer(
            title: "Overview",
            subtitle: "A live view of your connected coding plans.",
            icon: DashboardPage.overview.icon,
            tint: DashboardPage.overview.tint
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 16)], alignment: .leading, spacing: 16) {
                OverviewServiceCard(
                    service: .cursor,
                    isConnected: SessionTokenStore.hasToken,
                    plan: viewModel.cursorSnapshot?.planName,
                    percent: viewModel.cursorSnapshot?.primaryPercent,
                    detail: cursorDetail,
                    fetchedAt: viewModel.cursorSnapshot?.fetchedAt,
                    error: viewModel.cursorError
                ) {
                    Task { await viewModel.refreshCursor() }
                }
                OverviewServiceCard(
                    service: .codex,
                    isConnected: CodexTokenStore.hasCredentials,
                    plan: viewModel.codexSnapshot?.planName,
                    percent: viewModel.codexSnapshot?.primaryPercent,
                    detail: codexDetail,
                    fetchedAt: viewModel.codexSnapshot?.fetchedAt,
                    error: viewModel.codexError
                ) {
                    Task { await viewModel.refreshCodex() }
                }
            }

            if viewModel.hasAnyConnection {
                DashboardCard {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Monitoring automatically").font(.system(size: 12, weight: .semibold))
                            Text("Usage refreshes every \(viewModel.refreshInterval.label). You can also refresh anytime with ⌘R.")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(text: "Live", color: Theme.includedValue)
                    }
                }
            }

            if !viewModel.hasAnyConnection {
                DashboardEmptyState(
                    title: "Connect an account",
                    message: "Open Settings to connect Cursor or the experimental Codex integration.",
                    icon: "link.badge.plus"
                )
            }
        }
    }

    private var cursorDetail: String? {
        guard let snapshot = viewModel.cursorSnapshot else { return nil }
        if let days = snapshot.daysLeftInCycle {
            return days == 0 ? "Billing cycle resets today" : "\(days) days left in this billing cycle"
        }
        return snapshot.onDemandEnabled ? "On-demand usage enabled" : "Included plan usage"
    }

    private var codexDetail: String? {
        guard let snapshot = viewModel.codexSnapshot else { return nil }
        if let reset = snapshot.primaryWindow?.resetDescription { return "Primary window resets \(reset)" }
        return snapshot.isAllowed ? "Codex is currently available" : "Codex is currently limited"
    }
}

private struct OverviewServiceCard: View {
    let service: TrackedService
    let isConnected: Bool
    let plan: String?
    let percent: Double?
    let detail: String?
    let fetchedAt: Date?
    let error: String?
    let refresh: () -> Void

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ServiceIcon(service: service, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(service.title).font(.system(size: 13, weight: .semibold))
                        Text(plan ?? (isConnected ? "Connected plan" : "No account"))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: isConnected ? "Connected" : "Set up", color: isConnected ? Theme.includedValue : Theme.textTertiary)
                }

                if let percent {
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(UsageSnapshot.formatPercent(percent))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("used").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                    ProgressView(value: percent, total: 100)
                        .tint(Theme.usageColor(percent: percent))
                    Text(detail ?? "Plan usage is available.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else if isConnected {
                    Label(error ?? "Loading usage…", systemImage: error == nil ? "clock" : "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(error == nil ? Color.secondary : Theme.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Connect this service in Settings to include it in your overview.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.55)
                HStack(spacing: 6) {
                    if let fetchedAt {
                        Image(systemName: "clock")
                        Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text(isConnected ? "Waiting for data" : "Connection required")
                    }
                    Spacer()
                    if isConnected {
                        Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                            .help("Refresh \(service.title)")
                    }
                }
                .font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
    }
}

struct CursorDashboardView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var costPeriod: UsageCostsPanel.Period = .today

    var body: some View {
        DashboardPageContainer(
            title: "Cursor",
            subtitle: "Plan balance, billing, and model routing.",
            icon: DashboardPage.cursor.icon,
            tint: DashboardPage.cursor.tint
        ) {
            if let snapshot = viewModel.cursorSnapshot {
                UsageHeroCard(
                    title: snapshot.planName,
                    percent: snapshot.primaryPercent,
                    pacePercent: snapshot.evenPacePercent,
                    resetText: snapshot.daysLeftInCycle.map { $0 == 0 ? "Resets today" : "Resets in \($0) days" },
                    updatedAt: snapshot.fetchedAt
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                    DashboardMetricCard(title: "Included used", value: snapshot.used.formatted(), detail: "of \(snapshot.limit.formatted())", icon: "chart.bar.fill", tint: Theme.apiModels)
                    DashboardMetricCard(title: "Included left", value: snapshot.remaining.formatted(), detail: "plan units", icon: "arrow.down.circle", tint: Theme.includedValue)
                    DashboardMetricCard(title: "Requests today", value: snapshot.todayEventCount?.formatted() ?? "—", detail: "since midnight", icon: "arrow.left.arrow.right", tint: Theme.accent)
                    DashboardMetricCard(title: "On-demand", value: snapshot.onDemandEnabled ? "Enabled" : "Off", detail: snapshot.onDemandUsed.map { "\($0.formatted()) used" } ?? "usage billing", icon: "creditcard", tint: snapshot.onDemandEnabled ? Theme.warning : Theme.textTertiary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], alignment: .leading, spacing: 16) {
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
        DashboardPageContainer(
            title: "Codex",
            subtitle: "Rate-limit windows and account availability.",
            icon: DashboardPage.codex.icon,
            tint: DashboardPage.codex.tint
        ) {
            if let snapshot = viewModel.codexSnapshot {
                if let percent = snapshot.primaryPercent {
                    UsageHeroCard(
                        title: snapshot.planName,
                        percent: percent,
                        pacePercent: snapshot.primaryWindow?.evenPacePercent(),
                        resetText: snapshot.primaryWindow?.resetDescription.map { "Resets \($0)" },
                        updatedAt: snapshot.fetchedAt
                    )
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    if let window = snapshot.primaryWindow {
                        DashboardMetricCard(
                            title: window.windowDescription.map { "\($0) window" } ?? "Current window",
                            value: "\(Int(window.usedPercent.rounded()))% used",
                            detail: window.resetCountdown().map { "Resets in \($0)" } ?? "Reset not reported",
                            icon: "gauge.with.dots.needle.67percent",
                            tint: Theme.autoModels
                        )
                        DashboardMetricCard(
                            title: "Allowance left",
                            value: UsageSnapshot.formatPercent(window.remainingPercent),
                            detail: "in the current window",
                            icon: "arrow.down.circle",
                            tint: Theme.includedValue
                        )
                    }
                    if let today = viewModel.codexTodayUsage {
                        DashboardMetricCard(
                            title: "Observed today",
                            value: today.displayValue,
                            detail: "since \(today.firstObservedAt.formatted(date: .omitted, time: .shortened))",
                            icon: "sun.max.fill",
                            tint: Theme.warning
                        )
                    }
                    if let secondary = snapshot.secondaryWindow {
                        DashboardMetricCard(
                            title: secondary.windowDescription.map { "\($0) window" } ?? "Secondary window",
                            value: "\(Int(secondary.usedPercent.rounded()))% used",
                            detail: secondary.resetCountdown().map { "Resets in \($0)" } ?? "Reset not reported",
                            icon: "calendar",
                            tint: Theme.apiModels
                        )
                    }
                    if snapshot.creditsUnlimited || (snapshot.creditsRemaining ?? 0) > 0 {
                        DashboardMetricCard(
                            title: "Credits",
                            value: snapshot.creditsUnlimited ? "Unlimited" : snapshot.creditsRemaining?.formatted() ?? "—",
                            detail: "remaining balance",
                            icon: "creditcard",
                            tint: Theme.includedValue
                        )
                    }
                }
                if !snapshot.isAllowed {
                    DashboardCard {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Codex is currently limited").font(.system(size: 12, weight: .semibold))
                                Text("The service reported that this account cannot start additional work until its allowance resets.")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
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
    var updatedAt: Date? = nil

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
                    if pacePercent != nil || updatedAt != nil {
                        HStack {
                            if pacePercent != nil, let resetText {
                                Label(resetText, systemImage: "calendar")
                            }
                            Spacer()
                            if let updatedAt {
                                Label("Updated \(updatedAt.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
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

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        DashboardCard {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 30, height: 30).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(detail).font(.system(size: 9)).foregroundStyle(Theme.textTertiary).lineLimit(1)
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
        DashboardPageContainer(
            title: "Settings",
            subtitle: "Connections, refresh behavior, and app preferences.",
            icon: DashboardPage.settings.icon,
            tint: DashboardPage.settings.tint
        ) {
            DashboardSection(title: "Menu bar", subtitle: "Choose the service shown in the menu bar") {
                HStack(spacing: 12) {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30).background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Displayed service").font(.system(size: 12, weight: .medium))
                        Text("Its icon and current usage stay visible in the menu bar.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Display", selection: $viewModel.selectedService) {
                        ForEach(TrackedService.allCases) { service in Text(service.title).tag(service) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            DashboardSection(title: "Cursor", subtitle: "Dashboard session connection") { cursorSettings }
            DashboardSection(title: "Codex", subtitle: "Experimental ChatGPT account connection") { codexSettings }
            DashboardSection(title: "App", subtitle: "Background behavior and launch preferences") { appSettings }
            DashboardSection(title: "Updates", subtitle: "Version and release installation") { updateSettings }
        }
    }

    private var cursorSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            connectionHeader(service: .cursor, connected: SessionTokenStore.hasToken, detail: "Cursor dashboard session")
            Divider().opacity(0.55)
            CredentialGuide(service: .cursor)
            SettingsFieldLabel(title: "Session token", detail: "WorkosCursorSessionToken")
            SecureField("WorkosCursorSessionToken", text: $viewModel.cursorTokenInput)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                Button(SessionTokenStore.hasToken ? "Replace Cursor token" : "Save Cursor token") { Task { await viewModel.saveCursorToken() } }
                    .buttonStyle(.borderedProminent)
                if SessionTokenStore.hasToken { Button("Remove", role: .destructive) { viewModel.removeCursorConnection() }.buttonStyle(.bordered) }
            }
            if let error = viewModel.cursorSaveError { InlineNotice(text: error, icon: "exclamationmark.triangle.fill", color: Theme.destructive) }
            InlineNotice(text: "Stored locally on this Mac with owner-only permissions.", icon: "lock.fill", color: Theme.textSecondary)
        }
    }

    private var codexSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            connectionHeader(service: .codex, connected: CodexTokenStore.hasCredentials, detail: "Experimental ChatGPT connection")
            Divider().opacity(0.55)
            CredentialGuide(service: .codex)
            SettingsFieldLabel(title: "OAuth access token", detail: "Required")
            SecureField("OAuth access token", text: $viewModel.codexAccessTokenInput)
                .textFieldStyle(.roundedBorder)
            SettingsFieldLabel(title: "Account or workspace ID", detail: "Optional")
            TextField("ChatGPT account/workspace ID (optional)", text: $viewModel.codexAccountIDInput)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                Button(CodexTokenStore.hasCredentials ? "Replace Codex credentials" : "Save Codex credentials") { Task { await viewModel.saveCodexCredentials() } }
                    .buttonStyle(.borderedProminent)
                if CodexTokenStore.hasCredentials { Button("Remove", role: .destructive) { viewModel.removeCodexConnection() }.buttonStyle(.bordered) }
            }
            if let error = viewModel.codexSaveError { InlineNotice(text: error, icon: "exclamationmark.triangle.fill", color: Theme.destructive) }
            InlineNotice(text: "This unsupported integration depends on an internal endpoint and may change without notice.", icon: "flask.fill", color: Theme.warning)
        }
    }

    private var appSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                PreferenceIcon(symbol: "arrow.clockwise", color: Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-refresh").font(.system(size: 12, weight: .medium))
                    Text("Keep menu-bar usage current in the background.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Auto-refresh", selection: $viewModel.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in Text("Every \(interval.label)").tag(interval) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            .padding(.vertical, 6)
            Divider().padding(.leading, 42)
            PreferenceToggleRow(
                icon: "power",
                color: Theme.includedValue,
                title: "Start at Login",
                detail: "Launch quietly and keep the tracker in the menu bar.",
                isOn: Binding(get: { viewModel.launchAtLoginEnabled }, set: { viewModel.setLaunchAtLoginEnabled($0) })
            )
            Divider().padding(.leading, 42)
            PreferenceToggleRow(
                icon: "moon.zzz.fill",
                color: Theme.autoModels,
                title: "Keep Mac awake",
                detail: "Prevent system sleep while the tracker is running.",
                isOn: Binding(get: { viewModel.caffeinateEnabled }, set: { viewModel.setCaffeinateEnabled($0) })
            )
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

    private func connectionHeader(service: TrackedService, connected: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            ServiceIcon(service: service, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: connected ? "Connected" : "Not connected", color: connected ? Theme.includedValue : Theme.textTertiary)
        }
    }
}

private struct SettingsFieldLabel: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .medium))
            Spacer()
            Text(detail).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
        }
    }
}

private struct InlineNotice: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PreferenceIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 30, height: 30)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PreferenceToggleRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            PreferenceIcon(symbol: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.vertical, 8)
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
