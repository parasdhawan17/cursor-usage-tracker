import Foundation

struct UsageSnapshot: Equatable {
    /// Primary metric: included used ÷ limit (what users expect).
    let includedPercent: Double
    let used: Int
    let limit: Int
    let remaining: Int
    let planName: String
    let billingStart: String
    let billingEnd: String
    let daysLeftInCycle: Int?
    let fetchedAt: Date

    let breakdownIncluded: Int?
    let breakdownBonus: Int?
    let breakdownTotal: Int?
    let apiPercentUsed: Double?
    let autoPercentUsed: Double?
    let dashboardTotalPercent: Double?

    let onDemandEnabled: Bool
    let onDemandUsed: Int?
    let isUnlimited: Bool
    let statusMessage: String?

    /// On-demand / usage-based spend this cycle (actual bill), from usage events.
    let chargeableCents: Double?
    /// Notional token value of included-plan usage this cycle (not billed separately).
    let includedUsageValueCents: Double?
    /// Whether cycle cost totals were loaded from the events API.
    let cycleCostsLoaded: Bool
    let cycleCostEventCount: Int?

    /// On-demand spend today (local calendar day).
    let todayChargeableCents: Double?
    /// Notional token value of included-plan usage today.
    let todayIncludedUsageValueCents: Double?
    let todayCostsLoaded: Bool
    let todayEventCount: Int?

    /// Dashboard “total usage” (totalPercentUsed) — matches Cursor’s main usage message.
    var primaryPercent: Double {
        if isUnlimited { return 0 }
        if let total = dashboardTotalPercent { return min(100, total) }
        return includedPercent
    }

    var menuBarLabel: String {
        if isUnlimited { return "∞" }
        return Self.formatPercent(primaryPercent)
    }

    var menuBarToolTip: String {
        if isUnlimited { return "Cursor Usage — Unlimited plan" }
        var lines = ["Plan usage: \(Self.formatPercent(primaryPercent))"]
        if let days = daysLeftInCycle {
            lines.append("\(days) day\(days == 1 ? "" : "s") left in cycle")
        }
        return lines.joined(separator: "\n")
    }

    static func formatPercent(_ p: Double) -> String {
        if p >= 100 { return "100%" }
        if p >= 10 { return "\(Int(p.rounded()))%" }
        return String(format: "%.1f%%", p)
    }

    /// Full-precision dollars for the panel and tooltips.
    static func formatDollarsFull(_ cents: Double) -> String {
        let dollars = cents / 100
        if dollars >= 100 { return String(format: "$%.2f", dollars) }
        if dollars >= 1 { return String(format: "$%.2f", dollars) }
        if cents >= 0.005 { return String(format: "$%.2f", dollars) }
        return "$0.00"
    }

    /// Expected usage % if 100% were spread evenly across the billing cycle (velocity target for today).
    var evenPacePercent: Double? {
        guard !isUnlimited,
              let start = Self.parseISO8601(billingStart),
              let end = Self.parseISO8601(billingEnd),
              end > start
        else { return nil }

        let now = min(Date(), end)
        let calendar = Calendar.current
        let totalDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        guard totalDays > 0 else { return nil }

        let elapsedDays = calendar.dateComponents([.day], from: start, to: now).day ?? 0
        let elapsed = min(max(0, elapsedDays), totalDays)
        return min(100, (Double(elapsed) / Double(totalDays)) * 100)
    }

    static func parseISO8601(_ iso: String) -> Date? {
        guard !iso.isEmpty, iso != "—" else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: iso) { return d }
        return ISO8601DateFormatter().date(from: iso)
    }
}

enum UsageFetcherError: LocalizedError {
    case missingToken
    case unauthorized
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Add your session token in the menu bar panel (gear icon)."
        case .unauthorized:
            return "Session expired. Open Session settings and save a new token."
        case .invalidResponse:
            return "Could not parse usage data."
        case .network(let msg):
            return msg
        }
    }
}

enum UsageFetcher {
    private static let base = URL(string: "https://cursor.com")!
    private static let cookieName = "WorkosCursorSessionToken"

    static func loadToken() -> String? {
        SessionTokenStore.load()
    }

    static func fetch() async throws -> UsageSnapshot {
        try await fetchOffMainActor()
    }

    /// Network + JSON parsing off the main actor so the menu bar UI stays responsive.
    static func fetchOffMainActor() async throws -> UsageSnapshot {
        try await Task.detached(priority: .utility) {
            try await fetchImpl()
        }.value
    }

    private static func fetchImpl() async throws -> UsageSnapshot {
        guard let token = loadToken() else { throw UsageFetcherError.missingToken }

        var request = URLRequest(url: base.appendingPathComponent("api/usage-summary"))
        request.setValue("\(cookieName)=\(token)", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 20

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageFetcherError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageFetcherError.invalidResponse
        }
        if http.statusCode == 401 { throw UsageFetcherError.unauthorized }
        guard http.statusCode == 200 else {
            throw UsageFetcherError.network("HTTP \(http.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageFetcherError.invalidResponse
        }

        let snapshot = try parseSummary(json)
        async let cycleCosts = fetchEventCosts(
            token: token,
            from: UsageSnapshot.parseISO8601(snapshot.billingStart),
            to: min(Date(), UsageSnapshot.parseISO8601(snapshot.billingEnd) ?? Date())
        )
        async let todayCosts = fetchTodayCosts(token: token)
        return mergeCosts(
            into: snapshot,
            cycle: try? await cycleCosts,
            today: try? await todayCosts
        )
    }

    private struct CostTotals {
        let chargeableCents: Double
        let includedUsageValueCents: Double
        let eventCount: Int
    }

    private static func fetchTodayCosts(token: String) async throws -> CostTotals {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = Date()
        return try await fetchEventCosts(token: token, from: start, to: end)
    }

    private static func fetchEventCosts(
        token: String,
        from start: Date?,
        to end: Date?
    ) async throws -> CostTotals {
        guard let start, let end, end >= start else {
            throw UsageFetcherError.invalidResponse
        }

        let startMs = String(Int(start.timeIntervalSince1970 * 1000))
        let endMs = String(Int(end.timeIntervalSince1970 * 1000))

        let pageSize = 100
        var page = 1
        var fetched = 0
        var totalEvents = 0
        var chargeableCents = 0.0
        var includedValueCents = 0.0

        repeat {
            let payload: [String: Any] = [
                "startDate": startMs,
                "endDate": endMs,
                "page": page,
                "pageSize": pageSize,
            ]
            let events = try await postUsageEvents(token: token, json: payload)
            if page == 1 {
                totalEvents = events["totalUsageEventsCount"] as? Int ?? 0
            }
            let list = events["usageEventsDisplay"] as? [[String: Any]] ?? []
            if list.isEmpty { break }

            for event in list {
                fetched += 1
                let cents = doubleValue(event["chargedCents"]) ?? 0
                if isBillableEvent(event) {
                    chargeableCents += cents
                } else if isIncludedUsageEvent(event) {
                    includedValueCents += cents
                }
            }

            if fetched >= totalEvents || list.count < pageSize { break }
            page += 1
            if page > 500 { break }
        } while true

        return CostTotals(
            chargeableCents: chargeableCents,
            includedUsageValueCents: includedValueCents,
            eventCount: totalEvents
        )
    }

    private static func postUsageEvents(token: String, json: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: base.appendingPathComponent("api/dashboard/get-filtered-usage-events"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("\(cookieName)=\(token)", forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        request.timeoutInterval = 60

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageFetcherError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageFetcherError.invalidResponse
        }
        if http.statusCode == 401 { throw UsageFetcherError.unauthorized }
        guard http.statusCode == 200 else {
            throw UsageFetcherError.network("HTTP \(http.statusCode)")
        }

        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageFetcherError.invalidResponse
        }
        return parsed
    }

    private static func isBillableEvent(_ event: [String: Any]) -> Bool {
        let kind = event["kind"] as? String ?? ""
        if kind == "USAGE_EVENT_KIND_USAGE_BASED" { return true }
        if let costs = event["usageBasedCosts"] as? String {
            let trimmed = costs.trimmingCharacters(in: .whitespaces)
            return trimmed != "-" && trimmed != "$0.00" && !trimmed.isEmpty
        }
        return false
    }

    private static func isIncludedUsageEvent(_ event: [String: Any]) -> Bool {
        let kind = event["kind"] as? String ?? ""
        if kind.contains("ERRORED") { return false }
        if isBillableEvent(event) { return false }
        if kind.contains("INCLUDED") || kind.contains("FREE_CREDIT") { return true }
        return event["isChargeable"] as? Bool != true
    }

    private static func parseSummary(_ json: [String: Any]) throws -> UsageSnapshot {
        let plan = (json["individualUsage"] as? [String: Any])?["plan"] as? [String: Any] ?? [:]
        let onDemand = (json["individualUsage"] as? [String: Any])?["onDemand"] as? [String: Any]
        let breakdown = plan["breakdown"] as? [String: Any]

        let used = plan["used"] as? Int ?? 0
        let limit = plan["limit"] as? Int ?? 0
        let remaining = plan["remaining"] as? Int ?? max(0, limit - used)

        let includedPercent: Double
        if json["isUnlimited"] as? Bool == true {
            includedPercent = 0
        } else if limit > 0 {
            includedPercent = min(100, (Double(used) / Double(limit)) * 100)
        } else {
            includedPercent = 0
        }

        let billingEnd = json["billingCycleEnd"] as? String ?? ""
        let daysLeft = daysUntilCycleEnd(billingEnd)

        let statusParts = [
            json["namedModelSelectedDisplayMessage"] as? String,
            json["autoModelSelectedDisplayMessage"] as? String,
        ].compactMap { $0 }.filter { !$0.isEmpty }
        let statusMessage = statusParts.isEmpty ? nil : statusParts.joined(separator: "\n")

        return UsageSnapshot(
            includedPercent: includedPercent,
            used: used,
            limit: limit,
            remaining: remaining,
            planName: (json["membershipType"] as? String ?? "unknown").capitalized,
            billingStart: json["billingCycleStart"] as? String ?? "—",
            billingEnd: billingEnd.isEmpty ? "—" : billingEnd,
            daysLeftInCycle: daysLeft,
            fetchedAt: Date(),
            breakdownIncluded: breakdown?["included"] as? Int,
            breakdownBonus: breakdown?["bonus"] as? Int,
            breakdownTotal: breakdown?["total"] as? Int,
            apiPercentUsed: doubleValue(plan["apiPercentUsed"]),
            autoPercentUsed: doubleValue(plan["autoPercentUsed"]),
            dashboardTotalPercent: doubleValue(plan["totalPercentUsed"]),
            onDemandEnabled: onDemand?["enabled"] as? Bool ?? false,
            onDemandUsed: onDemand?["enabled"] as? Bool == true ? (onDemand?["used"] as? Int) : nil,
            isUnlimited: json["isUnlimited"] as? Bool ?? false,
            statusMessage: statusMessage,
            chargeableCents: nil,
            includedUsageValueCents: nil,
            cycleCostsLoaded: false,
            cycleCostEventCount: nil,
            todayChargeableCents: nil,
            todayIncludedUsageValueCents: nil,
            todayCostsLoaded: false,
            todayEventCount: nil
        )
    }

    private static func mergeCosts(
        into snapshot: UsageSnapshot,
        cycle: CostTotals?,
        today: CostTotals?
    ) -> UsageSnapshot {
        UsageSnapshot(
            includedPercent: snapshot.includedPercent,
            used: snapshot.used,
            limit: snapshot.limit,
            remaining: snapshot.remaining,
            planName: snapshot.planName,
            billingStart: snapshot.billingStart,
            billingEnd: snapshot.billingEnd,
            daysLeftInCycle: snapshot.daysLeftInCycle,
            fetchedAt: snapshot.fetchedAt,
            breakdownIncluded: snapshot.breakdownIncluded,
            breakdownBonus: snapshot.breakdownBonus,
            breakdownTotal: snapshot.breakdownTotal,
            apiPercentUsed: snapshot.apiPercentUsed,
            autoPercentUsed: snapshot.autoPercentUsed,
            dashboardTotalPercent: snapshot.dashboardTotalPercent,
            onDemandEnabled: snapshot.onDemandEnabled,
            onDemandUsed: snapshot.onDemandUsed,
            isUnlimited: snapshot.isUnlimited,
            statusMessage: snapshot.statusMessage,
            chargeableCents: cycle?.chargeableCents,
            includedUsageValueCents: cycle?.includedUsageValueCents,
            cycleCostsLoaded: cycle != nil,
            cycleCostEventCount: cycle?.eventCount,
            todayChargeableCents: today?.chargeableCents,
            todayIncludedUsageValueCents: today?.includedUsageValueCents,
            todayCostsLoaded: today != nil,
            todayEventCount: today?.eventCount
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    private static func daysUntilCycleEnd(_ isoEnd: String) -> Int? {
        guard !isoEnd.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let end = f.date(from: isoEnd) ?? ISO8601DateFormatter().date(from: isoEnd)
        guard let end else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: end).day
        return max(0, days ?? 0)
    }
}
