import Darwin
import Foundation

@_silgen_name("launch_activate_socket")
private func activateSocket(_ name: UnsafePointer<CChar>, _ fds: UnsafeMutablePointer<UnsafeMutablePointer<Int32>?>,
                            _ count: UnsafeMutablePointer<Int>) -> Int32

/// Root controller, activated by launchd on demand through its socket. It serves
/// one fixed command at a time for the installing account and exits after a
/// second of inactivity; launchd keeps the socket while it is not running.
@main enum ControlMain {
    static func main() {
        guard geteuid() == 0, CommandLine.arguments.count == 2,
              let owner = uid_t(CommandLine.arguments[1]), owner > 0 else { exit(1) }
        umask(0o077)
        var fds: UnsafeMutablePointer<Int32>?
        var count = 0
        guard activateSocket("Control", &fds, &count) == 0, count == 1, let fds else { exit(1) }
        let listener = fds[0]
        free(fds)
        defer { close(listener) }
        _ = fcntl(listener, F_SETFD, FD_CLOEXEC)
        let engine = EngineControl(deployment: .current)
        while true {
            var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 1000)
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { return }
            let client = accept(listener, nil, nil)
            guard client >= 0 else { continue }
            ControlSocket.configure(client, timeout: 2)
            let reply = serve(client, owner: owner, engine: engine)
            if let data = try? JSONEncoder().encode(reply) { try? ControlSocket.write(client, data: data) }
            close(client)
        }
    }

    static func serve(_ client: Int32, owner: uid_t, engine: EngineControl) -> ControlReply {
        let peer = try? ControlSocket.peerUID(client)
        guard let peer, peer == owner || peer == 0 else {
            return .failed(.unauthorized, "This account is not authorized to control Tetherline.")
        }
        guard let data = try? ControlSocket.read(client, limit: 32),
              let text = String(data: data, encoding: .utf8), text.hasSuffix("\n"),
              let action = ControlAction(rawValue: String(text.dropLast())) else {
            return .failed(.unsupported, "Unsupported control command.")
        }
        let reply: ControlReply
        do {
            try engine.perform(action)
            reply = .success
        } catch let error as ControlError {
            reply = .failed(error.failure, String(error.detail.prefix(8000)))
        } catch {
            reply = .failed(action == .start ? .startFailed : .stopFailed, error.localizedDescription)
        }
        log("uid \(peer) \(action.rawValue): \(reply.ok ? "ok" : reply.failure ?? "failed") \(reply.message)")
        return reply
    }

    static func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        print(stamp + " " + line.trimmingCharacters(in: .whitespacesAndNewlines))
        fflush(stdout)
    }
}

/// Starts and stops the engine job. The launchd enable/disable override records
/// the user's choice, so the engine starts at boot exactly when it was left on.
struct EngineControl {
    let deployment: Deployment

    func perform(_ action: ControlAction) throws {
        switch action {
        case .start: try start()
        case .stop: try stop()
        }
    }

    private func start() throws {
        try verifyInstallation()
        var state = try read(.startFailed)
        guard !state.conflict else { throw ControlError(failure: .conflict, detail: "") }
        try launchctl(["enable", deployment.engineJob], .startFailed)
        if !state.running {
            if state.loaded {
                // Loaded but not running: launchd is throttling a failing engine. Retry now.
                try launchctl(["kickstart", "-k", deployment.engineJob], .startFailed)
            } else {
                try launchctl(["bootstrap", "system", deployment.enginePlistPath], .startFailed)
            }
            state = try wait(seconds: 5, failure: .startFailed) { $0.running }
            guard state.running else {
                throw ControlError(failure: .startFailed, detail: "The engine did not stay running.")
            }
        }
        // Reply once muta answers its status socket. A freshly started engine is not a failure.
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if (try? Command.runBlocking(deployment.enginePath, ["status"], timeout: 1))?.succeeded == true { return }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
    }

    private func stop() throws {
        // First the boot override: even if unloading fails, the engine stays off after a restart.
        try launchctl(["disable", deployment.engineJob], .stopFailed)
        let state = try read(.stopFailed)
        if state.loaded {
            // Unloading may race with launchd finishing it; the wait below decides.
            _ = try? Command.runBlocking("/bin/launchctl", ["bootout", deployment.engineJob], timeout: 10)
        }
        let deadline = Date().addingTimeInterval(10)
        while try read(.stopFailed).loaded || state.pid.map(isAlive) == true {
            guard Date() < deadline else {
                throw ControlError(failure: .stopFailed, detail: "The engine is still stopping.")
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// Only the installed, root-owned definition is ever loaded.
    private func verifyInstallation() throws {
        for path in [deployment.enginePath, deployment.enginePlistPath] {
            var info = stat()
            guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_uid == 0, info.st_mode & 0o022 == 0 else {
                throw ControlError(failure: .notInstalled, detail: path)
            }
        }
        guard NSDictionary(contentsOfFile: deployment.enginePlistPath) == deployment.enginePlist as NSDictionary else {
            throw ControlError(failure: .notInstalled, detail: deployment.enginePlistPath)
        }
    }

    private func read(_ failure: ControlFailure) throws -> ServiceState {
        do { return try ServiceState.read(deployment) }
        catch { throw ControlError(failure: failure, detail: "Unable to read the service state.") }
    }

    private func wait(seconds: TimeInterval, failure: ControlFailure,
                      until done: (ServiceState) -> Bool) throws -> ServiceState {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            let state = try read(failure)
            if done(state) || Date() >= deadline { return state }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func launchctl(_ arguments: [String], _ failure: ControlFailure) throws {
        let result = try Command.runBlocking("/bin/launchctl", arguments, timeout: 10)
        guard result.succeeded else {
            throw ControlError(failure: failure, detail: "launchctl \(arguments[0]): " + result.output)
        }
    }

    private func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
