import Darwin
import Foundation

/// Resolves the Unix-socket path used by `CLISocketServer` and the bundled
/// `crispy` CLI binary. The path is bundle-ID-scoped so multiple Crispy
/// instances on the same machine never collide (F044-R03).
enum CLISocketPathResolver {
    static func defaultPath() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.crispyvibe.app"
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("crispy.sock", isDirectory: false)
    }
}

/// Listens on a Unix domain socket for agent CLI requests and dispatches them
/// to `CLICommandRouter`.
///
/// Implements:
/// - F044-R01 (Unix socket transport)
/// - F044-R02 (process ancestry authorization)
/// - F044-R06 / F044-R07 (JSON-RPC v2 line-delimited)
/// - F044-R08 (one-shot connection model)
/// - F044-R13 (background I/O, hop to @MainActor for service calls)
@MainActor
final class CLISocketServer {
    private let socketPath: URL
    private let router: CLICommandRouter

    private let acceptQueue = DispatchQueue(
        label: "com.crispyvibe.agent-cli.accept",
        qos: .utility
    )
    private let connectionQueue = DispatchQueue(
        label: "com.crispyvibe.agent-cli.connection",
        qos: .utility,
        attributes: .concurrent
    )

    private var listenFD: Int32 = -1
    /// Read concurrently from the accept loop on a background queue, so it
    /// must not be a `@MainActor`-isolated stored property. The lock keeps
    /// reads/writes consistent even though `Bool` stores are normally atomic
    /// on ARM64 — Swift's strict concurrency model treats unsynchronized
    /// cross-actor access as undefined.
    private let runningFlag = LockedBool(initial: false)

    init(socketPath: URL = CLISocketPathResolver.defaultPath(), router: CLICommandRouter) {
        self.socketPath = socketPath
        self.router = router
    }

    /// Binds the socket and starts the accept loop. Throws if the socket
    /// cannot be created or bound. Safe to call multiple times — subsequent
    /// calls are no-ops while already running.
    func start() throws {
        guard !runningFlag.get() else { return }

        let fileManager = FileManager.default
        let directory = socketPath.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Liveness-guarded cleanup (F044-T10): only remove a socket file that
        // is NOT backed by a live listener. This prevents a second instance
        // from clobbering a healthy one, and only reclaims confirmed-stale
        // sockets left by an unclean exit.
        if fileManager.fileExists(atPath: socketPath.path) {
            if Self.isSocketAlive(at: socketPath) {
                throw CLISocketServerError.alreadyServing
            }
            try? fileManager.removeItem(at: socketPath)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CLISocketServerError.bindFailed(errno: errno)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.path.utf8CString
        let maxBytes = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxBytes else {
            close(fd)
            throw CLISocketServerError.pathTooLong(path: socketPath.path)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            pathBytes.withUnsafeBytes { src in
                dest.copyMemory(from: src)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            let err = errno
            close(fd)
            throw CLISocketServerError.bindFailed(errno: err)
        }

        // Owner-only permissions (F044-R01 / F044-T01).
        chmod(socketPath.path, 0o600)

        guard listen(fd, 16) == 0 else {
            let err = errno
            close(fd)
            try? fileManager.removeItem(at: socketPath)
            throw CLISocketServerError.bindFailed(errno: err)
        }

        listenFD = fd
        runningFlag.set(true)

        let appPID = getpid()
        let listenFD = fd
        let router = self.router
        let connectionQueue = self.connectionQueue
        let runningFlag = self.runningFlag

        acceptQueue.async {
            CLISocketServer.runAcceptLoop(
                listenFD: listenFD,
                appPID: appPID,
                router: router,
                connectionQueue: connectionQueue,
                isRunning: { runningFlag.get() },
                onAbnormalExit: {
                    // Listener died unexpectedly (not a clean shutdown). Reset
                    // state and release the descriptor so a later start() can
                    // rebind and recover instead of leaving an orphaned,
                    // bound-but-not-listening socket.
                    runningFlag.set(false)
                    close(listenFD)
                }
            )
        }
    }

    /// Closes the listening socket and removes the socket file. Safe to call
    /// multiple times.
    func shutdown() {
        guard runningFlag.get() else { return }
        runningFlag.set(false)
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        try? FileManager.default.removeItem(at: socketPath)
    }

    var resolvedSocketPath: URL { socketPath }

    /// Returns `true` if a process is actively listening on `path` (a
    /// `connect()` succeeds). Used to avoid clobbering a healthy listener and
    /// to distinguish a stale socket file from a live one.
    nonisolated static func isSocketAlive(at path: URL) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            pathBytes.withUnsafeBytes { src in dest.copyMemory(from: src) }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }
        return result == 0
    }

    // MARK: Accept loop

    nonisolated private static func runAcceptLoop(
        listenFD: Int32,
        appPID: pid_t,
        router: CLICommandRouter,
        connectionQueue: DispatchQueue,
        isRunning: @escaping () -> Bool,
        onAbnormalExit: @escaping () -> Void
    ) {
        while isRunning() {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr -> Int32 in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(listenFD, sockPtr, &clientLen)
                }
            }
            if clientFD < 0 {
                let acceptErrno = errno
                // Transient errors must not kill the loop — silently exiting
                // here was the root cause of orphaned bound-but-not-listening
                // sockets (the listener stayed bound while nothing accepted).
                if acceptErrno == EINTR || acceptErrno == ECONNABORTED { continue }
                if acceptErrno == EMFILE || acceptErrno == ENFILE {
                    // Descriptor exhaustion — back off briefly and retry.
                    usleep(100_000)
                    continue
                }
                // Listener closed. If we're still "running" this is a fatal,
                // unexpected exit (not shutdown) — reset state so the server
                // can be restarted and recover.
                if isRunning() { onAbnormalExit() }
                return
            }

            // Ancestry check before reading any bytes (F044-R02 / F044-T01).
            let peerPID = CLIProcessAncestry.peerPID(of: clientFD) ?? -1
            let allowed = CLIProcessAncestry.isDescendantOfApp(peerPID: peerPID, appPID: appPID)
            CLIProcessAncestry.logConnectionAttempt(
                peerPID: peerPID,
                appPID: appPID,
                allowed: allowed
            )
            guard allowed || CLIProcessAncestry.isAncestryCheckBypassed else {
                // Reject silently. No bytes written.
                close(clientFD)
                continue
            }

            // Bound how long a single connection can hold a worker thread
            // (F044-T07 mitigation). 30s is more than enough for any
            // implemented command; future wait-style commands manage their
            // own timeouts and will need this raised or removed per-request.
            var rcvTimeout = timeval(tv_sec: 30, tv_usec: 0)
            setsockopt(
                clientFD,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &rcvTimeout,
                socklen_t(MemoryLayout<timeval>.size)
            )

            connectionQueue.async {
                CLISocketServer.handleConnection(clientFD: clientFD, router: router)
            }
        }
    }

    nonisolated private static func handleConnection(clientFD: Int32, router: CLICommandRouter) {
        defer { close(clientFD) }
        guard let line = readLine(from: clientFD, maxBytes: 1 << 20) else { return }

        let request: CLIRequest
        do {
            request = try JSONDecoder().decode(CLIRequest.self, from: line)
        } catch {
            // Malformed JSON closes the connection without echo (F044-T08).
            return
        }

        // Hop to MainActor for the actual service call (F044-R13).
        let semaphore = DispatchSemaphore(value: 0)
        var encoded: Data?
        Task { @MainActor in
            let response = await router.dispatch(request)
            encoded = try? response.encode()
            semaphore.signal()
        }
        semaphore.wait()
        guard var payload = encoded else { return }
        payload.append(0x0A) // newline-delimited
        _ = payload.withUnsafeBytes { ptr in
            write(clientFD, ptr.baseAddress, payload.count)
        }
    }

    nonisolated private static func readLine(from fd: Int32, maxBytes: Int) -> Data? {
        var buffer = Data()
        var byte: UInt8 = 0
        while buffer.count < maxBytes {
            let n = read(fd, &byte, 1)
            if n == 0 { break }
            if n < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if byte == 0x0A { break }
            buffer.append(byte)
        }
        return buffer.isEmpty ? nil : buffer
    }
}

enum CLISocketServerError: Error {
    /// A live server is already listening on the socket path; this instance
    /// must not clobber it.
    case alreadyServing
    case bindFailed(errno: Int32)
    case pathTooLong(path: String)
}

/// Lock-protected boolean usable from any thread. Used by `CLISocketServer`
/// to coordinate startup/shutdown between the @MainActor-isolated server
/// instance and the background accept loop.
final class LockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(initial: Bool) { self.value = initial }

    func get() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Bool) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }
}
