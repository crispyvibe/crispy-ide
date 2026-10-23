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
    func moveTerminalTile(
        _ tileID: UUID,
        relativeTo targetTileID: UUID,
        placement: TerminalTabMovePlacement,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> Bool {
        var didMove = false
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            var layout = state.surfaces[index].layout
            guard layout.moveTileInLinearOrder(
                tileID,
                relativeTo: targetTileID,
                placement: placement
            ) else { return }
            state.surfaces[index].layout = layout
            didMove = true
        }
        return didMove
    }

    @discardableResult
    func moveTerminalTabTile(
        projectPath: String,
        tabID: UUID,
        relativeToProjectPath targetProjectPath: String,
        targetTabID: UUID,
        placement: TerminalTabMovePlacement,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> Bool {
        let layout = layout(for: surfaceID)
        guard let sourceTileID = layout.tiles.first(where: {
            ($0.projectIdentifier ?? $0.projectPath) == projectPath && $0.terminalTabID == tabID
        })?.id,
        let targetTileID = layout.tiles.first(where: {
            ($0.projectIdentifier ?? $0.projectPath) == targetProjectPath && $0.terminalTabID == targetTabID
        })?.id else {
            return false
        }
        return moveTerminalTile(
            sourceTileID,
            relativeTo: targetTileID,
            placement: placement,
            surfaceID: surfaceID
        )
    }

    /// Legacy compatibility for callers whose board cannot contain duplicate tab IDs.
    @discardableResult
    func moveTerminalTabTile(
        _ tabID: UUID,
        relativeTo targetTabID: UUID,
        placement: TerminalTabMovePlacement,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> Bool {
        let layout = layout(for: surfaceID)
        guard let sourceTileID = layout.tiles.first(where: { $0.terminalTabID == tabID })?.id,
              let targetTileID = layout.tiles.first(where: { $0.terminalTabID == targetTabID })?.id else {
            return false
        }
        return moveTerminalTile(
            sourceTileID,
            relativeTo: targetTileID,
            placement: placement,
            surfaceID: surfaceID
        )
    }

    func spotlightReconciliation(
        liveIDs: [SpotlightPersistentItemID],
        currentID: SpotlightPersistentItemID?,
        surfaceID: UUID
    ) -> SpotlightReconciliationResult {
        let seed = boardState.surface(id: surfaceID)?.spotlightLayout ?? SpotlightLayoutSnapshot()
        return SpotlightLayoutReconciler.reconcile(snapshot: seed, liveIDs: liveIDs, currentID: currentID)
    }

    func spotlightLayout(
        liveIDs: [SpotlightPersistentItemID],
        surfaceID: UUID
    ) -> SpotlightLayoutSnapshot {
        let surface = boardState.surface(id: surfaceID)
        let seed = surface?.spotlightLayout ?? SpotlightLayoutSnapshot()
        return seed.normalized(liveIDs: liveIDs)
    }

    /// Commits the main VibeSpace Spotlight layout and its primary-board mirror together.
    ///
    /// Only visible primary-surface tiles represented by flattened Spotlight members move.
    /// Existing column IDs/counts/widths and destination row weights remain attached to
    /// their slots; minimized and detached surfaces are not modified.
    @discardableResult
    func commitMainSpotlightLayout(
        _ snapshot: SpotlightLayoutSnapshot,
        liveIDs: [SpotlightPersistentItemID]
    ) -> Bool {
        let normalized = snapshot.normalized(liveIDs: liveIDs)
        let previousState = boardState
        mutateLive { state in
            guard let primaryIndex = state.surfaces.firstIndex(where: { $0.id == state.primarySurfaceID }) else {
                return
            }
            state.surfaces[primaryIndex].spotlightLayout = normalized
            let layout = state.surfaces[primaryIndex].layout
            let orderedTileIDs = normalized.flattenedMembers.compactMap { id in
                Self.spotlightTileID(for: id, in: layout)
            }
            var mirroredLayout = layout
            _ = mirroredLayout.reorderTilesInLinearOrder(orderedTileIDs)
            state.surfaces[primaryIndex].layout = mirroredLayout
        }
        let persistedState = snapshotProviders.enriched(boardState)
        let didPersist = layoutPersistence.commitMainSpotlightLayout(
            normalized,
            liveIDs: liveIDs,
            terminalBoardState: persistedState,
            for: vibespaceID
        )
        return didPersist || boardState != previousState
    }

    @discardableResult
    func setSpotlightLayout(
        _ snapshot: SpotlightLayoutSnapshot,
        liveIDs: [SpotlightPersistentItemID],
        surfaceID: UUID
    ) -> Bool {
        let normalized = snapshot.normalized(liveIDs: liveIDs)
        guard boardState.surface(id: surfaceID)?.spotlightLayout != normalized else { return false }
        mutate { state in
            guard let surfaceIndex = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            state.surfaces[surfaceIndex].spotlightLayout = normalized

            let layout = state.surfaces[surfaceIndex].layout
            let orderedTileIDs = normalized.flattenedMembers.compactMap { id in
                Self.spotlightTileID(for: id, in: layout)
            }
            var mirroredLayout = layout
            _ = mirroredLayout.reorderTilesInLinearOrder(orderedTileIDs)
            state.surfaces[surfaceIndex].layout = mirroredLayout
        }
        return true
    }

    private static func spotlightTileID(
        for id: SpotlightPersistentItemID,
        in layout: VibeSpaceTerminalBoardLayout
    ) -> UUID? {
        switch id {
        case let .terminal(projectPath, tabID):
            return layout.tiles.first { tile in
                guard tile.terminalTabID == tabID,
                      let tileOwner = tile.projectIdentifier ?? tile.projectPath else { return false }
                if projectPath.hasPrefix("ssh://") || tileOwner.hasPrefix("ssh://") {
                    return tileOwner == projectPath
                }
                return URL(fileURLWithPath: tileOwner).standardizedFileURL.path
                    == URL(fileURLWithPath: projectPath).standardizedFileURL.path
            }?.id
        case let .standaloneTerminal(_, tileID, _),
             let .file(tileID),
             let .browser(tileID):
            return layout.tiles.contains(where: { $0.id == tileID }) ? tileID : nil
        case let .acp(tileID, _):
            return layout.tiles.contains(where: { $0.id == tileID }) ? tileID : nil
        case .vibeCast:
            return layout.tiles.first(where: \.isVibeCast)?.id
        case .vibeLanes:
            return layout.tiles.first(where: \.isVibeLanes)?.id
        }
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
            if let detached {
                Self.removeSpotlightMember(for: detached, from: &state.surfaces[index])
            }
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
            Self.removeSpotlightMember(for: tile, from: &state.surfaces[sourceIndex])
            Self.removeDuplicateTerminalIdentity(for: tile, in: &state.surfaces, exceptIndex: targetIndex)
            Self.reattach(tile: tile, into: &state.surfaces[targetIndex].layout)
            Self.appendSpotlightMember(for: tile, to: &state.surfaces[targetIndex])
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
            Self.appendSpotlightMember(for: tile, to: &state.surfaces[index])
            didAttach = true
        }
        return didAttach
    }


    /// Removes every board presentation owned by a project across primary and
    /// detached surfaces without closing terminal sessions individually. Project
    /// lifecycle teardown owns the sessions; this mutation owns only layout,
    /// Spotlight membership, active-tile repair, and persistence.
    @discardableResult
    func removeTilesForProject(
        rootPath: String,
        projectIdentifier: String,
        terminalTabIDs: Set<UUID> = []
    ) -> [VibeSpaceTerminalBoardTile] {
        let normalizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        var removedTiles: [VibeSpaceTerminalBoardTile] = []

        mutate { state in
            for surfaceIndex in state.surfaces.indices {
                let candidates = state.surfaces[surfaceIndex].layout.tiles
                    + state.surfaces[surfaceIndex].layout.minimizedTiles
                let matchingIDs = candidates.filter { tile in
                    Self.tile(
                        tile,
                        belongsToProjectRoot: normalizedRoot,
                        projectIdentifier: projectIdentifier,
                        terminalTabIDs: terminalTabIDs
                    )
                }.map(\.id)

                for tileID in matchingIDs {
                    guard let removed = state.surfaces[surfaceIndex].layout.removeTile(withID: tileID) else {
                        continue
                    }
                    Self.removeSpotlightMember(for: removed, from: &state.surfaces[surfaceIndex])
                    removedTiles.append(removed)
                }
            }
        }

        hiddenTerminalIDsByProjectPath[normalizedRoot] = nil
        return removedTiles
    }

    private static func tile(
        _ tile: VibeSpaceTerminalBoardTile,
        belongsToProjectRoot rootPath: String,
        projectIdentifier: String,
        terminalTabIDs: Set<UUID>
    ) -> Bool {
        if let tileProjectIdentifier = tile.projectIdentifier {
            return tileProjectIdentifier == projectIdentifier
        }
        if let selectedProject = tile.acpSnapshot?.selectedProjectIdentifier {
            return selectedProject == projectIdentifier
                || (!projectIdentifier.hasPrefix("ssh://") && selectedProject == rootPath)
        }
        if let terminalTabID = tile.terminalTabID,
           terminalTabIDs.contains(terminalTabID) {
            return true
        }

        // Local identifiers are their canonical root path, so legacy tiles can
        // still be matched by root containment. A remote root path is not
        // globally unique; ambiguous legacy SSH tiles are deliberately retained
        // rather than deleting another host's presentation.
        guard !projectIdentifier.hasPrefix("ssh://") else { return false }
        if tile.projectPath == rootPath { return true }
        if let fileURL = tile.fileURL,
           path(fileURL.standardizedFileURL.path, isWithin: rootPath) {
            return true
        }
        return false
    }

    private static func path(_ candidate: String, isWithin root: String) -> Bool {
        let candidate = URL(fileURLWithPath: candidate).standardizedFileURL.path
        let root = URL(fileURLWithPath: root).standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
    // MARK: - Bulk Cross-Surface Transfer (F048-R13/R16)

    /// F048-R13: collect all tile IDs on `surfaceID` whose `projectPath` matches
    /// `projectPath`. Returns visible tiles followed by minimized tiles. Used by
    /// the bulk-move-to-new-window flow to identify which tiles to relocate.
    func tileIDs(forProject projectPath: String, onSurface surfaceID: UUID) -> [UUID] {
        let surfaceLayout = layout(for: surfaceID)
        let visible = surfaceLayout.tiles
            .filter { ($0.projectIdentifier ?? $0.projectPath) == projectPath }
            .map(\.id)
        let minimized = surfaceLayout.minimizedTiles
            .filter { ($0.projectIdentifier ?? $0.projectPath) == projectPath }
            .map(\.id)
        return visible + minimized
    }

    /// F048-R13: detach every tile on `surfaceID` belonging to `projectPath` in
    /// one mutation, returning them in their original column-then-minimized
    /// order. Caller is responsible for re-attaching them onto another surface
    /// (typically a new detached surface created with `createDetachedSurface(with:title:placement:)`).
    @discardableResult
    func bulkDetachTilesForProject(
        _ projectPath: String,
        fromSurface surfaceID: UUID
    ) -> [VibeSpaceTerminalBoardTile] {
        var detached: [VibeSpaceTerminalBoardTile] = []
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            let visibleIDs = state.surfaces[index].layout.tiles
                .filter { ($0.projectIdentifier ?? $0.projectPath) == projectPath }
                .map(\.id)
            let minimizedIDs = state.surfaces[index].layout.minimizedTiles
                .filter { ($0.projectIdentifier ?? $0.projectPath) == projectPath }
                .map(\.id)
            // Preserve original order: visible first (column-flattened), then minimized.
            for tileID in visibleIDs + minimizedIDs {
                if let removed = state.surfaces[index].layout.removeTile(withID: tileID) {
                    Self.removeSpotlightMember(for: removed, from: &state.surfaces[index])
                    detached.append(removed)
                }
            }
        }
        return detached
    }

    /// F048-R13: create a new detached surface populated with the given tiles
    /// (visible only — minimized tiles are folded into a single visible column
    /// since the new surface is fresh and the user expects to see what they just
    /// moved). The first tile becomes the active tile. Returns the new
    /// surface's UUID. Caller is responsible for opening the NSWindow.
    @discardableResult
    func createDetachedSurface(
        with tiles: [VibeSpaceTerminalBoardTile],
        title: String,
        placement: VibeSpaceTerminalBoardWindowPlacement? = nil
    ) -> UUID {
        let surfaceID = UUID()
        // Distribute up to 16 tiles across up to 4 columns, mirroring the
        // existing layout cap. Excess tiles (>16, which shouldn't happen since
        // each surface caps at 16) fall into minimizedTiles.
        let visibleCap = VibeSpaceTerminalBoardLayout.maximumTileCount
        let visible = Array(tiles.prefix(visibleCap))
        let overflow = Array(tiles.dropFirst(visibleCap))
        let columns = Self.distributeIntoColumns(visible)
        let spotlightLayout = SpotlightLayoutSnapshot(positions: (visible + overflow).compactMap { tile in
            Self.spotlightPersistentID(for: tile, surfaceID: surfaceID).map {
                SpotlightPositionSnapshot(members: [$0])
            }
        })
        let surface = VibeSpaceTerminalBoardSurface(
            id: surfaceID,
            kind: .detached,
            layout: VibeSpaceTerminalBoardLayout(
                columns: columns,
                activeTileID: visible.first?.id,
                minimizedTiles: overflow
            ),
            title: title,
            placement: placement,
            isOpen: true,
            spotlightLayout: spotlightLayout
        )
        mutate { state in
            state.surfaces.append(surface)
        }
        return surfaceID
    }

    /// Distribute `tiles` into up to `maxColumns` columns of up to
    /// `maxRowsPerColumn` each, filling columns left-to-right. Used by bulk
    /// detach so the new detached surface lays the tiles out predictably.
    static func distributeIntoColumns(_ tiles: [VibeSpaceTerminalBoardTile]) -> [VibeSpaceTerminalBoardColumn] {
        guard !tiles.isEmpty else { return [] }
        let maxRows = VibeSpaceTerminalBoardLayout.maxRowsPerColumn
        let maxCols = VibeSpaceTerminalBoardLayout.maxColumns
        let columnCount = min(maxCols, Int(ceil(Double(tiles.count) / Double(maxRows))))
        var columns: [VibeSpaceTerminalBoardColumn] = []
        columns.reserveCapacity(columnCount)
        var i = 0
        for _ in 0..<columnCount {
            let remaining = tiles.count - i
            let take = min(maxRows, remaining)
            let slice = Array(tiles[i..<(i + take)])
            columns.append(VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: slice))
            i += take
        }
        return columns
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


@MainActor
extension VibeSpaceTerminalBoardStore {
    /// Builds stable Spotlight terminal items in canonical visible-then-minimized
    /// board order for one surface.
    func spotlightTerminalItems(
        surfaceID: UUID,
        projects: [AnyProjectSession],
        includeProjectTerminals: Bool
    ) -> [SpotlightItem] {
        let surfaceLayout = layout(for: surfaceID)
        return (surfaceLayout.tiles + surfaceLayout.minimizedTiles).compactMap { tile in
            guard let context = tileContext(for: tile) else { return nil }
            if let projectPath = context.projectPath,
               let project = projects.first(where: {
                   $0.projectIdentifier == projectPath
                       || $0.rootURL.standardizedFileURL.path == projectPath
               }) {
                guard includeProjectTerminals else { return nil }
                return .terminal(project: project, tab: context.terminalTab)
            }
            return .standaloneTerminal(
                surfaceID: surfaceID,
                tileID: tile.id,
                terminalViewModel: context.terminalViewModel,
                tab: context.terminalTab
            )
        }
    }
}


@MainActor
extension VibeSpaceTerminalBoardStore {
    static func removeSpotlightMember(
        for tile: VibeSpaceTerminalBoardTile,
        from surface: inout VibeSpaceTerminalBoardSurface
    ) {
        guard let id = spotlightPersistentID(for: tile, surfaceID: surface.id),
              let snapshot = surface.spotlightLayout else { return }
        surface.spotlightLayout = snapshot.normalized(
            liveIDs: snapshot.flattenedMembers.filter { $0 != id }
        )
    }

    static func appendSpotlightMember(
        for tile: VibeSpaceTerminalBoardTile,
        to surface: inout VibeSpaceTerminalBoardSurface
    ) {
        guard let id = spotlightPersistentID(for: tile, surfaceID: surface.id) else { return }
        let snapshot = surface.spotlightLayout ?? SpotlightLayoutSnapshot()
        surface.spotlightLayout = snapshot.normalized(liveIDs: snapshot.flattenedMembers + [id])
    }

    static func spotlightPersistentID(
        for tile: VibeSpaceTerminalBoardTile,
        surfaceID: UUID
    ) -> SpotlightPersistentItemID? {
        if let tabID = tile.terminalTabID {
            if let projectIdentity = tile.projectIdentifier ?? tile.projectPath {
                return .terminal(projectPath: projectIdentity, tabID: tabID)
            }
            return .standaloneTerminal(surfaceID: surfaceID, tileID: tile.id, tabID: tabID)
        }
        if tile.isVibeCast { return .vibeCast }
        if tile.isVibeLanes { return .vibeLanes }
        if let snapshot = tile.acpSnapshot { return .acp(tileID: tile.id, storeID: snapshot.id) }
        if tile.isFile { return .file(tileID: tile.id) }
        if tile.isBrowser { return .browser(tileID: tile.id) }
        return nil
    }
}
