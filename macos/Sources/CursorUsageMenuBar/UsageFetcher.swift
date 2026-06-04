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

    static func formatPercent(_ p: Double) -> String {
        if p >= 100 { return "100%" }
        if p >= 10 { return "\(Int(p.rounded()))%" }
        return String(format: "%.1f%%", p)
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
        guard let token = loadToken() else { throw UsageFetcherError.missingToken }

        var request = URLRequest(url: base.appendingPathComponent("api/usage-summary"))
        request.setValue("\(cookieName)=\(token)", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 30

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

        return try parseSummary(json)
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
            statusMessage: statusMessage
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
