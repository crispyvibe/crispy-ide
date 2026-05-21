// KnownHostsValidator.swift — SSH Remote Development
// Validates SSH host keys against ~/.ssh/known_hosts.

import Foundation

enum KnownHostsValidator {
    enum HostKeyStatus: Equatable {
        case trusted
        case changed
        case unknown
    }

    /// Check host key status against known_hosts.
    static func preflight(host: String, port: UInt16 = 22) async -> HostKeyStatus {
        await Task.detached(priority: .utility) {
            let hostEntry = port == 22 ? host : "[\(host)]:\(port)"
            let lookup = run("/usr/bin/ssh-keygen", args: ["-F", hostEntry])
            let hasStoredKey = lookup.status == 0
                && lookup.stdout.split(whereSeparator: \.isNewline).contains { !$0.hasPrefix("#") && !$0.isEmpty }

            guard hasStoredKey else { return .unknown }

            // Host is known — verify key hasn't changed via a no-op ssh with strict checking
            var sshArgs = [
                "-o", "BatchMode=yes",
                "-o", "StrictHostKeyChecking=yes",
                "-o", "ConnectTimeout=5",
                "-o", "LogLevel=ERROR",
                "-N", "-O", "check"  // just check, don't connect
            ]
            if port != 22 { sshArgs += ["-p", String(port)] }
            sshArgs.append(host)

            // If no ControlMaster is running, fall back to a quick connect-and-exit
            let check = run("/usr/bin/ssh", args: sshArgs)
            if check.status == 0 { return .trusted }

            // Check failed — could be changed key or just no control socket.
            // Look for the specific "REMOTE HOST IDENTIFICATION HAS CHANGED" marker
            if check.stderr.contains("REMOTE HOST IDENTIFICATION HAS CHANGED")
                || check.stderr.contains("host key for") && check.stderr.contains("has changed") {
                return .changed
            }

            // No control socket to check against — trust the stored key
            return .trusted
        }.value
    }

    /// Fetches the server's host key fingerprint for display to the user.
    static func fetchFingerprint(host: String, port: UInt16 = 22) async -> String? {
        await Task.detached(priority: .utility) {
            let keys = scanHostKeys(host: host, port: port)
            guard !keys.isEmpty else { return nil as String? }
            // ssh-keygen -l needs a file — use stdin via /dev/stdin
            let tmp = NSTemporaryDirectory() + "crispyvibes-hk-\(UUID().uuidString)"
            defer { try? FileManager.default.removeItem(atPath: tmp) }
            try? keys.write(toFile: tmp, atomically: true, encoding: .utf8)
            let fp = run("/usr/bin/ssh-keygen", args: ["-l", "-f", tmp])
            let result = fp.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        }.value
    }

    /// Saves the host key to ~/.ssh/known_hosts.
    static func acceptHostKey(host: String, port: UInt16 = 22) async {
        await Task.detached(priority: .utility) {
            // Capture key to temp file first, then append to real known_hosts
            let tmp = NSTemporaryDirectory() + "crispyvibes-hkaccept-\(UUID().uuidString)"
            defer { try? FileManager.default.removeItem(atPath: tmp) }
            var args = [
                "-o", "BatchMode=yes",
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=\(tmp)",
                "-o", "ConnectTimeout=5"
            ]
            if port != 22 { args += ["-p", String(port)] }
            args += [host, "true"]
            _ = run("/usr/bin/ssh", args: args)

            guard let keys = try? String(contentsOfFile: tmp, encoding: .utf8), !keys.isEmpty else { return }
            let knownHostsPath = NSString(string: "~/.ssh/known_hosts").expandingTildeInPath
            let dir = (knownHostsPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if let handle = FileHandle(forWritingAtPath: knownHostsPath) {
                handle.seekToEndOfFile()
                handle.write(Data(keys.utf8))
                handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: knownHostsPath, contents: Data(keys.utf8))
            }
        }.value
    }

    // MARK: - Private

    /// Fetches host key lines — uses ssh-keyscan for direct hosts, ssh for ProxyCommand hosts.
    /// Only needed by fetchFingerprint (for display). Returns raw known_hosts-format lines.
    private static func scanHostKeys(host: String, port: UInt16) -> String {
        // Check if host uses a ProxyCommand
        var sshGArgs = ["-G"]
        if port != 22 { sshGArgs += ["-p", String(port)] }
        sshGArgs.append(host)
        let config = run("/usr/bin/ssh", args: sshGArgs)
        let hasProxy = config.stdout.split(whereSeparator: \.isNewline)
            .contains { $0.lowercased().hasPrefix("proxycommand ") && !$0.hasSuffix(" none") }

        if hasProxy {
            // ssh-keyscan can't use ProxyCommand — use ssh to capture the key to a temp file.
            // StrictHostKeyChecking=no + temp UserKnownHostsFile captures without trusting.
            let tmp = NSTemporaryDirectory() + "crispyvibes-hkscan-\(UUID().uuidString)"
            defer { try? FileManager.default.removeItem(atPath: tmp) }
            var args = [
                "-o", "BatchMode=yes",
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=\(tmp)",
                "-o", "ConnectTimeout=5"
            ]
            if port != 22 { args += ["-p", String(port)] }
            args += [host, "true"]
            _ = run("/usr/bin/ssh", args: args)
            return (try? String(contentsOfFile: tmp, encoding: .utf8)) ?? ""
        }

        let result = run("/usr/bin/ssh-keyscan", args: scanArgs(host: host, port: port))
        return result.stdout
    }

    private static func scanArgs(host: String, port: UInt16) -> [String] {
        var args = ["-T", "5"]
        if port != 22 { args += ["-p", String(port)] }
        args.append(host)
        return args
    }

    private static func run(_ executable: String, args: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe
        do { try process.run() } catch { return (-1, "", error.localizedDescription) }
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}
