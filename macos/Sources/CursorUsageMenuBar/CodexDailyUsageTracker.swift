import Foundation

struct CodexDailyUsage: Equatable {
    let observedPercent: Double
    let firstObservedAt: Date
    let lastObservedAt: Date

    var displayValue: String {
        if observedPercent < 0.05 { return "0 pp" }
        if observedPercent >= 10 { return "+\(Int(observedPercent.rounded())) pp" }
        return String(format: "+%.1f pp", observedPercent)
    }
}

struct CodexDailyUsageState: Codable, Equatable {
    let dayStart: Date
    var lastPercent: Double
    var accumulatedPercent: Double
    let firstObservedAt: Date
    var lastObservedAt: Date
    var windowResetAt: Date?
}

enum CodexDailyUsageTracker {
    private static let fileName = "codex_daily_usage.json"

    static func record(_ snapshot: CodexUsageSnapshot, calendar: Calendar = .current) -> CodexDailyUsage? {
        guard let window = snapshot.primaryWindow else { return nil }
        let previous = load()
        let next = reduce(
            previous,
            percent: window.usedPercent,
            observedAt: snapshot.fetchedAt,
            resetAt: window.resetAt,
            calendar: calendar
        )
        save(next)
        return usage(from: next)
    }

    static func reduce(
        _ state: CodexDailyUsageState?,
        percent: Double,
        observedAt: Date,
        resetAt: Date?,
        calendar: Calendar
    ) -> CodexDailyUsageState {
        let dayStart = calendar.startOfDay(for: observedAt)
        let clamped = min(max(percent, 0), 100)
        guard var state, calendar.isDate(state.dayStart, inSameDayAs: dayStart) else {
            return CodexDailyUsageState(
                dayStart: dayStart,
                lastPercent: clamped,
                accumulatedPercent: 0,
                firstObservedAt: observedAt,
                lastObservedAt: observedAt,
                windowResetAt: resetAt
            )
        }

        if clamped >= state.lastPercent {
            state.accumulatedPercent += clamped - state.lastPercent
        } else if resetAt != state.windowResetAt {
            // A new quota window began during this calendar day.
            state.accumulatedPercent += clamped
        }

        state.lastPercent = clamped
        state.lastObservedAt = observedAt
        state.windowResetAt = resetAt
        return state
    }

    private static func usage(from state: CodexDailyUsageState) -> CodexDailyUsage {
        CodexDailyUsage(
            observedPercent: state.accumulatedPercent,
            firstObservedAt: state.firstObservedAt,
            lastObservedAt: state.lastObservedAt
        )
    }

    private static func load() -> CodexDailyUsageState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CodexDailyUsageState.self, from: data)
    }

    private static func save(_ state: CodexDailyUsageState) {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static var storageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CursorUsageTracker", isDirectory: true)
    }

    private static var fileURL: URL {
        storageDirectory.appendingPathComponent(fileName, isDirectory: false)
    }
}
