import Foundation

struct CodexQuotaWindow: Equatable {
    let usedPercent: Double
    let resetAt: Date?
    let windowSeconds: Int?

    var resetDescription: String? {
        guard let resetAt else { return nil }
        return resetAt.formatted(date: .abbreviated, time: .shortened)
    }

    /// Expected consumed quota if this rate-limit window were used evenly from its start until now.
    func evenPacePercent(now: Date = Date()) -> Double? {
        guard let resetAt, let windowSeconds, windowSeconds > 0 else { return nil }
        let start = resetAt.addingTimeInterval(-TimeInterval(windowSeconds))
        let elapsed = min(max(now.timeIntervalSince(start), 0), TimeInterval(windowSeconds))
        return (elapsed / TimeInterval(windowSeconds)) * 100
    }
}

struct CodexUsageSnapshot: Equatable {
    let planName: String
    let primaryWindow: CodexQuotaWindow?
    let secondaryWindow: CodexQuotaWindow?
    let creditsRemaining: Double?
    let isAllowed: Bool
    let fetchedAt: Date

    var primaryPercent: Double? { primaryWindow?.usedPercent }

    var menuBarLabel: String {
        guard let primaryPercent else { return "Codex —" }
        return "Codex \(Int(primaryPercent.rounded()))%"
    }
}

enum CodexUsageFetcherError: LocalizedError {
    case missingCredentials
    case unauthorized
    case invalidResponse
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Add a Codex access token in Settings."
        case .unauthorized: return "Codex access token expired. Save a new token in Settings."
        case .invalidResponse: return "Codex returned an unrecognized usage response."
        case .unavailable(let message): return message
        }
    }
}

/// Experimental adapter for the internal usage endpoint used by ChatGPT-authenticated Codex clients.
enum CodexUsageFetcher {
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    static func fetch() async throws -> CodexUsageSnapshot {
        guard let credentials = CodexTokenStore.load() else {
            throw CodexUsageFetcherError.missingCredentials
        }

        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
        request.setValue("Cursor Usage Tracker/1.0", forHTTPHeaderField: "User-Agent")
        if let accountID = credentials.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CodexUsageFetcherError.unavailable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CodexUsageFetcherError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw CodexUsageFetcherError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw CodexUsageFetcherError.unavailable("Codex usage endpoint returned HTTP \(http.statusCode).")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageFetcherError.invalidResponse
        }
        return try parse(json: json)
    }

    static func parse(json: [String: Any], fetchedAt: Date = Date()) throws -> CodexUsageSnapshot {
        let rateLimit = json["rate_limit"] as? [String: Any] ?? json["rateLimit"] as? [String: Any]
        guard let rateLimit else { throw CodexUsageFetcherError.invalidResponse }

        let primary = parseWindow(rateLimit["primary_window"] as? [String: Any] ?? rateLimit["primaryWindow"] as? [String: Any])
        let secondary = parseWindow(rateLimit["secondary_window"] as? [String: Any] ?? rateLimit["secondaryWindow"] as? [String: Any])
        let plan = (json["plan_type"] as? String ?? json["planType"] as? String ?? "Codex").capitalized
        let allowed = rateLimit["allowed"] as? Bool ?? !(rateLimit["limit_reached"] as? Bool ?? false)
        let credits = json["credits"] as? [String: Any]

        return CodexUsageSnapshot(
            planName: plan,
            primaryWindow: primary,
            secondaryWindow: secondary,
            creditsRemaining: numeric(credits?["remaining"]) ?? numeric(credits?["balance"]),
            isAllowed: allowed,
            fetchedAt: fetchedAt
        )
    }

    private static func parseWindow(_ json: [String: Any]?) -> CodexQuotaWindow? {
        guard let json, let used = numeric(json["used_percent"] ?? json["usedPercent"]) else { return nil }
        let reset = numeric(json["reset_at"] ?? json["resetAt"]).map { Date(timeIntervalSince1970: $0) }
        let duration = numeric(json["limit_window_seconds"] ?? json["limitWindowSeconds"]).map(Int.init)
        return CodexQuotaWindow(usedPercent: min(max(used, 0), 100), resetAt: reset, windowSeconds: duration)
    }

    private static func numeric(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
