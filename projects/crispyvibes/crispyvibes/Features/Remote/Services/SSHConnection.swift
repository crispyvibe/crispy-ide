// SSHConnection.swift — SSH Remote Development
// Uses system ssh with ControlMaster for multiplexed connections.

import Combine
import Foundation

struct HostKeyUnknownError: Error, LocalizedError {
    let host: String
    var errorDescription: String? {
        "The authenticity of host '\(host)' can't be established. Accept the host key to continue."
    }
}

struct HostKeyChangedError: Error, LocalizedError {
    let host: String
    var errorDescription: String? {
        "Host key for \(host) has changed. This could indicate a security issue. Remove the old entry from ~/.ssh/known_hosts if you trust this change."
    }
}

/// Manages a single SSH connection via system ssh ControlMaster.
@MainActor
final class SSHConnection: ObservableObject, SSHConnectionProviding {
    let profile: SSHConnectionProfile
    @Published private(set) var state: ConnectionState = .disconnected

    var statePublisher: AnyPublisher<ConnectionState, Never> {
        $state.eraseToAnyPublisher()
    }

    nonisolated(unsafe) var hasTmux: Bool = false
    nonisolated(unsafe) private var sftpSubprocess: SFTPSubprocess?
    let portForwardService = SSHPortForwardService()

    private var healthTask: Task<Void, Never>?
    private var masterProcess: Process?

    /// Control socket path — private, hashed to stay under 104-byte Unix socket limit.
    private let controlPath: String

    init(profile: SSHConnectionProfile) {
        self.profile = profile
        let raw = "\(profile.user)@\(profile.host):\(profile.port)"
        let hash = raw.utf8.withContiguousStorageIfAvailable { buf -> String in
            var h: (UInt64, UInt64, UInt64, UInt64) = (0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1)
            for b in buf { h.0 = h.0 &+ UInt64(b) &* 31; h.1 = h.1 ^ (h.0 &<< 13); h.2 = h.2 &+ h.1; h.3 = h.3 ^ (h.2 &>> 7) }
            return String(h.0 ^ h.1 ^ h.2 ^ h.3, radix: 16)
        } ?? String(raw.hashValue, radix: 16)
        let dir = NSString(string: "~/.crispyvibes/ssh").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        self.controlPath = "\(dir)/\(hash)"
    }

    /// Base ssh args that use the control socket.
    nonisolated func sshArgs(_ extraArgs: [String] = []) -> [String] {
        var args = ["-o", "ControlPath=\(controlPath)"]
        if profile.port != 22 { args += ["-p", String(profile.port)] }
        args += extraArgs
        args.append("\(profile.user)@\(profile.host)")
        return args
    }

    /// Execute a command on the remote host via the control socket.
    nonisolated func executeCommand(_ command: String, timeout: TimeInterval = 30) async throws -> String {
        let result = try await runSSH(args: sshArgs() + [command], timeout: timeout)
        guard result.status == 0 else {
            let errStr = String(data: result.stderr, encoding: .utf8) ?? ""
            throw SSHRemoteError.timeout("Command failed (exit \(result.status)): \(errStr)")
        }
        return String(data: result.stdout, encoding: .utf8) ?? ""
    }

    /// Returns the shared SFTP subprocess, creating it on first use.
    nonisolated func availableSFTP() throws -> SFTPSubprocess {
        if let sftp = sftpSubprocess, sftp.isRunning { return sftp }
        guard FileManager.default.fileExists(atPath: controlPath) else {
            throw SFTPError.notConnected
        }
        AppDiagnostics.record(category: .remote, level: .info, event: "sftp_subprocess_creating", metadata: ["host": profile.host])
        let sftp = try SFTPSubprocess(
            controlPath: controlPath,
            user: profile.user,
            host: profile.host,
            port: profile.port
        )
        sftpSubprocess = sftp
        AppDiagnostics.record(category: .remote, level: .info, event: "sftp_subprocess_ready", metadata: ["host": profile.host])
        return sftp
    }

    func connect() async throws {
        guard state != .connected, state != .connecting else { return }
        masterProcess?.terminate()
        masterProcess = nil
        sftpSubprocess?.terminate()
        sftpSubprocess = nil
        hasTmux = false
        state = .connecting

        do {
            // Pre-flight: check host key BEFORE connecting (BatchMode=yes won't prompt)
            let hostKeyStatus = await KnownHostsValidator.preflight(host: profile.host, port: profile.port)
            switch hostKeyStatus {
            case .changed:
                throw HostKeyChangedError(host: profile.host)
            case .unknown:
                throw HostKeyUnknownError(host: profile.host)
            case .trusted:
                break
            }

            // Build ControlMaster ssh command
            var args = [
                "-o", "ControlMaster=yes",
                "-o", "ControlPath=\(controlPath)",
                "-o", "ControlPersist=yes",
                "-o", "ServerAliveInterval=15",
                "-o", "ServerAliveCountMax=3",
                "-o", "ConnectTimeout=10",
                "-o", "BatchMode=yes",
                "-N"
            ]
            if profile.port != 22 { args += ["-p", String(profile.port)] }
            switch profile.authMethod {
            case .keyFile(let path):
                args += ["-i", NSString(string: path).expandingTildeInPath]
            case .agent:
                break // ssh uses agent/default keys automatically
            }
            args.append("\(profile.user)@\(profile.host)")

            // Spawn master in background, wait for control socket to appear
            let process = Process()
            let errPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errPipe
            try process.run()
            masterProcess = process

            // Wait for control socket (up to 15s)
            let connected = await waitForControlSocket(timeout: 15)
            guard connected else {
                let errData = errPipe.fileHandleForReading.availableData
                let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                process.terminate()
                masterProcess = nil
                state = .failed(errMsg.isEmpty ? "Connection timed out" : errMsg)
                throw SSHRemoteError.timeout(errMsg.isEmpty ? "SSH connection timed out" : errMsg)
            }

            // Check for tmux
            if let out = try? await executeCommand("which tmux", timeout: 5), !out.isEmpty {
                hasTmux = true
            }

            state = .connected
            AppDiagnostics.record(category: .remote, level: .info, event: "ssh_connected", metadata: ["host": profile.host, "port": String(profile.port)])
            startHealthMonitor()
        } catch {
            if state != .failed(error.localizedDescription) {
                state = .failed(error.localizedDescription)
            }
            AppDiagnostics.record(category: .remote, level: .error, event: "ssh_connect_failed", metadata: ["host": profile.host, "error": String(error.localizedDescription.prefix(200))])
            throw error
        }
    }

    /// Accept host key and retry — for system ssh, we add the key via ssh-keyscan then reconnect.
    func acceptAndConnect() async throws {
        await KnownHostsValidator.acceptHostKey(host: profile.host, port: profile.port)
        state = .disconnected
        try await connect()
    }

    func disconnect() async {
        healthTask?.cancel()
        healthTask = nil
        sftpSubprocess?.terminate()
        sftpSubprocess = nil
        await portForwardService.removeAll(controlPath: controlPath, profile: profile)
        // Tell ControlMaster to exit
        let _ = try? await runSSH(args: [
            "-o", "ControlPath=\(controlPath)", "-O", "exit",
            "\(profile.user)@\(profile.host)"
        ], timeout: 3)
        masterProcess?.terminate()
        masterProcess = nil
        try? FileManager.default.removeItem(atPath: controlPath)
        state = .disconnected
    }

    func addPortForward(_ rule: PortForwardRule) async throws {
        try await portForwardService.addForward(rule, controlPath: controlPath, profile: profile)
    }

    func removePortForward(_ rule: PortForwardRule) async throws {
        await portForwardService.removeForward(rule, controlPath: controlPath, profile: profile)
    }

    // MARK: - Private

    private func waitForControlSocket(timeout: TimeInterval) async -> Bool {
        let cp = controlPath
        let host = "\(profile.user)@\(profile.host)"
        return await Task.detached(priority: .utility) {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if FileManager.default.fileExists(atPath: cp) {
                    let result = try? await Self.runSSH(args: [
                        "-o", "ControlPath=\(cp)", "-O", "check", host
                    ], timeout: 2)
                    if result?.status == 0 { return true }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            return false
        }.value
    }

    private func startHealthMonitor() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, let self else { return }
                let cp = self.controlPath
                let host = "\(self.profile.user)@\(self.profile.host)"
                let profileHost = self.profile.host
                let result = try? await Self.runSSH(args: [
                    "-o", "ControlPath=\(cp)", "-O", "check", host
                ], timeout: 3)
                guard !Task.isCancelled else { return }
                if result?.status != 0 {
                    self.sftpSubprocess?.terminate()
                    self.sftpSubprocess = nil
                    self.masterProcess = nil
                    self.state = .disconnected
                    AppDiagnostics.record(category: .remote, level: .error, event: "ssh_health_lost", metadata: ["host": profileHost])
                    return
                }
            }
        }
    }

    /// Run an ssh command and capture stdout/stderr.
    /// Follows Process/Pipe cleanup patterns from commit 1923117.
    /// Blocking work is dispatched off the cooperative thread pool.
    nonisolated static func runSSH(
        args: [String],
        timeout: TimeInterval = 30,
        stdinData: Data? = nil
    ) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        try await Task.detached(priority: .utility) {
            try _runSSHBlocking(args: args, timeout: timeout, stdinData: stdinData)
        }.value
    }

    /// Synchronous core — safe to call DispatchGroup.wait() here.
    private nonisolated static func _runSSHBlocking(
        args: [String],
        timeout: TimeInterval,
        stdinData: Data?
    ) throws -> (status: Int32, stdout: Data, stderr: Data) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outWriteEnd = outPipe.fileHandleForWriting
        let errWriteEnd = errPipe.fileHandleForWriting
        var writeEndsClosed = false

        let stdoutBox = UnsafeMutableTransferBox(Data())
        let stderrBox = UnsafeMutableTransferBox(Data())
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            autoreleasepool { stdoutBox.value = outPipe.fileHandleForReading.readDataToEndOfFile() }
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            autoreleasepool { stderrBox.value = errPipe.fileHandleForReading.readDataToEndOfFile() }
            readGroup.leave()
        }

        let terminationGroup = DispatchGroup()
        terminationGroup.enter()

        defer {
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
                if terminationGroup.wait(timeout: .now() + 1.0) == .timedOut {
                    let pid = process.processIdentifier
                    if pid > 0 { kill(pid, SIGKILL) }
                    _ = terminationGroup.wait(timeout: .now() + 0.5)
                }
            }
            if !writeEndsClosed {
                outWriteEnd.closeFile()
                errWriteEnd.closeFile()
            }
            readGroup.wait()
            outPipe.fileHandleForReading.closeFile()
            errPipe.fileHandleForReading.closeFile()
        }

        if let stdinData {
            let inPipe = Pipe()
            process.standardInput = inPipe
            try process.run()
            outWriteEnd.closeFile()
            errWriteEnd.closeFile()
            writeEndsClosed = true
            DispatchQueue.global(qos: .utility).async {
                inPipe.fileHandleForWriting.write(stdinData)
                inPipe.fileHandleForWriting.closeFile()
            }
        } else {
            process.standardInput = FileHandle.nullDevice
            try process.run()
            outWriteEnd.closeFile()
            errWriteEnd.closeFile()
            writeEndsClosed = true
        }

        process.terminationHandler = { _ in terminationGroup.leave() }

        if timeout > 0 {
            if terminationGroup.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                if terminationGroup.wait(timeout: .now() + 1.0) == .timedOut {
                    let pid = process.processIdentifier
                    if pid > 0 { kill(pid, SIGKILL) }
                    _ = terminationGroup.wait(timeout: .now() + 0.5)
                }
                readGroup.wait()
                throw SSHRemoteError.timeout(args.last ?? "ssh")
            }
        } else {
            terminationGroup.wait()
        }

        readGroup.wait()
        return (process.terminationStatus, stdoutBox.value, stderrBox.value)
    }

    nonisolated func runSSH(args: [String], timeout: TimeInterval = 30, stdinData: Data? = nil) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        try await Self.runSSH(args: args, timeout: timeout, stdinData: stdinData)
    }

    deinit { healthTask?.cancel() }
}

// MARK: - RemoteNotebookHosting (F050)

/// Lets a remote project host a Jupyter server: run the launch/poll/kill scripts
/// in a login shell and forward a loopback port to the remote server, both over
/// the existing ControlMaster socket.
extension SSHConnection: RemoteNotebookHosting {
    var notebookHostKey: String { profile.sshURI }

    func runLoginScript(_ script: String, timeout: TimeInterval) async throws -> String {
        let result = try await runSSH(
            args: sshArgs() + ["bash", "-l", "-s"],
            timeout: timeout,
            stdinData: Data(script.utf8)
        )
        guard result.status == 0 else {
            let errStr = String(data: result.stderr, encoding: .utf8) ?? ""
            throw SSHRemoteError.timeout("Remote script failed (exit \(result.status)): \(errStr)")
        }
        return String(data: result.stdout, encoding: .utf8) ?? ""
    }

    func forwardPort(localPort: UInt16, remotePort: UInt16) async throws {
        try await addPortForward(
            PortForwardRule(
                id: UUID(),
                localPort: localPort,
                remoteHost: "127.0.0.1",
                remotePort: remotePort,
                autoDetected: false
            )
        )
    }

    func cancelForward(localPort: UInt16, remotePort: UInt16) async {
        guard let rule = portForwardService.activeForwards.first(where: {
            $0.localPort == localPort && $0.remotePort == remotePort
        }) else { return }
        try? await removePortForward(rule)
    }
}
