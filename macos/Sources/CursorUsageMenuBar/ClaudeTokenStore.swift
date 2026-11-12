import Foundation

/// Stores the Claude OAuth access token used by the Claude usage adapter.
///
/// The token is normally copied from Claude Code's own credential record (macOS Keychain item
/// "Claude Code-credentials"), only when the user presses Auto fill. The refresh token is never read or stored.
enum ClaudeTokenStore {
    private static let fileName = "claude_credentials.json"
    private static let keychainService = "Claude Code-credentials"
    private static let fallbackCredentialsPath = ".claude/.credentials.json"

    struct Credentials: Codable, Equatable {
        let accessToken: String
    }

    static var hasCredentials: Bool { load() != nil }

    static func load() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data)
        else { return nil }
        let token = credentials.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    static func save(accessToken: String) throws {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw StoreError.emptyToken }
        guard !token.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "," || $0 == "{" || $0 == "}" }) else {
            throw StoreError.invalidToken
        }
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Credentials(accessToken: token))
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Reads the access token from Claude Code's Keychain record, falling back to its JSON file.
    static func loadFromClaudeCode(now: Date = Date()) throws -> String {
        let data = readKeychainCredentials() ?? readCredentialsFile()
        guard let data else { throw AutoFillError.notFound }
        return try accessToken(fromCredentialsJSON: data, now: now)
    }

    /// Extracts `claudeAiOauth.accessToken`, rejecting a record whose access token has already expired.
    static func accessToken(fromCredentialsJSON data: Data, now: Date = Date()) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = (oauth["accessToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { throw AutoFillError.invalidRecord }

        if let expiresMillis = oauth["expiresAt"] as? Double,
           Date(timeIntervalSince1970: expiresMillis / 1_000) < now {
            throw AutoFillError.expired
        }
        return token
    }

    private static func readKeychainCredentials() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    private static func readCredentialsFile() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(fallbackCredentialsPath)
        return try? Data(contentsOf: url)
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
            case .emptyToken: return "Enter a Claude access token before saving."
            case .invalidToken: return "Enter only the accessToken value, not the surrounding JSON."
            }
        }
    }

    enum AutoFillError: LocalizedError {
        case notFound
        case invalidRecord
        case expired

        var errorDescription: String? {
            switch self {
            case .notFound: return "No Claude Code credentials found. Sign in to Claude Code first."
            case .invalidRecord: return "Claude Code credentials do not contain a usable access token."
            case .expired: return "The Claude Code token has expired. Run Claude Code once to refresh it, then Auto fill again."
            }
        }
    }
}
