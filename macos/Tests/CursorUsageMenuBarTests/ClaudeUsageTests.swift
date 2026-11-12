import XCTest
@testable import CursorUsageMenuBar

final class ClaudeUsageTests: XCTestCase {
    func testParsesSessionAndWeeklyWindows() throws {
        let snapshot = try ClaudeUsageFetcher.parse(json: [
            "five_hour": ["utilization": 7.0, "resets_at": "2026-11-12T19:50:00.478214+00:00"],
            "seven_day": ["utilization": 15.0, "resets_at": "2026-11-14T08:00:00.478236+00:00"],
            "extra_usage": ["is_enabled": false],
        ])
        XCTAssertEqual(snapshot.primaryPercent, 7)
        XCTAssertEqual(snapshot.sessionWindow?.windowSeconds, 5 * 3_600)
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 15)
        XCTAssertEqual(snapshot.weeklyWindow?.windowSeconds, 7 * 86_400)
        XCTAssertNotNil(snapshot.sessionWindow?.resetAt)
        XCTAssertEqual(snapshot.menuBarLabel, "Claude 7%")
    }

    func testRejectsResponseWithoutAnyWindow() {
        XCTAssertThrowsError(try ClaudeUsageFetcher.parse(json: ["extra_usage": [:]]))
    }

    func testClampsUtilization() throws {
        let snapshot = try ClaudeUsageFetcher.parse(json: ["five_hour": ["utilization": 140.0]])
        XCTAssertEqual(snapshot.primaryPercent, 100)
    }

    func testParsesFractionalAndPlainTimestamps() {
        XCTAssertNotNil(ClaudeUsageFetcher.parseDate("2026-11-12T19:50:00.478214+00:00"))
        XCTAssertNotNil(ClaudeUsageFetcher.parseDate("2026-11-12T19:50:00Z"))
        XCTAssertNil(ClaudeUsageFetcher.parseDate("not a date"))
    }

    func testExtractsAccessTokenAndRejectsExpiredRecord() throws {
        let future = Date(timeIntervalSince1970: 1_800_000_000)
        let valid = """
        {"claudeAiOauth":{"accessToken":"tok-abc","refreshToken":"secret","expiresAt":1800000000000}}
        """.data(using: .utf8)!
        XCTAssertEqual(try ClaudeTokenStore.accessToken(fromCredentialsJSON: valid, now: future.addingTimeInterval(-60)), "tok-abc")

        XCTAssertThrowsError(try ClaudeTokenStore.accessToken(fromCredentialsJSON: valid, now: future.addingTimeInterval(60)))
    }

    func testRejectsRecordWithoutAccessToken() {
        let data = #"{"claudeAiOauth":{"refreshToken":"only"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try ClaudeTokenStore.accessToken(fromCredentialsJSON: data))
    }

    func testLocalScannerCountsTodayOncePerMessage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now)
        let old = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3 * 86_400))
        let lines = [
            #"{"timestamp":"\#(stamp)","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":20}}}"#,
            // Same message id repeated while streaming must be counted once.
            #"{"timestamp":"\#(stamp)","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":20}}}"#,
            #"{"timestamp":"\#(old)","message":{"id":"m0","model":"claude-opus-5-5","usage":{"input_tokens":999,"output_tokens":999}}}"#,
        ].joined(separator: "\n")
        try lines.write(to: root.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let usage = ClaudeLocalUsageScanner.scanToday(now: now, root: root)
        XCTAssertEqual(usage.messages, 1)
        XCTAssertEqual(usage.totalTokens, 135)
        XCTAssertEqual(usage.outputTokens, 5)
        XCTAssertEqual(usage.tokensByModel["claude-opus-5-5"], 135)
    }
}
