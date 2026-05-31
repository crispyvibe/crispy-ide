// SSHConnectionProfile.swift — SSH Remote Development

import Foundation

/// Persistent SSH connection profile. Stored as JSON in Application Support.
/// No secrets — only host, port, user, and path to key file.
struct SSHConnectionProfile: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var displayName: String
    var host: String
    var port: UInt16
    var user: String
    var authMethod: SSHAuthMethod
    var importedFromConfig: Bool
    /// F051: whether the Agent CLI relay (`crispy`) is set up for terminals on
    /// this connection. Optional so legacy profiles (key absent) decode cleanly;
    /// nil is treated as enabled. Toggle it off for shared/untrusted hosts.
    var agentCLIEnabled: Bool?

    /// Resolved Agent CLI enablement; defaults to enabled when unset.
    var isAgentCLIEnabled: Bool { agentCLIEnabled ?? true }

    enum SSHAuthMethod: Codable, Hashable, Sendable {
        case agent
        case keyFile(String)
    }

    var connectionString: String { "\(user)@\(host):\(port)" }
    var sshURI: String { "ssh://\(user)@\(host):\(port)" }

    /// Parses an identifier like "ssh://user@host:22/path/to/project" into (profile, remotePath).
    /// Looks up saved profiles to resolve the correct auth method.
    /// Falls back to .agent if no saved profile matches.
    static func parse(identifier: String) -> (profile: SSHConnectionProfile, remotePath: String)? {
        guard identifier.hasPrefix("ssh://"),
              let url = URL(string: identifier),
              let host = url.host, !host.isEmpty else { return nil }

        let user = url.user ?? NSUserName()
        let port = UInt16(url.port ?? 22)
        let remotePath = url.path.isEmpty ? "~" : url.path

        let saved = loadSavedProfiles().first {
            $0.host == host && $0.port == port && $0.user == user
        }

        let profile = saved ?? SSHConnectionProfile(
            id: UUID(), displayName: host, host: host, port: port,
            user: user, authMethod: .agent, importedFromConfig: false
        )
        return (profile, remotePath)
    }

    // MARK: - Private

    private static func loadSavedProfiles() -> [SSHConnectionProfile] {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CrispyVibes")
            .appendingPathComponent("ssh-profiles.json")
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SSHConnectionProfile].self, from: data)) ?? []
    }
}
