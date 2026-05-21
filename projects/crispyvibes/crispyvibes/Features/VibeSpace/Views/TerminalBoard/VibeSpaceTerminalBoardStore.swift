import Combine
import Foundation

/// Owns the terminal board state for a single vibespace.
///
/// Design invariants:
/// - `boardState` is the single source of truth. It is `private(set)`.
/// - Every mutation goes through `mutate(_:)`, which normalizes and persists atomically.
/// - Persistence is a pure sink. External state (browser sessions, URLs) is captured via
///   `BoardSnapshotProviders` at persist time, not injected by the persistence layer.
/// - No notifications are posted on mutation. Views observe `@Published` state directly.
///   Detached board windows share the same store instance and re-render via SwiftUI.
@MainActor
final class VibeSpaceTerminalBoardStore: ObservableObject {
    struct TileContext {
        let tile: VibeSpaceTerminalBoardTile
        let projectPath: String?
        let projectTitle: String
        let terminalViewModel: TerminalViewModel
        let terminalTab: TerminalTab
    }

    @Published private(set) var boardState: VibeSpaceTerminalBoardState

    var vibespaceID: UUID?
    let layoutPersistence: LayoutPersistenceService
    let terminalBoardStandaloneRegistry: VibeSpaceTerminalBoardStandaloneRegistry

    /// External state providers invoked at persist time. Default is a no-op; AppContainer
    /// installs a provider that captures browser sessions from DockedBrowserCoordinator.
    var snapshotProviders: BoardSnapshotProviders = .noop

    var standaloneTerminalViewModel: TerminalViewModel

    var didSeedInitialTile = false
    var isReconciling = false

    var orderedProjectPaths: [String] = []
    var projectsByPath: [String: AnyProjectSession] = [:]
    var tabsByProjectPathAndID: [String: [UUID: TerminalTab]] = [:]
    var tabsByProjectPathAndDirectory: [String: [String: [TerminalTab]]] = [:]
    var standaloneTabsByID: [UUID: TerminalTab] = [:]
    var standaloneTabsByDirectory: [String: [TerminalTab]] = [:]
    var tileIDByTerminalTabID: [UUID: UUID] = [:]
    var hiddenTerminalIDsByProjectPath: [String: Set<UUID>] = [:]
    var projectTabSubscriptionsByPath: [String: AnyCancellable] = [:]
    var subscribedTerminalViewModelIDsByPath: [String: ObjectIdentifier] = [:]
    var standaloneTabsSubscription: AnyCancellable?
    var focusedSessionSubscription: AnyCancellable?
    var acpStoreRemovedSubscription: AnyCancellable?

    init(
        vibespaceID: UUID?,
        layoutPersistence: LayoutPersistenceService,
        terminalBoardStandaloneRegistry: VibeSpaceTerminalBoardStandaloneRegistry,
        snapshotProviders: BoardSnapshotProviders? = nil
    ) {
        self.vibespaceID = vibespaceID
        self.layoutPersistence = layoutPersistence
        self.terminalBoardStandaloneRegistry = terminalBoardStandaloneRegistry
        self.snapshotProviders = snapshotProviders ?? .noop
        boardState = layoutPersistence.terminalBoardState(for: vibespaceID)

        standaloneTerminalViewModel = terminalBoardStandaloneRegistry.viewModel(for: vibespaceID)
        rebuildTileLookup()
        pruneStaleFileTiles()
        configureStandaloneTerminalViewModel(for: vibespaceID)
        focusedSessionSubscription = NotificationCenter.default.publisher(for: .terminalFocusedSessionDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                let sessionID = notification.userInfo?[TerminalFocusCoordinatorUserInfoKey.sessionID] as? UUID
                self?.focusedSessionDidChange(to: sessionID)
            }
        acpStoreRemovedSubscription = NotificationCenter.default.publisher(for: .acpStoreRemoved)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let storeID = notification.userInfo?["storeID"] as? UUID else { return }
                self?.removeACPTiles(storeID: storeID)
            }
    }

    deinit {
        standaloneTabsSubscription?.cancel()
        focusedSessionSubscription?.cancel()
        acpStoreRemovedSubscription?.cancel()
        for subscription in projectTabSubscriptionsByPath.values {
            subscription.cancel()
        }
    }

    // MARK: - Single Mutation Boundary

    /// The only method that changes `boardState` and persists.
    ///
    /// Contract:
    /// - Applies `transform` to a mutable copy of the current state.
    /// - Normalizes the result.
    /// - If the normalized result equals the current state, does nothing (no publish, no
    ///   disk write).
    /// - Otherwise, publishes the new state, rebuilds lookup tables, and persists.
    ///
    /// `transform` must be pure with respect to `boardState`: it may touch other stores
    /// or services, but it must not mutate `boardState` outside of the inout parameter.
    func mutate(_ transform: (inout VibeSpaceTerminalBoardState) -> Void) {
        applyMutation(transform, persistAfter: true)
    }

    /// Variant of `mutate` that publishes the new state but does not write to disk.
    /// Used for in-progress live interactions (e.g., drag-resize) where frequent writes
    /// would be wasteful. Callers must invoke `commit()` when the interaction completes.
    func mutateLive(_ transform: (inout VibeSpaceTerminalBoardState) -> Void) {
        applyMutation(transform, persistAfter: false)
    }

    /// Persists the current state. Idempotent. Called automatically at the end of `mutate`;
    /// callers invoke directly after a sequence of `mutateLive` calls or when an external
    /// source (e.g., browser coordinator) has changed its snapshotted state without a
    /// layout mutation.
    func commit() {
        persist()
    }

    private func applyMutation(
        _ transform: (inout VibeSpaceTerminalBoardState) -> Void,
        persistAfter: Bool
    ) {
        var next = boardState
        transform(&next)
        next = next.normalized()
        guard next != boardState else { return }
        boardState = next
        rebuildTileLookup()
        if persistAfter {
            persist()
        }
    }

    /// Captures external snapshots and writes the current state to the persistence layer.
    /// Called automatically at the end of every `mutate`. Can also be called directly by
    /// external coordinators (e.g., browser state changes) to re-capture snapshots without
    /// any layout mutation.
    func persist() {
        let enriched = snapshotProviders.enriched(boardState)
        standaloneTerminalViewModel.terminalServices.diagnosticsSnapshot.visibleBoardTileCount =
            enriched.layout(for: VibeSpaceTerminalBoardState.primarySurfaceID).tiles.count
        layoutPersistence.setTerminalBoardState(enriched, for: vibespaceID)
    }

    // MARK: - Lifecycle

    /// Re-bind the store to a different vibespace. This is a swap, not a mutation: the
    /// previous vibespace's state is not modified; we load the new vibespace's state
    /// from persistence and reset our caches. Callers must ensure they have no pending
    /// operations against the old vibespace before invoking this.
    func updateVibeSpaceID(_ vibespaceID: UUID?) {
        guard self.vibespaceID != vibespaceID else { return }
        self.vibespaceID = vibespaceID
        boardState = layoutPersistence.terminalBoardState(for: vibespaceID)
        rebuildTileLookup()
        pruneStaleFileTiles()
        didSeedInitialTile = false
        configureStandaloneTerminalViewModel(for: vibespaceID)
    }

    // MARK: - Computed Access

    /// Convenience accessor for the primary surface layout. Read-only.
    var layout: VibeSpaceTerminalBoardLayout {
        layout(for: VibeSpaceTerminalBoardState.primarySurfaceID)
    }

    var primarySurfaceID: UUID {
        boardState.primarySurfaceID
    }

    var detachedSurfaces: [VibeSpaceTerminalBoardSurface] {
        boardState.surfaces.filter { $0.kind == .detached && $0.isOpen }
    }

    func layout(for surfaceID: UUID) -> VibeSpaceTerminalBoardLayout {
        boardState.layout(for: surfaceID)
    }

    var activeProjectPath: String? {
        guard let activeTileID = layout.activeTileID else { return nil }
        return layout.tile(for: activeTileID)?.projectPath
    }

    func activeProjectPath(surfaceID: UUID) -> String? {
        let surfaceLayout = layout(for: surfaceID)
        guard let activeTileID = surfaceLayout.activeTileID else { return nil }
        return surfaceLayout.tile(for: activeTileID)?.projectPath
    }

    // MARK: - Surface Commands

    func setSurfacePlacement(_ placement: VibeSpaceTerminalBoardWindowPlacement?, for surfaceID: UUID) {
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            state.surfaces[index].placement = placement
        }
    }

    func setSurfaceTitle(_ title: String, for surfaceID: UUID) {
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            state.surfaces[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func createDetachedSurface(
        with tile: VibeSpaceTerminalBoardTile,
        title: String,
        placement: VibeSpaceTerminalBoardWindowPlacement? = nil
    ) -> UUID {
        let surfaceID = UUID()
        let surface = VibeSpaceTerminalBoardSurface(
            id: surfaceID,
            kind: .detached,
            layout: VibeSpaceTerminalBoardLayout(
                columns: [VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [tile])],
                activeTileID: tile.id
            ),
            title: title,
            placement: placement,
            isOpen: true
        )
        mutate { state in
            state.surfaces.append(surface)
        }
        return surfaceID
    }

    func closeDetachedSurface(_ surfaceID: UUID, mergeIntoPrimary: Bool) {
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }),
                  state.surfaces[index].kind == .detached else { return }
            let tilesToMerge = state.surfaces[index].layout.tiles + state.surfaces[index].layout.minimizedTiles
            state.surfaces.remove(at: index)
            guard mergeIntoPrimary else { return }
            guard let primaryIndex = state.surfaces.firstIndex(where: { $0.id == state.primarySurfaceID }) else { return }
            for tile in tilesToMerge {
                Self.reattach(tile: tile, into: &state.surfaces[primaryIndex].layout)
            }
        }
    }

    func isSurfaceEmpty(_ surfaceID: UUID) -> Bool {
        let layout = layout(for: surfaceID)
        return layout.tiles.isEmpty && layout.minimizedTiles.isEmpty
    }

    func surfaceID(containing tileID: UUID) -> UUID? {
        boardState.surfaces.first { surface in
            surface.layout.allTileIDs.contains(tileID)
        }?.id
    }

    // MARK: - Projects & Hidden Terminals

    func syncProjects(_ projects: [AnyProjectSession]) {
        orderedProjectPaths = projects.map { $0.rootURL.standardizedFileURL.path }
        projectsByPath = projects.reduce(into: [:]) { result, project in
            result[project.rootURL.standardizedFileURL.path] = project
        }
        rebuildProjectTabLookups()
        syncProjectSubscriptions()
        reconcileTerminalTiles()
    }

    func setHiddenTerminalIDsByProjectPath(_ hiddenTerminalIDsByProjectPath: [String: Set<UUID>]) {
        let normalized = hiddenTerminalIDsByProjectPath.reduce(into: [String: Set<UUID>]()) { result, entry in
            let filteredIDs = entry.value
            guard !filteredIDs.isEmpty else { return }
            result[entry.key] = filteredIDs
        }
        guard self.hiddenTerminalIDsByProjectPath != normalized else { return }
        self.hiddenTerminalIDsByProjectPath = normalized
        reconcileTerminalTiles()
    }

    func seedInitialTileIfNeeded(projects: [AnyProjectSession]) {
        guard !didSeedInitialTile else { return }
        didSeedInitialTile = true

        syncProjects(projects)
        guard layout.tiles.isEmpty else { return }

        for project in projects {
            let projectPath = project.rootURL.standardizedFileURL.path
            if project.terminal.tabs.contains(where: {
                hiddenTerminalIDsByProjectPath[projectPath]?.contains($0.id) ?? false
            }) {
                return
            }
        }

        guard let fallbackProjectPath = orderedProjectPaths.first,
              let fallbackProject = projectsByPath[fallbackProjectPath] else {
            return
        }

        _ = addTile(
            projectPath: fallbackProjectPath,
            directoryURL: fallbackProject.rootURL.standardizedFileURL,
            preferStandalone: false
        )
    }

    // MARK: - Tile Lookup

    func tileContext(for tile: VibeSpaceTerminalBoardTile) -> TileContext? {
        guard let terminalTabID = tile.terminalTabID else { return nil }

        if let projectPath = tile.projectPath,
           let project = projectsByPath[projectPath],
           let terminalTab = tabsByProjectPathAndID[projectPath]?[terminalTabID] {
            return TileContext(
                tile: tile,
                projectPath: projectPath,
                projectTitle: project.title,
                terminalViewModel: project.terminalViewModel,
                terminalTab: terminalTab
            )
        }

        guard let terminalTab = standaloneTabsByID[terminalTabID] else {
            return nil
        }

        return TileContext(
            tile: tile,
            projectPath: nil,
            projectTitle: "VibeSpace",
            terminalViewModel: standaloneTerminalViewModel,
            terminalTab: terminalTab
        )
    }

    func tile(
        for tileID: UUID,
        includeMinimized: Bool = false,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> VibeSpaceTerminalBoardTile? {
        let surfaceLayout = layout(for: surfaceID)
        if let tile = surfaceLayout.tile(for: tileID) {
            return tile
        }
        if includeMinimized, let tile = surfaceLayout.minimizedTiles.first(where: { $0.id == tileID }) {
            return tile
        }
        guard surfaceID == VibeSpaceTerminalBoardState.primarySurfaceID else { return nil }
        for surface in boardState.surfaces where surface.id != surfaceID {
            if let tile = surface.layout.tile(for: tileID) {
                return tile
            }
            if includeMinimized, let tile = surface.layout.minimizedTiles.first(where: { $0.id == tileID }) {
                return tile
            }
        }
        return nil
    }

    func tileContext(
        for tileID: UUID,
        includeMinimized: Bool = false,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> TileContext? {
        guard let tile = tile(for: tileID, includeMinimized: includeMinimized, surfaceID: surfaceID) else { return nil }
        return tileContext(for: tile)
    }

    // MARK: - Display Helpers

    func surfaceTitle(for surfaceID: UUID) -> String {
        guard let surface = boardState.surface(id: surfaceID) else {
            return AppStrings.Terminal.boardTitle
        }
        let title = surface.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title != AppStrings.Terminal.boardTitle, title != "Terminal Board" {
            return title
        }
        return surfaceContentTitle(for: surface) ?? AppStrings.Terminal.boardTitle
    }

    func surfaceTransferTitle(for surfaceID: UUID, ordinal: Int) -> String {
        "\(AppStrings.Terminal.Tile.boardWindow) \(ordinal): \(surfaceTitle(for: surfaceID))"
    }

    private func surfaceContentTitle(for surface: VibeSpaceTerminalBoardSurface) -> String? {
        let layout = surface.layout
        let selectedTile = layout.activeTileID.flatMap { layout.tile(for: $0) }
            ?? layout.tiles.first
            ?? layout.minimizedTiles.first
        guard let selectedTile else { return nil }

        let title = displayTitle(for: selectedTile).trimmingCharacters(in: .whitespacesAndNewlines)
        let tileCount = layout.tiles.count + layout.minimizedTiles.count
        guard tileCount > 1 else {
            return title.isEmpty ? nil : title
        }
        let baseTitle = title.isEmpty ? AppStrings.Terminal.boardTitle : title
        return "\(baseTitle) (\(tileCount) \(AppStrings.Terminal.Tile.panes))"
    }

    func dragProxyInfo(
        for tileID: UUID,
        sourceFrame: CGRect,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> BoardDragProxyInfo? {
        guard let tile = tile(for: tileID, surfaceID: surfaceID) else { return nil }
        if let context = tileContext(for: tile) {
            return BoardDragProxyInfo(
                title: context.projectTitle,
                subtitle: context.terminalTab.workingDirectory.path,
                sourceFrame: sourceFrame
            )
        }
        let info = nonTerminalTileDisplayInfo(for: tile)
        return BoardDragProxyInfo(
            title: info.title,
            subtitle: info.subtitle,
            sourceFrame: sourceFrame
        )
    }

    func minimizedDragProxyInfo(
        for tileID: UUID,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> BoardDragProxyInfo {
        guard let tile = tile(for: tileID, includeMinimized: true, surfaceID: surfaceID) else {
            return BoardDragProxyInfo(
                title: "Terminal",
                subtitle: "",
                sourceFrame: CGRect(origin: .zero, size: CGSize(width: 120, height: 30))
            )
        }
        if let context = tileContext(for: tile) {
            return BoardDragProxyInfo(
                title: context.projectTitle,
                subtitle: tile.workingDirectoryPath,
                sourceFrame: CGRect(origin: .zero, size: CGSize(width: 120, height: 30))
            )
        }
        let info = nonTerminalTileDisplayInfo(for: tile)
        return BoardDragProxyInfo(
            title: info.title,
            subtitle: info.subtitle,
            sourceFrame: CGRect(origin: .zero, size: CGSize(width: 120, height: 30))
        )
    }

    func displayTitle(for tile: VibeSpaceTerminalBoardTile) -> String {
        if let context = tileContext(for: tile) {
            return context.terminalTab.title.isEmpty ? context.projectTitle : context.terminalTab.title
        }
        return nonTerminalTileDisplayInfo(for: tile).title
    }

    private func nonTerminalTileDisplayInfo(for tile: VibeSpaceTerminalBoardTile) -> (title: String, subtitle: String) {
        if let fileURL = tile.fileURL {
            return (fileURL.lastPathComponent, fileURL.deletingLastPathComponent().path)
        }
        if let browserURL = tile.browserURL {
            return (browserURL.host ?? browserURL.absoluteString, browserURL.absoluteString)
        }
        if tile.isVibeCast {
            return (AppStrings.VibeCast.title, "")
        }
        if let snapshot = tile.acpSnapshot {
            let title = snapshot.selectedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = snapshot.selectedProjectIdentifier ?? ""
            return ((title?.isEmpty == false ? title! : AppStrings.ACP.agentContentTitle), subtitle)
        }
        return ("Board Tile", tile.workingDirectoryPath)
    }

    // MARK: - Lookup Maintenance

    private func rebuildTileLookup() {
        tileIDByTerminalTabID = boardState.surfaces.reduce(into: [:]) { result, surface in
            for tile in surface.layout.tiles {
                guard let terminalTabID = tile.terminalTabID else { continue }
                result[terminalTabID] = tile.id
            }
        }
    }

    private func pruneStaleFileTiles() {
        let staleIDs = boardState.surfaces.flatMap { surface -> [UUID] in
            (surface.layout.tiles + surface.layout.minimizedTiles).compactMap { tile -> UUID? in
                guard let url = tile.fileURL else { return nil }
                return FileManager.default.fileExists(atPath: url.path) ? nil : tile.id
            }
        }
        guard !staleIDs.isEmpty else { return }
        mutate { state in
            for id in staleIDs {
                for surfaceIndex in state.surfaces.indices {
                    _ = state.surfaces[surfaceIndex].layout.removeTile(withID: id)
                }
            }
        }
    }

    func rebuildProjectTabLookups() {
        let validPaths = Set(orderedProjectPaths)
        tabsByProjectPathAndID = tabsByProjectPathAndID.filter { validPaths.contains($0.key) }
        tabsByProjectPathAndDirectory = tabsByProjectPathAndDirectory.filter { validPaths.contains($0.key) }

        for projectPath in orderedProjectPaths {
            guard let terminalViewModel = projectsByPath[projectPath]?.terminalViewModel else { continue }
            refreshProjectTabLookup(projectPath: projectPath, terminalViewModel: terminalViewModel)
        }
    }

    func refreshProjectTabLookup(projectPath: String, terminalViewModel: TerminalViewModel) {
        let tabs = terminalViewModel.tabs
        tabsByProjectPathAndID[projectPath] = tabs.reduce(into: [:]) { result, tab in
            result[tab.id] = tab
        }
        tabsByProjectPathAndDirectory[projectPath] = Dictionary(grouping: tabs) {
            $0.workingDirectory.standardizedFileURL.path
        }
    }

    func refreshStandaloneTabLookup() {
        let tabs = standaloneTerminalViewModel.tabs
        standaloneTabsByID = tabs.reduce(into: [:]) { result, tab in
            result[tab.id] = tab
        }
        standaloneTabsByDirectory = Dictionary(grouping: tabs) {
            $0.workingDirectory.standardizedFileURL.path
        }
    }

    // MARK: - Tile Commands

    @discardableResult
    func addTile(
        projectPath: String?,
        directoryURL: URL,
        preferStandalone: Bool = false,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> Bool {
        guard layout(for: surfaceID).tileCount < VibeSpaceTerminalBoardLayout.maximumTileCount else {
            return false
        }

        let normalizedDirectory = directoryURL.standardizedFileURL
        let scope: VibeSpaceTerminalBoardTerminalScope
        if preferStandalone {
            scope = .standalone
        } else if let resolvedProjectPath = VibeSpaceTerminalBoardLayoutSync.resolveProjectPath(
            preferredProjectPath: projectPath,
            workingDirectoryPath: normalizedDirectory.path,
            orderedProjectPaths: orderedProjectPaths,
            projectsByPath: projectsByPath,
            activeProjectPath: activeProjectPath(surfaceID: surfaceID)
        ) {
            scope = .project(resolvedProjectPath)
        } else {
            scope = .standalone
        }

        let terminalViewModel: TerminalViewModel
        switch scope {
        case let .project(projectPath):
            terminalViewModel = projectsByPath[projectPath]?.terminalViewModel ?? standaloneTerminalViewModel
        case .standalone:
            terminalViewModel = standaloneTerminalViewModel
        }
        // Suppress reconciler during tab creation; we'll add the tile explicitly below.
        isReconciling = true
        terminalViewModel.createTab(directoryURL: normalizedDirectory, startImmediately: true)
        isReconciling = false

        switch scope {
        case let .project(projectPath):
            refreshProjectTabLookup(projectPath: projectPath, terminalViewModel: terminalViewModel)
        case .standalone:
            refreshStandaloneTabLookup()
        }

        guard let createdTab = terminalViewModel.activeTab else {
            return false
        }

        let tileProjectPath: String?
        switch scope {
        case let .project(projectPath):
            tileProjectPath = projectPath
        case .standalone:
            tileProjectPath = nil
        }

        let tile = VibeSpaceTerminalBoardTile(
            heightWeight: 1,
            projectPath: tileProjectPath,
            terminalTabID: createdTab.id,
            workingDirectoryPath: createdTab.workingDirectory.standardizedFileURL.path
        )

        var didInsert = false
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            didInsert = state.surfaces[index].layout.insertNewTile(
                tile,
                activeHintTileID: state.surfaces[index].layout.activeTileID,
                activateInsertedTile: true
            )
        }

        guard didInsert else { return false }

        focusTerminal(
            for: TileContext(
                tile: tile,
                projectPath: tileProjectPath,
                projectTitle: tileProjectPath.flatMap { projectsByPath[$0]?.title } ?? "VibeSpace",
                terminalViewModel: terminalViewModel,
                terminalTab: createdTab
            )
        )
        return true
    }

    @discardableResult
    func addVibeCastTile(surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID) -> Bool {
        var didInsert = false
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            guard state.surfaces[index].layout.tileCount < VibeSpaceTerminalBoardLayout.maximumTileCount else { return }
            guard !state.surfaces[index].layout.tiles.contains(where: { $0.isVibeCast }) else { return }
            let tile = VibeSpaceTerminalBoardTile(workingDirectoryPath: "", contentKind: .vibeCast)
            didInsert = state.surfaces[index].layout.insertNewTile(
                tile,
                activeHintTileID: state.surfaces[index].layout.activeTileID,
                activateInsertedTile: true
            )
        }
        return didInsert
    }

    @discardableResult
    func addACPTile(
        snapshot: ACPStandalonePaneSnapshot,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> Bool {
        var didInsert = false
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            guard state.surfaces[index].layout.tileCount < VibeSpaceTerminalBoardLayout.maximumTileCount else { return }
            guard !state.surfaces[index].layout.tiles.contains(where: { $0.acpSnapshot?.id == snapshot.id }) else { return }
            guard !state.surfaces[index].layout.minimizedTiles.contains(where: { $0.acpSnapshot?.id == snapshot.id }) else { return }
            let tile = VibeSpaceTerminalBoardTile(
                workingDirectoryPath: "",
                contentKind: .acp(snapshot)
            )
            didInsert = state.surfaces[index].layout.insertNewTile(
                tile,
                activeHintTileID: state.surfaces[index].layout.activeTileID,
                activateInsertedTile: true
            )
        }
        return didInsert
    }

    /// Remove all board tiles associated with an ACP store ID.
    func removeACPTiles(storeID: UUID) {
        mutate { state in
            for surfaceIndex in state.surfaces.indices {
                let matchingIDs = state.surfaces[surfaceIndex].layout.tiles
                    .filter { $0.acpSnapshot?.id == storeID }
                    .map(\.id)
                    + state.surfaces[surfaceIndex].layout.minimizedTiles
                        .filter { $0.acpSnapshot?.id == storeID }
                        .map(\.id)
                for id in matchingIDs {
                    _ = state.surfaces[surfaceIndex].layout.removeTile(withID: id)
                }
            }
        }
    }

    func removeTile(
        _ tileID: UUID,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) {
        if let context = tileContext(for: tileID, includeMinimized: true, surfaceID: surfaceID) {
            context.terminalViewModel.closeTab(context.terminalTab)
        }
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            _ = state.surfaces[index].layout.removeTile(withID: tileID)
        }
    }

    func minimizeTile(
        _ tileID: UUID,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) {
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            _ = state.surfaces[index].layout.minimizeTile(withID: tileID)
        }
    }

    func restoreTile(
        _ tileID: UUID,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) {
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            _ = state.surfaces[index].layout.restoreTile(withID: tileID)
        }
    }

    func restoreMinimizedTile(
        _ tileID: UUID,
        using intent: VibeSpaceTerminalBoardDropIntent,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) {
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            guard state.surfaces[index].layout.restoreTile(withID: tileID) else { return }
            state.surfaces[index].layout.moveTile(tileID, using: intent)
        }
    }

    func activateTile(
        _ tileID: UUID,
        requestFocus: Bool,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) {
        guard tile(for: tileID, surfaceID: surfaceID) != nil else { return }
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            guard state.surfaces[index].layout.activeTileID != tileID else { return }
            state.surfaces[index].layout.activeTileID = tileID
        }

        guard requestFocus, let context = tileContext(for: tileID, surfaceID: surfaceID) else { return }
        focusTerminal(for: context)
    }

    func focusedSessionDidChange(to sessionID: UUID?) {
        guard let sessionID,
              let tileID = tileIDByTerminalTabID[sessionID],
              let surfaceID = surfaceID(containing: tileID) else {
            return
        }
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            guard state.surfaces[index].layout.activeTileID != tileID else { return }
            state.surfaces[index].layout.activeTileID = tileID
        }
    }

    // MARK: - Dock Preview

    @discardableResult
    func pinPreviewToDock(
        fileURL: URL,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> UUID? {
        let tile = VibeSpaceTerminalBoardTile(workingDirectoryPath: "", contentKind: .file(fileURL))
        var didInsert = false
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            guard state.surfaces[index].layout.tileCount < VibeSpaceTerminalBoardLayout.maximumTileCount else { return }
            didInsert = state.surfaces[index].layout.insertNewTile(
                tile,
                activeHintTileID: state.surfaces[index].layout.activeTileID,
                activateInsertedTile: true
            )
        }
        return didInsert ? tile.id : nil
    }

    @discardableResult
    func pinBrowserToDock(
        url: URL,
        projectPath: String? = nil,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> UUID? {
        pinBrowserToDock(id: UUID(), url: url, projectPath: projectPath, surfaceID: surfaceID)
    }

    @discardableResult
    func pinBrowserToDock(
        id tileID: UUID,
        url: URL,
        projectPath: String? = nil,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) -> UUID? {
        let tile = VibeSpaceTerminalBoardTile(
            id: tileID,
            projectPath: projectPath,
            workingDirectoryPath: "",
            contentKind: .browser(url)
        )
        var didInsert = false
        mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == surfaceID }) else { return }
            guard state.surfaces[index].layout.tileCount < VibeSpaceTerminalBoardLayout.maximumTileCount else { return }
            didInsert = state.surfaces[index].layout.insertNewTile(
                tile,
                activeHintTileID: state.surfaces[index].layout.activeTileID,
                activateInsertedTile: true
            )
        }
        return didInsert ? tile.id : nil
    }

    func dockedFileEntries(surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID) -> [DockedFileEntry] {
        let surfaceLayout = layout(for: surfaceID)
        return (surfaceLayout.tiles + surfaceLayout.minimizedTiles).compactMap { tile in
            guard let url = tile.fileURL else { return nil }
            return DockedFileEntry(id: tile.id, fileURL: url)
        }
    }

    // MARK: - Layout Helpers (Pure)

    /// Reattach a tile to a layout, dedup existing terminal identities, insert, fall back
    /// to minimized. Shared by closeDetachedSurface and tile-transfer commands.
    static func reattach(tile: VibeSpaceTerminalBoardTile, into layout: inout VibeSpaceTerminalBoardLayout) {
        if let identity = VibeSpaceTerminalBoardLayoutSync.terminalIdentity(for: tile) {
            for existingTile in layout.tiles where existingTile.id != tile.id {
                if VibeSpaceTerminalBoardLayoutSync.terminalIdentity(for: existingTile) == identity {
                    _ = layout.removeTile(withID: existingTile.id)
                }
            }
            for existingTile in layout.minimizedTiles where existingTile.id != tile.id {
                if VibeSpaceTerminalBoardLayoutSync.terminalIdentity(for: existingTile) == identity {
                    _ = layout.removeTile(withID: existingTile.id)
                }
            }
        }
        if layout.tile(for: tile.id) != nil { return }
        if layout.minimizedTiles.contains(where: { $0.id == tile.id }) { return }
        if !layout.insertNewTile(tile, activeHintTileID: layout.activeTileID, activateInsertedTile: true) {
            layout.minimizedTiles.append(tile)
        }
    }
}
