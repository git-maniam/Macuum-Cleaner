import Foundation

public struct ShellResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool
    public var succeeded: Bool { status == 0 && !timedOut }
}

private final class LockedBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var string: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}

private final class Flag: @unchecked Sendable {
    private var value = false
    private let lock = NSLock()
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

/// The only place the app spawns subprocesses (`lsof`, `tmutil`, `brew`).
public enum ShellRunner {
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { cont in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let outPipe = Pipe(), errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = FileHandle.nullDevice

            let out = LockedBuffer(), err = LockedBuffer(), timedOut = Flag()
            outPipe.fileHandleForReading.readabilityHandler = { out.append($0.availableData) }
            errPipe.fileHandleForReading.readabilityHandler = { err.append($0.availableData) }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                out.append((try? outPipe.fileHandleForReading.readToEnd()) ?? Data())
                err.append((try? errPipe.fileHandleForReading.readToEnd()) ?? Data())
                cont.resume(returning: ShellResult(status: proc.terminationStatus, stdout: out.string,
                                                   stderr: err.string, timedOut: timedOut.isSet))
            }
            do { try process.run() } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                cont.resume(throwing: error); return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { timedOut.set(); process.terminate() }
            }
        }
    }
}
