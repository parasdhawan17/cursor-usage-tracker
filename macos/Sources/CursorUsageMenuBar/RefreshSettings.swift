import Foundation

/// Auto-refresh interval for background usage fetches (1–5 minutes).
enum RefreshInterval: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    var id: Int { rawValue }

    var minutes: Int { rawValue }

    var label: String { "\(minutes) min" }

    var nanoseconds: UInt64 { UInt64(minutes) * 60 * 1_000_000_000 }

    private static let userDefaultsKey = "autoRefreshIntervalMinutes"

    static var stored: RefreshInterval {
        get {
            let raw = UserDefaults.standard.integer(forKey: userDefaultsKey)
            if raw == 0 { return .one }
            return RefreshInterval(rawValue: raw) ?? .one
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}
