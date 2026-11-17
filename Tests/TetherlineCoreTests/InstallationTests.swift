import Foundation
import XCTest
@testable import TetherlineCore

final class InstallationTests: XCTestCase {
    var root: URL!
    var deployment: Deployment!
    var bundle: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        bundle = root.appendingPathComponent("bundle")
        for directory in ["installed", "daemons", "bundle"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        deployment = Deployment(engineLabel: "test.engine", controlLabel: "test.control",
                                directory: root.appendingPathComponent("installed").path, logDirectory: root.path,
                                appIdentifier: "test.app", engineName: "muta", engineSocket: nil,
                                launchDaemons: root.appendingPathComponent("daemons").path)
        try Data("engine v1".utf8).write(to: bundle.appendingPathComponent("muta"))
        try Data("control v1".utf8).write(to: bundle.appendingPathComponent("control"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    var check: InstallationCheck {
        InstallationCheck(deployment: deployment, bundledEngine: bundle.appendingPathComponent("muta").path,
                          bundledControl: bundle.appendingPathComponent("control").path, owner: 501)
    }

    func install(owner: uid_t = 501) throws {
        try FileManager.default.copyItem(atPath: check.bundledEngine, toPath: deployment.enginePath)
        try FileManager.default.copyItem(atPath: check.bundledControl, toPath: deployment.controlPath)
        try (deployment.enginePlist as NSDictionary).write(to: URL(fileURLWithPath: deployment.enginePlistPath))
        try (deployment.controlPlist(owner: owner) as NSDictionary).write(to: URL(fileURLWithPath: deployment.controlPlistPath))
    }

    func testNothingInstalledIsMissing() {
        XCTAssertEqual(check.state(), .missing)
    }

    func testMatchingInstallationIsCurrent() throws {
        try install()
        XCTAssertEqual(check.state(), .current)
    }

    /// The previous design deleted the engine plist when tethering was off.
    func testPartialInstallationIsOutdated() throws {
        try install()
        try FileManager.default.removeItem(atPath: deployment.enginePlistPath)
        XCTAssertEqual(check.state(), .outdated)
    }

    func testChangedExecutableIsDetectedDespiteCachedDigest() throws {
        try install()
        XCTAssertEqual(check.state(), .current)
        try Data("control v2".utf8).write(to: URL(fileURLWithPath: check.bundledControl)) // same size, new content
        XCTAssertEqual(check.state(), .outdated)
    }

    func testControllerOwnedByAnotherAccountIsOutdated() throws {
        try install(owner: 502)
        XCTAssertEqual(check.state(), .outdated)
    }

    func testChangedLaunchdDefinitionIsOutdated() throws {
        try install()
        let modified = NSMutableDictionary(dictionary: deployment.enginePlist)
        modified["ProcessType"] = "Background"
        try modified.write(to: URL(fileURLWithPath: deployment.enginePlistPath))
        XCTAssertEqual(check.state(), .outdated)
    }

    func testInstallScriptCarriesDigestsOfTheBundle() throws {
        let script = try check.installScript()
        XCTAssertTrue(script.contains(try XCTUnwrap(FileDigest.sha256(check.bundledEngine))))
        XCTAssertTrue(script.contains(try XCTUnwrap(FileDigest.sha256(check.bundledControl))))
    }
}
