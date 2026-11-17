import Darwin
import Foundation

/// The complete command set of the root controller. Requests carry no arguments.
enum ControlAction: String, Sendable {
    case start, stop
}

/// Stable failure identifiers. The controller has no localization; the app maps
/// these to localized text and appends the controller's detail when useful.
enum ControlFailure: String, Sendable {
    case unauthorized, unsupported, conflict, notInstalled, startFailed, stopFailed
}

struct ControlReply: Codable, Equatable {
    static let currentVersion = 2

    let version: Int
    let ok: Bool
    /// Raw `ControlFailure`; kept as text so an unknown value still decodes.
    /// Version 1 replies (the previous controller) have none.
    let failure: String?
    let message: String

    static let success = ControlReply(version: currentVersion, ok: true, failure: nil, message: "")

    static func failed(_ failure: ControlFailure, _ message: String) -> ControlReply {
        ControlReply(version: currentVersion, ok: false, failure: failure.rawValue, message: message)
    }
}

struct ControlError: Error {
    let failure: ControlFailure
    let detail: String
}

enum ControlSocket {
    static func configure(_ fd: Int32, timeout: Int) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        var interval = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout.size(ofValue: interval)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &interval, socklen_t(MemoryLayout.size(ofValue: interval)))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    /// The peer's UID as recorded by the kernel; the client cannot claim another.
    static func peerUID(_ fd: Int32) throws -> uid_t {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { throw failure("Cannot identify the control connection.") }
        return uid
    }

    static func read(_ fd: Int32, limit: Int) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count == 0 { return data }
            if count < 0 {
                if errno == EINTR { continue }
                throw failure("The control connection timed out or closed.")
            }
            guard data.count + count <= limit else { throw failure("The control message is too large.") }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    static func write(_ fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let n = send(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw failure("Cannot send the control message.") }
                sent += n
            }
        }
    }

    static func failure(_ text: String) -> TetherlineError { .message(text) }
}

enum ControlClient {
    /// Longer than the controller's slowest operation (stop waits up to 10 s).
    static let timeout = 40

    static func request(_ action: ControlAction, deployment: Deployment) throws {
        let reply: ControlReply
        do {
            reply = try exchange(Data((action.rawValue + "\n").utf8), path: deployment.socketPath)
        } catch ControlClientError.unavailable {
            throw TetherlineError.message(L10n.text("The Tetherline helper is not available. Enable tethering to reinstall it."))
        }
        guard reply.ok else { throw error(for: reply) }
    }

    static func error(for reply: ControlReply) -> TetherlineError {
        let detail = reply.message.trimmingCharacters(in: .whitespacesAndNewlines)
        func withDetail(_ text: String) -> TetherlineError {
            .message(detail.isEmpty ? text : text + "\n\n" + detail)
        }
        switch reply.failure.flatMap(ControlFailure.init) {
        case .conflict:
            return .message(L10n.text("Another tethering service is running. Stop it before enabling Tetherline."))
        case .unauthorized:
            return .message(L10n.text("This account cannot control Tetherline. It was set up from another account."))
        case .notInstalled:
            return .message(L10n.text("Tetherline's background components are incomplete. Enable tethering to reinstall them."))
        case .startFailed:
            return withDetail(L10n.text("The service did not start. Check the log and background permission in System Settings."))
        case .stopFailed:
            return withDetail(L10n.text("The service did not stop. Try again shortly."))
        case .unsupported, nil:
            return .message(detail.isEmpty ? L10n.text("The Tetherline helper rejected the request.") : detail)
        }
    }

    enum ControlClientError: Error { case unavailable }

    static func exchange(_ request: Data, path: String) throws -> ControlReply {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw ControlSocket.failure("The control socket path is too long.")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlSocket.failure("Cannot create the control connection.") }
        defer { close(fd) }
        ControlSocket.configure(fd, timeout: timeout)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw ControlClientError.unavailable }
        // Only root may answer: a socket planted by another process is rejected.
        guard try ControlSocket.peerUID(fd) == 0 else { throw ControlSocket.failure("The control helper is not owned by root.") }
        try ControlSocket.write(fd, data: request)
        shutdown(fd, SHUT_WR)
        return try JSONDecoder().decode(ControlReply.self, from: ControlSocket.read(fd, limit: 65_536))
    }
}
