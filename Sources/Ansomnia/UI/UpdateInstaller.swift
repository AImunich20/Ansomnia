import AppKit
import CryptoKit
import Foundation
import Observation

/// Where a release's files live on GitHub, and the pieces of an online
/// update that need no network: the checksum lookup, the redirect rule and
/// the installer script. The Release workflow publishes, for each version,
/// `Ansomnia-<version>.dmg`, `Ansomnia.dmg` (the same bytes under a fixed
/// name, for the README's download link) and `SHA256SUMS`.
enum UpdateAsset {
    static let repository = "AImunich20/Ansomnia"

    static func dmgName(_ version: SemanticVersion) -> String { "Ansomnia-\(version).dmg" }

    static func downloadURL(_ version: SemanticVersion, file: String) -> URL {
        URL(string: "https://github.com/\(repository)/releases/download/v\(version)/\(file)")!
    }

    /// GitHub answers a release download with a redirect to its asset
    /// storage. Only HTTPS to github.com or a githubusercontent.com host is
    /// followed; anything else ends the download with the 3xx.
    static func isTrustedRedirect(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host == "githubusercontent.com" || host.hasSuffix(".githubusercontent.com")
    }

    /// The lowercase hex SHA-256 that a `shasum -a 256` listing gives for
    /// `name` (`<hex>  <name>` or `<hex> *<name>` per line), or nil.
    static func checksum(for name: String, in listing: String) -> String? {
        for line in listing.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            var file = parts[1].trimmingCharacters(in: .whitespaces)
            if file.hasPrefix("*") { file.removeFirst() }
            let hex = parts[0].lowercased()
            if file == name, hex.count == 64, hex.utf8.allSatisfy(ReleaseTag.isLowercaseHex) { return hex }
        }
        return nil
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `text` as one single-quoted shell word.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// The script the updater runs in the background, with no Terminal:
    /// mount the verified DMG read-only, run the install.sh it carries on
    /// the Ansomnia.app beside it with --background (the installer asks the
    /// running app to quit and replaces the bundle and its recovery agent
    /// together; it needs no password when the sudoers rule already works,
    /// and otherwise asks through a macOS password dialog, the askpass
    /// helper written here), unmount, say how it went in a notification and
    /// open Ansomnia again: the new one, or the old one if the install
    /// stopped. Its output goes to `UpdateAsset.logName` in the logs folder.
    static func installScript(dmg: URL, version: SemanticVersion) -> String {
        """
        #!/bin/bash
        # Written by Ansomnia's "Download and install" (Settings > App). Runs in
        # the background, with no window of its own; its output is in
        # ~/Library/Logs/Ansomnia/\(logName).
        set -uo pipefail
        DMG=\(shellQuoted(dmg.path))
        echo "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ) Installing Ansomnia \(version) from $DMG"
        MNT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/ansomnia-update.XXXXXX")"
        ASKPASS="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/ansomnia-askpass.XXXXXX")"
        cleanup() {
          /usr/bin/hdiutil detach -quiet "$MNT" >/dev/null 2>&1 || true
          /bin/rmdir "$MNT" 2>/dev/null || true
          /bin/rm -f "$ASKPASS"
        }
        trap cleanup EXIT
        notify() { /usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Ansomnia"' -e 'end run' "$1" >/dev/null 2>&1 || true; }
        # sudo runs this for the password when the sudoers rule has to be written.
        /bin/cat > "$ASKPASS" <<'ASKPASS'
        #!/bin/bash
        exec /usr/bin/osascript -e 'text returned of (display dialog "Ansomnia needs your password to update the rule that lets it turn sleep off and on (/etc/sudoers.d/ansomnia)." default answer "" with hidden answer with title "Update Ansomnia" with icon caution)'
        ASKPASS
        /bin/chmod 700 "$ASKPASS"
        export SUDO_ASKPASS="$ASKPASS"
        status=0
        /usr/bin/hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MNT" "$DMG" >/dev/null || status=$?
        if (( status == 0 )); then
          /bin/bash "$MNT/install.sh" --allow-unverified-origin --app "$MNT/Ansomnia.app" --background </dev/null || status=$?
        fi
        cleanup
        trap - EXIT
        if (( status == 0 )); then
          echo "Ansomnia \(version) is installed."
          notify "Updated to \(version)."
        else
          echo "The install stopped (exit $status); see the lines above."
          notify "Could not update to \(version). Details: ~/Library/Logs/Ansomnia/\(logName)"
        fi
        /usr/bin/open "$HOME/Applications/Ansomnia.app"
        exit "$status"

        """
    }

    /// The background installer's output, in the logs folder.
    static let logName = "update.log"
}

enum UpdateInstallError: LocalizedError, Equatable {
    case status(String, Int)
    case notHTTP
    case noChecksum(String)
    case checksumMismatch(String)
    case launch(String)

    var errorDescription: String? {
        switch self {
        case let .status(file, code): "GitHub answered HTTP \(code) for \(file)"
        case .notHTTP: "the answer was not an HTTP response"
        case let .noChecksum(file): "SHA256SUMS lists no checksum for \(file)"
        case let .checksumMismatch(file): "\(file) does not match its checksum in SHA256SUMS"
        case let .launch(reason): "could not start the installer: \(reason)"
        }
    }
}

/// Follows GitHub's redirect to its asset storage and nothing else.
final class GitHubAssetRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        UpdateAsset.isTrustedRedirect(request.url) ? request : nil
    }
}

/// The "Download and install" button in Settings > App, shown when the
/// update check found a newer stable release. It downloads that release's
/// DMG and SHA256SUMS, checks the DMG against its line, keeps it under
/// ~/Library/Caches/Ansomnia/Updates, and starts a script there in the
/// background that runs the DMG's installer, quits this app and opens the
/// new one. No Terminal window: the installer's output goes to
/// ~/Library/Logs/Ansomnia/update.log, and a password, when one is needed
/// at all, is asked for in a macOS dialog.
@MainActor
@Observable
final class UpdateInstaller {
    enum State: Equatable {
        case idle
        case downloading(String)
        /// The installer is running in the background; it quits this app.
        case installing(String)
        case failed(String)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    /// A download is running. Read from `state`, so the button follows it.
    var isBusy: Bool {
        if case .downloading = state { return true }
        return false
    }

    func install(_ version: SemanticVersion) {
        guard inFlight == nil else { return }
        state = .downloading("\(version)")
        Log.info("update: downloading Ansomnia \(version) from GitHub")
        inFlight = Task {
            do {
                let script = try await Self.prepare(version)
                Log.info("update: \(UpdateAsset.dmgName(version)) matches SHA256SUMS; running the installer in the background")
                let log = Paths.fromEnvironment().logs.appendingPathComponent(UpdateAsset.logName)
                try Self.launchDetached(script: script, log: log)
                state = .installing("\(version)")
            } catch {
                Log.error("update failed: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
            inFlight = nil
        }
    }

    /// Downloads and verifies the DMG, writes the install script beside it
    /// and returns the script's URL.
    nonisolated static func prepare(_ version: SemanticVersion) async throws -> URL {
        let name = UpdateAsset.dmgName(version)
        let sums = try await fetch(UpdateAsset.downloadURL(version, file: "SHA256SUMS"), file: "SHA256SUMS")
        guard let expected = UpdateAsset.checksum(for: name, in: String(decoding: sums, as: UTF8.self)) else {
            throw UpdateInstallError.noChecksum(name)
        }
        let dmg = try await fetch(UpdateAsset.downloadURL(version, file: name), file: name)
        guard UpdateAsset.sha256(of: dmg) == expected else { throw UpdateInstallError.checksumMismatch(name) }

        let fm = FileManager.default
        let caches = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = caches.appendingPathComponent("Ansomnia/Updates", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let dmgURL = folder.appendingPathComponent(name)
        try dmg.write(to: dmgURL, options: .atomic)
        let script = folder.appendingPathComponent("install-\(version).sh")
        try Data(UpdateAsset.installScript(dmg: dmgURL, version: version).utf8).write(to: script, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }

    /// Starts `script` with bash in a session of its own, so it outlives
    /// this app (the installer quits it), with no input and its output
    /// appended to `log`.
    nonisolated static func launchDetached(script: URL, log: URL) throws {
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        var attributes = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var actions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, log.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        let argv = ["/bin/bash", script.path]
        var cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, "/bin/bash", &actions, &attributes, &cArgs, environ)
        guard rc == 0 else { throw UpdateInstallError.launch(String(cString: strerror(rc))) }
        Log.info("update: installer running as pid \(pid); output in \(log.path)")
    }

    nonisolated private static func fetch(_ url: URL, file: String) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 120)
        request.setValue("Ansomnia/\(AppBuild.current.version ?? "unpackaged")", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request, delegate: GitHubAssetRedirects())
        guard let http = response as? HTTPURLResponse else { throw UpdateInstallError.notHTTP }
        guard http.statusCode == 200 else { throw UpdateInstallError.status(file, http.statusCode) }
        return data
    }
}
