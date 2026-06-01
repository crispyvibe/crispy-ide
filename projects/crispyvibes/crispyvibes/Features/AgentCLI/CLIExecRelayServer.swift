import Darwin
import Foundation

/// Resolves the Unix-socket path for the remote-CLI exec relay (F051). Distinct
/// from `crispy.sock` (F044) so IDE JSON-RPC traffic and argv-exec traffic never
/// mix. Bundle-ID-scoped like the command socket.
enum CLIExecRelayPathResolver {
    /// The relay socket is reverse-forwarded over SSH (`ssh -R`), and OpenSSH's
    /// forward-spec parser breaks on spaces — so it MUST live on a space-free
    /// path. Unlike the command socket (under "Application Support"), this lives
    /// under `~/.crispyvibes/`, the same space-free area used for SSH control paths.
    static func defaultPath() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.crispyvibe.app"
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".crispyvibes", isDirectory: true)
            .appendingPathComponent("\(bundleID).crispy-relay.sock", isDirectory: false)
    }
}

/// F051: relays remote `crispy` invocations to the local machine. A tiny remote
/// shim (reached via an SSH reverse forward) sends NUL-separated
/// `cwd \0 projectPath \0 arg0 \0 arg1 \0 …`; this server runs the *bundled*
/// `crispy` binary locally with that argv (so all command logic is reused),
/// then replies `"<exitCode>\n"` followed by the combined stdout+stderr.
///
/// Authorization is the socket's owner-only (`0600`) permission plus the SSH
/// channel that reaches it; see F051 threat-model.
@MainActor
final class CLIExecRelayServer {
    private let socketPath: URL
    private let executableURL: URL
    private let crispySocketPath: URL

    private let acceptQueue = DispatchQueue(label: "com.crispyvibe.agent-cli.relay.accept", qos: .utility)
    private let connectionQueue = DispatchQueue(label: "com.crispyvibe.agent-cli.relay.connection", qos: .utility, attributes: .concurrent)
    private var listenFD: Int32 = -1
    private let runningFlag = LockedBool(initial: false)

    /// - Parameter executableURL: the `crispy` binary to run. Defaults to the
    ///   bundled CLI; injectable for tests.
    init(
        socketPath: URL = CLIExecRelayPathResolver.defaultPath(),
        executableURL: URL? = nil,
        crispySocketPath: URL = CLISocketPathResolver.defaultPath()
    ) {
        self.socketPath = socketPath
        self.executableURL = executableURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/crispy", isDirectory: false)
        self.crispySocketPath = crispySocketPath
    }

    var resolvedSocketPath: URL { socketPath }

    func start() throws {
        guard !runningFlag.get() else { return }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: socketPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Liveness-guarded: never clobber a live listener; reclaim stale files.
        if fileManager.fileExists(atPath: socketPath.path) {
            if CLISocketServer.isSocketAlive(at: socketPath) { throw CLISocketServerError.alreadyServing }
            try? fileManager.removeItem(at: socketPath)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CLISocketServerError.bindFailed(errno: errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw CLISocketServerError.pathTooLong(path: socketPath.path)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            pathBytes.withUnsafeBytes { src in dest.copyMemory(from: src) }
        }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, addrLen) }
        }
        guard bindResult == 0 else { let e = errno; close(fd); throw CLISocketServerError.bindFailed(errno: e) }
        chmod(socketPath.path, 0o600)
        guard listen(fd, 16) == 0 else {
            let e = errno; close(fd); try? fileManager.removeItem(at: socketPath)
            throw CLISocketServerError.bindFailed(errno: e)
        }

        listenFD = fd
        runningFlag.set(true)
        let listenFD = fd
        let executableURL = self.executableURL
        let crispySocketPath = self.crispySocketPath
        let runningFlag = self.runningFlag
        acceptQueue.async { [connectionQueue] in
            while runningFlag.get() {
                let clientFD = accept(listenFD, nil, nil)
                if clientFD < 0 {
                    let e = errno
                    if e == EINTR || e == ECONNABORTED { continue }
                    if e == EMFILE || e == ENFILE { usleep(100_000); continue }
                    if runningFlag.get() { runningFlag.set(false); close(listenFD) }
                    return
                }
                var rcv = timeval(tv_sec: 30, tv_usec: 0)
                setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &rcv, socklen_t(MemoryLayout<timeval>.size))
                connectionQueue.async {
                    CLIExecRelayServer.handleConnection(clientFD: clientFD, executableURL: executableURL, crispySocketPath: crispySocketPath)
                }
            }
        }
    }

    func shutdown() {
        guard runningFlag.get() else { return }
        runningFlag.set(false)
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        try? FileManager.default.removeItem(at: socketPath)
    }

    // MARK: - Connection handling

    nonisolated private static func handleConnection(clientFD: Int32, executableURL: URL, crispySocketPath: URL) {
        defer { close(clientFD) }
        guard let request = readRequest(from: clientFD, cap: 1 << 20) else { return }

        // Fields: cwd \0 projectPath \0 arg0 \0 arg1 \0 … (trailing empty dropped).
        var fields = request.split(separator: 0x00, omittingEmptySubsequences: false).map { Data($0) }
        if fields.last?.isEmpty == true { fields.removeLast() }
        guard fields.count >= 2 else { write(clientFD, "127\ncrispy: malformed relay request\n") ; return }
        let projectPath = String(data: fields[1], encoding: .utf8) ?? ""
        let argv = fields.dropFirst(2).map { String(data: $0, encoding: .utf8) ?? "" }

        var env = ProcessInfo.processInfo.environment
        env["CRISPY_SOCKET"] = crispySocketPath.path
        if !projectPath.isEmpty { env["CRISPY_PROJECT_PATH"] = projectPath }

        let result = try? ManagedProcessRunner().run(
            executableURL: executableURL,
            arguments: argv,
            environment: env,
            stdinData: nil,
            timeout: 25,
            throwOnTimeout: true
        )
        guard let result else { write(clientFD, "124\ncrispy: relay timed out\n"); return }
        var payload = Data("\(result.terminationStatus)\n".utf8)
        payload.append(result.stdoutData)
        payload.append(result.stderrData)
        _ = payload.withUnsafeBytes { Darwin.write(clientFD, $0.baseAddress, payload.count) }
    }

    nonisolated private static func write(_ fd: Int32, _ string: String) {
        let data = Data(string.utf8)
        _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, data.count) }
    }

    /// Reads one request terminated by a newline — so clients need not half-close
    /// the socket (plain `nc -U` works on every netcat variant) — or by EOF.
    /// Returns the bytes before the newline.
    nonisolated private static func readRequest(from fd: Int32, cap: Int) -> Data? {
        var buffer = Data()
        var byte: UInt8 = 0
        while buffer.count < cap {
            let n = read(fd, &byte, 1)
            if n == 0 { break }
            if n < 0 { if errno == EINTR { continue }; return buffer.isEmpty ? nil : buffer }
            if byte == 0x0A { break }
            buffer.append(byte)
        }
        return buffer.isEmpty ? nil : buffer
    }
}
