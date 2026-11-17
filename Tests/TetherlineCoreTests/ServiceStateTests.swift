import Foundation
import XCTest
@testable import TetherlineCore

final class ServiceStateTests: XCTestCase {
    let program = "/Library/Application Support/Tetherline/muta"

    func job(_ state: String = "running", program: String? = nil, pid: Int32? = 123) -> String {
        var lines = ["system/pl.tetherline.muta = {", "\tstate = \(state)", "\tprogram = \(program ?? self.program)"]
        if let pid { lines.append("\tpid = \(pid)") }
        return (lines + ["}"]).joined(separator: "\n")
    }

    func testLaunchdJobReadsOnlyTopLevelFields() {
        let crashed = LaunchdJob(output: """
        system/pl.tetherline.muta = {
        \tstate = spawn scheduled
        \tprogram = \(program)
        \tresource coalition = {
        \t\tstate = running
        \t\tpid = 123
        \t}
        }
        """)
        XCTAssertFalse(crashed.isRunning(expectedProgram: program))
        XCTAssertNil(crashed.pid)
        XCTAssertTrue(LaunchdJob(output: job()).isRunning(expectedProgram: program))
        for output in ["", "Could not find service", "state = running\npid = 123"] {
            XCTAssertFalse(LaunchdJob(output: output).isRunning(expectedProgram: program))
        }
    }

    var ours: String { program + " run" }

    func testNotLoadedWithoutEnginesIsOff() {
        XCTAssertEqual(ServiceState(job: nil, engines: [], expectedProgram: program), ServiceState())
    }

    func testRunningFollowsLaunchd() {
        XCTAssertEqual(ServiceState(job: job(), engines: [ours], expectedProgram: program), ServiceState(loaded: true, pid: 123))
        // The process table, read a moment apart, may not show a just-started engine yet.
        XCTAssertEqual(ServiceState(job: job(), engines: [], expectedProgram: program), ServiceState(loaded: true, pid: 123))
    }

    func testOwnEngineStartingOrStoppingIsNeverAConflict() {
        // Unloaded by launchd, process still exiting; or spawned before launchd reports it.
        XCTAssertEqual(ServiceState(job: nil, engines: [ours], expectedProgram: program), ServiceState())
        XCTAssertEqual(ServiceState(job: job("spawn scheduled", pid: nil), engines: [ours + " -v"], expectedProgram: program),
                       ServiceState(loaded: true))
    }

    func testLoadedButFailingEngineIsOnAndNotRunning() {
        let state = ServiceState(job: job("spawn scheduled", pid: nil), engines: [], expectedProgram: program)
        XCTAssertEqual(state, ServiceState(loaded: true))
        XCTAssertFalse(state.running)
    }

    func testOtherInstallationsAndForeignLabelOwnersAreConflicts() {
        let upstream = "/usr/local/libexec/muta/muta run"
        XCTAssertEqual(ServiceState(job: nil, engines: [upstream], expectedProgram: program), ServiceState(conflict: true))
        XCTAssertEqual(ServiceState(job: job(), engines: [ours, upstream], expectedProgram: program),
                       ServiceState(loaded: true, pid: 123, conflict: true))
        // A path that merely starts like ours is another program.
        XCTAssertTrue(ServiceState(job: nil, engines: [program + "-copy run"], expectedProgram: program).conflict)
        let foreign = ServiceState(job: job(program: "/tmp/other"), engines: [], expectedProgram: program)
        XCTAssertFalse(foreign.loaded)
        XCTAssertTrue(foreign.conflict)
        // Unparseable launchd output fails closed.
        XCTAssertTrue(ServiceState(job: "unexpected", engines: [], expectedProgram: program).conflict)
    }

    /// Runs real processes through pgrep: an engine in service mode matches, a status client does not.
    func testEnginePatternMatchesServiceModeOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = directory.appendingPathComponent("TLPatternTest")
        try "#!/bin/sh\n/bin/sleep 5\n".write(to: engine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: engine.path)
        var deployment = Deployment.probe
        deployment = Deployment(engineLabel: deployment.engineLabel, controlLabel: deployment.controlLabel,
                                directory: directory.path, logDirectory: directory.path,
                                appIdentifier: deployment.appIdentifier, engineName: "TLPatternTest", engineSocket: nil)
        func matches(_ arguments: [String]) throws -> Bool {
            let process = Process()
            process.executableURL = engine
            process.arguments = arguments
            try process.run()
            defer { process.terminate(); process.waitUntilExit() }
            Thread.sleep(forTimeInterval: 0.2)
            let result = try Command.runBlocking("/usr/bin/pgrep", ["-lf", ServiceState.enginePattern(deployment)], timeout: 2)
            return result.output.split(whereSeparator: \.isNewline).contains { $0.hasPrefix("\(process.processIdentifier) ") }
        }
        XCTAssertTrue(try matches(["run"]))
        XCTAssertTrue(try matches(["run", "-v"]))
        XCTAssertFalse(try matches(["status"]))
        XCTAssertFalse(try matches(["running"]))
    }
}
