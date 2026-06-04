import Foundation
import Security

/// Persists the Cursor session cookie locally (Application Support).
/// Keychain is only used to migrate older installs; reads never show a password dialog.
enum SessionTokenStore {
    private static let service = "com.local.cursor-usage-tracker.session-token"
    private static let account = "WorkosCursorSessionToken"
    private static let migrationKey = "didMigrateSessionTokenFromEnv"
    private static let didMigrateKeychainKey = "didMigrateSessionTokenFromKeychain"

    static var hasToken: Bool { load() != nil }

    static func load() -> String? {
        if let token = loadFromFile() { return token }
        if let token = loadFromKeychain(promptForAccess: false) {
            _ = try? saveToFile(token)
            deleteKeychainItem()
            UserDefaults.standard.set(true, forKey: didMigrateKeychainKey)
            return token
        }
        return nil
    }

    @discardableResult
    static func save(_ token: String) throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyToken }
        try saveToFile(trimmed)
        deleteKeychainItem()
        return trimmed
    }

    static func delete() {
        deleteFile()
        deleteKeychainItem()
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

    // MARK: - File storage (primary for DMG / ad-hoc signed builds)

    private static var storageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("CursorUsageTracker", isDirectory: true)
    }

    private static var tokenFileURL: URL {
        storageDirectory.appendingPathComponent("session_token", isDirectory: false)
    }

    private static func loadFromFile() -> String? {
        guard let data = try? Data(contentsOf: tokenFileURL),
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func saveToFile(_ token: String) throws {
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try token.data(using: .utf8)?.write(to: tokenFileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFileURL.path)
    }

    private static func deleteFile() {
        try? FileManager.default.removeItem(at: tokenFileURL)
    }

    // MARK: - Keychain (legacy migration only — no UI prompts)

    private static func loadFromKeychain(promptForAccess: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !promptForAccess {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func deleteKeychainItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func legacyEnvPaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Documents/Projects/Cursor Usage Tracker/.env"),
            home.appendingPathComponent("Library/Application Support/CursorUsageTracker/.env"),
        ]
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
        case storage(String)

        var errorDescription: String? {
            switch self {
            case .emptyToken:
                return "Enter your session token before saving."
            case .storage(let msg):
                return "Could not save token (\(msg))."
            }
        }
    }
}
