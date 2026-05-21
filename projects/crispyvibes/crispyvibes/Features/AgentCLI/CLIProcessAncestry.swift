import Darwin
import Foundation

/// Verifies that a Unix-socket connection's peer process is a descendant of
/// this app process via `LOCAL_PEERPID` + parent-PID walk.
///
/// Implements F044-R02 (process ancestry authorization) and the threat
/// mitigation in F044-T01.
enum CLIProcessAncestry {
    /// Returns `true` if `peerPID` is the running app's PID or any of its
    /// transitive descendants.
    ///
    /// Walks up the parent chain from `peerPID` using `proc_pidinfo` until it
    /// finds the app's PID, hits PID 1, or exceeds a depth bound. Returns
    /// `false` on any error or when the app's PID never appears.
    static func isDescendantOfApp(peerPID: pid_t, appPID: pid_t = getpid()) -> Bool {
        if peerPID <= 0 { return false }
        if peerPID == appPID { return true }

        var current = peerPID
        // Bound the walk to defend against pathological process trees.
        for _ in 0 ..< 256 {
            guard let parent = parentPID(of: current) else { return false }
            if parent == appPID { return true }
            if parent <= 1 { return false }
            current = parent
        }
        return false
    }

    /// Reads the `LOCAL_PEERPID` socket option from a connected Unix socket.
    static func peerPID(of socketFD: Int32) -> pid_t? {
        var pid: pid_t = -1
        var size = socklen_t(MemoryLayout<pid_t>.size)
        let result = withUnsafeMutablePointer(to: &pid) { ptr -> Int32 in
            getsockopt(socketFD, SOL_LOCAL, LOCAL_PEERPID, ptr, &size)
        }
        guard result == 0, pid > 0 else { return nil }
        return pid
    }

    /// Optional debug flag — set the Info.plist key
    /// `CrispyVibesAgentCLIBypassAncestry` to `YES` to allow connections from
    /// any local process. ONLY for local development; never ship enabled.
    static var isAncestryCheckBypassed: Bool {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CrispyVibesAgentCLIBypassAncestry") else {
            return false
        }
        if let bool = raw as? Bool { return bool }
        if let str = raw as? String {
            switch str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes": return true
            default: return false
            }
        }
        return false
    }

    /// Logs a connection attempt with peer ancestry chain. Useful for diagnosing
    /// "why was my connection rejected?" cases.
    static func logConnectionAttempt(peerPID: pid_t, appPID: pid_t, allowed: Bool) {
        let chain = ancestryChain(startingFrom: peerPID, maxDepth: 16)
        let chainText = chain
            .map { "\($0.pid):\($0.name)" }
            .joined(separator: " -> ")
        let level: DiagnosticsLevel = allowed ? .info : .notice
        AppDiagnostics.record(
            category: .vibespaceLifecycle,
            level: level,
            event: allowed ? "agent_cli_connection_accepted" : "agent_cli_connection_rejected",
            metadata: [
                "peer_pid": "\(peerPID)",
                "app_pid": "\(appPID)",
                "ancestry": chainText
            ]
        )
    }

    private static func ancestryChain(
        startingFrom pid: pid_t,
        maxDepth: Int
    ) -> [(pid: pid_t, name: String)] {
        var chain: [(pid: pid_t, name: String)] = []
        var current = pid
        for _ in 0 ..< maxDepth {
            if current <= 1 { break }
            chain.append((pid: current, name: processName(of: current)))
            guard let parent = parentPID(of: current), parent != current else { break }
            current = parent
        }
        return chain
    }

    private static func processName(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let size = proc_name(pid, &buffer, UInt32(buffer.count))
        guard size > 0 else { return "?" }
        return String(cString: buffer)
    }

    // MARK: Private

    /// Returns the parent PID of a given process. Uses `sysctl(KERN_PROC_PID)`
    /// rather than `proc_pidinfo(PROC_PIDTBSDINFO)` because the latter requires
    /// read permission, which non-root processes lack for setuid-root processes
    /// like `/usr/bin/login`. Without this, an ancestry walk through
    /// `shell -> login -> Crispy` would terminate prematurely at `login`.
    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = mib.withUnsafeMutableBufferPointer { mibPtr -> Int32 in
            sysctl(mibPtr.baseAddress, UInt32(mibPtr.count), &info, &size, nil, 0)
        }
        guard result == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
