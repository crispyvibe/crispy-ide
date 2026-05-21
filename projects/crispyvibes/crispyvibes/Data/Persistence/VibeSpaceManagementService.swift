import Combine
import Foundation

// MARK: - Protocol

@MainActor
protocol VibeSpaceManaging: AnyObject {
    // Lifecycle
    func createVibeSpace(name: String, projectURLs: [URL]) -> VibeSpaceConfigFile
    func loadVibeSpace(id: UUID) -> (config: VibeSpaceConfigFile, trusted: Bool)?
    func deleteVibeSpace(id: UUID)
    func renameVibeSpace(id: UUID, to name: String)

    // Project management
    func addProjects(_ paths: [String], to vibespaceID: UUID)
    func removeProject(at path: String, from vibespaceID: UUID)
    func setFocusedProject(path: String, in vibespaceID: UUID)

    // VibeSpace-level startup
    func setStartupProfile(_ profile: VibeSpaceTerminalStartupProfile, at index: Int, for vibespaceID: UUID)
    func setStartupTerminalCount(_ count: Int, for vibespaceID: UUID)
    func setFocusTerminalOnProjectSwitch(_ enabled: Bool, for vibespaceID: UUID)
    func setDefaultTerminalShell(_ shell: TerminalShellPreference?, for vibespaceID: UUID)

    // Per-project config
    func setProjectColorTag(_ tag: String?, forProject path: String, in vibespaceID: UUID)
    func setProjectShortcut(_ index: Int?, forProject path: String, in vibespaceID: UUID)
    func setProjectStartupOverride(_ override: VibeSpaceProjectStartupOverride?, forProject path: String, in vibespaceID: UUID)
    func setProjectTerminalShell(_ shell: TerminalShellPreference?, forProject path: String, in vibespaceID: UUID)

    // Per-project session state
    func saveProjectSession(
        entries: [TerminalSessionEntry],
        activeDirectory: String?,
        activeIdentity: String?,
        forProject path: String,
        in vibespaceID: UUID
    )
    func loadProjectSession(forProject path: String, in vibespaceID: UUID) -> (
        entries: [TerminalSessionEntry],
        activeDirectory: String?,
        activeIdentity: String?,
        trusted: Bool
    )?

    // Scoped shortcuts
    func setVibeSpaceShortcuts(_ shortcuts: [TerminalShortcutDefinition], vibespaceID: UUID)
    func setProjectShortcuts(_ shortcuts: [TerminalShortcutDefinition], vibespaceID: UUID, projectPath: String)
    func vibespaceShortcuts(vibespaceID: UUID) -> [TerminalShortcutDefinition]
    func projectShortcuts(vibespaceID: UUID, projectPath: String) -> [TerminalShortcutDefinition]

    // Read-only
    func vibespaceRefs() -> [VibeSpaceRef]
    func recentVibeSpaceIDs() -> [UUID]
    func recentVibeSpaceConfigs(limit: Int) -> [VibeSpaceConfigFile]
    func loadProjectConfig(forProject path: String, in vibespaceID: UUID) -> ProjectConfigFile?
    func loadProjectConfigs(for config: VibeSpaceConfigFile) -> [String: ProjectConfigFile]
    func persistVibeSpaceState(_ vibespace: VibeSpaceState)

    // App state
    func touchRecent(_ vibespaceID: UUID)
    func removeFromRecent(_ vibespaceID: UUID)
    func hasAcceptedDisclaimer() -> Bool
    func setAcceptedDisclaimer(_ accepted: Bool?)

    // Pruning
    func pruneOnLaunch()
}

// MARK: - Concrete Implementation

@MainActor
final class VibeSpaceManagementService: VibeSpaceManaging {
    let exposedPersistenceStore: VibeSpacePersistenceStore
    private var persistenceStore: VibeSpacePersistenceStore { exposedPersistenceStore }
    private var debounceWorkItems: [UUID: DispatchWorkItem] = [:]
    private var dirtyConfigs: [UUID: VibeSpaceConfigFile] = [:]
    private var dirtyProjectConfigs: [String: (vibespaceID: UUID, config: ProjectConfigFile)] = [:]
    private var projectShortcutsCache: [String: [TerminalShortcutDefinition]] = [:]
    private var vibespaceShortcutsCache: [UUID: [TerminalShortcutDefinition]] = [:]

    init(persistenceStore: VibeSpacePersistenceStore) {
        self.exposedPersistenceStore = persistenceStore
    }

    // MARK: - Lifecycle

    func createVibeSpace(name: String, projectURLs: [URL]) -> VibeSpaceConfigFile {
        let id = UUID()
        let paths = projectURLs.map { VibeSpaceValidator.normalizedPath($0.standardizedFileURL.path) }
        var config = VibeSpaceConfigFile(
            id: id,
            name: name,
            projectPaths: paths,
            unresolvedProjectPaths: [],
            focusedProjectPath: paths.first,
            startupSettings: .default,
            defaultTerminalShell: nil
        )
        config = VibeSpaceValidator.validateVibeSpaceConfig(config)
        persistenceStore.saveVibeSpaceConfig(config)

        for path in paths {
            let projectConfig = ProjectConfigFile.empty(projectPath: path)
            persistenceStore.saveProjectConfig(projectConfig, in: id)
        }

        var appState = persistenceStore.loadAppState()
        appState.touchVibeSpace(id)
        persistenceStore.saveAppState(appState)

        return config
    }

    func loadVibeSpace(id: UUID) -> (config: VibeSpaceConfigFile, trusted: Bool)? {
        guard let result = persistenceStore.loadVibeSpaceConfig(for: id) else { return nil }
        let validated = VibeSpaceValidator.validateVibeSpaceConfig(result.value)
        return (validated, result.verified)
    }

    func deleteVibeSpace(id: UUID) {
        debounceWorkItems[id]?.cancel()
        debounceWorkItems.removeValue(forKey: id)
        dirtyConfigs.removeValue(forKey: id)
        vibespaceShortcutsCache.removeValue(forKey: id)
        projectShortcutsCache = projectShortcutsCache.filter { !$0.key.hasPrefix(id.uuidString) }
        persistenceStore.deleteVibeSpace(id)

        var appState = persistenceStore.loadAppState()
        appState.removeVibeSpace(id)
        if appState.terminalModeVibeSpaceID == id {
            appState.terminalModeVibeSpaceID = nil
        }
        persistenceStore.saveAppState(appState)
    }

    func terminalModeVibeSpaceID() -> UUID? {
        persistenceStore.loadAppState().terminalModeVibeSpaceID
    }

    func setTerminalModeVibeSpaceID(_ id: UUID?) {
        var appState = persistenceStore.loadAppState()
        guard appState.terminalModeVibeSpaceID != id else { return }
        appState.terminalModeVibeSpaceID = id
        persistenceStore.saveAppState(appState)
    }

    func renameVibeSpace(id: UUID, to name: String) {
        mutateVibeSpaceConfig(id) { config in
            config.name = name
        }
    }

    // MARK: - Project Management

    func addProjects(_ paths: [String], to vibespaceID: UUID) {
        let normalized = paths.map { VibeSpaceValidator.normalizedPath($0) }
        mutateVibeSpaceConfig(vibespaceID) { config in
            let existing = Set(config.projectPaths)
            for path in normalized where !existing.contains(path) {
                config.projectPaths.append(path)
            }
        }
        for path in normalized {
            let existing = persistenceStore.loadProjectConfig(for: path, in: vibespaceID)
            if existing == nil {
                persistenceStore.saveProjectConfig(ProjectConfigFile.empty(projectPath: path), in: vibespaceID)
            }
        }
    }

    func removeProject(at path: String, from vibespaceID: UUID) {
        let normalized = VibeSpaceValidator.normalizedPath(path)
        mutateVibeSpaceConfig(vibespaceID) { config in
            config.projectPaths.removeAll { $0 == normalized }
            config.unresolvedProjectPaths.removeAll { $0 == normalized }
            if config.focusedProjectPath == normalized {
                config.focusedProjectPath = config.projectPaths.first
            }
        }
        // INV-009: Delete project file — all per-project config gone
        projectShortcutsCache.removeValue(forKey: "\(vibespaceID.uuidString):\(normalized)")
        persistenceStore.deleteProjectConfig(for: normalized, in: vibespaceID)
    }

    func setFocusedProject(path: String, in vibespaceID: UUID) {
        let normalized = VibeSpaceValidator.normalizedPath(path)
        mutateVibeSpaceConfig(vibespaceID) { config in
            if config.projectPaths.contains(normalized) {
                config.focusedProjectPath = normalized
            }
        }
    }

    // MARK: - VibeSpace Startup

    func setStartupProfile(_ profile: VibeSpaceTerminalStartupProfile, at index: Int, for vibespaceID: UUID) {
        mutateVibeSpaceConfig(vibespaceID) { config in
            config.startupSettings.setProfile(profile, at: index)
        }
    }

    func setStartupTerminalCount(_ count: Int, for vibespaceID: UUID) {
        mutateVibeSpaceConfig(vibespaceID) { config in
            config.startupSettings.startupTerminalCount = count
        }
    }

    func setFocusTerminalOnProjectSwitch(_ enabled: Bool, for vibespaceID: UUID) {
        mutateVibeSpaceConfig(vibespaceID) { config in
            config.startupSettings.focusTerminalOnProjectSwitch = enabled
        }
    }

    func setDefaultTerminalShell(_ shell: TerminalShellPreference?, for vibespaceID: UUID) {
        mutateVibeSpaceConfig(vibespaceID) { config in
            config.defaultTerminalShell = shell
        }
    }

    // MARK: - Per-Project Config

    func setProjectColorTag(_ tag: String?, forProject path: String, in vibespaceID: UUID) {
        mutateProjectConfig(path, in: vibespaceID) { config in
            config.colorTag = tag
        }
    }

    func setProjectShortcut(_ index: Int?, forProject path: String, in vibespaceID: UUID) {
        mutateProjectConfig(path, in: vibespaceID) { config in
            config.shortcutIndex = index
        }
    }

    func setProjectStartupOverride(_ override: VibeSpaceProjectStartupOverride?, forProject path: String, in vibespaceID: UUID) {
        mutateProjectConfig(path, in: vibespaceID) { config in
            config.startupOverride = override
        }
    }

    func setProjectTerminalShell(_ shell: TerminalShellPreference?, forProject path: String, in vibespaceID: UUID) {
        mutateProjectConfig(path, in: vibespaceID) { config in
            config.terminalShellOverride = shell
        }
    }

    // MARK: - Per-Project Session

    func saveProjectSession(
        entries: [TerminalSessionEntry],
        activeDirectory: String?,
        activeIdentity: String?,
        forProject path: String,
        in vibespaceID: UUID
    ) {
        mutateProjectConfig(path, in: vibespaceID) { config in
            config.terminalEntries = entries
            config.activeTerminalDirectory = activeDirectory
            config.activeTerminalIdentity = activeIdentity
        }
    }

    func loadProjectSession(forProject path: String, in vibespaceID: UUID) -> (
        entries: [TerminalSessionEntry],
        activeDirectory: String?,
        activeIdentity: String?,
        trusted: Bool
    )? {
        let normalized = VibeSpaceValidator.normalizedPath(path)
        if let result = persistenceStore.loadProjectConfig(for: normalized, in: vibespaceID) {
            return (
                result.value.terminalEntries,
                result.value.activeTerminalDirectory,
                result.value.activeTerminalIdentity,
                result.verified
            )
        }

        for legacyIdentifier in legacyProjectSessionAliases(for: normalized) {
            guard let legacyResult = persistenceStore.loadProjectConfig(for: legacyIdentifier, in: vibespaceID) else {
                continue
            }
            let migrated = migrateLegacyProjectSession(
                legacyResult.value,
                from: legacyIdentifier,
                to: normalized,
                in: vibespaceID
            )
            return (
                migrated.terminalEntries,
                migrated.activeTerminalDirectory,
                migrated.activeTerminalIdentity,
                legacyResult.verified
            )
        }

        return nil
    }

    private func legacyProjectSessionAliases(for normalizedIdentifier: String) -> [String] {
        guard let parsed = SSHConnectionProfile.parse(identifier: normalizedIdentifier) else {
            return []
        }

        var aliases: [String] = []
        var seen = Set<String>()

        func append(_ candidate: String?) {
            guard let candidate, !candidate.isEmpty else { return }
            guard candidate != normalizedIdentifier else { return }
            guard seen.insert(candidate).inserted else { return }
            aliases.append(candidate)
        }

        append(parsed.remotePath)
        append(URL(fileURLWithPath: normalizedIdentifier).standardizedFileURL.path)

        return aliases
    }

    private func migrateLegacyProjectSession(
        _ config: ProjectConfigFile,
        from legacyIdentifier: String,
        to normalizedIdentifier: String,
        in vibespaceID: UUID
    ) -> ProjectConfigFile {
        var migrated = config
        migrated.projectPath = normalizedIdentifier
        persistenceStore.saveProjectConfig(migrated, in: vibespaceID)
        persistenceStore.deleteProjectConfig(for: legacyIdentifier, in: vibespaceID)
        dirtyProjectConfigs.removeValue(forKey: "\(vibespaceID.uuidString):\(legacyIdentifier)")
        return migrated
    }

    // MARK: - Scoped Shortcuts

    func setVibeSpaceShortcuts(_ shortcuts: [TerminalShortcutDefinition], vibespaceID: UUID) {
        mutateVibeSpaceConfig(vibespaceID) { config in
            config.shortcuts = shortcuts
        }
        vibespaceShortcutsCache.removeValue(forKey: vibespaceID)
        NotificationCenter.default.post(name: .vibespaceShortcutsDidChange, object: nil)
    }

    func setProjectShortcuts(_ shortcuts: [TerminalShortcutDefinition], vibespaceID: UUID, projectPath: String) {
        mutateProjectConfig(projectPath, in: vibespaceID) { config in
            config.shortcuts = shortcuts
        }
        let normalized = VibeSpaceValidator.normalizedPath(projectPath)
        projectShortcutsCache.removeValue(forKey: "\(vibespaceID.uuidString):\(normalized)")
        NotificationCenter.default.post(name: .vibespaceShortcutsDidChange, object: nil)
    }

    func vibespaceShortcuts(vibespaceID: UUID) -> [TerminalShortcutDefinition] {
        if let shortcuts = dirtyConfigs[vibespaceID]?.shortcuts {
            return shortcuts
        }
        if let cached = vibespaceShortcutsCache[vibespaceID] {
            return cached
        }
        let shortcuts = persistenceStore.loadVibeSpaceConfig(for: vibespaceID)?.value.shortcuts ?? []
        vibespaceShortcutsCache[vibespaceID] = shortcuts
        return shortcuts
    }

    func projectShortcuts(vibespaceID: UUID, projectPath: String) -> [TerminalShortcutDefinition] {
        let normalized = VibeSpaceValidator.normalizedPath(projectPath)
        let key = "\(vibespaceID.uuidString):\(normalized)"
        if let shortcuts = dirtyProjectConfigs[key]?.config.shortcuts {
            return shortcuts
        }
        if let cached = projectShortcutsCache[key] {
            return cached
        }
        let shortcuts = persistenceStore.loadProjectConfig(for: normalized, in: vibespaceID)?.value.shortcuts ?? []
        projectShortcutsCache[key] = shortcuts
        return shortcuts
    }

    // MARK: - Read-Only

    func vibespaceRefs() -> [VibeSpaceRef] {
        persistenceStore.existingVibeSpaceIDs().compactMap { id in
            guard let result = persistenceStore.loadVibeSpaceConfig(for: id) else { return nil }
            return VibeSpaceRef(id: id, name: result.value.name)
        }
    }

    func recentVibeSpaceIDs() -> [UUID] {
        let appState = persistenceStore.loadAppState()
        let existing = Set(persistenceStore.existingVibeSpaceIDs())
        return appState.recentVibeSpaceIDs.filter { existing.contains($0) }
    }

    func recentVibeSpaceConfigs(limit: Int) -> [VibeSpaceConfigFile] {
        var configs: [VibeSpaceConfigFile] = []
        for id in recentVibeSpaceIDs().prefix(limit) {
            guard let result = loadVibeSpace(id: id) else { continue }
            configs.append(result.config)
        }
        return configs
    }

    func loadProjectConfig(forProject path: String, in vibespaceID: UUID) -> ProjectConfigFile? {
        let normalized = VibeSpaceValidator.normalizedPath(path)
        return persistenceStore.loadProjectConfig(for: normalized, in: vibespaceID)?.value
    }

    func loadProjectConfigs(for config: VibeSpaceConfigFile) -> [String: ProjectConfigFile] {
        var configs: [String: ProjectConfigFile] = [:]
        for path in config.projectPaths {
            if let projectConfig = loadProjectConfig(forProject: path, in: config.id) {
                configs[path] = projectConfig
            }
        }
        return configs
    }

    func persistVibeSpaceState(_ vibespace: VibeSpaceState) {
        let config = vibespace.configFile
        saveVibeSpaceConfig(config)

        let allProjectPaths = config.projectPaths + config.unresolvedProjectPaths
        for path in allProjectPaths {
            var projectConfig = loadProjectConfig(forProject: path, in: vibespace.id)
                ?? ProjectConfigFile.empty(projectPath: path)
            projectConfig.colorTag = vibespace.projectColorTagsByPath[path]?.storageToken
            projectConfig.shortcutIndex = vibespace.projectShortcutByPath[path]
            projectConfig.startupOverride = vibespace.projectStartupOverridesByPath[path]
            projectConfig.acpAgentOverrideID = vibespace.projectACPAgentOverrideIDsByPath[path]
            projectConfig.terminalShellOverride = vibespace.projectTerminalShellOverridesByPath[path]
            projectConfig.shortcuts = vibespace.projectScopedShortcutsByPath[path] ?? []
            saveProjectConfig(projectConfig, in: vibespace.id)
        }

        touchRecent(vibespace.id)
    }

    // MARK: - App State

    func touchRecent(_ vibespaceID: UUID) {
        var appState = persistenceStore.loadAppState()
        appState.touchVibeSpace(vibespaceID)
        persistenceStore.saveAppState(appState)
    }

    func removeFromRecent(_ vibespaceID: UUID) {
        var appState = persistenceStore.loadAppState()
        appState.removeVibeSpace(vibespaceID)
        persistenceStore.saveAppState(appState)
    }

    func hasAcceptedDisclaimer() -> Bool {
        if UserDefaults.standard.object(forKey: AppPreferences.onboardingDisclaimerAcceptedKey) as? Bool == true {
            return true
        }
        return persistenceStore.loadAppState().hasAcceptedDisclaimer == true
    }

    func setAcceptedDisclaimer(_ accepted: Bool?) {
        var appState = persistenceStore.loadAppState()
        appState.hasAcceptedDisclaimer = accepted
        persistenceStore.saveAppState(appState)
        if let accepted {
            UserDefaults.standard.set(accepted, forKey: AppPreferences.onboardingDisclaimerAcceptedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppPreferences.onboardingDisclaimerAcceptedKey)
        }
    }

    // MARK: - Pruning

    func pruneOnLaunch() {
        persistenceStore.pruneInvalidVibeSpaceDirectories()
        let existing = Set(persistenceStore.existingVibeSpaceIDs())
        var appState = persistenceStore.loadAppState()
        appState = appState.pruned(existingIDs: existing)
        persistenceStore.saveAppState(appState)
    }

    // MARK: - Flush

    func flushAll() {
        for (id, config) in dirtyConfigs {
            debounceWorkItems[id]?.cancel()
            persistenceStore.saveVibeSpaceConfig(config)
        }
        dirtyConfigs.removeAll()
        for (_, entry) in dirtyProjectConfigs {
            persistenceStore.saveProjectConfig(entry.config, in: entry.vibespaceID)
        }
        dirtyProjectConfigs.removeAll()
    }

    // MARK: - VibeSpace Config

    func saveVibeSpaceConfig(_ config: VibeSpaceConfigFile) {
        let validated = VibeSpaceValidator.validateVibeSpaceConfig(config)
        persistenceStore.saveVibeSpaceConfig(validated)
    }

    func saveProjectConfig(_ config: ProjectConfigFile, in vibespaceID: UUID) {
        persistenceStore.saveProjectConfig(config, in: vibespaceID)
    }

    // MARK: - Internal Mutation Helpers

    private func mutateVibeSpaceConfig(_ id: UUID, _ mutate: (inout VibeSpaceConfigFile) -> Void) {
        var config = dirtyConfigs[id]
            ?? persistenceStore.loadVibeSpaceConfig(for: id)?.value
            ?? VibeSpaceConfigFile(id: id, name: "Untitled", projectPaths: [], unresolvedProjectPaths: [], startupSettings: .default)
        mutate(&config)
        config = VibeSpaceValidator.validateVibeSpaceConfig(config)
        dirtyConfigs[id] = config
        scheduleDebouncedWrite(for: id)
    }

    private func mutateProjectConfig(_ path: String, in vibespaceID: UUID, _ mutate: (inout ProjectConfigFile) -> Void) {
        let normalized = VibeSpaceValidator.normalizedPath(path)
        let key = "\(vibespaceID.uuidString):\(normalized)"
        var config = dirtyProjectConfigs[key]?.config
            ?? persistenceStore.loadProjectConfig(for: normalized, in: vibespaceID)?.value
            ?? ProjectConfigFile.empty(projectPath: normalized)
        mutate(&config)
        config = VibeSpaceValidator.validateProjectConfig(config, validProjectPaths: [])
        dirtyProjectConfigs[key] = (vibespaceID, config)
        scheduleProjectDebouncedWrite(key: key)
    }

    private func scheduleDebouncedWrite(for id: UUID) {
        debounceWorkItems[id]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let config = self.dirtyConfigs.removeValue(forKey: id) else { return }
            self.persistenceStore.saveVibeSpaceConfig(config)
        }
        debounceWorkItems[id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func scheduleProjectDebouncedWrite(key: String) {
        // Project writes are less frequent — write immediately
        if let entry = dirtyProjectConfigs.removeValue(forKey: key) {
            persistenceStore.saveProjectConfig(entry.config, in: entry.vibespaceID)
        }
    }
}
