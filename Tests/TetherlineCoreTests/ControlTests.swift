import Darwin
import Foundation
import XCTest
@testable import TetherlineCore

final class ControlTests: XCTestCase {
    func testOnlyStartAndStopCanBeDecoded() {
        for command in ["start; id", "stop\nstart", "run /bin/sh", "install /tmp/muta", "uninstall", "hello", "status", "START", ""] {
            XCTAssertNil(ControlAction(rawValue: command))
        }
        XCTAssertEqual(ControlAction(rawValue: "start"), .start)
        XCTAssertEqual(ControlAction(rawValue: "stop"), .stop)
    }

    /// Quit and Turn off may still reach the previous controller until the next Enable updates it.
    func testPreviousControllerRepliesStillDecode() throws {
        let success = try JSONDecoder().decode(ControlReply.self, from: Data(#"{"version":1,"ok":true,"message":""}"#.utf8))
        XCTAssertTrue(success.ok)
        XCTAssertNil(success.failure)
        let failure = try JSONDecoder().decode(ControlReply.self, from: Data(#"{"version":1,"ok":false,"message":"Busy"}"#.utf8))
        XCTAssertEqual(ControlClient.error(for: failure), .message("Busy"))
    }

    func testFailuresMapToLocalizedTextWithDetail() throws {
        let reply = ControlReply.failed(.startFailed, "launchctl bootstrap: 5")
        let roundTrip = try JSONDecoder().decode(ControlReply.self, from: JSONEncoder().encode(reply))
        XCTAssertEqual(roundTrip, reply)
        guard case .message(let text) = ControlClient.error(for: roundTrip) else { return XCTFail() }
        XCTAssertTrue(text.hasSuffix("launchctl bootstrap: 5"))
        XCTAssertNotEqual(text, "launchctl bootstrap: 5")
        // An unknown failure from a newer controller still decodes and shows its message.
        let future = try JSONDecoder().decode(ControlReply.self, from: Data(#"{"version":3,"ok":false,"failure":"new","message":"Detail"}"#.utf8))
        XCTAssertEqual(ControlClient.error(for: future), .message("Detail"))
    }

    func testSocketUsesKernelCredentialsAndCapsMessageSize() throws {
        var pair: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
        defer { close(pair[0]); close(pair[1]) }
        XCTAssertEqual(try ControlSocket.peerUID(pair[0]), getuid())
        try ControlSocket.write(pair[0], data: Data(repeating: 65, count: 128))
        shutdown(pair[0], SHUT_WR)
        XCTAssertThrowsError(try ControlSocket.read(pair[1], limit: 32))
    }
}
