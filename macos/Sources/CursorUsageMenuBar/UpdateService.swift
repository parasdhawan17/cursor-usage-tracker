import AppKit
import Foundation

struct AppUpdateInfo: Equatable {
    let version: String
    let tagName: String
    let dmgDownloadURL: URL
    let releasePageURL: URL
}

enum UpdateService {
    static let githubRepo = "parasdhawan17/cursor-usage-tracker"
    static let userAgent = "Cursor-Usage-Tracker/\(AppVersion.current)"

    private static let lastCheckKey = "updateLastCheckAt"
    private static let checkInterval: TimeInterval = 6 * 60 * 60

    static func shouldCheckNow() -> Bool {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        guard let last else { return true }
        return Date().timeIntervalSince(last) >= checkInterval
    }

    static func markChecked() {
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
    }

    static func fetchLatestUpdate() async throws -> AppUpdateInfo? {
        let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw UpdateError.httpStatus(http.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = AppVersion.normalized(release.tagName)
        guard AppVersion.isNewer(candidate: version, than: AppVersion.current) else {
            return nil
        }

        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              let dmgURL = URL(string: asset.browserDownloadURL),
              let pageURL = URL(string: release.htmlURL)
        else {
            throw UpdateError.missingDMG
        }

        return AppUpdateInfo(
            version: version,
            tagName: release.tagName,
            dmgDownloadURL: dmgURL,
            releasePageURL: pageURL
        )
    }

    static func downloadDMG(from url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cursor-Usage-Update-\(UUID().uuidString).dmg")

        let delegate = DMGDownloadDelegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        delegate.session = session

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(continuation: continuation)
                session.downloadTask(with: request).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    static func installAndRelaunch(dmgURL: URL) throws {
        let appURL = Bundle.main.bundleURL
        let parent = appURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: parent.path)
        else {
            throw UpdateError.installLocationNotWritable(parent.path)
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-usage-install-\(UUID().uuidString).sh")

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-usage-install-\(UUID().uuidString).log")

        let script = """
        #!/bin/bash
        set -euo pipefail
        DMG=\(shellQuote(dmgURL.path))
        TARGET=\(shellQuote(appURL.path))
        PID=\(ProcessInfo.processInfo.processIdentifier)
        LOG=\(shellQuote(logURL.path))

        exec > >(tee -a "$LOG") 2>&1
        echo "=== Cursor Usage update started $(date) ==="

        while kill -0 "$PID" 2>/dev/null; do sleep 0.25; done
        echo "Old process exited."

        MOUNT=$(hdiutil attach -nobrowse -noverify -noautofsck "$DMG" | grep -m1 '/Volumes/' | sed 's/.*\\(\\/Volumes\\/.*\\)/\\1/')
        if [[ -z "$MOUNT" || ! -d "$MOUNT/Cursor Usage.app" ]]; then
          echo "Could not mount DMG or find app inside." >&2
          exit 1
        fi
        echo "Mounted at $MOUNT"
        cleanup() { hdiutil detach "$MOUNT" -quiet || true; }
        trap cleanup EXIT

        STAGING="$(dirname "$TARGET")/.Cursor Usage.app.staging"
        rm -rf "$STAGING"
        cp -R "$MOUNT/Cursor Usage.app" "$STAGING"
        rm -rf "$TARGET"
        mv "$STAGING" "$TARGET"
        xattr -cr "$TARGET" 2>/dev/null || true
        echo "Installed to $TARGET"
        open -a "$TARGET"
        echo "=== Update complete $(date) ==="
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        NSApp.terminate(nil)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private final class DMGDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let progress: @Sendable (Double?) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    var session: URLSession?

    init(destination: URL, progress: @escaping @Sendable (Double?) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func start(continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            progress(nil)
            return
        }
        progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let http = downloadTask.response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else {
            finish(.failure(UpdateError.downloadFailed))
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            progress(1)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        guard let continuation else { return }
        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}

enum UpdateError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case missingDMG
    case downloadFailed
    case installLocationNotWritable(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Could not read the update server response."
        case .httpStatus(let code):
            return "Update check failed (HTTP \(code))."
        case .missingDMG:
            return "The latest release has no downloadable DMG."
        case .downloadFailed:
            return "Could not download the update."
        case .installLocationNotWritable(let path):
            return "Cannot write to \(path). Move Cursor Usage to Applications and try again."
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

@MainActor
final class UpdateViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case available(AppUpdateInfo)
        case downloading(Double?)
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    var showsUpdateBanner: Bool {
        switch phase {
        case .available, .downloading, .installing, .failed:
            return true
        case .idle, .checking:
            return false
        }
    }

    func checkForUpdates(force: Bool = false) async {
        if case .checking = phase { return }
        if !force, !UpdateService.shouldCheckNow() { return }

        phase = .checking
        defer { UpdateService.markChecked() }

        do {
            if let update = try await UpdateService.fetchLatestUpdate() {
                phase = .available(update)
            } else {
                phase = .idle
            }
        } catch {
            phase = .idle
        }
    }

    func installUpdate() async {
        guard case .available(let update) = phase else { return }

        phase = .downloading(0)
        do {
            let dmgURL = try await UpdateService.downloadDMG(from: update.dmgDownloadURL) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    if case .downloading = self.phase {
                        self.phase = .downloading(progress)
                    }
                }
            }
            phase = .installing
            try UpdateService.installAndRelaunch(dmgURL: dmgURL)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func dismissFailure() {
        if case .failed = phase {
            phase = .idle
        }
    }
}
