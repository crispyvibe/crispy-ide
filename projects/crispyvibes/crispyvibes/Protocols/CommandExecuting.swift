// CommandExecuting.swift — SSH Remote Development

import Darwin
import Foundation

/// Result of a command execution (local Process or remote SSH exec).
struct CommandExecutionResult: Sendable {
    let terminationStatus: Int32
    let stdoutData: Data
    let stderrData: Data
}

/// Abstraction over shell command execution.
/// Local: wraps Foundation.Process. Remote: wraps SSH exec channel.
/// All methods are async and run off the main actor.
protocol CommandExecuting: Sendable {
    func execute(
        tool: String,
        arguments: [String],
        stdinData: Data?,
        timeout: TimeInterval
    ) async throws -> CommandExecutionResult
}

enum ManagedProcessRunnerError: Error {
    case timedOut(TimeInterval)
}

final class ManagedProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var currentProcess: Process?

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        stdinData: Data? = nil,
        timeout: TimeInterval,
        throwOnTimeout: Bool
    ) throws -> CommandExecutionResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        var inputPipe: Pipe?
        let terminationGroup = DispatchGroup()
        let stdoutReadHandle = outputPipe.fileHandleForReading
        let stdoutWriteHandle = outputPipe.fileHandleForWriting
        let stderrReadHandle = errorPipe.fileHandleForReading
        let stderrWriteHandle = errorPipe.fileHandleForWriting
        var writeHandlesClosed = false

        let stdoutBox = UnsafeMutableTransferBox(Data())
        let stderrBox = UnsafeMutableTransferBox(Data())
        let readGroup = DispatchGroup()

        let drainQueue = DispatchQueue.global(qos: drainQoS())

        readGroup.enter()
        drainQueue.async {
            autoreleasepool {
                stdoutBox.value = stdoutReadHandle.readDataToEndOfFile()
            }
            readGroup.leave()
        }

        readGroup.enter()
        drainQueue.async {
            autoreleasepool {
                stderrBox.value = stderrReadHandle.readDataToEndOfFile()
            }
            readGroup.leave()
        }

        defer {
            process.terminationHandler = nil
            terminateIfNeeded(process, terminationGroup: terminationGroup)
            if !writeHandlesClosed {
                stdoutWriteHandle.closeFile()
                stderrWriteHandle.closeFile()
            }
            stdinCleanup(inputPipe)
            readGroup.wait()
            stdoutReadHandle.closeFile()
            stderrReadHandle.closeFile()
            setCurrentProcess(nil)
        }

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        terminationGroup.enter()
        process.terminationHandler = { _ in
            terminationGroup.leave()
        }

        setCurrentProcess(process)

        if let stdinData {
            let createdInputPipe = Pipe()
            inputPipe = createdInputPipe
            process.standardInput = createdInputPipe
            try process.run()
            stdoutWriteHandle.closeFile()
            stderrWriteHandle.closeFile()
            writeHandlesClosed = true
            createdInputPipe.fileHandleForWriting.write(stdinData)
            createdInputPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
            stdoutWriteHandle.closeFile()
            stderrWriteHandle.closeFile()
            writeHandlesClosed = true
        }

        if timeout > 0 {
            let didExit = terminationGroup.wait(timeout: .now() + timeout)
            if didExit == .timedOut {
                terminateIfNeeded(process, terminationGroup: terminationGroup)
                if throwOnTimeout {
                    readGroup.wait()
                    throw ManagedProcessRunnerError.timedOut(timeout)
                }
            }
        } else {
            terminationGroup.wait()
        }

        readGroup.wait()

        return CommandExecutionResult(
            terminationStatus: process.terminationStatus,
            stdoutData: stdoutBox.value,
            stderrData: stderrBox.value
        )
    }

    func cancel() {
        lock.lock()
        let process = currentProcess
        lock.unlock()
        guard let process else { return }
        terminateIfNeeded(process, terminationGroup: nil)
    }

    private func setCurrentProcess(_ process: Process?) {
        lock.lock()
        currentProcess = process
        lock.unlock()
    }

    private func terminateIfNeeded(_ process: Process, terminationGroup: DispatchGroup?) {
        guard process.isRunning else { return }
        process.terminate()
        if terminationGroup?.wait(timeout: .now() + 1.0) == .timedOut {
            let pid = process.processIdentifier
            if pid > 0 {
                kill(pid, SIGKILL)
            }
            _ = terminationGroup?.wait(timeout: .now() + 0.5)
        }
    }

    private func stdinCleanup(_ pipe: Pipe?) {
        guard let pipe else { return }
        pipe.fileHandleForReading.closeFile()
    }

    private func drainQoS() -> DispatchQoS.QoSClass {
        switch qos_class_self() {
        case QOS_CLASS_USER_INTERACTIVE:
            return .userInteractive
        case QOS_CLASS_USER_INITIATED:
            return .userInitiated
        case QOS_CLASS_DEFAULT:
            return .default
        case QOS_CLASS_UTILITY:
            return .utility
        case QOS_CLASS_BACKGROUND:
            return .background
        default:
            return .userInitiated
        }
    }
}
