import Foundation

enum TrackedService: String, CaseIterable, Identifiable {
    case cursor
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        }
    }

    var icon: String {
        switch self {
        case .cursor: return "cursorarrow.rays"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private static let selectedKey = "selectedMenuBarService"

    static var selected: TrackedService {
        get {
            guard let raw = UserDefaults.standard.string(forKey: selectedKey),
                  let service = TrackedService(rawValue: raw)
            else { return .cursor }
            return service
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selectedKey) }
    }
}
