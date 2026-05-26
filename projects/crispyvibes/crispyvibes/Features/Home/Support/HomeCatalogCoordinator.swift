import AppKit
import Foundation

@MainActor
final class HomeCatalogCoordinator {
    private let appContainer: AppContainer
    private let appShellStore: AppShellStore
    private let vibespaceCatalogStore: VibeSpaceCatalogStore
    private let vibespaceManagement: VibeSpaceManagementService
    private let layoutPersistence: LayoutPersistenceService
    private let shelfStore: ShelfStore
    private let walkthroughController: FeatureWalkthroughController
    private let terminalSpotlightCoordinator: TerminalSpotlightCoordinator
    private let vibespaceHydrationCoordinator: VibeSpaceHydrationCoordinator

    private let maximumRecentVibeSpaceCount = 12
    private var didLoadPersistedCatalog = false
    private var catalogLoadTask: Task<Void, Never>?

    init(
        appContainer: AppContainer,
        appShellStore: AppShellStore,
        vibespaceCatalogStore: VibeSpaceCatalogStore,
        vibespaceManagement: VibeSpaceManagementService,
        layoutPersistence: LayoutPersistenceService,
        shelfStore: ShelfStore,
        walkthroughController: FeatureWalkthroughController,
        terminalSpotlightCoordinator: TerminalSpotlightCoordinator,
        vibespaceHydrationCoordinator: VibeSpaceHydrationCoordinator
    ) {
        self.appContainer = appContainer
        self.appShellStore = appShellStore
        self.vibespaceCatalogStore = vibespaceCatalogStore
        self.vibespaceManagement = vibespaceManagement
        self.layoutPersistence = layoutPersistence
        self.shelfStore = shelfStore
        self.walkthroughController = walkthroughController
        self.terminalSpotlightCoordinator = terminalSpotlightCoordinator
        self.vibespaceHydrationCoordinator = vibespaceHydrationCoordinator
    }

    private var catalogUseCase: HomeVibeSpaceCatalogUseCase {
        HomeVibeSpaceCatalogUseCase(container: appContainer)
    }

    private var importUseCase: HomeVibeSpaceImportUseCase {
        HomeVibeSpaceImportUseCase()
    }

    private var activeVibeSpaceID: UUID? {
        appShellStore.activeVibeSpaceID
    }

    private var vibespaceNamingCandidatesLowercased: Set<String> {
        var existingNames = vibespaceCatalogStore.vibespaceNamesLowercased()
        for config in vibespaceManagement.recentVibeSpaceConfigs(limit: maximumRecentVibeSpaceCount) {
            existingNames.insert(config.name.lowercased())
        }
        return existingNames
    }

    func cancelCatalogLoading() {
        catalogLoadTask?.cancel()
        catalogLoadTask = nil
    }

    func markCatalogNeedsReload() {
        didLoadPersistedCatalog = false
    }

    func loadVibeSpaceCatalogIfNeeded(
        shouldRestoreVibeSpaceCatalogOnLaunch: Bool,
        onUntrustedVibeSpaceNameResolved: @escaping (String?) -> Void
    ) {
        guard !didLoadPersistedCatalog else { return }
        let startTime = Date()
        didLoadPersistedCatalog = true

        let recentIDs = vibespaceManagement.recentVibeSpaceIDs()
        guard let vibespaceID = recentIDs.first,
              let result = vibespaceManagement.loadVibeSpace(id: vibespaceID) else {
            return
        }
        let entry = (
            config: result.config,
            projectConfigs: vibespaceManagement.loadProjectConfigs(for: result.config),
            trusted: result.trusted
        )

        if !entry.trusted {
            onUntrustedVibeSpaceNameResolved(entry.config.name)
        }

        loadCatalogFromConfig(
            entry.config,
            projectConfigs: entry.projectConfigs,
            trusted: entry.trusted,
            shouldRestoreVibeSpaceCatalogOnLaunch: shouldRestoreVibeSpaceCatalogOnLaunch
        )
        appContainer.operationMetricsStore.recordOperation(name: "catalog.load", startTime: startTime)
    }

    func persistWelcomeVibeSpaceCLIProfile(_ selection: VibeSpaceCLISelection) {
        let normalizedSelection = selection.normalized
        let resolvedConfiguration = normalizedSelection.resolvedTextServiceConfiguration
        UserDefaults.standard.set(normalizedSelection.profile.rawValue, forKey: AppPreferences.textServiceCLIProfileKey)
        UserDefaults.standard.set(resolvedConfiguration.trustMode.rawValue, forKey: AppPreferences.textServiceCLITrustModeKey)
        UserDefaults.standard.set(resolvedConfiguration.command, forKey: AppPreferences.textServiceCLICommandKey)
        UserDefaults.standard.set(resolvedConfiguration.arguments, forKey: AppPreferences.textServiceCLIArgumentsKey)
        UserDefaults.standard.set(resolvedConfiguration.passAgentFlag, forKey: AppPreferences.textServicePassAgentFlagKey)
    }

    @discardableResult
    func drainPendingExternalOpenRequestsIfNeeded(
        openFilesInShelf: ([URL], Bool) -> Void,
        focusProject: (AnyProjectSession, Bool) -> Void,
        openTerminalOnlyVibeSpaceView: () -> Void
    ) -> Bool {
        let requests = ExternalOpenRelay.drain()
        guard !requests.isEmpty else { return false }

        cancelCatalogLoading()
        for request in requests {
            openExternalPaths(
                request.urls,
                preferTerminal: request.preferTerminal,
                openFilesInShelf: openFilesInShelf,
                focusProject: focusProject,
                openTerminalOnlyVibeSpaceView: openTerminalOnlyVibeSpaceView
            )
        }
        return true
    }

    func addVibeSpaceFromFolderPicker() {
        let projectURLs = chooseDirectoryURLs(prompt: "Open VibeSpace From Folder(s)")
        guard !projectURLs.isEmpty else { return }

        openVibeSpace(
            named: initialVibeSpaceName(for: projectURLs),
            projectURLs: projectURLs
        )
    }

    func restoreVibeSpaceConfig(
        _ config: VibeSpaceConfigFile,
        projectConfigs: [String: ProjectConfigFile]? = nil
    ) {
        loadCatalogFromConfig(
            config,
            projectConfigs: projectConfigs ?? vibespaceManagement.loadProjectConfigs(for: config),
            trusted: true,
            shouldRestoreVibeSpaceCatalogOnLaunch: true
        )
    }

    func applyVibeSpaceCreationResult(_ result: VibeSpaceCreationResult) {
        let startTime = Date()
        if let selection = result.cliSelection {
            persistWelcomeVibeSpaceCLIProfile(selection)
        }

        openVibeSpace(named: result.name, projectURLs: result.folders)

        vibespaceCatalogStore.mutateActiveVibeSpace(for: activeVibeSpaceID) { vibespace, _ in
            catalogUseCase.applyCreationResult(result, to: &vibespace)
        }

        persistVibeSpaceCatalog()
        appContainer.operationMetricsStore.recordOperation(name: "vibespace.create", startTime: startTime)
    }

    func cancelWelcomeVibeSpaceCreation() {
        appShellStore.dismissModalSheet(.vibeSpaceCreation)
    }

    func continueWithTerminalVibeSpaceFromWelcome() {
        if let existingID = vibespaceManagement.terminalModeVibeSpaceID(),
           let result = vibespaceManagement.loadVibeSpace(id: existingID) {
            restoreVibeSpaceConfig(result.config)
            return
        }
        openVibeSpace(
            named: AppStrings.Home.terminalVibeSpaceName,
            projectURLs: [FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL],
            preferredCanvasMode: .terminalOnly
        )
        if let createdID = activeVibeSpaceID {
            vibespaceManagement.setTerminalModeVibeSpaceID(createdID)
        }
    }

    func resetLocalAppState(
        clearExpandedVibeSpaceSidebarProjectPaths: () -> Void,
        applyDefaultPreferences: () -> Void,
        ensureAuthDefaultsIfNeeded: () -> Void
    ) {
        cancelCatalogLoading()
        vibespaceHydrationCoordinator.cancelVibeSpaceHydration()
        vibespaceCatalogStore.shutdownDisplayedVibeSpaces()
        appContainer.terminalBoardDetachedWindowManager.closeAll()
        appContainer.terminalBoardStandaloneRegistry.shutdownAll()
        AppPreferences.resetAllUserOverrides()
        vibespaceManagement.pruneOnLaunch()
        appContainer.appPersistenceStore.resetAppStorage()
        layoutPersistence.resetToFirstRunState()
        shelfStore.resetForFreshStart()
        walkthroughController.resetForFreshStart()
        vibespaceCatalogStore.resetDisplayedVibeSpaces()
        appShellStore.resetForFreshStart()
        vibespaceHydrationCoordinator.resetStartupExecutionFlags()
        cancelWelcomeVibeSpaceCreation()
        terminalSpotlightCoordinator.dismiss(animated: false)
        clearExpandedVibeSpaceSidebarProjectPaths()
        applyDefaultPreferences()
        ensureAuthDefaultsIfNeeded()
        didLoadPersistedCatalog = false
    }

    func renameVibeSpace(
        _ vibespaceID: UUID,
        to proposedName: String,
        onActiveVibeSpaceRenamed: () -> Void
    ) {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard vibespaceCatalogStore.vibespaceValue(for: vibespaceID, { $0.name }) != trimmedName else { return }

        vibespaceCatalogStore.mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.rename(trimmedName)
        }
        if activeVibeSpaceID == vibespaceID {
            onActiveVibeSpaceRenamed()
        }
        vibespaceManagement.touchRecent(vibespaceID)
        persistVibeSpaceCatalog()
    }

    func addProjectsToActiveVibeSpaceFromFolderPicker(
        focusProject: (AnyProjectSession, Bool) -> Void,
        openTerminalOnlyVibeSpaceView: () -> Void
    ) {
        guard let vibespaceID = activeVibeSpaceID else { return }
        let projectURLs = chooseDirectoryURLs(prompt: "Open Project Folder(s)")
        guard !projectURLs.isEmpty else { return }
        addProjects(
            projectURLs,
            to: vibespaceID,
            forceTerminalFocus: false,
            focusProject: focusProject,
            openTerminalOnlyVibeSpaceView: openTerminalOnlyVibeSpaceView
        )
    }

    func closeActiveVibeSpaceSession() {
        let startTime = Date()
        guard let vibespaceID = activeVibeSpaceID else { return }

        vibespaceCatalogStore.mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.resetSession()
        }
        appContainer.terminalBoardDetachedWindowManager.closeWindows(for: vibespaceID)
        appContainer.terminalBoardStandaloneRegistry.release(vibespaceID: vibespaceID)
        vibespaceHydrationCoordinator.clearStartupExecutionFlags(for: vibespaceID)
        vibespaceHydrationCoordinator.cancelVibeSpaceHydration()
        appShellStore.dismissSurface()
        appShellStore.selectVibeSpace(nil)
        persistVibeSpaceCatalog()
        appShellStore.showHome()
        appContainer.operationMetricsStore.recordOperation(name: "vibespace.close", projectContext: vibespaceID.uuidString, startTime: startTime)
    }

    /// Permanently deletes one or more vibespaces and their persisted state.
    ///
    /// If the active vibespace is among the IDs, the active session is closed
    /// first so in-memory state matches disk. After the persistence layer
    /// removes the vibespaces, the recents catalog token is bumped so views
    /// reading `vibespaceManagement.recentVibeSpaceConfigs(...)` re-fetch.
    func deleteVibeSpaces(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let startTime = Date()
        if let activeID = activeVibeSpaceID, ids.contains(activeID) {
            closeActiveVibeSpaceSession()
        }
        for id in ids {
            vibespaceManagement.deleteVibeSpace(id: id)
        }
        appContainer.operationMetricsStore.recordOperation(
            name: "vibespace.delete",
            projectContext: ids.count == 1 ? ids.first?.uuidString : nil,
            startTime: startTime
        )
    }

    func nextTemporaryVibeSpaceName() -> String {
        importUseCase.nextTemporaryVibeSpaceName(
            defaultName: AppStrings.Home.defaultVibeSpaceBaseName,
            existingNamesLowercased: vibespaceNamingCandidatesLowercased
        )
    }

    func clearDisplayedVibeSpaces() {
        vibespaceCatalogStore.clearDisplayedVibeSpaces()
        appShellStore.clearVibeSpaceSelection()
        appShellStore.dismissHome()
    }

    func persistVibeSpaceCatalog() {
        if let vibespace = vibespaceCatalogStore.vibespaces.first {
            vibespaceManagement.persistVibeSpaceState(vibespace)
        }
    }

    private func loadCatalogFromConfig(
        _ config: VibeSpaceConfigFile,
        projectConfigs: [String: ProjectConfigFile],
        trusted: Bool,
        shouldRestoreVibeSpaceCatalogOnLaunch: Bool
    ) {
        cancelCatalogLoading()
        catalogLoadTask = Task { [weak self] in
            guard let self else { return }
            let vibespace = await catalogUseCase.loadVibeSpaceState(
                config: config,
                projectConfigs: projectConfigs
            )
            guard !Task.isCancelled else { return }

            guard shouldRestoreVibeSpaceCatalogOnLaunch else {
                clearDisplayedVibeSpaces()
                return
            }

            replaceDisplayedVibeSpace(with: vibespace)

            if !trusted {
                for project in vibespace.projects {
                    let path = project.rootURL.standardizedFileURL.path
                    vibespaceHydrationCoordinator.markStartupExecuted(forProjectPath: path, in: config.id)
                }
            }

            persistAndHydrateVibeSpace(config.id)
        }
    }

    private func initialVibeSpaceName(for projectURLs: [URL]) -> String {
        importUseCase.initialVibeSpaceName(
            for: projectURLs,
            defaultName: AppStrings.Home.defaultVibeSpaceBaseName,
            existingNamesLowercased: vibespaceNamingCandidatesLowercased
        )
    }

    private func chooseDirectoryURLs(prompt: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = prompt

        guard panel.runModal() == .OK else { return [] }
        return importUseCase.normalizedUniqueDirectoryURLs(from: panel.urls)
    }

    private func openVibeSpace(
        named vibespaceName: String,
        projectURLs: [URL],
        preferredCanvasMode: VibeSpaceCanvasMode? = nil
    ) {
        cancelCatalogLoading()
        let finalName = importUseCase.resolvedVibeSpaceName(
            proposedName: vibespaceName,
            projectURLs: projectURLs,
            defaultName: AppStrings.Home.defaultVibeSpaceBaseName,
            existingNamesLowercased: vibespaceNamingCandidatesLowercased
        )
        let vibespace = catalogUseCase.makeVibeSpace(named: finalName, projectURLs: projectURLs)
        replaceDisplayedVibeSpace(with: vibespace)
        vibespaceHydrationCoordinator.resetStartupExecutionFlags()
        vibespaceManagement.touchRecent(vibespace.id)
        if let preferredCanvasMode {
            layoutPersistence.setCanvasMode(preferredCanvasMode, for: vibespace.id)
        }
        persistAndHydrateVibeSpace(vibespace.id)
    }

    private func openExternalPaths(
        _ urls: [URL],
        preferTerminal: Bool,
        openFilesInShelf: ([URL], Bool) -> Void,
        focusProject: (AnyProjectSession, Bool) -> Void,
        openTerminalOnlyVibeSpaceView: () -> Void
    ) {
        let targets = importUseCase.normalizedExistingExternalTargets(from: urls)
        guard !targets.directories.isEmpty || !targets.files.isEmpty else { return }

        if !targets.files.isEmpty {
            openFilesInShelf(targets.files, true)
        }

        guard !targets.directories.isEmpty else { return }

        let candidateProjectURLs = importUseCase.normalizedUniqueDirectoryURLs(from: targets.directories)
        guard !candidateProjectURLs.isEmpty else { return }

        if let vibespaceID = activeVibeSpaceID {
            addProjects(
                candidateProjectURLs,
                to: vibespaceID,
                forceTerminalFocus: preferTerminal && targets.files.isEmpty,
                focusProject: focusProject,
                openTerminalOnlyVibeSpaceView: openTerminalOnlyVibeSpaceView
            )
        } else {
            openVibeSpace(
                named: initialVibeSpaceName(for: candidateProjectURLs),
                projectURLs: candidateProjectURLs,
                preferredCanvasMode: preferTerminal ? .terminalOnly : nil
            )
        }
    }

    private func addProjects(
        _ projectURLs: [URL],
        to vibespaceID: UUID,
        forceTerminalFocus: Bool,
        focusProject: (AnyProjectSession, Bool) -> Void,
        openTerminalOnlyVibeSpaceView: () -> Void
    ) {
        var focusedProject: AnyProjectSession?
        vibespaceCatalogStore.mutateVibeSpace(id: vibespaceID) { vibespace in
            focusedProject = vibespace.addProjects(from: projectURLs)
        }

        if let focusedProject {
            focusProject(focusedProject, forceTerminalFocus)
            if forceTerminalFocus {
                openTerminalOnlyVibeSpaceView()
            }
        }

        persistAndHydrateVibeSpace(vibespaceID)
    }

    private func replaceDisplayedVibeSpace(
        with vibespace: VibeSpaceState,
        cancelWelcomeCreation: Bool = true
    ) {
        vibespaceCatalogStore.replaceDisplayedVibeSpace(with: vibespace)
        appShellStore.showVibeSpace(vibespace.id)
        if cancelWelcomeCreation {
            cancelWelcomeVibeSpaceCreation()
        }
    }

    private func persistAndHydrateVibeSpace(_ vibespaceID: UUID) {
        persistVibeSpaceCatalog()
        vibespaceHydrationCoordinator.scheduleVibeSpaceTerminalHydration(for: vibespaceID)
    }

    deinit { catalogLoadTask?.cancel() }
}
