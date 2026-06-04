import Foundation
import Security

/// Persists the Cursor session cookie in the Keychain (not `.env`).
enum SessionTokenStore {
    private static let service = "com.local.cursor-usage-tracker.session-token"
    private static let account = "WorkosCursorSessionToken"
    private static let migrationKey = "didMigrateSessionTokenFromEnv"

    static var hasToken: Bool { load() != nil }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    static func save(_ token: String) throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyToken }

        let data = Data(trimmed.utf8)
        if load() != nil {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let attrs: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            guard status == errSecSuccess else { throw StoreError.keychain(status) }
        } else {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw StoreError.keychain(status) }
        }
        return trimmed
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        // Do not re-import from legacy `.env` after the user removes their token.
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// One-time import from legacy `.env` so existing installs keep working.
    static func migrateFromLegacyEnvIfNeeded() {
        guard !hasToken,
              !UserDefaults.standard.bool(forKey: migrationKey)
        else { return }

        UserDefaults.standard.set(true, forKey: migrationKey)
        for path in legacyEnvPaths() {
            if let token = parseEnvFile(at: path) {
                _ = try? save(token)
                return
            }
        }
    }

    private static func legacyEnvPaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths: [URL] = [
            home.appendingPathComponent("Documents/Projects/Cursor Usage Tracker/.env"),
            home.appendingPathComponent("Library/Application Support/CursorUsageTracker/.env"),
        ]
        if let cwd = FileManager.default.currentDirectoryPath as String? {
            paths.insert(URL(fileURLWithPath: cwd).appendingPathComponent(".env"), at: 0)
        }
        return paths
    }

    private static func parseEnvFile(at url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("CURSOR_SESSION_TOKEN=") {
                var value = String(s.dropFirst("CURSOR_SESSION_TOKEN=".count))
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    enum StoreError: LocalizedError {
        case emptyToken
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .emptyToken:
                return "Enter your session token before saving."
            case .keychain(let status):
                return "Could not save token (Keychain error \(status))."
            }
        }
    }
}
