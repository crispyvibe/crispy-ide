import Foundation

/// Pure reconciliation helpers for aligning terminal board tiles with the live
/// terminal view models. Non-terminal tiles (browser, ACP, file, vibecast) are
/// invariant across every function in this file — they are not inspected or
/// modified.
///
/// These helpers mutate `VibeSpaceTerminalBoardState` in place so they can be
/// invoked inside the store's `mutate` block and participate in the single
/// mutation boundary.
@MainActor
enum TerminalTileReconciler {
    /// Phase 1 of reconciliation: bind each terminal tile to a live tab.
    ///
    /// For each terminal tile across all surfaces:
    /// - If the tile has a `projectPath` that resolves to a known project, try to
    ///   match the tile's `terminalTabID` against that project's tabs; otherwise
    ///   match by working directory and reassign `terminalTabID`.
    /// - If the tile has a `projectPath` that no longer resolves to a known project,
    ///   clear the path and fall through to standalone matching.
    /// - If the tile has no `projectPath`, match against the standalone view model.
    ///
    /// This phase does not create new tabs and does not change the set of tiles.
    /// It only updates `projectPath`, `terminalTabID`, and `workingDirectoryPath`
    /// on existing terminal tiles.
    static func reconcileProjectAssignments(
        state: inout VibeSpaceTerminalBoardState,
        projectsByPath: [String: AnyProjectSession],
        tabsByProjectPathAndID: [String: [UUID: TerminalTab]],
        tabsByProjectPathAndDirectory: [String: [String: [TerminalTab]]],
        standaloneTabsByID: [UUID: TerminalTab],
        standaloneTabsByDirectory: [String: [TerminalTab]]
    ) {
        for surfaceIndex in state.surfaces.indices {
            let tileIDs = state.surfaces[surfaceIndex].layout.tileIDs
            for tileID in tileIDs {
                guard let tile = state.surfaces[surfaceIndex].layout.tile(for: tileID) else { continue }
                guard tile.isTerminal else { continue }

                if let projectPath = tile.projectPath {
                    if projectsByPath[projectPath] != nil {
                        bindTile(
                            tileID: tileID,
                            surfaces: &state.surfaces,
                            surfaceIndex: surfaceIndex,
                            projectPath: projectPath,
                            tabsByID: tabsByProjectPathAndID[projectPath] ?? [:],
                            tabsByDirectory: tabsByProjectPathAndDirectory[projectPath] ?? [:]
                        )
                        continue
                    }
                    // Project gone — clear path and fall through to standalone.
                    state.surfaces[surfaceIndex].layout.updateTile(tileID) { updated in
                        updated.projectPath = nil
                        updated.terminalTabID = nil
                    }
                }

                bindTile(
                    tileID: tileID,
                    surfaces: &state.surfaces,
                    surfaceIndex: surfaceIndex,
                    projectPath: nil,
                    tabsByID: standaloneTabsByID,
                    tabsByDirectory: standaloneTabsByDirectory
                )
            }
        }
    }

    /// Phase 3 of reconciliation: for terminal tiles that still have no matching
    /// tab after Phase 2, instruct the appropriate view model to create one. The
    /// caller is notified via `onTabCreated` so it can refresh its lookup tables
    /// before the state is published.
    static func restorePersistedTerminalTiles(
        state: inout VibeSpaceTerminalBoardState,
        projectsByPath: [String: AnyProjectSession],
        standaloneViewModel: TerminalViewModel,
        tabsByProjectPathAndID: [String: [UUID: TerminalTab]],
        standaloneTabsByID: [UUID: TerminalTab],
        onTabCreated: (_ projectPath: String?, _ terminalViewModel: TerminalViewModel) -> Void
    ) {
        for surfaceIndex in state.surfaces.indices {
            let tiles = state.surfaces[surfaceIndex].layout.tiles
            for tile in tiles where tile.isTerminal {
                let viewModel: TerminalViewModel
                if let projectPath = tile.projectPath {
                    guard let project = projectsByPath[projectPath] else { continue }
                    viewModel = project.terminalViewModel
                } else {
                    viewModel = standaloneViewModel
                }

                // Skip tiles that are already bound to a live tab.
                if let tabID = tile.terminalTabID {
                    let knownTabs: [UUID: TerminalTab]
                    if let projectPath = tile.projectPath {
                        knownTabs = tabsByProjectPathAndID[projectPath] ?? [:]
                    } else {
                        knownTabs = standaloneTabsByID
                    }
                    if knownTabs[tabID] != nil { continue }
                }

                // Create a tab in the appropriate view model and reassign the tile.
                viewModel.createTab(
                    directoryURL: tile.workingDirectoryURL,
                    startImmediately: true
                )
                onTabCreated(tile.projectPath, viewModel)

                if let createdTab = viewModel.activeTab {
                    state.surfaces[surfaceIndex].layout.updateTile(tile.id) { updated in
                        updated.terminalTabID = createdTab.id
                        updated.workingDirectoryPath = createdTab.workingDirectory.standardizedFileURL.path
                    }
                }
            }
        }
    }

    // MARK: - Private

    /// Try to match a terminal tile to a known tab, first by exact `terminalTabID`,
    /// then by working directory. Updates the tile in place only when a match is found.
    private static func bindTile(
        tileID: UUID,
        surfaces: inout [VibeSpaceTerminalBoardSurface],
        surfaceIndex: Int,
        projectPath: String?,
        tabsByID: [UUID: TerminalTab],
        tabsByDirectory: [String: [TerminalTab]]
    ) {
        guard let tile = surfaces[surfaceIndex].layout.tile(for: tileID) else { return }
        let normalizedWorkingDirectoryPath = tile.workingDirectoryURL.path

        if let terminalTabID = tile.terminalTabID,
           let matchedTab = tabsByID[terminalTabID] {
            let matchedWorkingDirectoryPath = matchedTab.workingDirectory.standardizedFileURL.path
            if tile.workingDirectoryPath != matchedWorkingDirectoryPath {
                surfaces[surfaceIndex].layout.updateTile(tileID) { updated in
                    updated.workingDirectoryPath = matchedWorkingDirectoryPath
                }
            }
            return
        }

        if let directoryMatchedTab = tabsByDirectory[normalizedWorkingDirectoryPath]?.first(where: { candidate in
            surfaces.allSatisfy { surface in
                surface.layout.tiles.allSatisfy { $0.id == tileID || $0.terminalTabID != candidate.id }
            }
        }) {
            surfaces[surfaceIndex].layout.updateTile(tileID) { updated in
                updated.projectPath = projectPath
                updated.terminalTabID = directoryMatchedTab.id
                updated.workingDirectoryPath = directoryMatchedTab.workingDirectory.standardizedFileURL.path
            }
        }
    }
}

/// Store-level entry point used by view code (e.g., unresolved tile card). Binds
/// the tile to its terminal tab, creating a tab if needed.
@MainActor
extension VibeSpaceTerminalBoardStore {
    func restoreTerminalIfNeeded(
        for tileID: UUID,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) {
        guard let tile = layout(for: surfaceID).tile(for: tileID), tile.isTerminal else { return }

        let terminalViewModel: TerminalViewModel
        if let projectPath = tile.projectPath {
            guard let project = projectsByPath[projectPath] else { return }
            terminalViewModel = project.terminalViewModel
        } else {
            terminalViewModel = standaloneTerminalViewModel
        }

        // If the tile's terminalTabID is already known, nothing to do.
        if let terminalTabID = tile.terminalTabID {
            let knownTabs: [UUID: TerminalTab]
            if let projectPath = tile.projectPath {
                knownTabs = tabsByProjectPathAndID[projectPath] ?? [:]
            } else {
                knownTabs = standaloneTabsByID
            }
            if knownTabs[terminalTabID] != nil { return }
        }

        terminalViewModel.createTab(
            directoryURL: tile.workingDirectoryURL,
            startImmediately: true
        )
        if let projectPath = tile.projectPath {
            refreshProjectTabLookup(projectPath: projectPath, terminalViewModel: terminalViewModel)
        } else {
            refreshStandaloneTabLookup()
        }

        guard let createdTab = terminalViewModel.activeTab else { return }
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            state.surfaces[index].layout.updateTile(tileID) { updated in
                updated.terminalTabID = createdTab.id
                updated.workingDirectoryPath = createdTab.workingDirectory.standardizedFileURL.path
            }
        }
    }
}
