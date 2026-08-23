import XCTest
@testable import CursorUsageMenuBar

final class CodexUsageFetcherTests: XCTestCase {
    func testParsesUsageWindowsAndCredits() throws {
        let snapshot = try CodexUsageFetcher.parse(json: [
            "plan_type": "plus",
            "rate_limit": [
                "allowed": true,
                "primary_window": [
                    "used_percent": 24.5,
                    "reset_at": 1_800_000_000,
                    "limit_window_seconds": 18_000,
                ],
                "secondary_window": [
                    "used_percent": 8,
                    "reset_at": 1_800_100_000,
                    "limit_window_seconds": 604_800,
                ],
            ],
            "credits": ["remaining": 12.5],
        ], fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(snapshot.planName, "Plus")
        XCTAssertEqual(snapshot.primaryWindow?.usedPercent, 24.5)
        XCTAssertEqual(snapshot.primaryWindow?.windowSeconds, 18_000)
        XCTAssertEqual(snapshot.secondaryWindow?.usedPercent, 8)
        XCTAssertEqual(snapshot.creditsRemaining, 12.5)
        XCTAssertTrue(snapshot.isAllowed)
    }

    func testRejectsResponseWithoutRateLimit() {
        XCTAssertThrowsError(try CodexUsageFetcher.parse(json: ["plan_type": "plus"]))
    }

    func testClampsQuotaPercent() throws {
        let snapshot = try CodexUsageFetcher.parse(json: [
            "rate_limit": [
                "limit_reached": true,
                "primary_window": ["used_percent": 125],
            ],
        ])

        XCTAssertEqual(snapshot.primaryWindow?.usedPercent, 100)
        XCTAssertFalse(snapshot.isAllowed)
    }

    func testDerivesEvenPaceFromQuotaWindow() {
        let reset = Date(timeIntervalSince1970: 10_000)
        let window = CodexQuotaWindow(usedPercent: 40, resetAt: reset, windowSeconds: 1_000)

        XCTAssertEqual(window.evenPacePercent(now: Date(timeIntervalSince1970: 9_250)), 25)
        XCTAssertEqual(window.evenPacePercent(now: Date(timeIntervalSince1970: 8_000)), 0)
        XCTAssertEqual(window.evenPacePercent(now: Date(timeIntervalSince1970: 11_000)), 100)
    }
}
