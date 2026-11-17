import Foundation
import XCTest
@testable import TetherlineCore

final class InstallerTests: XCTestCase {
    let digest = String(repeating: "a", count: 64)

    func testShellQuotingDoesNotExecuteValues() throws {
        let value = "/tmp/engine ' $(echo injected) `echo injected`\nnext"
        let result = try Command.runBlocking("/bin/sh", ["-c", "printf '%s' " + Installer.quote(value)], timeout: 2)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, value)
    }

    func testScriptsParseAsPOSIXShellForBothDeployments() throws {
        for deployment in [Deployment.production, .probe] {
            let installer = Installer(deployment: deployment)
            let install = try installer.install(engine: "/tmp/engine ' $(id)", engineHash: digest,
                                                control: "/tmp/control ' $(id)", controlHash: digest, owner: 501)
            for script in [install, installer.uninstall] {
                let result = try Command.runBlocking("/bin/sh", ["-n", "-c", script], timeout: 2)
                XCTAssertEqual(result.status, 0, result.output)
            }
        }
    }

    func testInvalidDigestsAndOwnersAreRejectedBeforeAuthorization() {
        let installer = Installer(deployment: .probe)
        for invalid in ["", "$(echo injected)", String(repeating: "g", count: 64)] {
            XCTAssertThrowsError(try installer.install(engine: "/e", engineHash: invalid, control: "/c", controlHash: digest, owner: 501))
            XCTAssertThrowsError(try installer.install(engine: "/e", engineHash: digest, control: "/c", controlHash: invalid, owner: 501))
        }
        XCTAssertThrowsError(try installer.install(engine: "/e", engineHash: digest, control: "/c", controlHash: digest, owner: 0))
    }

    /// The probe test must never touch production paths or muta's real socket.
    func testProbeIsIsolatedFromProduction() throws {
        let probe = Deployment.probe, production = Deployment.production
        for (a, b) in [(probe.engineLabel, production.engineLabel), (probe.controlLabel, production.controlLabel),
                       (probe.directory, production.directory), (probe.logDirectory, production.logDirectory),
                       (probe.engineName, production.engineName)] {
            XCTAssertNotEqual(a, b)
        }
        XCTAssertNil(probe.engineSocket)
        XCTAssertFalse(Installer(deployment: probe).uninstall.contains("/var/run/muta.sock"))
        XCTAssertTrue(Installer(deployment: production).uninstall.contains("/var/run/muta.sock"))
        // The engine name is embedded in a regular expression and fits the kernel's process name.
        for name in [probe.engineName, production.engineName] {
            XCTAssertTrue(name.allSatisfy { $0.isLetter && $0.isASCII })
            XCTAssertLessThanOrEqual(name.count, 15)
        }
    }

    func testEngineDefinitionMatchesPackagedReference() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let reference = NSDictionary(contentsOf: root.appendingPathComponent("Resources/pl.tetherline.muta.plist"))
        XCTAssertEqual(reference, Deployment.production.enginePlist as NSDictionary)
        XCTAssertEqual(reference?["ProgramArguments"] as? [String], ["/Library/Application Support/Tetherline/muta", "run"])
        XCTAssertNil(reference?["BundleProgram"])
        XCTAssertNil(reference?["Disabled"], "Boot behaviour follows the launchd override, not the plist")
    }

    func testControllerIsActivatedOnDemandForTheInstallingAccount() {
        let deployment = Deployment.production
        let plist = deployment.controlPlist(owner: 501)
        XCTAssertNil(plist["RunAtLoad"])
        XCTAssertNil(plist["KeepAlive"])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [deployment.controlPath, "501"])
        let socket = (plist["Sockets"] as! [String: [String: Any]])["Control"]!
        XCTAssertEqual(socket["SockPathName"] as? String, "/Library/Application Support/Tetherline/control.sock")
    }

    /// Stopped engines must not come back at boot; the installer leaves that to the override.
    func testInstallLeavesAStoppedEngineDisabled() throws {
        let script = try Installer(deployment: .production).install(engine: "/e", engineHash: digest, control: "/c", controlHash: digest, owner: 501)
        XCTAssertTrue(script.contains(#"if ! loaded "$engine_job"; then /bin/launchctl disable "$engine_job"; fi"#))
    }
}
