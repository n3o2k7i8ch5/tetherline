import Darwin
import Foundation

/// Talks to the isolated probe controller as the account it runs under.
@main enum Client {
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    static func run() throws {
        let command = CommandLine.arguments[1]
        let path = Deployment.probe.socketPath
        if command == "invalid" {
            for text in ["start;touch /tmp/tetherline-injection\n", "stop\nstart\n", "run /bin/sh\n", "hello\n", "status\n",
                         String(repeating: "x", count: 64)] {
                let reply = try ControlClient.exchange(Data(text.utf8), path: path)
                guard !reply.ok, reply.failure == ControlFailure.unsupported.rawValue else { exit(1) }
            }
            print("PASS arbitrary, removed and oversized commands are rejected")
        } else {
            guard let action = ControlAction(rawValue: command) else { exit(2) }
            let reply = try ControlClient.exchange(Data((action.rawValue + "\n").utf8), path: path)
            guard reply.ok else {
                print("REJECTED \(command): \(reply.failure ?? "-") \(reply.message)")
                exit(3)
            }
            print("OK \(command) as UID \(getuid())")
        }
    }
}
