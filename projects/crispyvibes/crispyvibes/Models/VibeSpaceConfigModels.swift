import Foundation

// MARK: - Terminal Session State

struct ProjectSessionPersistedState: Equatable {
    var terminalEntries: [TerminalSessionEntry]
    var activeTerminalDirectory: String?
    var activeTerminalIdentity: String?
}

struct TerminalSessionEntry: Codable, Equatable {
    var id: UUID?
    var workingDirectoryPath: String
    var customName: String?
    var origin: TerminalOrigin
    var tmuxSessionName: String?
}

// MARK: - App State (global, lightweight)

struct AppStateFile: Codable, Equatable {
    static let maxRecentCount = 20

    var recentVibeSpaceIDs: [UUID]
    var sidebarWidth: Double?
    var hasAcceptedDisclaimer: Bool?
    var terminalModeVibeSpaceID: UUID?

    static let empty = AppStateFile(recentVibeSpaceIDs: [])

    func pruned(existingIDs: Set<UUID>) -> AppStateFile {
        let filtered = recentVibeSpaceIDs.filter { existingIDs.contains($0) }
        return AppStateFile(
            recentVibeSpaceIDs: Array(filtered.prefix(Self.maxRecentCount)),
            sidebarWidth: sidebarWidth,
            hasAcceptedDisclaimer: hasAcceptedDisclaimer,
            terminalModeVibeSpaceID: terminalModeVibeSpaceID.flatMap { existingIDs.contains($0) ? $0 : nil }
        )
    }

    mutating func touchVibeSpace(_ id: UUID) {
        recentVibeSpaceIDs.removeAll { $0 == id }
        recentVibeSpaceIDs.insert(id, at: 0)
        if recentVibeSpaceIDs.count > Self.maxRecentCount {
            recentVibeSpaceIDs = Array(recentVibeSpaceIDs.prefix(Self.maxRecentCount))
        }
    }

    mutating func removeVibeSpace(_ id: UUID) {
        recentVibeSpaceIDs.removeAll { $0 == id }
    }
}

// MARK: - VibeSpace Config (per vibespace)

struct VibeSpaceSourceControlSettings: Codable, Equatable {
    static let minimumScanDepth = 1
    static let maximumScanDepth = 16
    static let minimumRepositoryCount = 1
    static let maximumRepositoryCount = 256
    static let minimumPresentedRepositoryCount = 1
    static let maximumPresentedRepositoryCount = 48
    static let defaultIgnoredDirectoryNames: [String] = [
        ".build",
        ".cache",
        ".derived",
        ".next",
        ".nuxt",
        ".swiftpm",
        "Build",
        "Carthage",
        "DerivedData",
        "Pods",
        "SourcePackages",
        "build",
        "checkouts",
        "dist",
        "node_modules",
        "out"
    ]
    static let `default` = VibeSpaceSourceControlSettings()

    var ignoredDirectoryNames: [String] = Self.defaultIgnoredDirectoryNames
    var scanMaxDepth: Int = 8
    var scanMaxRepositories: Int = 64
    var autoPresentedRepositoryLimit: Int = 12

    func normalized() -> VibeSpaceSourceControlSettings {
        var normalized = self
        var seenNames = Set<String>()
        normalized.ignoredDirectoryNames = ignoredDirectoryNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seenNames.insert($0.lowercased()).inserted }
            .sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        normalized.scanMaxDepth = max(Self.minimumScanDepth, min(scanMaxDepth, Self.maximumScanDepth))
        normalized.scanMaxRepositories = max(
            Self.minimumRepositoryCount,
            min(scanMaxRepositories, Self.maximumRepositoryCount)
        )
        normalized.autoPresentedRepositoryLimit = max(
            Self.minimumPresentedRepositoryCount,
            min(autoPresentedRepositoryLimit, Self.maximumPresentedRepositoryCount)
        )
        normalized.autoPresentedRepositoryLimit = min(
            normalized.autoPresentedRepositoryLimit,
            normalized.scanMaxRepositories
        )
        return normalized
    }
}

struct VibeSpaceConfigFile: Codable, Equatable {
    var version: Int = 2
    var id: UUID
    var name: String
    var projectPaths: [String]
    var unresolvedProjectPaths: [String]
    var focusedProjectPath: String?
    var startupSettings: VibeSpaceStartupSettings
    var defaultTerminalShell: TerminalShellPreference?
    var sourceControlSettings: VibeSpaceSourceControlSettings = .default

    var shortcuts: [TerminalShortcutDefinition] = []

    private enum CodingKeys: String, CodingKey {
        case version
        case id
        case name
        case projectPaths
        case unresolvedProjectPaths
        case focusedProjectPath
        case startupSettings
        case defaultTerminalShell
        case sourceControlSettings
        case shortcuts
    }

    init(
        version: Int = 2,
        id: UUID,
        name: String,
        projectPaths: [String],
        unresolvedProjectPaths: [String],
        focusedProjectPath: String? = nil,
        startupSettings: VibeSpaceStartupSettings,
        defaultTerminalShell: TerminalShellPreference? = nil,
        sourceControlSettings: VibeSpaceSourceControlSettings = .default,
        shortcuts: [TerminalShortcutDefinition] = []
    ) {
        self.version = version
        self.id = id
        self.name = name
        self.projectPaths = projectPaths
        self.unresolvedProjectPaths = unresolvedProjectPaths
        self.focusedProjectPath = focusedProjectPath
        self.startupSettings = startupSettings
        self.defaultTerminalShell = defaultTerminalShell
        self.sourceControlSettings = sourceControlSettings
        self.shortcuts = shortcuts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 2
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        projectPaths = try container.decode([String].self, forKey: .projectPaths)
        unresolvedProjectPaths = try container.decodeIfPresent([String].self, forKey: .unresolvedProjectPaths) ?? []
        focusedProjectPath = try container.decodeIfPresent(String.self, forKey: .focusedProjectPath)
        startupSettings = try container.decode(VibeSpaceStartupSettings.self, forKey: .startupSettings)
        defaultTerminalShell = try container.decodeIfPresent(TerminalShellPreference.self, forKey: .defaultTerminalShell)
        sourceControlSettings = try container.decode(VibeSpaceSourceControlSettings.self, forKey: .sourceControlSettings)
        shortcuts = try container.decodeIfPresent([TerminalShortcutDefinition].self, forKey: .shortcuts) ?? []
    }

}

// MARK: - Project Config (per project within vibespace)

struct ProjectConfigFile: Codable, Equatable {
    var version: Int = 2
    var projectPath: String
    var colorTag: String?
    var shortcutIndex: Int?
    var startupOverride: VibeSpaceProjectStartupOverride?
    var acpAgentOverrideID: String?
    var terminalShellOverride: TerminalShellPreference?
    var terminalEntries: [TerminalSessionEntry]
    var activeTerminalDirectory: String?
    var activeTerminalIdentity: String?
    var shortcuts: [TerminalShortcutDefinition] = []

    private enum CodingKeys: String, CodingKey {
        case version, projectPath, colorTag, shortcutIndex, startupOverride
        case acpAgentOverrideID, terminalShellOverride, terminalEntries, activeTerminalDirectory
        case activeTerminalIdentity, shortcuts
    }

    init(
        version: Int = 2,
        projectPath: String,
        colorTag: String? = nil,
        shortcutIndex: Int? = nil,
        startupOverride: VibeSpaceProjectStartupOverride? = nil,
        acpAgentOverrideID: String? = nil,
        terminalShellOverride: TerminalShellPreference? = nil,
        terminalEntries: [TerminalSessionEntry] = [],
        activeTerminalDirectory: String? = nil,
        activeTerminalIdentity: String? = nil,
        shortcuts: [TerminalShortcutDefinition] = []
    ) {
        self.version = version
        self.projectPath = projectPath
        self.colorTag = colorTag
        self.shortcutIndex = shortcutIndex
        self.startupOverride = startupOverride
        self.acpAgentOverrideID = acpAgentOverrideID
        self.terminalShellOverride = terminalShellOverride
        self.terminalEntries = terminalEntries
        self.activeTerminalDirectory = activeTerminalDirectory
        self.activeTerminalIdentity = activeTerminalIdentity
        self.shortcuts = shortcuts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 2
        projectPath = try container.decode(String.self, forKey: .projectPath)
        colorTag = try container.decodeIfPresent(String.self, forKey: .colorTag)
        shortcutIndex = try container.decodeIfPresent(Int.self, forKey: .shortcutIndex)
        startupOverride = try container.decodeIfPresent(VibeSpaceProjectStartupOverride.self, forKey: .startupOverride)
        acpAgentOverrideID = try container.decodeIfPresent(String.self, forKey: .acpAgentOverrideID)
        terminalShellOverride = try container.decodeIfPresent(TerminalShellPreference.self, forKey: .terminalShellOverride)
        terminalEntries = try container.decodeIfPresent([TerminalSessionEntry].self, forKey: .terminalEntries) ?? []
        activeTerminalDirectory = try container.decodeIfPresent(String.self, forKey: .activeTerminalDirectory)
        activeTerminalIdentity = try container.decodeIfPresent(String.self, forKey: .activeTerminalIdentity)
        shortcuts = try container.decodeIfPresent([TerminalShortcutDefinition].self, forKey: .shortcuts) ?? []
    }

    static func empty(projectPath: String) -> ProjectConfigFile {
        ProjectConfigFile(
            projectPath: projectPath,
            terminalEntries: []
        )
    }
}

// MARK: - VibeSpace Ref (lightweight, for listing)

struct VibeSpaceRef: Identifiable, Equatable {
    var id: UUID
    var name: String
}
