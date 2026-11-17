import CryptoKit
import Darwin
import Foundation

enum InstallationState: Equatable, Sendable {
    /// Nothing is installed.
    case missing
    /// Something is installed but differs from this app (older version, another account, partial).
    case outdated
    /// Engine, controller and both launchd definitions match this app.
    case current
}

/// Compares the root-owned installation with the app bundle. Executables are
/// compared by SHA-256, launchd definitions by content.
struct InstallationCheck: Sendable {
    let deployment: Deployment
    let bundledEngine: String
    let bundledControl: String
    let owner: uid_t

    func state() -> InstallationState {
        let d = deployment
        let installed = [d.enginePath, d.controlPath, d.enginePlistPath, d.controlPlistPath]
        let present = installed.filter { FileManager.default.fileExists(atPath: $0) }
        if present.isEmpty { return .missing }
        guard present.count == installed.count,
              let engine = FileDigest.sha256(d.enginePath), engine == FileDigest.sha256(bundledEngine),
              let control = FileDigest.sha256(d.controlPath), control == FileDigest.sha256(bundledControl),
              NSDictionary(contentsOfFile: d.enginePlistPath) == d.enginePlist as NSDictionary,
              NSDictionary(contentsOfFile: d.controlPlistPath) == d.controlPlist(owner: owner) as NSDictionary
        else { return .outdated }
        return .current
    }

    /// Script installing this bundle. Digests are taken now; the script refuses
    /// copies that changed by the time the administrator approves.
    func installScript() throws -> String {
        guard let engineHash = FileDigest.sha256(bundledEngine), let controlHash = FileDigest.sha256(bundledControl) else {
            throw TetherlineError.message(L10n.text("The app is incomplete. Reinstall Tetherline."))
        }
        return try Installer(deployment: deployment).install(
            engine: bundledEngine, engineHash: engineHash, control: bundledControl, controlHash: controlHash, owner: owner)
    }
}

/// SHA-256 of files, cached by file identity so polling re-hashes only files that changed.
enum FileDigest {
    private struct Identity: Hashable {
        let device: dev_t, inode: ino_t, size: off_t
        let modified: Timestamp, changed: Timestamp
    }

    private struct Timestamp: Hashable {
        let seconds: Int, nanoseconds: Int
        init(_ value: timespec) { seconds = value.tv_sec; nanoseconds = value.tv_nsec }
    }

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var entries: [String: (Identity, String)] = [:]
    }

    private static let cache = Cache()

    static func sha256(_ path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let identity = Identity(device: info.st_dev, inode: info.st_ino, size: info.st_size,
                                modified: Timestamp(info.st_mtimespec), changed: Timestamp(info.st_ctimespec))
        cache.lock.lock()
        if let (known, digest) = cache.entries[path], known == identity {
            cache.lock.unlock()
            return digest
        }
        cache.lock.unlock()
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        cache.lock.lock()
        cache.entries[path] = (identity, digest)
        cache.lock.unlock()
        return digest
    }
}
