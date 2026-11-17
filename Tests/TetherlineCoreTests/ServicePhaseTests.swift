import XCTest
@testable import TetherlineCore

final class ServicePhaseTests: XCTestCase {
    let connected = try! MutaStatus(output: "state connected\ninterface utun5\naddress 10.0.0.2\nin 7\nout 8")
    let waiting = try! MutaStatus(output: "state waiting")

    func phase(_ observation: ServiceObservation?, _ operation: ServiceOperation? = nil) -> ServicePhase {
        ServicePhase(operation: operation, observation: observation)
    }

    func testRunningEngineShowsItsStatus() {
        let on = ServiceObservation(installation: .current, service: ServiceState(loaded: true, pid: 9), status: connected)
        XCTAssertEqual(phase(on), .connected(connected))
        XCTAssertEqual(phase(ServiceObservation(installation: .current, service: ServiceState(loaded: true, pid: 9), status: waiting)), .waiting)
        // An unreadable status of a running engine is a failure, never "connected".
        let unreadable = ServiceObservation(installation: .current, service: ServiceState(loaded: true, pid: 9), error: "no socket")
        XCTAssertEqual(phase(unreadable), .failed("no socket"))
    }

    func testOffAsksForAdministratorOnlyWhenComponentsMustBeInstalled() {
        XCTAssertEqual(phase(ServiceObservation(installation: .current)), .off(needsAdministrator: false))
        XCTAssertEqual(phase(ServiceObservation(installation: .outdated)), .off(needsAdministrator: true))
        XCTAssertEqual(phase(ServiceObservation(installation: .missing)), .off(needsAdministrator: true))
    }

    func testLoadedButNotRunningIsAFailureWithTurnOffAvailable() {
        guard case .failed = phase(ServiceObservation(installation: .current, service: ServiceState(loaded: true))) else {
            return XCTFail("A loaded engine that does not run must be reported")
        }
    }

    func testConflictOutranksEverythingObserved() {
        let both = ServiceObservation(service: ServiceState(loaded: true, pid: 9, conflict: true), status: connected)
        XCTAssertEqual(phase(both), .conflict)
        XCTAssertEqual(phase(ServiceObservation(service: ServiceState(conflict: true))), .conflict)
        XCTAssertTrue(ServicePhase.conflict.isError)
    }

    func testApprovalAndReadErrorsWhenNotRunning() {
        XCTAssertEqual(phase(ServiceObservation(installation: .current, approvalRequired: true)), .approvalRequired)
        XCTAssertEqual(phase(ServiceObservation(error: "launchd timed out")), .failed("launchd timed out"))
    }

    /// While an action runs, intermediate system states (a job unloading, an engine
    /// not answering yet) must not surface as failures.
    func testServiceActionsOwnThePhase() {
        let unloading = ServiceObservation(installation: .current, service: ServiceState(loaded: true))
        XCTAssertEqual(phase(unloading, .disabling), .stopping)
        XCTAssertEqual(phase(unloading, .quitting), .stopping)
        XCTAssertEqual(phase(unloading, .enabling), .starting)
        XCTAssertEqual(phase(unloading, .uninstalling), .uninstalling)
        XCTAssertFalse(phase(unloading, .disabling).isError)
        // A settings action does not hide the service state.
        XCTAssertEqual(phase(unloading, .changingLoginItem), phase(unloading))
        XCTAssertEqual(phase(nil), .checking)
    }
}
