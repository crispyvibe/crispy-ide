import Foundation

struct VibeSpaceSidebarTmuxSession: Identifiable, Equatable {
    enum Source: Equatable {
        case local
        case remote
    }

    let id: String
    let source: Source
    let launchContextProjectID: UUID?
    let owningProjectID: UUID?
    let connectionProfile: SSHConnectionProfile?
    let sessionName: String
    let displayTitle: String
    let workingDirectory: String
    let workingDirectoryURL: URL
    let currentCommand: String
    let lastActivity: Date
    let isAttached: Bool

    var isCrispyVibesManaged: Bool {
        sessionName.hasPrefix("crispyvibes-")
    }

    var attachCommand: String {
        switch source {
        case .local:
            return "tmux attach-session -t \(Self.shellEscape(sessionName))"
        case .remote:
            guard let connectionProfile else {
                return "tmux attach-session -t \(Self.shellEscape(sessionName))"
            }
            return Self.remoteAttachCommand(
                profile: connectionProfile,
                sessionName: sessionName
            )
        }
    }

    private static func remoteAttachCommand(
        profile: SSHConnectionProfile,
        sessionName: String
    ) -> String {
        let remoteCommand = "tmux attach-session -t \(shellEscape(sessionName))"
        var args = ["ssh", "-t"]

        if profile.importedFromConfig {
            args.append(profile.displayName)
        } else {
            if profile.port != 22 {
                args += ["-p", String(profile.port)]
            }
            if case .keyFile(let path) = profile.authMethod {
                args += ["-i", NSString(string: path).expandingTildeInPath]
            }
            args.append("\(profile.user)@\(profile.host)")
        }

        args.append(remoteCommand)
        return args.map(shellEscape).joined(separator: " ")
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct VibeSpaceSidebarTmuxSessionSection: Identifiable, Equatable {
    enum Availability: Equatable {
        case ready
        case message(String)
    }

    let id: String
    let projectID: UUID?
    let title: String
    let subtitle: String?
    let iconName: String
    let sessions: [VibeSpaceSidebarTmuxSession]
    let availability: Availability
}

struct VibeSpaceSidebarTmuxVibeSpaceGroup: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isCurrentVibeSpace: Bool
    let sections: [VibeSpaceSidebarTmuxSessionSection]
}
