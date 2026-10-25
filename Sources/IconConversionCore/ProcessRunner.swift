import Foundation
import Darwin

public struct ProcessOutput: Sendable {
    public let output: String
    public let status: Int32
}

public protocol ProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], directory: URL?, environment: [String: String]?) async throws -> ProcessOutput
}

private final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false

    func launch(_ value: Process) throws {
        try lock.withLock {
            if cancelled { throw CancellationError() }
            try value.run()
            process = value
        }
    }

    func stop(timeout: Bool = false) {
        lock.withLock {
            if timeout { timedOut = true } else { cancelled = true }
            guard let process, process.isRunning else { return }
            process.terminate()
            // Some Apple tools ignore SIGTERM. Keep the Process alive until it is reaped.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
                lock.withLock {
                    if let process = self.process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
    }

    func finish() throws {
        try lock.withLock {
            process = nil
            if cancelled { throw CancellationError() }
            if timedOut { throw ConversionError.validation("Developer tool timed out. Retry the operation; check Xcode's installation if it persists.") }
        }
    }
}

/// Regular files drain both output streams without pipe deadlocks; only the diagnostic tail is read into memory.
public struct ProcessRunner: ProcessRunning {
    public let timeout: TimeInterval
    public init(timeout: TimeInterval = 180) { self.timeout = timeout }

    public func run(executable: URL, arguments: [String], directory: URL? = nil,
                    environment: [String: String]? = nil) async throws -> ProcessOutput {
        try Task.checkCancellation()
        let state = RunningProcess()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let log = FileManager.default.temporaryDirectory.appendingPathComponent("IconMator-process-\(UUID().uuidString).log")
                    do {
                        guard FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                            throw ConversionError.validation("Cannot create a temporary process log.")
                        }
                        defer { try? FileManager.default.removeItem(at: log) }
                        let handle = try FileHandle(forWritingTo: log)
                        defer { try? handle.close() }
                        let process = Process()
                        process.executableURL = executable
                        process.arguments = arguments
                        process.currentDirectoryURL = directory
                        process.environment = environment
                        process.standardOutput = handle
                        process.standardError = handle
                        try state.launch(process)
                        let timer = DispatchWorkItem { state.stop(timeout: true) }
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                        process.waitUntilExit()
                        timer.cancel()
                        try state.finish()
                        let input = try FileHandle(forReadingFrom: log)
                        defer { try? input.close() }
                        let length = try input.seekToEnd()
                        try input.seek(toOffset: length > 65_536 ? length - 65_536 : 0)
                        let output = String(decoding: try input.readToEnd() ?? Data(), as: UTF8.self)
                        if process.terminationStatus != 0 {
                            throw ConversionError.processFailed(executable.lastPathComponent, process.terminationStatus, output)
                        }
                        continuation.resume(returning: ProcessOutput(output: output, status: process.terminationStatus))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { state.stop() }
    }
}
