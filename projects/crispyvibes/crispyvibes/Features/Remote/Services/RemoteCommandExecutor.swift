// RemoteCommandExecutor.swift — SSH Remote Development
// Executes shell commands on a remote host via system ssh control socket.

import Foundation

struct RemoteCommandExecutor: CommandExecuting {
    let connection: SSHConnection

    func execute(
        tool: String,
        arguments: [String],
        stdinData: Data?,
        timeout: TimeInterval
    ) async throws -> CommandExecutionResult {
        let escapedArgs = ([tool] + arguments).map(shellEscape).joined(separator: " ")
        let sep = "__CRISPYVIBES_\(UUID().uuidString.prefix(8))__"
        let cmd = "exec 3>&1; __err=$( { \(escapedArgs); } 2>&1 1>&3 ); __rc=$?; exec 3>&-; printf '\\n\(sep)%d\(sep)%s' \"$__rc\" \"$__err\""

        var args = connection.sshArgs()
        args.append(cmd)

        let result = try await SSHConnection.runSSH(args: args, timeout: timeout, stdinData: stdinData)
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""

        let parts = raw.components(separatedBy: sep)
        let stdout = parts.first ?? ""
        let exitCode = parts.count > 1 ? Int32(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 : 0
        let stderr = parts.count > 2 ? parts[2] : ""

        return CommandExecutionResult(
            terminationStatus: exitCode,
            stdoutData: Data(stdout.utf8),
            stderrData: Data(stderr.utf8)
        )
    }

    private func shellEscape(_ arg: String) -> String {
        let safe = arg.allSatisfy {
            $0.isLetter || $0.isNumber || "-_./:%@=".contains($0)
        }
        if safe && !arg.isEmpty { return arg }
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
