import Foundation

/// launchd's description of one job (`launchctl print`).
struct LaunchdJob: Equatable, Sendable {
    let state: String?
    let program: String?
    let pid: Int32?

    init(output: String) {
        var fields: [String: String] = [:]
        // Only job-level fields count. Nested coalitions also contain a state and a pid.
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("\t"), !line.hasPrefix("\t\t") else { continue }
            let pair = line.dropFirst().components(separatedBy: " = ")
            if pair.count == 2 { fields[pair[0]] = pair[1] }
        }
        state = fields["state"]
        program = fields["program"]
        pid = fields["pid"].flatMap(Int32.init)
    }

    func isRunning(expectedProgram: String) -> Bool {
        state == "running" && program == expectedProgram && (pid ?? 0) > 0
    }
}

/// What launchd and the process table say about the engine. The app reads it to
/// display state; the controller reads it the same way to start and stop.
struct ServiceState: Equatable, Sendable {
    /// Our job is loaded: tethering is on, even while the engine restarts or fails.
    var loaded = false
    /// Our running engine, as launchd reports it.
    var pid: Int32?
    /// An engine from another installation runs, or another program uses our label.
    var conflict = false

    var running: Bool { pid != nil }

    init(loaded: Bool = false, pid: Int32? = nil, conflict: Bool = false) {
        self.loaded = loaded
        self.pid = pid
        self.conflict = conflict
    }

    /// - Parameters:
    ///   - job: `launchctl print` output, or nil when the label is not loaded.
    ///   - engines: command lines of engines in service mode (`… muta run`).
    ///
    /// Engines are told apart by executable path, not PID: the two reads happen at
    /// different moments, and a PID comparison would mistake our own engine,
    /// starting or stopping in between, for another installation.
    init(job: String?, engines: [String], expectedProgram: String) {
        if let job {
            let description = LaunchdJob(output: job)
            if description.program == expectedProgram {
                loaded = true
                if description.isRunning(expectedProgram: expectedProgram) { pid = description.pid }
            } else {
                conflict = true // Fail closed: never treat an unverified job as ours.
            }
        }
        if engines.contains(where: { !$0.hasPrefix(expectedProgram + " ") }) { conflict = true }
    }

    /// Matches engines in service mode (`muta run`), wherever installed. Short-lived
    /// clients such as `muta status`, from this app or a terminal, are not engines.
    static func enginePattern(_ deployment: Deployment) -> String {
        "(^|/)" + deployment.engineName + " run( |$)"
    }

    static func read(_ deployment: Deployment) throws -> ServiceState {
        let job = try Command.runBlocking("/bin/launchctl", ["print", deployment.engineJob], timeout: 3)
        let processes = try Command.runBlocking("/usr/bin/pgrep", ["-lf", enginePattern(deployment)], timeout: 3)
        // launchctl: 113 = label not loaded; pgrep: 1 = no match.
        guard !job.timedOut, job.status == 0 || job.status == 113,
              !processes.timedOut, processes.status == 0 || processes.status == 1 else {
            throw TetherlineError.message(L10n.text("Unable to read the service state. Try again shortly."))
        }
        // `pgrep -l` prints "PID command line".
        let engines = processes.output.split(whereSeparator: \.isNewline).compactMap { line in
            line.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init)
        }
        return ServiceState(job: job.status == 0 ? job.output : nil, engines: engines, expectedProgram: deployment.enginePath)
    }
}
