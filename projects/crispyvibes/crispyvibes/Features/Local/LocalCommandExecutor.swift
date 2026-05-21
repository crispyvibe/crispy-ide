// LocalCommandExecutor.swift — SSH Remote Development

import Foundation

/// Executes shell commands locally via Foundation.Process.
/// All work runs off the main actor.
struct LocalCommandExecutor: CommandExecuting {
    func execute(
        tool: String,
        arguments: [String],
        stdinData: Data?,
        timeout: TimeInterval
    ) async throws -> CommandExecutionResult {
        let runner = ManagedProcessRunner()
        return try await withTaskCancellationHandler {
            try await Task(priority: .utility) {
                try runner.run(
                    executableURL: URL(fileURLWithPath: tool),
                    arguments: arguments,
                    stdinData: stdinData,
                    timeout: timeout,
                    throwOnTimeout: false
                )
            }.value
        } onCancel: {
            runner.cancel()
        }
    }
}
