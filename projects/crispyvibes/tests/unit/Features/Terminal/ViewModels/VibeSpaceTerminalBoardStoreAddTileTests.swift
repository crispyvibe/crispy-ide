import Combine
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class VibeSpaceTerminalBoardStoreAddTileTests: XCTestCase {
    var container: AppContainer!
    var boardStore: VibeSpaceTerminalBoardStore!
    var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-board-add-tile")
        container = AppContainer.makeDefault()
        boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: nil,
            layoutPersistence: container.layoutPersistence,
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        boardStore = nil
        container = nil
    }

    // MARK: - Regression: split creates two terminals

    /// Regression: addTile must refresh the tab lookup so that tileContext()
    /// resolves the new tile immediately. Without the refresh, the stale lookup
    /// causes the tile to appear unresolved, triggering restoreTerminalIfNeeded
    /// which creates a second tab.
    func testAddTileMakesTileContextResolvableImmediately() {
        _ = boardStore.addTile(projectPath: nil, directoryURL: tempRoot, preferStandalone: true)
        XCTAssertEqual(boardStore.layout.tiles.count, 1)

        let tile = boardStore.layout.tiles[0]
        let context = boardStore.tileContext(for: tile)
        XCTAssertNotNil(context, "tileContext must resolve immediately after addTile without waiting for tabsPublisher")
        XCTAssertEqual(context?.terminalTab.id, tile.terminalTabID)
    }

    // MARK: - Regression: duplicate terminalTabID crash

    /// Regression: when one of two tiles sharing a working directory loses its
    /// tab, the reconciler's directory matching must not reassign it to the tab
    /// already owned by the other tile.
    func testBindDoesNotAssignSameTabToMultipleTiles() {
        // Create two tiles at the same directory.
        _ = boardStore.addTile(projectPath: nil, directoryURL: tempRoot, preferStandalone: true)
        _ = boardStore.addTile(projectPath: nil, directoryURL: tempRoot, preferStandalone: true)
        XCTAssertEqual(boardStore.layout.tiles.count, 2)

        // Close the first tile's tab so the reconciler falls through to directory matching.
        let firstTabID = boardStore.layout.tiles[0].terminalTabID!
        let vm = boardStore.standaloneTerminalViewModel
        if let tab = vm.tabs.first(where: { $0.id == firstTabID }) {
            vm.closeTab(tab)
        }
        boardStore.refreshStandaloneTabLookup()

        boardStore.reconcileTerminalTiles()

        let terminalTabIDs = boardStore.layout.tiles.compactMap(\.terminalTabID)
        let uniqueIDs = Set(terminalTabIDs)
        XCTAssertEqual(
            terminalTabIDs.count, uniqueIDs.count,
            "reconciler assigned the same tab to multiple tiles: \(terminalTabIDs)"
        )
    }

    func testMoveTerminalTabTileReordersBoardLinearOrder() throws {
        _ = boardStore.addTile(projectPath: nil, directoryURL: tempRoot, preferStandalone: true)
        _ = boardStore.addTile(projectPath: nil, directoryURL: tempRoot, preferStandalone: true)
        _ = boardStore.addTile(projectPath: nil, directoryURL: tempRoot, preferStandalone: true)
        let originalTabIDs = boardStore.layout.tiles.compactMap(\.terminalTabID)
        XCTAssertEqual(originalTabIDs.count, 3)

        let firstID = try XCTUnwrap(originalTabIDs.first)
        let thirdID = try XCTUnwrap(originalTabIDs.last)

        let didMove = boardStore.moveTerminalTabTile(
            firstID,
            relativeTo: thirdID,
            placement: .after
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(
            boardStore.layout.tiles.compactMap(\.terminalTabID),
            [originalTabIDs[1], thirdID, firstID]
        )
    }

    func testAddVibeLanesTileTargetsSurfaceAndPreventsDuplicate() throws {
        let seedTile = VibeSpaceTerminalBoardTile(workingDirectoryPath: tempRoot.path)
        let detachedSurfaceID = boardStore.createDetachedSurface(with: seedTile, title: "Lanes")

        XCTAssertTrue(boardStore.addVibeLanesTile(surfaceID: detachedSurfaceID))
        XCTAssertFalse(boardStore.addVibeLanesTile(surfaceID: detachedSurfaceID))
        XCTAssertTrue(boardStore.layout.tiles.isEmpty)

        let detachedLayout = boardStore.layout(for: detachedSurfaceID)
        XCTAssertEqual(detachedLayout.tiles.count, 2)
        XCTAssertEqual(detachedLayout.tiles.filter(\.isVibeLanes).count, 1)
    }

    func testVibeLanesTileSurvivesCodableRoundTrip() throws {
        let tile = VibeSpaceTerminalBoardTile(workingDirectoryPath: "", contentKind: .vibeLanes)

        let data = try JSONEncoder().encode(tile)
        let decoded = try JSONDecoder().decode(VibeSpaceTerminalBoardTile.self, from: data)

        XCTAssertEqual(decoded, tile)
        XCTAssertTrue(decoded.isVibeLanes)
    }
}
