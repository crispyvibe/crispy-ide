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

    func projectIdentifier(remotePath: String) -> String {
        var components = URLComponents()
        components.scheme = "ssh"
        components.user = user
        components.host = host
        components.port = Int(port)
        components.path = remotePath.hasPrefix("/") ? remotePath : "/\(remotePath)"
        return components.string ?? "\(sshURI)\(remotePath)"
    }

    static func parseIdentifierLocation(
        _ identifier: String
    ) -> (user: String, host: String, port: UInt16, remotePath: String)? {
        guard identifier.hasPrefix("ssh://"),
              let components = URLComponents(string: identifier),
              let host = components.host,
              !host.isEmpty else { return nil }

        let user = components.user ?? NSUserName()
        let parsedPort = components.port ?? 22
        guard (1...Int(UInt16.max)).contains(parsedPort) else { return nil }
        let port = UInt16(parsedPort)
        var remotePath = components.path.isEmpty ? "~" : components.path
        // Legacy identifiers appended raw paths without percent-encoding. Treat
        // query/fragment delimiters as path bytes because SSH project IDs never
        // define URL query or fragment semantics.
        if let query = components.percentEncodedQuery {
            remotePath += "?" + (query.removingPercentEncoding ?? query)
        }
        if let fragment = components.percentEncodedFragment {
            remotePath += "#" + (fragment.removingPercentEncoding ?? fragment)
        }
        return (user, host, port, remotePath)
    }

    /// Parses an identifier like "ssh://user@host:22/path/to/project" into (profile, remotePath).
    /// Looks up saved profiles to resolve the correct auth method.
    /// Falls back to .agent if no saved profile matches.
    static func parse(identifier: String) -> (profile: SSHConnectionProfile, remotePath: String)? {
        guard let location = parseIdentifierLocation(identifier) else { return nil }

        let saved = loadSavedProfiles().first {
            $0.host == location.host && $0.port == location.port && $0.user == location.user
        }

        let profile = saved ?? SSHConnectionProfile(
            id: UUID(), displayName: location.host, host: location.host, port: location.port,
            user: location.user, authMethod: .agent, importedFromConfig: false
        )
        return (profile, location.remotePath)
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
