import Foundation

/// Stores the manually supplied OAuth bearer credentials used by the experimental Codex usage adapter.
enum CodexTokenStore {
    private static let fileName = "codex_credentials.json"

    struct Credentials: Codable, Equatable {
        let accessToken: String
        let accountID: String?
    }

    static var hasCredentials: Bool { load() != nil }

    static func load() -> Credentials? {
        guard let data = try? Data(contentsOf: fileURL),
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data)
        else { return nil }
        let token = credentials.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        let accountID = credentials.accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Credentials(accessToken: token, accountID: accountID?.isEmpty == true ? nil : accountID)
    }

    static func save(accessToken: String, accountID: String?) throws {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw StoreError.emptyToken }
        guard !token.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "," || $0 == "{" || $0 == "}" }) else {
            throw StoreError.invalidToken
        }
        let id = accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let credentials = Credentials(accessToken: token, accountID: id?.isEmpty == true ? nil : id)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(credentials)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var storageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CursorUsageTracker", isDirectory: true)
    }

    private static var fileURL: URL {
        storageDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    enum StoreError: LocalizedError {
        case emptyToken
        case invalidToken

        var errorDescription: String? {
            switch self {
            case .emptyToken: return "Enter a Codex access token before saving."
            case .invalidToken: return "Enter only the access_token value, not the surrounding JSON or refresh token."
            }
        }
    }

    /// Reads the access token and account ID from the Codex CLI's file-backed auth record.
    /// This intentionally does not attempt to read the OS credential store.
    static func loadFromCodexAuthFile() throws -> Credentials {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { throw AutoFillError.fileNotFound }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw AutoFillError.invalidFile }
        let accountID = (tokens["account_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Credentials(accessToken: accessToken, accountID: accountID?.isEmpty == true ? nil : accountID)
    }

    enum AutoFillError: LocalizedError {
        case fileNotFound
        case invalidFile

        var errorDescription: String? {
            switch self {
            case .fileNotFound: return "Could not find ~/.codex/auth.json. Sign in to Codex first."
            case .invalidFile: return "~/.codex/auth.json does not contain a usable access_token."
            }
        }
    }
}
