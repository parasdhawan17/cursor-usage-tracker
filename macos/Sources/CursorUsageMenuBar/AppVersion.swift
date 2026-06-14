import Foundation

enum AppVersion {
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Returns `true` when `candidate` is strictly newer than `installed`.
    static func isNewer(candidate: String, than installed: String) -> Bool {
        compare(candidate, installed) == .orderedDescending
    }

    static func normalized(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value.trimmingPrefix("v")
        value.trimmingPrefix("V")
        return value
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = normalized(lhs).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let right = normalized(rhs).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = Int(left[safe: index] ?? "0") ?? 0
            let r = Int(right[safe: index] ?? "0") ?? 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }
}

private extension String {
    mutating func trimmingPrefix(_ prefix: String) {
        if hasPrefix(prefix) {
            removeFirst(prefix.count)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
