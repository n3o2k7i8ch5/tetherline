import XCTest
@testable import TetherlineCore

final class CoreTests: XCTestCase {
    func testRealSamsungOutputAndPacketUnits() throws {
        let status = try MutaStatus(output: """
        state      connected
        device     SAMSUNG SAMSUNG_Android (04e8:6864)
        interface  utun5
        address    10.221.188.173
        gateway    10.221.188.209
        dns        10.221.188.209
        in         43597
        out        40568
        """)
        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.device, "SAMSUNG SAMSUNG_Android (04e8:6864)")
        XCTAssertEqual(status.interface, "utun5")
        XCTAssertEqual(status.address, "10.221.188.173")
        XCTAssertEqual(status.packetsIn, 43597)
        XCTAssertEqual(status.packetsOut, 40568)
    }

    func testDisconnectedAndFutureFields() throws {
        let status = try MutaStatus(output: "state\twaiting\ndevice -\ninterface -\naddress -\nin 0\nout 0\nfuture anything\n")
        XCTAssertEqual(status.state, .waiting)
        XCTAssertNil(status.device)
        XCTAssertNil(status.interface)
        XCTAssertEqual(status.packetsIn, 0)
    }

    func testMalformedOrIncompleteOutputDoesNotClaimConnected() {
        for text in ["", "muta: cannot reach the service", "state future", "state connected\ninterface utun5"] {
            XCTAssertThrowsError(try MutaStatus(output: text))
        }
    }

    func testBadCountersAreUnknownAndLargeCountersDoNotOverflow() throws {
        let status = try MutaStatus(output: "state waiting\nin -1\nout 18446744073709551615")
        XCTAssertNil(status.packetsIn)
        XCTAssertEqual(status.packetsOut, UInt64.max)
    }

    func testRoutingDistinguishesWifiVPNAndUnknown() {
        let actual = "   route to: default\n    gateway: 10.221.188.209\n  interface: utun5\n      flags: <UP>"
        XCTAssertEqual(RouteStatus.interface(from: actual), "utun5")
        XCTAssertNil(RouteStatus.interface(from: "route: not in table"))
        XCTAssertNil(RouteStatus.warning(tether: "utun5", primary: "utun5", wifiInterfaces: ["en0"]))
        XCTAssertTrue(RouteStatus.warning(tether: "utun5", primary: "en0", wifiInterfaces: ["en0"])!.contains("Wi-Fi"))
        XCTAssertFalse(RouteStatus.warning(tether: "utun5", primary: "utun2", wifiInterfaces: ["en0"])!.contains("Wi-Fi"))
        XCTAssertTrue(RouteStatus.warning(tether: "utun5", primary: nil, wifiInterfaces: [])!.contains("could not be determined"))
    }

    func testProcessTimeout() throws {
        let start = Date()
        let result = try Command.runBlocking("/bin/sleep", ["10"], timeout: 0.1)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testLargeOutputDoesNotDeadlock() throws {
        let result = try Command.runBlocking("/usr/bin/awk", ["BEGIN { for(i=0; i<20000; i++) print \"outputoutputoutput\" }"], timeout: 3)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.utf8.count, 65_536)
    }

    func testQuickCommandReturnsWithoutWaitingForPipeTimeout() throws {
        let start = Date()
        let result = try Command.runBlocking("/bin/echo", ["ready"], timeout: 5)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, "ready\n")
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    func testNonzeroExitAndStderrArePreserved() throws {
        let result = try Command.runBlocking("/bin/sh", ["-c", "echo failure >&2; exit 7"], timeout: 2)
        XCTAssertEqual(result.status, 7)
        XCTAssertTrue(result.output.contains("failure"))
    }
}

