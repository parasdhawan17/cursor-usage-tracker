import Foundation

struct ClaudeUsageSnapshot: Equatable {
    /// The rolling 5-hour session limit.
    let sessionWindow: CodexQuotaWindow?
    /// The rolling 7-day weekly limit.
    let weeklyWindow: CodexQuotaWindow?
    let fetchedAt: Date

    var primaryPercent: Double? { sessionWindow?.usedPercent }

    var menuBarLabel: String {
        guard let primaryPercent else { return "Claude —" }
        return "Claude \(Int(primaryPercent.rounded()))%"
    }
}

enum ClaudeUsageFetcherError: LocalizedError {
    case missingCredentials
    case unauthorized
    case invalidResponse
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Add a Claude token in Settings."
        case .unauthorized: return "Claude token expired. Open Claude Code to refresh it, then Auto fill and Save in Settings."
        case .invalidResponse: return "Claude returned an unrecognized usage response."
        case .unavailable(let message): return message
        }
    }
}

/// Experimental adapter for the OAuth usage endpoint used by Claude Code.
enum ClaudeUsageFetcher {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let betaHeader = "oauth-2025-04-20"

    static func fetch() async throws -> ClaudeUsageSnapshot {
        guard let token = ClaudeTokenStore.load() else {
            throw ClaudeUsageFetcherError.missingCredentials
        }

        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Cursor Usage Tracker/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeUsageFetcherError.unavailable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeUsageFetcherError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ClaudeUsageFetcherError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw ClaudeUsageFetcherError.unavailable("Claude usage endpoint returned HTTP \(http.statusCode).")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageFetcherError.invalidResponse
        }
        return try parse(json: json)
    }

    static func parse(json: [String: Any], fetchedAt: Date = Date()) throws -> ClaudeUsageSnapshot {
        let session = parseWindow(json["five_hour"] as? [String: Any], windowSeconds: 5 * 3_600)
        let weekly = parseWindow(json["seven_day"] as? [String: Any], windowSeconds: 7 * 86_400)
        guard session != nil || weekly != nil else { throw ClaudeUsageFetcherError.invalidResponse }
        return ClaudeUsageSnapshot(sessionWindow: session, weeklyWindow: weekly, fetchedAt: fetchedAt)
    }

    private static func parseWindow(_ json: [String: Any]?, windowSeconds: Int) -> CodexQuotaWindow? {
        guard let json, let used = numeric(json["utilization"]) else { return nil }
        let reset = (json["resets_at"] as? String).flatMap(parseDate)
        return CodexQuotaWindow(usedPercent: min(max(used, 0), 100), resetAt: reset, windowSeconds: windowSeconds)
    }

    /// The endpoint emits microsecond fractions, which ISO8601DateFormatter may reject, so fall back to dropping them.
    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        let stripped = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: stripped)
    }

    private static func numeric(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
