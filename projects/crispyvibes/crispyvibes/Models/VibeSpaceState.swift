import Foundation

@MainActor
struct VibeSpaceState: Identifiable {
    private let projectSessionFactory: @MainActor (URL) -> AnyProjectSession
    private let identifierSessionFactory: (@MainActor (String) -> AnyProjectSession)?
    var id: UUID
    var name: String
    var projects: [AnyProjectSession]
    var unresolvedProjectPaths: [String]
    /// F021-R09: paths of parked projects. Parked projects are NOT instantiated
    /// as live sessions; they retain their `ProjectConfigFile` (with `isParked = true`)
    /// for restoration via `unparkProject(path:)`.
    var parkedProjectPaths: [String]
    var focusedProjectID: UUID?
    var storedProjectPaths: [String]
    var storedFocusedProjectPath: String?
    var projectColorTagsByPath: [String: ProjectColorTag]
    var startupSettings: VibeSpaceStartupSettings
    var projectStartupOverridesByPath: [String: VibeSpaceProjectStartupOverride]
    var projectACPAgentOverrideIDsByPath: [String: String]
    var defaultTerminalShell: TerminalShellPreference?
    var projectTerminalShellOverridesByPath: [String: TerminalShellPreference]
    var projectShortcutByPath: [String: Int]
    var sourceControlSettings: VibeSpaceSourceControlSettings
    var vibespaceShortcuts: [TerminalShortcutDefinition]
    var projectScopedShortcutsByPath: [String: [TerminalShortcutDefinition]]

    init(
        id: UUID = UUID(),
        name: String,
        projectURLs: [URL],
        projectSessionFactory: @escaping @MainActor (URL) -> AnyProjectSession
    ) {
        self.projectSessionFactory = projectSessionFactory
        self.identifierSessionFactory = nil
        self.id = id
        self.name = name

        var seenPaths = Set<String>()
        var sessions: [AnyProjectSession] = []
        var unresolvedPaths: [String] = []
        for url in projectURLs {
            let normalized = url.standardizedFileURL
            guard seenPaths.insert(normalized.path).inserted else { continue }
            if Self.isExistingDirectory(path: normalized.path) {
                sessions.append(projectSessionFactory(normalized))
            } else {
                unresolvedPaths.append(normalized.path)
            }
        }
        self.projects = sessions
        self.unresolvedProjectPaths = unresolvedPaths
        self.parkedProjectPaths = []
        self.focusedProjectID = sessions.first?.id
        self.storedProjectPaths = sessions.map(\.projectIdentifier) + unresolvedPaths
        self.storedFocusedProjectPath = sessions.first?.projectIdentifier
        self.projectColorTagsByPath = [:]
        self.startupSettings = .default
        self.projectStartupOverridesByPath = [:]
        self.projectACPAgentOverrideIDsByPath = [:]
        self.defaultTerminalShell = nil
        self.projectTerminalShellOverridesByPath = [:]
        self.projectShortcutByPath = [:]
        self.sourceControlSettings = .default
        self.vibespaceShortcuts = []
        self.projectScopedShortcutsByPath = [:]

        for path in sessions.map(\.projectIdentifier) + unresolvedPaths {
            assignAutoColorTagIfNeeded(forPath: path)
        }
        normalizeProjectShortcuts()
    }

    init(
        config: VibeSpaceConfigFile,
        projectConfigs: [String: ProjectConfigFile] = [:],
        existingDirectoryPaths: Set<String>? = nil,
        projectSessionFactory: @escaping @MainActor (URL) -> AnyProjectSession,
        identifierSessionFactory: @escaping @MainActor (String) -> AnyProjectSession
    ) {
        self.projectSessionFactory = projectSessionFactory
        self.identifierSessionFactory = identifierSessionFactory
        id = config.id
        name = config.name

        var seenPaths = Set<String>()
        var sessions: [AnyProjectSession] = []
        var unresolvedPaths: [String] = []
        let parkedSet = Set(config.parkedProjectPaths.map { Self.normalizedPath(from: $0) })
        let configuredPaths = config.projectPaths + config.unresolvedProjectPaths
        for path in configuredPaths {
            guard seenPaths.insert(path).inserted else { continue }
            // Parked projects are tracked separately and MUST NOT be instantiated
            // as live sessions (F021-R09, F021-R14).
            let normalizedForParkCheck = path.hasPrefix("ssh://")
                ? path
                : Self.normalizedPath(from: path)
            if parkedSet.contains(normalizedForParkCheck) { continue }

            if path.hasPrefix("ssh://") {
                // Remote project — always create (connection happens async)
                sessions.append(identifierSessionFactory(path))
            } else {
                let normalizedPath = Self.normalizedPath(from: path)
                let pathExists: Bool
                if let existingDirectoryPaths {
                    pathExists = existingDirectoryPaths.contains(normalizedPath)
                } else {
                    pathExists = Self.isExistingDirectory(path: normalizedPath)
                }
                if pathExists {
                    sessions.append(projectSessionFactory(URL(fileURLWithPath: normalizedPath)))
                } else {
                    unresolvedPaths.append(normalizedPath)
                }
            }
        }

        projects = sessions
        unresolvedProjectPaths = unresolvedPaths
        parkedProjectPaths = config.parkedProjectPaths.map { Self.normalizedPath(from: $0) }
        storedProjectPaths = sessions.map(\.projectIdentifier) + unresolvedPaths
        sourceControlSettings = config.sourceControlSettings.normalized()
        if let focusedProjectPath = config.focusedProjectPath {
            let normalizedFocusedPath = Self.normalizedPath(from: focusedProjectPath)
            focusedProjectID = sessions.first(where: { $0.projectIdentifier == normalizedFocusedPath })?.id
            storedFocusedProjectPath = normalizedFocusedPath
        } else {
            focusedProjectID = sessions.first?.id
            storedFocusedProjectPath = sessions.first?.projectIdentifier
        }

        startupSettings = config.startupSettings.normalized()
        defaultTerminalShell = config.defaultTerminalShell
        vibespaceShortcuts = config.shortcuts

        var restoredTags: [String: ProjectColorTag] = [:]
        var restoredStartupOverrides: [String: VibeSpaceProjectStartupOverride] = [:]
        var restoredACPAgentOverrides: [String: String] = [:]
        var restoredShellOverrides: [String: TerminalShellPreference] = [:]
        var restoredShortcuts: [String: Int] = [:]
        var restoredScopedShortcuts: [String: [TerminalShortcutDefinition]] = [:]
        for (path, projectConfig) in projectConfigs {
            let normalizedPath = Self.normalizedPath(from: path)
            if let tag = projectConfig.colorTag, let parsed = ProjectColorTag(storageToken: tag) {
                restoredTags[normalizedPath] = parsed
            }
            if let override = projectConfig.startupOverride {
                restoredStartupOverrides[normalizedPath] = override.normalized()
            }
            if let agentOverrideID = projectConfig.acpAgentOverrideID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !agentOverrideID.isEmpty {
                restoredACPAgentOverrides[normalizedPath] = agentOverrideID
            }
            if let shell = projectConfig.terminalShellOverride {
                restoredShellOverrides[normalizedPath] = shell
            }
            if let idx = projectConfig.shortcutIndex {
                restoredShortcuts[normalizedPath] = idx
            }
            restoredScopedShortcuts[normalizedPath] = projectConfig.shortcuts
        }
        projectColorTagsByPath = restoredTags
        projectStartupOverridesByPath = restoredStartupOverrides
        projectACPAgentOverrideIDsByPath = restoredACPAgentOverrides
        projectTerminalShellOverridesByPath = restoredShellOverrides
        projectShortcutByPath = restoredShortcuts
        projectScopedShortcutsByPath = restoredScopedShortcuts
        pruneColorTags()
    }

    var configFile: VibeSpaceConfigFile {
        let paths: [String]
        let unresolved: [String]
        let focusedPath: String?
        if projects.isEmpty {
            // Derive entirely from storedProjectPaths — it already includes
            // both resolved and unresolved paths from before shutdown.
            paths = storedProjectPaths.filter { Self.isExistingDirectory(path: $0) }
            unresolved = storedProjectPaths.filter { !Self.isExistingDirectory(path: $0) }
            focusedPath = storedFocusedProjectPath
        } else {
            paths = projects.map { $0.projectIdentifier }
            unresolved = unresolvedProjectPaths
            focusedPath = focusedProject?.projectIdentifier
        }
        return VibeSpaceConfigFile(
            id: id,
            name: name,
            projectPaths: paths,
            unresolvedProjectPaths: unresolved,
            parkedProjectPaths: parkedProjectPaths,
            focusedProjectPath: focusedPath,
            startupSettings: startupSettings.normalized(),
            defaultTerminalShell: defaultTerminalShell,
            sourceControlSettings: sourceControlSettings,
            shortcuts: vibespaceShortcuts
        )
    }

    var focusedProject: AnyProjectSession? {
        if let focusedProjectID,
           let project = projects.first(where: { $0.id == focusedProjectID }) {
            project.activate()
            return project
        }
        let project = projects.first
        project?.activate()
        return project
    }

    var stackedProjects: [AnyProjectSession] {
        let focusedID = focusedProject?.id
        return projects.filter { $0.id != focusedID }
    }

    func shutdownProjects() {
        for project in projects {
            project.shutdown()
        }
    }

    /// Tears down all live project sessions without recreating them.
    /// The vibespace remains in the catalog and can be reopened later,
    /// which will create fresh sessions from `storedProjectPaths`.
    mutating func resetSession() {
        // Snapshot paths before shutdown
        storedProjectPaths = projects.map(\.projectIdentifier) + unresolvedProjectPaths
        storedFocusedProjectPath = projects.first(where: { $0.id == focusedProjectID })?.projectIdentifier

        shutdownProjects()
        projects = []
        focusedProjectID = nil
    }

    func makeProjectSession(rootURL: URL) -> AnyProjectSession {
        projectSessionFactory(rootURL)
    }

    /// Creates a remote (SSH) project session via the identifier-based factory if available.
    /// Returns nil for vibespaces created without an identifier-based factory.
    func makeIdentifierSession(identifier: String) -> AnyProjectSession? {
        identifierSessionFactory?(identifier)
    }
}
