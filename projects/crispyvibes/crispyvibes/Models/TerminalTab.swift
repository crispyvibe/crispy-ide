import Foundation

// MARK: - Terminal Origin

enum TerminalOrigin: Codable, Equatable {
    case preset(profileIndex: Int, command: String)
    case adHoc
    case acp(sessionID: String)
    case agentCLI(callerTerminalID: String?)
}

// MARK: - Terminal Tab

struct TerminalTab: Identifiable, Equatable {
    let id: UUID
    var workingDirectory: URL
    var customName: String?
    var sessionTitle: String?
    var gitBranchName: String?
    var exitCode: Int32?
    var isActive: Bool = false
    var origin: TerminalOrigin = .adHoc

    init(
        id: UUID = UUID(),
        workingDirectory: URL,
        customName: String? = nil,
        sessionTitle: String? = nil,
        gitBranchName: String? = nil,
        exitCode: Int32? = nil,
        isActive: Bool = false,
        origin: TerminalOrigin = .adHoc
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.customName = customName
        self.sessionTitle = sessionTitle
        self.gitBranchName = gitBranchName
        self.exitCode = exitCode
        self.isActive = isActive
        self.origin = origin
    }

    private static let bareShellNames: Set<String> = [
        "zsh", "bash", "sh", "fish", "tcsh", "csh", "ksh", "dash",
        "-zsh", "-bash", "-sh", "-fish",
    ]

    var title: String {
        if let customName, !customName.isEmpty {
            return customName
        }

        let folderName = workingDirectory.lastPathComponent
        return folderName.isEmpty ? workingDirectory.path : folderName
    }

    var statusText: String {
        guard let exitCode else { return "Running" }
        return "Exited (\(exitCode))"
    }
}
