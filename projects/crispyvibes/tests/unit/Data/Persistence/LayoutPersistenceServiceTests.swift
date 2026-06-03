import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class LayoutPersistenceServiceTests: XCTestCase {
    private var tempRoot: URL!
    private var persistenceStore: VibeSpacePersistenceStore!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-layout-unit")
        let appStore = AppPersistenceDataStore(fileManager: .default, appDirectoryURL: tempRoot)
        persistenceStore = VibeSpacePersistenceStore(store: appStore)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    private func makeSUT() -> LayoutPersistenceService {
        let sut = LayoutPersistenceService(fileManager: .default)
        sut.setVibeSpacePersistenceStore(persistenceStore)
        return sut
    }

    func testSetterDoesNotClobberPersistedBoardWhenLayoutNotYetLoaded() {
        let vibespaceID = UUID()

        // Persist a board containing a browser tile.
        let tile = VibeSpaceTerminalBoardTile(
            workingDirectoryPath: "",
            contentKind: .browser(URL(string: "https://example.com")!)
        )
        let layout = VibeSpaceTerminalBoardLayout(
            columns: [VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [tile])],
            activeTileID: tile.id
        )
        makeSUT().setTerminalBoardState(.fromLegacyLayout(layout), for: vibespaceID)

        // Fresh instance (simulates relaunch — empty in-memory cache). Mutate a
        // rail size BEFORE ever reading the board. Must not wipe the saved board.
        let fresh = makeSUT()
        fresh.setRailSize(333, for: .left, vibespaceID: vibespaceID)

        let restored = fresh.terminalBoardState(for: vibespaceID).primaryLayout
        XCTAssertEqual(restored.tiles.count, 1, "a setter must not clobber the persisted board")
        XCTAssertTrue(restored.tiles.first?.isBrowser ?? false)
    }

    func testVibeSpaceFallsBackToGlobalRailDefaultsWhenVibeSpaceLayoutMissing() {
        let vibespaceID = UUID()
        let sut = makeSUT()

        // No layout set for this vibespace — should get defaults
        XCTAssertEqual(
            sut.railSize(for: .left, vibespaceID: vibespaceID),
            CGFloat(AppFirstRunExperience.Layout.defaultLeftRailWidth),
            accuracy: 0.01
        )
    }

    func testPaneLayoutPersistenceAndNormalization() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let sut = makeSUT()
        let raw = ProjectPaneLayoutState(
            explorerFraction: -1,
            terminalFraction: 9,
            explorerPoints: 120,
            terminalPoints: 100
        )
        sut.setPaneLayout(raw, for: projectRoot)

        let restored = sut.paneLayout(for: projectRoot)
        XCTAssertEqual(restored.explorerFraction, 0.18, accuracy: 0.0001)
        XCTAssertEqual(restored.terminalFraction, 0.72, accuracy: 0.0001)
        XCTAssertEqual(restored.explorerPoints, 190)
        XCTAssertEqual(restored.terminalPoints, 160)
    }

    func testPaneLayoutRoundTripsAcrossFreshServiceInstance() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let sut = makeSUT()
        let expected = ProjectPaneLayoutState(
            explorerFraction: 0.4,
            terminalFraction: 0.3,
            explorerPoints: 280,
            terminalPoints: 220
        ).normalized()
        sut.setPaneLayout(expected, for: projectRoot)

        let reloaded = makeSUT()

        XCTAssertEqual(reloaded.paneLayout(for: projectRoot), expected)
    }

    func testVibeSpaceCanvasModeAndOrientationPersistence() {
        let vibespaceID = UUID()
        let sut = makeSUT()

        sut.setCanvasMode(.terminalOnly, for: vibespaceID)
        sut.setTerminalOnlyLayoutOrientation(.horizontal, for: vibespaceID)
        sut.setDetailedTerminalPaneHeight(420, for: vibespaceID)
        sut.setDetailedTerminalPaneCollapsed(true, for: vibespaceID)

        // Verify in-memory state
        XCTAssertEqual(sut.canvasMode(for: vibespaceID), .terminalOnly)
        XCTAssertEqual(sut.terminalOnlyLayoutOrientation(for: vibespaceID), .horizontal)
        XCTAssertEqual(sut.detailedTerminalPaneHeight(for: vibespaceID), 420, accuracy: 0.01)
        XCTAssertTrue(sut.isDetailedTerminalPaneCollapsed(for: vibespaceID))

        // Verify round-trip: new instance loads from per-vibespace file
        let reloaded = makeSUT()
        reloaded.loadVibeSpaceLayoutIfNeeded(for: vibespaceID)
        XCTAssertEqual(reloaded.canvasMode(for: vibespaceID), .terminalOnly)
        XCTAssertEqual(reloaded.terminalOnlyLayoutOrientation(for: vibespaceID), .horizontal)
        XCTAssertEqual(reloaded.detailedTerminalPaneHeight(for: vibespaceID), 420, accuracy: 0.01)
        XCTAssertTrue(reloaded.isDetailedTerminalPaneCollapsed(for: vibespaceID))
    }

    func testVibeSpaceSpotlightTerminalOrderRoundTripsAcrossFreshServiceInstance() {
        let vibespaceID = UUID()
        let first = VibeSpaceSpotlightTerminalOrderEntry(projectPath: "/tmp/project-a", tabID: UUID())
        let second = VibeSpaceSpotlightTerminalOrderEntry(projectPath: "/tmp/project-b", tabID: UUID())
        let sut = makeSUT()

        sut.setVibeSpaceSpotlightTerminalOrder([first, second], for: vibespaceID)

        let reloaded = makeSUT()
        reloaded.loadVibeSpaceLayoutIfNeeded(for: vibespaceID)

        XCTAssertEqual(
            reloaded.vibespaceSpotlightTerminalOrder(liveIdentities: [first, second], for: vibespaceID),
            [first, second]
        )
    }

    func testVibeSpaceSpotlightTerminalOrderReconcilesMissingAndNewIdentities() {
        let vibespaceID = UUID()
        let stale = VibeSpaceSpotlightTerminalOrderEntry(projectPath: "/tmp/stale", tabID: UUID())
        let first = VibeSpaceSpotlightTerminalOrderEntry(projectPath: "/tmp/project-a", tabID: UUID())
        let second = VibeSpaceSpotlightTerminalOrderEntry(projectPath: "/tmp/project-b", tabID: UUID())
        let new = VibeSpaceSpotlightTerminalOrderEntry(projectPath: "/tmp/project-c", tabID: UUID())
        let sut = makeSUT()

        sut.setVibeSpaceSpotlightTerminalOrder([stale, second, first], for: vibespaceID)

        XCTAssertEqual(
            sut.vibespaceSpotlightTerminalOrder(liveIdentities: [first, second, new], for: vibespaceID),
            [second, first, new]
        )
    }

    func testMoveVibeSpaceSpotlightTerminalPersistsCrossProjectOrder() {
        let vibespaceID = UUID()
        let first = VibeSpaceSpotlightTerminalOrderEntry(projectPath: "/tmp/project-a", tabID: UUID())
        let second = VibeSpaceSpotlightTerminalOrderEntry(projectPath: "/tmp/project-b", tabID: UUID())
        let third = VibeSpaceSpotlightTerminalOrderEntry(projectPath: "/tmp/project-c", tabID: UUID())
        let sut = makeSUT()

        let didMove = sut.moveVibeSpaceSpotlightTerminal(
            third,
            relativeTo: first,
            placement: .before,
            liveIdentities: [first, second, third],
            for: vibespaceID
        )

        XCTAssertTrue(didMove)

        let reloaded = makeSUT()
        reloaded.loadVibeSpaceLayoutIfNeeded(for: vibespaceID)
        XCTAssertEqual(
            reloaded.vibespaceSpotlightTerminalOrder(liveIdentities: [first, second, third], for: vibespaceID),
            [third, first, second]
        )
    }

    func testUsesCentralizedFirstRunDefaultsWhenNoSnapshotExists() {
        let vibespaceID = UUID()
        let sut = makeSUT()

        XCTAssertEqual(sut.canvasMode(for: vibespaceID), AppFirstRunExperience.Layout.defaultCanvasMode)
        XCTAssertEqual(
            sut.terminalOnlyLayoutOrientation(for: vibespaceID),
            AppFirstRunExperience.Layout.defaultTerminalOnlyLayoutOrientation
        )
        XCTAssertEqual(
            sut.railSize(for: .left, vibespaceID: vibespaceID),
            CGFloat(AppFirstRunExperience.Layout.defaultLeftRailWidth),
            accuracy: 0.01
        )
        XCTAssertEqual(
            sut.railSize(for: .top, vibespaceID: vibespaceID),
            CGFloat(AppFirstRunExperience.Layout.defaultTopRailHeight),
            accuracy: 0.01
        )
        XCTAssertEqual(
            sut.detailedTerminalPaneHeight(for: vibespaceID),
            CGFloat(AppFirstRunExperience.Layout.defaultDetailedTerminalPaneHeight),
            accuracy: 0.01
        )
        XCTAssertFalse(sut.isDetailedTerminalPaneCollapsed(for: vibespaceID))
    }

    func testResetToFirstRunStateClearsPersistedLayoutAndRestoresDefaults() {
        let vibespaceID = UUID()
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let sut = makeSUT()
        sut.setCanvasMode(.terminalOnly, for: vibespaceID)
        sut.setTerminalOnlyLayoutOrientation(.horizontal, for: vibespaceID)
        sut.setDetailedTerminalPaneHeight(390, for: vibespaceID)
        sut.setDetailedTerminalPaneCollapsed(true, for: vibespaceID)
        sut.setPaneLayout(
            ProjectPaneLayoutState(explorerFraction: 0.5, terminalFraction: 0.5),
            for: projectRoot
        )

        sut.resetToFirstRunState()

        XCTAssertEqual(sut.canvasMode(for: vibespaceID), AppFirstRunExperience.Layout.defaultCanvasMode)
        XCTAssertEqual(
            sut.terminalOnlyLayoutOrientation(for: vibespaceID),
            AppFirstRunExperience.Layout.defaultTerminalOnlyLayoutOrientation
        )
        XCTAssertEqual(
            sut.detailedTerminalPaneHeight(for: vibespaceID),
            CGFloat(AppFirstRunExperience.Layout.defaultDetailedTerminalPaneHeight),
            accuracy: 0.01
        )
        XCTAssertFalse(sut.isDetailedTerminalPaneCollapsed(for: vibespaceID))
        XCTAssertEqual(sut.paneLayout(for: projectRoot), .default)
    }

    func testLayoutRoundTripThroughPerVibeSpaceFile() {
        let vibespaceID = UUID()
        let sut = makeSUT()

        sut.setRailSize(340, for: .left, vibespaceID: vibespaceID)
        sut.setCanvasMode(.terminalOnly, for: vibespaceID)
        sut.setDetailedTerminalPaneHeight(360, for: vibespaceID)
        sut.setDetailedTerminalPaneCollapsed(true, for: vibespaceID)

        // New instance loads from per-vibespace layout.json
        let reloaded = makeSUT()
        reloaded.loadVibeSpaceLayoutIfNeeded(for: vibespaceID)

        XCTAssertEqual(reloaded.railSize(for: .left, vibespaceID: vibespaceID), 340, accuracy: 0.01)
        XCTAssertEqual(reloaded.canvasMode(for: vibespaceID), .terminalOnly)
        XCTAssertEqual(reloaded.detailedTerminalPaneHeight(for: vibespaceID), 360, accuracy: 0.01)
        XCTAssertTrue(reloaded.isDetailedTerminalPaneCollapsed(for: vibespaceID))
    }

    func testBrowserSnapshotIsPreservedWhenNoLiveViewModelSnapshotIsAvailable() {
        let vibespaceID = UUID()
        let sut = makeSUT()
        let tileID = UUID()
        var tile = VibeSpaceTerminalBoardTile(
            id: tileID,
            workingDirectoryPath: "",
            contentKind: .browser(URL(string: "https://example.com/original")!)
        )
        tile.browserSession = BrowserSessionSnapshot(
            urlString: "https://example.com/original",
            backHistoryURLStrings: ["https://example.com/start"],
            pageZoom: 1.5
        )
        let layout = VibeSpaceTerminalBoardLayout(
            columns: [VibeSpaceTerminalBoardColumn(tiles: [tile])],
            activeTileID: tileID
        )
        let state = VibeSpaceTerminalBoardState(
            surfaces: [
                VibeSpaceTerminalBoardSurface(
                    id: VibeSpaceTerminalBoardState.primarySurfaceID,
                    kind: .primary,
                    layout: layout,
                    title: "Primary",
                    isOpen: true
                )
            ]
        )

        sut.setTerminalBoardState(state, for: vibespaceID)

        let restoredTile = sut.terminalBoardLayout(for: vibespaceID).tile(for: tileID)
        XCTAssertEqual(restoredTile?.browserSession?.urlString, "https://example.com/original")
        XCTAssertEqual(restoredTile?.browserSession?.backHistoryURLStrings, ["https://example.com/start"])
        XCTAssertEqual(restoredTile?.browserSession?.pageZoom, 1.5)
    }

    func testTerminalBoardStatePersistsDetachedSurfaces() {
        let vibespaceID = UUID()
        let sut = makeSUT()
        let primaryTile = VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/primary")
        let detachedTile = VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/detached")
        let detachedSurfaceID = UUID()
        let state = VibeSpaceTerminalBoardState(
            surfaces: [
                VibeSpaceTerminalBoardSurface(
                    id: VibeSpaceTerminalBoardState.primarySurfaceID,
                    kind: .primary,
                    layout: VibeSpaceTerminalBoardLayout(
                        columns: [VibeSpaceTerminalBoardColumn(tiles: [primaryTile])],
                        activeTileID: primaryTile.id
                    ),
                    title: "Primary",
                    isOpen: true
                ),
                VibeSpaceTerminalBoardSurface(
                    id: detachedSurfaceID,
                    kind: .detached,
                    layout: VibeSpaceTerminalBoardLayout(
                        columns: [VibeSpaceTerminalBoardColumn(tiles: [detachedTile])],
                        activeTileID: detachedTile.id
                    ),
                    title: "Detached",
                    placement: VibeSpaceTerminalBoardWindowPlacement(
                        frameX: 10,
                        frameY: 20,
                        frameWidth: 900,
                        frameHeight: 700,
                        screenID: "screen-1"
                    ),
                    isOpen: true
                )
            ]
        )

        sut.setTerminalBoardState(state, for: vibespaceID)

        let reloaded = makeSUT()
        reloaded.loadVibeSpaceLayoutIfNeeded(for: vibespaceID)
        let restored = reloaded.terminalBoardState(for: vibespaceID)

        XCTAssertEqual(restored.surfaces.count, 2)
        XCTAssertEqual(restored.primaryLayout.tiles.first?.workingDirectoryPath, "/tmp/primary")
        let detached = restored.surface(id: detachedSurfaceID)
        XCTAssertNotNil(detached)
        XCTAssertEqual(detached?.layout.tiles.first?.workingDirectoryPath, "/tmp/detached")
        XCTAssertEqual(detached?.placement?.frameWidth, 900)
        XCTAssertEqual(detached?.placement?.screenID, "screen-1")
    }
}
