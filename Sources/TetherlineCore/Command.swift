import Darwin
import Foundation

struct CommandResult: Sendable, Equatable {
    let status: Int32
    let output: String
    let timedOut: Bool

    var succeeded: Bool { status == 0 && !timedOut }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk.prefix(max(0, Command.outputLimit - data.count)))
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

enum Command {
    static let outputLimit = 65_536

    static func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 5) async throws -> CommandResult {
        try await offloaded { try runBlocking(executable, arguments, timeout: timeout) }
    }

    /// Runs a process with combined stdout/stderr, capped at `outputLimit`, and kills it at the deadline.
    static func runBlocking(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        // Drain while running, including past the capture limit, so the child never blocks on a full pipe.
        let buffer = OutputBuffer()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            defer { drained.signal() }
            while let data = try? pipe.fileHandleForReading.read(upToCount: 4096), !data.isEmpty {
                buffer.append(data)
            }
        }
        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            kill(process.processIdentifier, SIGKILL)
            exited.wait()
        }
        // A descendant that inherited the pipe must not hold the caller indefinitely.
        _ = drained.wait(timeout: .now() + 1)
        return CommandResult(status: process.terminationStatus, output: buffer.text, timedOut: timedOut)
    }
}

/// Runs blocking work (process I/O, file hashing) on a GCD thread, so it never
/// occupies the main actor or a thread of the Swift concurrency pool.
func offloaded<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            continuation.resume(with: Result { try work() })
        }
    }
}
