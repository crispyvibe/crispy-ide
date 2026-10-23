import Foundation
import XCTest
@testable import CrispyVibes

/// F048-R13/R15/R16 — Multi-Monitor Bulk Pane Move.
///
/// Covers the model-layer bulk move/recall API on
/// `VibeSpaceTerminalBoardStore`:
/// - `tileIDs(forProject:onSurface:)` filters by project (visible + minimized).
/// - `bulkDetachTilesForProject(_:fromSurface:)` removes matching tiles in a
///   single mutation, leaving non-matching tiles in place (R15 reorganization
///   is an automatic side effect of the existing layout reflow).
/// - `createDetachedSurface(with:title:placement:)` accepts an array of tiles
///   and lays them out in up to 4 columns.
/// - `closeDetachedSurface(_:mergeIntoPrimary: true)` is the existing R16
///   recall primitive — verified here to ensure bulk recall behavior.
@MainActor
final class VibeSpaceTerminalBoardStoreBulkMoveTests: XCTestCase {
    var container: AppContainer!
    var boardStore: VibeSpaceTerminalBoardStore!
    var tempRoot: URL!
    var projectA: AnyProjectSession!
    var projectB: AnyProjectSession!
    var projectAPath: String!
    var projectBPath: String!
    var projectAURL: URL!
    var projectBURL: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-board-bulk-move")
        container = AppContainer.makeDefault()
        boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: nil,
            layoutPersistence: container.layoutPersistence,
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )

        projectAURL = tempRoot.appendingPathComponent("projectA", isDirectory: true)
        projectBURL = tempRoot.appendingPathComponent("projectB", isDirectory: true)
        try FileManager.default.createDirectory(at: projectAURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectBURL, withIntermediateDirectories: true)
        projectAPath = projectAURL.standardizedFileURL.path
        projectBPath = projectBURL.standardizedFileURL.path

        let depsA = ProjectSessionDependencies(
            layoutPersistence: container.layoutPersistence,
            vibespaceManagement: container.vibespaceManagement,
            folderExplorerViewModelFactory: container.makeFolderExplorerViewModel,
            terminalViewModelFactory: container.makeTerminalViewModel,
            detachedWindowManager: container.detachedWindowManager,
            directoryWatcher: DirectoryWatcher()
        )
        projectA = AnyProjectSession(ProjectSession(rootURL: projectAURL, dependencies: depsA))
        projectB = AnyProjectSession(ProjectSession(rootURL: projectBURL, dependencies: depsA))
        boardStore.syncProjects([projectA, projectB])
    }

    override func tearDownWithError() throws {
        projectA?.shutdown()
        projectB?.shutdown()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        boardStore = nil
        container?.terminalServices.focusCoordinator.unfocusCurrent()
        container = nil
    }

    private func addProjectTile(_ projectPath: String, directoryURL: URL) {
        _ = boardStore.addTile(
            projectPath: projectPath,
            directoryURL: directoryURL,
            preferStandalone: false
        )
    }

    // MARK: - tileIDs(forProject:onSurface:)

    func testTileIDsForProjectReturnsOnlyMatchingVisibleTiles() {
        addProjectTile(projectAPath, directoryURL: projectAURL)
        addProjectTile(projectBPath, directoryURL: projectBURL)
        addProjectTile(projectAPath, directoryURL: projectAURL)
        XCTAssertEqual(boardStore.layout.tiles.count, 3)

        let matches = boardStore.tileIDs(forProject: projectAPath, onSurface: boardStore.primarySurfaceID)
        let expectedTileIDs = boardStore.layout.tiles
            .filter { $0.projectPath == projectAPath }
            .map(\.id)
        XCTAssertEqual(Set(matches), Set(expectedTileIDs))
        XCTAssertEqual(matches.count, 2)
    }

    func testTileIDsForProjectIncludesMinimizedTiles() {
        addProjectTile(projectAPath, directoryURL: projectAURL)
        let visible = boardStore.layout.tiles[0]
        boardStore.minimizeTile(visible.id)
        XCTAssertTrue(boardStore.layout.minimizedTiles.contains(where: { $0.id == visible.id }))

        let matches = boardStore.tileIDs(forProject: projectAPath, onSurface: boardStore.primarySurfaceID)
        XCTAssertEqual(matches, [visible.id])
    }

    func testTileIDsForProjectReturnsEmptyForUnknownProject() {
        addProjectTile(projectAPath, directoryURL: projectAURL)
        let matches = boardStore.tileIDs(forProject: "/tmp/unknown-path", onSurface: boardStore.primarySurfaceID)
        XCTAssertTrue(matches.isEmpty)
    }

    // MARK: - bulkDetachTilesForProject

    func testBulkDetachTilesForProjectRemovesOnlyMatching() {
        addProjectTile(projectAPath, directoryURL: projectAURL)
        addProjectTile(projectBPath, directoryURL: projectBURL)
        addProjectTile(projectAPath, directoryURL: projectAURL)
        XCTAssertEqual(boardStore.layout.tiles.count, 3)

        let detached = boardStore.bulkDetachTilesForProject(projectAPath, fromSurface: boardStore.primarySurfaceID)
        XCTAssertEqual(detached.count, 2)
        XCTAssertTrue(detached.allSatisfy { $0.projectPath == projectAPath })

        // Source should now contain only project B's tile.
        XCTAssertEqual(boardStore.layout.tiles.count, 1)
        XCTAssertEqual(boardStore.layout.tiles[0].projectPath, projectBPath)
    }

    func testBulkDetachTilesForProjectIncludesMinimized() {
        addProjectTile(projectAPath, directoryURL: projectAURL)
        addProjectTile(projectAPath, directoryURL: projectAURL)

        let secondTileID = boardStore.layout.tiles[1].id
        boardStore.minimizeTile(secondTileID)
        XCTAssertEqual(boardStore.layout.tiles.count, 1)
        XCTAssertEqual(boardStore.layout.minimizedTiles.count, 1)

        let detached = boardStore.bulkDetachTilesForProject(projectAPath, fromSurface: boardStore.primarySurfaceID)
        XCTAssertEqual(detached.count, 2)
        XCTAssertTrue(boardStore.layout.tiles.isEmpty)
        XCTAssertTrue(boardStore.layout.minimizedTiles.isEmpty)
    }

    func testBulkDetachTilesForProjectNoMatchIsNoOp() {
        addProjectTile(projectAPath, directoryURL: projectAURL)
        let beforeCount = boardStore.layout.tiles.count

        let detached = boardStore.bulkDetachTilesForProject("/tmp/no-such-project", fromSurface: boardStore.primarySurfaceID)
        XCTAssertTrue(detached.isEmpty)
        XCTAssertEqual(boardStore.layout.tiles.count, beforeCount)
    }

    // MARK: - createDetachedSurface(with: [Tile])

    func testCreateDetachedSurfaceWithTilesPopulatesAndSetsActive() {
        addProjectTile(projectAPath, directoryURL: projectAURL)
        addProjectTile(projectAPath, directoryURL: projectAURL)
        let detached = boardStore.bulkDetachTilesForProject(projectAPath, fromSurface: boardStore.primarySurfaceID)
        XCTAssertEqual(detached.count, 2)

        let surfaceID = boardStore.createDetachedSurface(
            with: detached,
            title: "Project A"
        )
        let layout = boardStore.layout(for: surfaceID)
        XCTAssertEqual(layout.tiles.count, 2)
        XCTAssertEqual(layout.activeTileID, detached[0].id)
        XCTAssertEqual(boardStore.boardState.surface(id: surfaceID)?.kind, .detached)
        XCTAssertEqual(boardStore.boardState.surface(id: surfaceID)?.title, "Project A")
    }

    func testCreateDetachedSurfaceWithEmptyTilesIsNormalizedAway() {
        // The store's normalization step removes empty detached surfaces.
        // `createDetachedSurface(with: [])` therefore allocates an ID but the
        // surface does not survive normalization. This test pins that behavior
        // so callers know to guard against passing empty arrays (the
        // production caller `bulkMoveCurrentProjectToNewWindow` already does).
        let surfaceID = boardStore.createDetachedSurface(
            with: [],
            title: "Empty"
        )
        XCTAssertNil(boardStore.boardState.surface(id: surfaceID), "empty detached surfaces are dropped during normalization")
    }

    // MARK: - Bulk recall via closeDetachedSurface(_:mergeIntoPrimary:true) (F048-R16)

    func testRecallMergesAllDetachedTilesBackToPrimary() {
        addProjectTile(projectAPath, directoryURL: projectAURL)
        addProjectTile(projectAPath, directoryURL: projectAURL)
        XCTAssertEqual(boardStore.layout.tiles.count, 2)

        // Move them to a new detached surface (simulating bulk-move-to-new-window).
        let detached = boardStore.bulkDetachTilesForProject(projectAPath, fromSurface: boardStore.primarySurfaceID)
        let detachedSurfaceID = boardStore.createDetachedSurface(with: detached, title: "Project A")
        XCTAssertEqual(boardStore.layout(for: detachedSurfaceID).tiles.count, 2)
        XCTAssertEqual(boardStore.layout.tiles.count, 0)

        // Recall back to primary.
        boardStore.closeDetachedSurface(detachedSurfaceID, mergeIntoPrimary: true)

        // Detached surface is gone; primary has both tiles back.
        XCTAssertNil(boardStore.boardState.surface(id: detachedSurfaceID))
        XCTAssertEqual(boardStore.layout.tiles.count, 2)
        XCTAssertTrue(boardStore.layout.tiles.allSatisfy { $0.projectPath == projectAPath })
    }

    // MARK: - Project lifecycle cleanup

    func testRemoveTilesForProjectCleansEverySurfaceAndContentKind() throws {
        addProjectTile(projectAPath, directoryURL: projectAURL)
        addProjectTile(projectBPath, directoryURL: projectBURL)
        let projectATileID = try XCTUnwrap(
            boardStore.layout.tiles.first(where: { $0.projectPath == projectAPath })?.id
        )
        let survivingTileID = try XCTUnwrap(
            boardStore.layout.tiles.first(where: { $0.projectPath == projectBPath })?.id
        )

        let minimizedFile = VibeSpaceTerminalBoardTile(
            projectPath: nil,
            workingDirectoryPath: "",
            contentKind: .file(projectAURL.appendingPathComponent("index.html"))
        )
        let detachedBrowser = VibeSpaceTerminalBoardTile(
            projectPath: projectAPath,
            workingDirectoryPath: "",
            contentKind: .browser(URL(string: "https://example.com")!)
        )
        let detachedACP = VibeSpaceTerminalBoardTile(
            workingDirectoryPath: "",
            contentKind: .acp(ACPStandalonePaneSnapshot(
                id: UUID(),
                selectedAgentID: nil,
                selectedModelID: nil,
                selectedProjectIdentifier: projectA.projectIdentifier,
                trustMode: .standard,
                reasoningLevel: .medium,
                shouldAutoConnect: false,
                threadId: nil
            ))
        )
        let detachedSurfaceID = UUID()
        boardStore.mutate { state in
            guard let primaryIndex = state.surfaces.firstIndex(where: { $0.id == state.primarySurfaceID }) else {
                return
            }
            state.surfaces[primaryIndex].layout.minimizedTiles.append(minimizedFile)
            state.surfaces.append(VibeSpaceTerminalBoardSurface(
                id: detachedSurfaceID,
                kind: .detached,
                layout: VibeSpaceTerminalBoardLayout(
                    columns: [VibeSpaceTerminalBoardColumn(tiles: [detachedBrowser, detachedACP])],
                    activeTileID: detachedBrowser.id
                ),
                title: "Project A",
                isOpen: true
            ))
        }

        let removed = boardStore.removeTilesForProject(
            rootPath: projectAPath,
            projectIdentifier: projectA.projectIdentifier
        )

        XCTAssertEqual(Set(removed.map(\.id)), Set([
            projectATileID,
            minimizedFile.id,
            detachedBrowser.id,
            detachedACP.id,
        ]))
        XCTAssertNotNil(boardStore.tile(for: survivingTileID, includeMinimized: true))
        XCTAssertNil(boardStore.boardState.surface(id: detachedSurfaceID))
        let remainingTiles = boardStore.boardState.surfaces.flatMap { surface in
            surface.layout.tiles + surface.layout.minimizedTiles
        }
        let projectAIdentifier = projectA.projectIdentifier
        let containsProjectATile = remainingTiles.contains { tile in
            if tile.projectIdentifier == projectAIdentifier || tile.projectPath == projectAPath {
                return true
            }
            if let fileURL = tile.fileURL, fileURL.path.hasPrefix(projectAPath) {
                return true
            }
            return tile.acpSnapshot?.selectedProjectIdentifier == projectAIdentifier
        }
        XCTAssertFalse(containsProjectATile)
    }

    func testSyncProjectsKeepsSameRemoteRootTerminalOwnershipIsolated() throws {
        let remoteRoot = "/srv/app"
        let firstProfile = SSHConnectionProfile(
            id: UUID(), displayName: "one", host: "one.example", port: 22,
            user: "dev", authMethod: .agent, importedFromConfig: false
        )
        let secondProfile = SSHConnectionProfile(
            id: UUID(), displayName: "two", host: "two.example", port: 22,
            user: "dev", authMethod: .agent, importedFromConfig: false
        )
        let first = AnyProjectSession(RemoteProjectSession(
            connection: SSHConnection(profile: firstProfile),
            remotePath: remoteRoot,
            terminalViewModelFactory: container.makeTerminalViewModel
        ))
        let second = AnyProjectSession(RemoteProjectSession(
            connection: SSHConnection(profile: secondProfile),
            remotePath: remoteRoot,
            terminalViewModelFactory: container.makeTerminalViewModel
        ))
        first.terminalViewModel.createTab(
            directoryURL: URL(fileURLWithPath: remoteRoot),
            startImmediately: false
        )
        second.terminalViewModel.createTab(
            directoryURL: URL(fileURLWithPath: remoteRoot),
            startImmediately: false
        )
        defer {
            first.shutdown()
            second.shutdown()
        }

        boardStore.syncProjects([first, second])

        XCTAssertEqual(boardStore.projectsByIdentifier.count, 2)
        let terminalTiles = boardStore.layout.tiles.filter(\.isTerminal)
        XCTAssertTrue(terminalTiles.contains(where: { $0.projectIdentifier == first.projectIdentifier }))
        XCTAssertTrue(terminalTiles.contains(where: { $0.projectIdentifier == second.projectIdentifier }))
        for tile in terminalTiles {
            let context = try XCTUnwrap(boardStore.tileContext(for: tile))
            XCTAssertEqual(context.projectPath, tile.projectIdentifier)
        }

        let fileTileID = try XCTUnwrap(boardStore.pinPreviewToDock(
            fileURL: URL(fileURLWithPath: "\(remoteRoot)/index.html"),
            projectIdentifier: first.projectIdentifier
        ))
        XCTAssertEqual(
            boardStore.tile(for: fileTileID)?.projectIdentifier,
            first.projectIdentifier
        )

        let browserTileID = try XCTUnwrap(boardStore.pinBrowserToDock(
            url: URL(string: "https://example.com")!,
            projectPath: remoteRoot,
            projectIdentifier: second.projectIdentifier
        ))
        XCTAssertEqual(
            boardStore.tile(for: browserTileID)?.projectIdentifier,
            second.projectIdentifier
        )

        let match = VibeSpaceProjectRoutingUseCase().terminalProjectMatch(
            for: URL(fileURLWithPath: "\(remoteRoot)/index.html"),
            preferredProjectIdentifier: second.projectIdentifier,
            preferredProjectRootURL: second.rootURL,
            candidates: [
                (vibespaceID: UUID(), project: first),
                (vibespaceID: UUID(), project: second),
            ]
        )
        XCTAssertEqual(match?.project.projectIdentifier, second.projectIdentifier)
    }

    func testDockPreviewBridgePreservesProjectIdentity() {
        let bridge = DockPreviewBridge()
        let identifier = "ssh://dev@example.com:22/srv/app"
        let fileURL = URL(fileURLWithPath: "/srv/app/index.html")

        bridge.requestPreview(for: fileURL, projectIdentifier: identifier)
        let target = bridge.consumePending()

        XCTAssertEqual(target?.url, fileURL.standardizedFileURL)
        XCTAssertEqual(target?.projectIdentifier, identifier)
        XCTAssertNil(bridge.consumePending())
    }

    func testLegacyRemoteFileTileSurvivesSyncAndMigratesOwnership() throws {
        let remoteRoot = "/srv/app"
        let profile = SSHConnectionProfile(
            id: UUID(), displayName: "remote", host: "remote.example", port: 22,
            user: "dev", authMethod: .agent, importedFromConfig: false
        )
        let project = AnyProjectSession(RemoteProjectSession(
            connection: SSHConnection(profile: profile),
            remotePath: remoteRoot,
            terminalViewModelFactory: container.makeTerminalViewModel
        ))
        defer { project.shutdown() }
        let legacyTile = VibeSpaceTerminalBoardTile(
            workingDirectoryPath: "",
            contentKind: .file(URL(fileURLWithPath: "\(remoteRoot)/index.html"))
        )
        boardStore.mutate { state in
            guard let index = state.surfaces.firstIndex(where: { $0.id == state.primarySurfaceID }) else {
                return
            }
            state.surfaces[index].layout.minimizedTiles.append(legacyTile)
        }

        boardStore.syncProjects([project])

        let restored = try XCTUnwrap(boardStore.tile(for: legacyTile.id, includeMinimized: true))
        XCTAssertEqual(restored.projectIdentifier, project.projectIdentifier)
        XCTAssertEqual(restored.fileURL?.path, "\(remoteRoot)/index.html")
    }

    func testRemoveTilesForRemoteProjectUsesHostQualifiedIdentity() {
        let sharedRoot = "/srv/app"
        let firstIdentifier = "ssh://dev@one.example:22/srv/app"
        let secondIdentifier = "ssh://dev@two.example:22/srv/app"
        let first = VibeSpaceTerminalBoardTile(
            projectPath: sharedRoot,
            projectIdentifier: firstIdentifier,
            workingDirectoryPath: "",
            contentKind: .browser(URL(string: "https://one.example")!)
        )
        let second = VibeSpaceTerminalBoardTile(
            projectPath: sharedRoot,
            projectIdentifier: secondIdentifier,
            workingDirectoryPath: "",
            contentKind: .browser(URL(string: "https://two.example")!)
        )
        let ambiguousLegacy = VibeSpaceTerminalBoardTile(
            projectPath: sharedRoot,
            workingDirectoryPath: "",
            contentKind: .browser(URL(string: "https://legacy.example")!)
        )
        boardStore.mutate { state in
            guard let primaryIndex = state.surfaces.firstIndex(where: { $0.id == state.primarySurfaceID }) else {
                return
            }
            state.surfaces[primaryIndex].layout.minimizedTiles.append(contentsOf: [first, second, ambiguousLegacy])
        }

        let removed = boardStore.removeTilesForProject(
            rootPath: sharedRoot,
            projectIdentifier: firstIdentifier
        )

        XCTAssertEqual(removed.map(\.id), [first.id])
        XCTAssertNil(boardStore.tile(for: first.id, includeMinimized: true))
        XCTAssertNotNil(boardStore.tile(for: second.id, includeMinimized: true))
        XCTAssertNotNil(boardStore.tile(for: ambiguousLegacy.id, includeMinimized: true))
    }

    func testRemoveTilesForProjectDoesNotMatchSiblingPathPrefix() {
        let siblingFile = VibeSpaceTerminalBoardTile(
            workingDirectoryPath: "",
            contentKind: .file(URL(fileURLWithPath: projectAPath + "-other/file.txt"))
        )
        boardStore.mutate { state in
            guard let primaryIndex = state.surfaces.firstIndex(where: { $0.id == state.primarySurfaceID }) else {
                return
            }
            state.surfaces[primaryIndex].layout.minimizedTiles.append(siblingFile)
        }

        _ = boardStore.removeTilesForProject(
            rootPath: projectAPath,
            projectIdentifier: projectA.projectIdentifier
        )

        XCTAssertNotNil(boardStore.tile(for: siblingFile.id, includeMinimized: true))
    }

    // MARK: - Single-mutation contract

    func testBulkDetachIsSingleMutation() {
        addProjectTile(projectAPath, directoryURL: projectAURL)
        addProjectTile(projectAPath, directoryURL: projectAURL)
        addProjectTile(projectAPath, directoryURL: projectAURL)

        var publishCount = 0
        let cancellable = boardStore.$boardState.sink { _ in publishCount += 1 }

        // Reset count after initial sink delivery.
        publishCount = 0
        _ = boardStore.bulkDetachTilesForProject(projectAPath, fromSurface: boardStore.primarySurfaceID)

        XCTAssertEqual(publishCount, 1, "bulkDetachTilesForProject must publish exactly once for batched mutation")
        cancellable.cancel()
    }
}
