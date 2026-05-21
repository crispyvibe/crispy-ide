import Foundation

@MainActor
extension VibeSpaceTerminalBoardStore {
    // MARK: - Clipboard

    func copyActiveTileTerminal() {
        guard let context = activeTileContext() else { return }
        context.terminalViewModel.selectTab(context.terminalTab)
        context.terminalViewModel.copy(tabID: context.terminalTab.id)
    }

    func pasteActiveTileTerminal() {
        guard let context = focusedTileContext() ?? activeTileContext() else { return }
        focusTerminal(for: context)
        context.terminalViewModel.paste(tabID: context.terminalTab.id)
    }

    // MARK: - Move

    func moveTile(
        _ tileID: UUID,
        using intent: VibeSpaceTerminalBoardDropIntent,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) {
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            _ = state.surfaces[index].layout.moveTile(tileID, using: intent)
        }
    }

    @discardableResult
    func moveTerminalTabTile(
        _ tabID: UUID,
        relativeTo targetTabID: UUID,
        placement: TerminalTabMovePlacement,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> Bool {
        var didMove = false
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            var layout = state.surfaces[index].layout
            guard let sourceTileID = layout.tiles.first(where: { $0.terminalTabID == tabID })?.id,
                  let targetTileID = layout.tiles.first(where: { $0.terminalTabID == targetTabID })?.id else {
                return
            }
            guard layout.moveTileInLinearOrder(
                sourceTileID,
                relativeTo: targetTileID,
                placement: placement
            ) else { return }
            state.surfaces[index].layout = layout
            didMove = true
        }
        return didMove
    }

    // MARK: - Resize (live + commit)

    /// When `commit` is false, publishes the state change but skips the disk write —
    /// used during drag-resize where writes would otherwise storm. The caller must
    /// call `commitLayoutChanges()` on drag end. When `commit` is true, behaves like
    /// any other mutation: publish + persist.
    func resizeColumns(
        leftColumnID: UUID,
        rightColumnID: UUID,
        deltaFraction: Double,
        commit: Bool,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) {
        let mutation: (inout VibeSpaceTerminalBoardState) -> Void = { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            _ = state.surfaces[index].layout.resizeColumns(
                leftColumnID: leftColumnID,
                rightColumnID: rightColumnID,
                deltaFraction: deltaFraction
            )
        }
        if commit {
            mutate(mutation)
        } else {
            mutateLive(mutation)
        }
    }

    func setColumnWeights(
        leftColumnID: UUID,
        rightColumnID: UUID,
        leftWeight: Double,
        rightWeight: Double,
        commit: Bool,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) {
        let mutation: (inout VibeSpaceTerminalBoardState) -> Void = { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            guard let leftIdx = state.surfaces[index].layout.columns.firstIndex(where: { $0.id == leftColumnID }),
                  let rightIdx = state.surfaces[index].layout.columns.firstIndex(where: { $0.id == rightColumnID }) else {
                return
            }
            state.surfaces[index].layout.columns[leftIdx].widthWeight = leftWeight
            state.surfaces[index].layout.columns[rightIdx].widthWeight = rightWeight
        }
        if commit {
            mutate(mutation)
        } else {
            mutateLive(mutation)
        }
    }

    func resizeRows(
        columnID: UUID,
        upperTileID: UUID,
        lowerTileID: UUID,
        deltaFraction: Double,
        commit: Bool,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) {
        let mutation: (inout VibeSpaceTerminalBoardState) -> Void = { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            _ = state.surfaces[index].layout.resizeRows(
                columnID: columnID,
                upperTileID: upperTileID,
                lowerTileID: lowerTileID,
                deltaFraction: deltaFraction
            )
        }
        if commit {
            mutate(mutation)
        } else {
            mutateLive(mutation)
        }
    }

    func setRowWeights(
        columnID: UUID,
        upperTileID: UUID,
        lowerTileID: UUID,
        upperWeight: Double,
        lowerWeight: Double,
        commit: Bool,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) {
        let mutation: (inout VibeSpaceTerminalBoardState) -> Void = { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            guard let colIdx = state.surfaces[index].layout.columns.firstIndex(where: { $0.id == columnID }) else { return }
            guard let upperIdx = state.surfaces[index].layout.columns[colIdx].tiles.firstIndex(where: { $0.id == upperTileID }),
                  let lowerIdx = state.surfaces[index].layout.columns[colIdx].tiles.firstIndex(where: { $0.id == lowerTileID }) else {
                return
            }
            state.surfaces[index].layout.columns[colIdx].tiles[upperIdx].heightWeight = upperWeight
            state.surfaces[index].layout.columns[colIdx].tiles[lowerIdx].heightWeight = lowerWeight
        }
        if commit {
            mutate(mutation)
        } else {
            mutateLive(mutation)
        }
    }

    /// Finalize pending live mutations by persisting the current state.
    func commitLayoutChanges() {
        commit()
    }

    // MARK: - Cross-Surface Transfer

    /// Detach a tile from a source surface. Returns the detached tile, or nil if the
    /// tile isn't on the source surface. For detach-then-reattach across surfaces, prefer
    /// `moveTile(_:fromSurface:toSurface:)` which batches both sides into a single
    /// mutation.
    func detachTile(
        _ tileID: UUID,
        fromSurface surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> VibeSpaceTerminalBoardTile? {
        var detached: VibeSpaceTerminalBoardTile?
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            detached = state.surfaces[index].layout.removeTile(withID: tileID)
        }
        return detached
    }

    @discardableResult
    func moveTile(
        _ tileID: UUID,
        fromSurface sourceSurfaceID: UUID,
        toSurface targetSurfaceID: UUID
    ) -> Bool {
        guard sourceSurfaceID != targetSurfaceID else { return false }
        var didMove = false
        mutate { state in
            guard let sourceIndex = state.surfaces.firstIndex(where: { $0.id == sourceSurfaceID }) else { return }
            guard let targetIndex = state.surfaces.firstIndex(where: { $0.id == targetSurfaceID }) else { return }
            guard let tile = state.surfaces[sourceIndex].layout.removeTile(withID: tileID) else { return }
            Self.removeDuplicateTerminalIdentity(for: tile, in: &state.surfaces, exceptIndex: targetIndex)
            Self.reattach(tile: tile, into: &state.surfaces[targetIndex].layout)
            didMove = true
        }
        return didMove
    }

    @discardableResult
    func reattachTile(
        _ tile: VibeSpaceTerminalBoardTile,
        toSurface surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> Bool {
        var didAttach = false
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            Self.removeDuplicateTerminalIdentity(for: tile, in: &state.surfaces, exceptIndex: index)
            Self.reattach(tile: tile, into: &state.surfaces[index].layout)
            didAttach = true
        }
        return didAttach
    }

    // MARK: - Tile Context Helpers

    func activeTileContext(surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID) -> TileContext? {
        guard let activeTileID = layout(for: surfaceID).activeTileID else { return nil }
        return tileContext(for: activeTileID, surfaceID: surfaceID)
    }

    func focusedTileContext() -> TileContext? {
        guard let focusedSessionID = standaloneTerminalViewModel.terminalServices.focusCoordinator.currentSessionID,
              let focusedTileID = tileIDByTerminalTabID[focusedSessionID] else {
            return nil
        }
        return tileContext(for: focusedTileID)
    }

    func focusTerminal(for context: TileContext) {
        context.terminalViewModel.selectTab(context.terminalTab)
        if let session = context.terminalViewModel.session(for: context.terminalTab.id) {
            session.startIfNeeded()
            session.requestKeyboardFocus()
        } else {
            context.terminalViewModel.focusActiveTerminal()
        }
    }

    // MARK: - Static helpers (pure)

    /// Remove any tiles on surfaces other than `exceptIndex` that share a terminal identity
    /// with `tile`. Used to prevent duplicate terminal tabs across surfaces during transfer.
    static func removeDuplicateTerminalIdentity(
        for tile: VibeSpaceTerminalBoardTile,
        in surfaces: inout [VibeSpaceTerminalBoardSurface],
        exceptIndex: Int
    ) {
        guard let identity = VibeSpaceTerminalBoardLayoutSync.terminalIdentity(for: tile) else { return }
        for i in surfaces.indices where i != exceptIndex {
            for existingTile in surfaces[i].layout.tiles
                where VibeSpaceTerminalBoardLayoutSync.terminalIdentity(for: existingTile) == identity {
                _ = surfaces[i].layout.removeTile(withID: existingTile.id)
            }
            for existingTile in surfaces[i].layout.minimizedTiles
                where VibeSpaceTerminalBoardLayoutSync.terminalIdentity(for: existingTile) == identity {
                _ = surfaces[i].layout.removeTile(withID: existingTile.id)
            }
        }
    }
}
