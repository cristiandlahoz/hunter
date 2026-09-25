import Darwin
import Foundation

struct CommandResult: Sendable {
    let status: Int32
    let output: String
    let error: String
    let timedOut: Bool

    var succeeded: Bool { status == 0 && !timedOut }
}

/// Runs only fixed, absolute system executables. Output is drained concurrently so large
/// `pmset -g log` responses cannot deadlock the app.
enum CommandRunner {
    static func run(
        _ executable: String,
        arguments: [String] = [],
        timeout: TimeInterval = 12,
        keepLine: (@Sendable (String) -> Bool)? = nil
    ) -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let outputBox = LockedBox(Data())
        let errorBox = LockedBox(Data())
        let readers = DispatchGroup()

        func drain(_ handle: FileHandle, into box: LockedBox<Data>, filter: (@Sendable (String) -> Bool)?) {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { readers.leave() }
                var pending = ""
                while true {
                    let chunk: Data
                    do {
                        guard let next = try handle.read(upToCount: 64 * 1_024), !next.isEmpty else { break }
                        chunk = next
                    } catch {
                        break
                    }
                    guard let filter else {
                        box.mutate { $0.append(chunk) }
                        continue
                    }
                    pending += String(data: chunk, encoding: .utf8) ?? ""
                    let lines = pending.split(separator: "\n", omittingEmptySubsequences: false)
                    pending = lines.last.map(String.init) ?? ""
                    for line in lines.dropLast() {
                        let value = String(line)
                        if filter(value) { box.mutate { $0.append(Data((value + "\n").utf8)) } }
                    }
                }
                if let filter, !pending.isEmpty, filter(pending) {
                    box.mutate { $0.append(Data(pending.utf8)) }
                }
            }
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: "", error: error.localizedDescription, timedOut: false)
        }

        drain(stdoutPipe.fileHandleForReading, into: outputBox, filter: keepLine)
        drain(stderrPipe.fileHandleForReading, into: errorBox, filter: nil)

        let wait = finished.wait(timeout: .now() + timeout)
        let timedOut = wait == .timedOut
        if timedOut, process.isRunning {
            process.terminate()
            if finished.wait(timeout: .now() + 0.5) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
        }
        _ = readers.wait(timeout: .now() + 1)

        return CommandResult(
            status: process.isRunning ? -1 : process.terminationStatus,
            output: String(data: outputBox.value, encoding: .utf8) ?? "",
            error: String(data: errorBox.value, encoding: .utf8) ?? "",
            timedOut: timedOut
        )
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value { lock.withLock { storage } }

    func mutate(_ body: (inout Value) -> Void) {
        lock.withLock { body(&storage) }
    }
}
