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
            "credits": [
                "remaining": 12.5,
                "unlimited": false,
                "approx_local_messages": [4, 8],
                "approx_cloud_messages": [2, 3],
            ],
            "rate_limit_reset_credits": ["applicable_available_count": 2],
        ], fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(snapshot.planName, "Plus")
        XCTAssertEqual(snapshot.primaryWindow?.usedPercent, 24.5)
        XCTAssertEqual(snapshot.primaryWindow?.windowSeconds, 18_000)
        XCTAssertEqual(snapshot.secondaryWindow?.usedPercent, 8)
        XCTAssertEqual(snapshot.creditsRemaining, 12.5)
        XCTAssertEqual(snapshot.approximateLocalMessages, 4...8)
        XCTAssertEqual(snapshot.approximateCloudMessages, 2...3)
        XCTAssertEqual(snapshot.resetCreditsAvailable, 2)
        XCTAssertFalse(snapshot.creditsUnlimited)
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

    func testDailyUsageAccumulatesObservedIncreases() {
        let calendar = utcCalendar()
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let initial = CodexDailyUsageTracker.reduce(
            nil,
            percent: 20,
            observedAt: first,
            resetAt: Date(timeIntervalSince1970: 1_800_100_000),
            calendar: calendar
        )
        let later = CodexDailyUsageTracker.reduce(
            initial,
            percent: 27.5,
            observedAt: first.addingTimeInterval(3_600),
            resetAt: Date(timeIntervalSince1970: 1_800_100_000),
            calendar: calendar
        )

        XCTAssertEqual(later.accumulatedPercent, 7.5)
    }

    func testDailyUsageCountsNewWindowAfterReset() {
        let calendar = utcCalendar()
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let initial = CodexDailyUsageState(
            dayStart: calendar.startOfDay(for: first),
            lastPercent: 95,
            accumulatedPercent: 4,
            firstObservedAt: first,
            lastObservedAt: first,
            windowResetAt: Date(timeIntervalSince1970: 1_800_001_000)
        )
        let next = CodexDailyUsageTracker.reduce(
            initial,
            percent: 3,
            observedAt: first.addingTimeInterval(3_600),
            resetAt: Date(timeIntervalSince1970: 1_800_700_000),
            calendar: calendar
        )

        XCTAssertEqual(next.accumulatedPercent, 7)
    }

    func testDailyUsageStartsFreshOnNewDay() {
        let calendar = utcCalendar()
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let initial = CodexDailyUsageState(
            dayStart: calendar.startOfDay(for: first),
            lastPercent: 25,
            accumulatedPercent: 5,
            firstObservedAt: first,
            lastObservedAt: first,
            windowResetAt: nil
        )
        let next = CodexDailyUsageTracker.reduce(
            initial,
            percent: 30,
            observedAt: first.addingTimeInterval(86_400),
            resetAt: nil,
            calendar: calendar
        )

        XCTAssertEqual(next.accumulatedPercent, 0)
        XCTAssertEqual(next.lastPercent, 30)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
