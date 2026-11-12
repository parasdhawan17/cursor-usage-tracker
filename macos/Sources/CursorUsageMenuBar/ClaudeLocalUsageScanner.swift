import Foundation

/// Token totals for Claude Code activity since local midnight, read from ~/.claude/projects session logs.
struct ClaudeLocalUsage: Equatable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheWriteTokens = 0
    var messages = 0
    var tokensByModel: [String: Int] = [:]

    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }
}

/// Sums today's assistant token usage from Claude Code's local JSONL transcripts. Read-only, no network.
enum ClaudeLocalUsageScanner {
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    static func scanToday(now: Date = Date(), calendar: Calendar = .current, root: URL = defaultRoot) -> ClaudeLocalUsage {
        let startOfDay = calendar.startOfDay(for: now)
        var usage = ClaudeLocalUsage()
        var seenMessageIDs = Set<String>()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]

        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return usage
        }
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            // Skip transcripts that have not been written since midnight; they cannot contain today's messages.
            guard let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  modified >= startOfDay,
                  let text = try? String(contentsOf: fileURL, encoding: .utf8)
            else { continue }

            for line in text.split(separator: "\n") where line.contains("\"usage\"") {
                accumulate(line: String(line), since: startOfDay, into: &usage, seen: &seenMessageIDs)
            }
        }
        return usage
    }

    /// Claude Code writes the same assistant message several times while streaming, so count each message ID once.
    private static func accumulate(line: String, since startOfDay: Date, into usage: inout ClaudeLocalUsage, seen: inout Set<String>) {
        guard let data = line.data(using: .utf8),
              let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestamp = (entry["timestamp"] as? String).flatMap(ClaudeUsageFetcher.parseDate),
              timestamp >= startOfDay,
              let message = entry["message"] as? [String: Any],
              let tokens = message["usage"] as? [String: Any]
        else { return }

        if let messageID = message["id"] as? String {
            guard seen.insert(messageID).inserted else { return }
        }

        let input = intValue(tokens["input_tokens"])
        let output = intValue(tokens["output_tokens"])
        let cacheRead = intValue(tokens["cache_read_input_tokens"])
        let cacheWrite = intValue(tokens["cache_creation_input_tokens"])
        usage.inputTokens += input
        usage.outputTokens += output
        usage.cacheReadTokens += cacheRead
        usage.cacheWriteTokens += cacheWrite
        usage.messages += 1

        let model = message["model"] as? String ?? "unknown"
        usage.tokensByModel[model, default: 0] += input + output + cacheRead + cacheWrite
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }
}
