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

        var errorDescription: String? {
            "Enter a Codex access token before saving."
        }
    }
}
