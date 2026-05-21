import Foundation

enum TerminalShellResolutionSource: String, Equatable, Sendable {
    case projectOverride = "project_override"
    case vibespaceDefault = "vibespace_default"
    case appDefault = "app_default"
    case processEnvironment = "process_environment"
    case hardcodedDefault = "hardcoded_default"
}

struct TerminalShellResolutionContext: Equatable, Sendable {
    var projectOverride: TerminalShellPreference?
    var vibespaceDefault: TerminalShellPreference?
    var appDefault: TerminalShellPreference?
    var processEnvironmentShell: String?

    init(
        projectOverride: TerminalShellPreference? = nil,
        vibespaceDefault: TerminalShellPreference? = nil,
        appDefault: TerminalShellPreference? = nil,
        processEnvironmentShell: String? = nil
    ) {
        self.projectOverride = projectOverride
        self.vibespaceDefault = vibespaceDefault
        self.appDefault = appDefault
        self.processEnvironmentShell = processEnvironmentShell
    }
}

struct TerminalShellResolutionCandidate: Equatable, Sendable {
    let executablePath: String
    let source: TerminalShellResolutionSource
}

struct TerminalShellResolution: Equatable, Sendable {
    let requested: TerminalShellResolutionCandidate
    let selected: TerminalShellResolutionCandidate
    let rejectedCandidates: [TerminalShellResolutionCandidate]

    var didFallback: Bool {
        requested != selected || !rejectedCandidates.isEmpty
    }
}

enum TerminalShellResolver {
    static func resolve(
        context: TerminalShellResolutionContext,
        fileManager: FileManager = .default
    ) -> TerminalShellResolution {
        var candidates: [TerminalShellResolutionCandidate] = []
        var seenPaths = Set<String>()

        func appendCandidate(path rawPath: String?, source: TerminalShellResolutionSource) {
            let cleanedPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cleanedPath.isEmpty else { return }
            guard seenPaths.insert(cleanedPath).inserted else { return }
            candidates.append(
                TerminalShellResolutionCandidate(
                    executablePath: cleanedPath,
                    source: source
                )
            )
        }

        appendCandidate(
            path: context.projectOverride?.executablePath,
            source: .projectOverride
        )
        appendCandidate(
            path: context.vibespaceDefault?.executablePath,
            source: .vibespaceDefault
        )
        appendCandidate(
            path: context.appDefault?.executablePath,
            source: .appDefault
        )
        appendCandidate(
            path: context.processEnvironmentShell ?? ProcessInfo.processInfo.environment["SHELL"],
            source: .processEnvironment
        )
        appendCandidate(
            path: TerminalShellPreference.zsh.executablePath,
            source: .hardcodedDefault
        )

        let requested = candidates.first
            ?? TerminalShellResolutionCandidate(
                executablePath: TerminalShellPreference.zsh.executablePath,
                source: .hardcodedDefault
            )
        var rejected: [TerminalShellResolutionCandidate] = []

        for candidate in candidates {
            if fileManager.isExecutableFile(atPath: candidate.executablePath) {
                return TerminalShellResolution(
                    requested: requested,
                    selected: candidate,
                    rejectedCandidates: rejected
                )
            }
            rejected.append(candidate)
        }

        let hardcodedDefault = TerminalShellResolutionCandidate(
            executablePath: TerminalShellPreference.zsh.executablePath,
            source: .hardcodedDefault
        )
        return TerminalShellResolution(
            requested: requested,
            selected: hardcodedDefault,
            rejectedCandidates: rejected
        )
    }
}

enum TerminalShellLaunchPolicy {
    static let startupArguments = ["-l", "-i"]
}
