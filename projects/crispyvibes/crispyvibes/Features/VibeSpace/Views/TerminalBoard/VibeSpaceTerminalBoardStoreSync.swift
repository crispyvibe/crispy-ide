import Combine
import Foundation

@MainActor
extension VibeSpaceTerminalBoardStore {
    // MARK: - Subscriptions

    func syncProjectSubscriptions() {
        let validPaths = Set(orderedProjectPaths)

        for path in projectTabSubscriptionsByPath.keys where !validPaths.contains(path) {
            projectTabSubscriptionsByPath[path]?.cancel()
            projectTabSubscriptionsByPath[path] = nil
            subscribedTerminalViewModelIDsByPath[path] = nil
            tabsByProjectPathAndID[path] = nil
            tabsByProjectPathAndDirectory[path] = nil
        }

        for path in orderedProjectPaths {
            guard let project = projectsByPath[path] else { continue }
            let terminalViewModelID = ObjectIdentifier(project.terminalViewModel)
            let hasMatchingSubscription = subscribedTerminalViewModelIDsByPath[path] == terminalViewModelID
                && projectTabSubscriptionsByPath[path] != nil
            guard !hasMatchingSubscription else { continue }

            projectTabSubscriptionsByPath[path]?.cancel()
            projectTabSubscriptionsByPath[path] = project.terminal.tabsPublisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.refreshProjectTabLookup(projectPath: path, terminalViewModel: project.terminalViewModel)
                    self.reconcileTerminalTiles()
                }
            subscribedTerminalViewModelIDsByPath[path] = terminalViewModelID
            refreshProjectTabLookup(projectPath: path, terminalViewModel: project.terminalViewModel)
        }
    }

    func configureStandaloneTerminalViewModel(for vibespaceID: UUID?) {
        standaloneTabsSubscription?.cancel()
        standaloneTerminalViewModel = terminalBoardStandaloneRegistry.viewModel(for: vibespaceID)
        standaloneTerminalViewModel.updateShellResolutionContext(
            TerminalShellResolutionContext(appDefault: AppPreferences.storedTerminalShellPreference())
        )
        refreshStandaloneTabLookup()
        standaloneTabsSubscription = standaloneTerminalViewModel.tabsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshStandaloneTabLookup()
                self.reconcileTerminalTiles()
            }
    }

    // MARK: - Reconciliation

    /// Reconciles board tiles with the current set of terminal tabs across all projects
    /// and the standalone view model.
    ///
    /// Non-terminal tiles (browser, ACP, file, vibecast) are invariant across this call.
    /// Minimized terminal tiles stay minimized. Hidden tabs are excluded from the desired
    /// set. Runs through `mutate`, so the result is normalized and persisted atomically.
    ///
    /// Always publishes `objectWillChange` on completion — even when the normalized state
    /// hasn't changed — because view context resolution depends on project/tab lookup
    /// tables that live outside `boardState` and may have been updated by the caller
    /// before invoking reconciliation.
    func reconcileTerminalTiles() {
        guard !isReconciling else { return }
        isReconciling = true
        defer {
            isReconciling = false
            objectWillChange.send()
        }

        let projectsByPath = self.projectsByPath
        let orderedProjectPaths = self.orderedProjectPaths
        let hiddenTerminalIDsByProjectPath = self.hiddenTerminalIDsByProjectPath
        let standaloneViewModel = self.standaloneTerminalViewModel

        var allKnownTabIDs = Set<UUID>()
        for projectPath in orderedProjectPaths {
            if let project = projectsByPath[projectPath] {
                for tab in project.terminal.tabs { allKnownTabIDs.insert(tab.id) }
            }
        }
        for tab in standaloneViewModel.tabs { allKnownTabIDs.insert(tab.id) }

        mutate { state in
            // Phase 1: bind tiles with stale project/tab references
            TerminalTileReconciler.reconcileProjectAssignments(
                state: &state,
                projectsByPath: projectsByPath,
                tabsByProjectPathAndID: self.tabsByProjectPathAndID,
                tabsByProjectPathAndDirectory: self.tabsByProjectPathAndDirectory,
                standaloneTabsByID: self.standaloneTabsByID,
                standaloneTabsByDirectory: self.standaloneTabsByDirectory
            )

            // Phase 2: sync terminal tiles with desired terminal set
            let detachedIdentities = state.surfaces.reduce(into: Set<VibeSpaceTerminalBoardTerminalIdentity>()) {
                result, surface in
                guard surface.kind == .detached else { return }
                result.formUnion((surface.layout.tiles + surface.layout.minimizedTiles).compactMap {
                    VibeSpaceTerminalBoardLayoutSync.terminalIdentity(for: $0)
                })
            }

            let desiredState = VibeSpaceTerminalBoardDesiredTabState(
                orderedProjectPaths: orderedProjectPaths,
                projectsByPath: projectsByPath,
                hiddenTerminalIDsByProjectPath: hiddenTerminalIDsByProjectPath,
                standaloneTabs: standaloneViewModel.tabs
            )
            let primaryDesiredState = VibeSpaceTerminalBoardDesiredTabState(
                orderedProjectPaths: orderedProjectPaths,
                projectsByPath: projectsByPath,
                hiddenTerminalIDsByProjectPath: hiddenTerminalIDsByProjectPath,
                standaloneTabs: standaloneViewModel.tabs,
                excludedTerminalIdentities: detachedIdentities
            )

            for surfaceIndex in state.surfaces.indices {
                let surface = state.surfaces[surfaceIndex]
                let desired = surface.kind == .primary ? primaryDesiredState : desiredState
                let addMissing = surface.kind == .primary
                _ = VibeSpaceTerminalBoardLayoutSync.syncTiles(
                    layout: &state.surfaces[surfaceIndex].layout,
                    desiredTabState: desired,
                    allKnownTabIDs: allKnownTabIDs,
                    addMissingTabs: addMissing
                )
            }

            // Phase 3: bind any terminal tile whose tab still needs attaching
            TerminalTileReconciler.restorePersistedTerminalTiles(
                state: &state,
                projectsByPath: projectsByPath,
                standaloneViewModel: standaloneViewModel,
                tabsByProjectPathAndID: self.tabsByProjectPathAndID,
                standaloneTabsByID: self.standaloneTabsByID,
                onTabCreated: { [weak self] projectPath, viewModel in
                    guard let self else { return }
                    if let projectPath {
                        self.refreshProjectTabLookup(projectPath: projectPath, terminalViewModel: viewModel)
                    } else {
                        self.refreshStandaloneTabLookup()
                    }
                }
            )
        }
    }
}
