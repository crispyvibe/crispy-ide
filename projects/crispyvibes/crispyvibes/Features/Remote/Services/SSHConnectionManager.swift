// SSHConnectionManager.swift — SSH Remote Development

import Combine
import Foundation

/// Manages SSH connections across the app. One connection per host.
@MainActor
final class SSHConnectionManager: ObservableObject {
    @Published private(set) var connections: [String: SSHConnection] = [:]
    private var connectionSubscriptions: [String: AnyCancellable] = [:]

    init() {
        cleanStaleControlSockets()
    }

    /// Removes stale control sockets left by crashes or force quits.
    private func cleanStaleControlSockets() {
        let dir = NSString(string: "~/.crispyvibes/ssh").expandingTildeInPath
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for file in files {
            let path = (dir as NSString).appendingPathComponent(file)
            // Try ssh -O check — if it fails, the socket is stale
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = ["-o", "ControlPath=\(path)", "-O", "check", "dummy"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    func connection(for profile: SSHConnectionProfile) -> SSHConnection {
        let key = profile.connectionString
        if let existing = connections[key] { return existing }
        let conn = SSHConnection(profile: profile)
        connections[key] = conn
        connectionSubscriptions[key] = conn.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        return conn
    }

    func connect(profile: SSHConnectionProfile) async throws -> SSHConnection {
        let key = profile.connectionString
        if let existing = connections[key], case .failed = existing.state {
            connections.removeValue(forKey: key)
        }
        let conn = connection(for: profile)
        if conn.state != .connected { try await conn.connect() }
        return conn
    }

    func disconnect(profile: SSHConnectionProfile) async {
        let key = profile.connectionString
        guard let conn = connections[key] else { return }
        await conn.disconnect()
        connections.removeValue(forKey: key)
        connectionSubscriptions.removeValue(forKey: key)
    }

    func disconnectAll() async {
        for conn in connections.values { await conn.disconnect() }
        connections.removeAll()
        connectionSubscriptions.removeAll()
    }

    var connectedCount: Int {
        connections.values.filter { $0.state == .connected }.count
    }

    deinit { connectionSubscriptions.removeAll() }
}
