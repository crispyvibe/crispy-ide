import Darwin
import Foundation

extension PaneWorkerExecutor {
    static func runToolCommand(
        tool: String,
        arguments: [String],
        stdinData: Data? = nil,
        timeout: TimeInterval = gitCommandTimeout
    ) throws -> CommandResult {
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

        // Read pipes concurrently to prevent deadlock when output exceeds
        // the ~64 KB pipe buffer. Without this, the process blocks on write
        // while we block waiting for termination.
        let stdoutBox = UnsafeMutableTransferBox(Data())
        let stderrBox = UnsafeMutableTransferBox(Data())
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                stdoutBox.value = stdoutReadHandle.readDataToEndOfFile()
            }
            readGroup.leave()
        }

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                stderrBox.value = stderrReadHandle.readDataToEndOfFile()
            }
            readGroup.leave()
        }

        defer {
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
                // Bounded wait — escalate to SIGKILL if SIGTERM is ignored.
                if terminationGroup.wait(timeout: .now() + 1.0) == .timedOut {
                    let pid = process.processIdentifier
                    if pid > 0 { kill(pid, SIGKILL) }
                    _ = terminationGroup.wait(timeout: .now() + 0.5)
                }
            }
            // Close write ends so GCD read blocks see EOF and return.
            if !writeHandlesClosed {
                stdoutWriteHandle.closeFile()
                stderrWriteHandle.closeFile()
            }
            stdinCleanup(inputPipe)
            // Always drain read blocks before closing read handles.
            readGroup.wait()
            stdoutReadHandle.closeFile()
            stderrReadHandle.closeFile()
        }

        process.executableURL = envExecutableURL
        process.arguments = [tool] + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        terminationGroup.enter()
        process.terminationHandler = { _ in
            terminationGroup.leave()
        }

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
                process.terminate()
                if terminationGroup.wait(timeout: .now() + 0.5) == .timedOut {
                    let processID = process.processIdentifier
                    if processID > 0 {
                        kill(processID, SIGKILL)
                    }
                    _ = terminationGroup.wait(timeout: .now() + 0.5)
                }
                readGroup.wait()
                throw PaneWorkerError.workerFailure(
                    String(format: "%@ command timed out after %.1f seconds.", tool, timeout)
                )
            }
        } else {
            terminationGroup.wait()
        }

        readGroup.wait()

        return CommandResult(
            terminationStatus: process.terminationStatus,
            stdoutData: stdoutBox.value,
            stderrData: stderrBox.value
        )
    }

    private static func stdinCleanup(_ pipe: Pipe?) {
        guard let pipe else { return }
        pipe.fileHandleForReading.closeFile()
    }

    static func runGitCommand(
        arguments: [String],
        stdinData: Data? = nil,
        timeout: TimeInterval = gitCommandTimeout
    ) throws -> CommandResult {
        try runToolCommand(
            tool: "git",
            arguments: arguments,
            stdinData: stdinData,
            timeout: timeout
        )
    }
}
