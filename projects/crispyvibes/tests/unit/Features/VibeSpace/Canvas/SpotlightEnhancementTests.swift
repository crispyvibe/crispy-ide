import AppKit
import SwiftUI
import XCTest

@testable import CrispyVibes

@MainActor
final class SpotlightLayoutSnapshotTests: XCTestCase {
    private let terminalA = SpotlightPersistentItemID.terminal(projectPath: "/tmp/a", tabID: UUID())
    private let terminalB = SpotlightPersistentItemID.terminal(projectPath: "/tmp/b", tabID: UUID())
    private let file = SpotlightPersistentItemID.file(tileID: UUID())
    private let browser = SpotlightPersistentItemID.browser(tileID: UUID())

    func testCodableRoundTripPreservesEveryKindComboAndOrientation() throws {
        let snapshot = SpotlightLayoutSnapshot(positions: [
            SpotlightPositionSnapshot(members: [terminalA, file], orientation: .stacked),
            SpotlightPositionSnapshot(members: [terminalB]),
            SpotlightPositionSnapshot(members: [.vibeCast]),
            SpotlightPositionSnapshot(members: [.vibeLanes]),
            SpotlightPositionSnapshot(members: [.acp(tileID: UUID(), storeID: UUID())]),
            SpotlightPositionSnapshot(members: [browser]),
            SpotlightPositionSnapshot(members: [
                .standaloneTerminal(surfaceID: UUID(), tileID: UUID(), tabID: UUID())
            ]),
        ])

        let restored = try JSONDecoder().decode(
            SpotlightLayoutSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(restored, snapshot)
    }

    func testVersionlessSnapshotMigratesAndFutureVersionIsRejected() throws {
        let position = SpotlightPositionSnapshot(members: [terminalA])
        let encodedPosition = try JSONEncoder().encode(position)
        let positionObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedPosition) as? [String: Any])
        let legacyData = try JSONSerialization.data(withJSONObject: ["positions": [positionObject]])
        let migrated = try JSONDecoder().decode(SpotlightLayoutSnapshot.self, from: legacyData)
        XCTAssertEqual(migrated.version, SpotlightLayoutSnapshot.currentVersion)
        XCTAssertEqual(migrated.positions, [position])

        let futureData = try JSONSerialization.data(withJSONObject: [
            "version": SpotlightLayoutSnapshot.currentVersion + 1,
            "positions": [],
        ])
        XCTAssertThrowsError(try JSONDecoder().decode(SpotlightLayoutSnapshot.self, from: futureData))
    }

    func testNormalizationDropsStaleDuplicatesAndThirdComboMemberThenAppendsNewLiveItems() {
        let duplicatePositionID = UUID()
        let stale = SpotlightPersistentItemID.file(tileID: UUID())
        let snapshot = SpotlightLayoutSnapshot(positions: [
            SpotlightPositionSnapshot(
                id: duplicatePositionID,
                members: [terminalA, terminalA, file, browser],
                orientation: .stacked
            ),
            SpotlightPositionSnapshot(id: duplicatePositionID, members: [terminalB, stale]),
        ])

        let normalized = snapshot.normalized(liveIDs: [terminalA, terminalB, file, browser])

        XCTAssertEqual(normalized.positions[0].members, [terminalA, file])
        XCTAssertEqual(normalized.positions[0].orientation, .stacked)
        XCTAssertEqual(normalized.positions[1].members, [terminalB])
        XCTAssertNotEqual(normalized.positions[0].id, normalized.positions[1].id)
        XCTAssertEqual(normalized.positions[2].members, [browser])
        XCTAssertEqual(normalized.flattenedMembers, [terminalA, file, terminalB, browser])
    }

    func testReconciliationMissingOneMemberBecomesSingleAndMissingBothUsesNearest() {
        let first = SpotlightPositionSnapshot(members: [terminalA, terminalB], orientation: .stacked)
        let second = SpotlightPositionSnapshot(members: [file])
        let snapshot = SpotlightLayoutSnapshot(positions: [first, second])

        let oneMissing = SpotlightLayoutReconciler.reconcile(
            snapshot: snapshot,
            liveIDs: [terminalB, file],
            currentID: terminalA
        )
        XCTAssertEqual(oneMissing.replacementForCurrent, terminalB)
        XCTAssertEqual(oneMissing.snapshot.positions[0].members, [terminalB])
        XCTAssertEqual(oneMissing.snapshot.positions[0].orientation, .sideBySide)

        let bothMissing = SpotlightLayoutReconciler.reconcile(
            snapshot: snapshot,
            liveIDs: [file],
            currentID: terminalA
        )
        XCTAssertEqual(bothMissing.replacementForCurrent, file)

        let precedingLive = SpotlightPersistentItemID.file(tileID: UUID())
        let precedingStale = SpotlightPersistentItemID.file(tileID: UUID())
        let missingCurrent = SpotlightPersistentItemID.browser(tileID: UUID())
        let followingLive = SpotlightPersistentItemID.browser(tileID: UUID())
        let outward = SpotlightLayoutSnapshot(positions: [
            SpotlightPositionSnapshot(members: [precedingLive]),
            SpotlightPositionSnapshot(members: [precedingStale]),
            SpotlightPositionSnapshot(members: [missingCurrent]),
            SpotlightPositionSnapshot(members: [followingLive]),
        ])
        let nearest = SpotlightLayoutReconciler.reconcile(
            snapshot: outward,
            liveIDs: [precedingLive, followingLive],
            currentID: missingCurrent
        )
        XCTAssertEqual(nearest.replacementForCurrent, followingLive)
    }

    func testReducerMoveClubUnclubAndRejectsInvalidDrops() throws {
        let first = SpotlightPositionSnapshot(members: [terminalA])
        let second = SpotlightPositionSnapshot(members: [terminalB])
        let third = SpotlightPositionSnapshot(members: [file])
        let base = SpotlightLayoutSnapshot(positions: [first, second, third])
        let host = "main:host"

        let clubbed = try XCTUnwrap(SpotlightLayoutReducer.dropping(
            payload: SpotlightDragPayload(hostID: host, generation: 7, subject: .position(first.id)),
            on: second.id,
            zone: .club,
            snapshot: base,
            hostID: host,
            generation: 7
        ))
        XCTAssertEqual(clubbed.positions.count, 2)
        XCTAssertEqual(clubbed.positions[0].members, [terminalB, terminalA])
        XCTAssertEqual(clubbed.positions[0].orientation, .sideBySide)

        let unclubbed = try XCTUnwrap(SpotlightLayoutReducer.dropping(
            payload: SpotlightDragPayload(
                hostID: host,
                generation: 7,
                subject: .member(terminalA, positionID: second.id)
            ),
            on: third.id,
            zone: .after,
            snapshot: clubbed,
            hostID: host,
            generation: 7
        ))
        XCTAssertEqual(unclubbed.positions.map(\.members), [[terminalB], [file], [terminalA]])

        XCTAssertNil(SpotlightLayoutReducer.dropping(
            payload: SpotlightDragPayload(hostID: "other", generation: 7, subject: .position(first.id)),
            on: third.id, zone: .before, snapshot: base, hostID: host, generation: 7
        ))
        XCTAssertNil(SpotlightLayoutReducer.dropping(
            payload: SpotlightDragPayload(hostID: host, generation: 6, subject: .position(first.id)),
            on: third.id, zone: .before, snapshot: base, hostID: host, generation: 7
        ))
        XCTAssertNil(SpotlightLayoutReducer.dropping(
            payload: SpotlightDragPayload(hostID: host, generation: 7, subject: .position(first.id)),
            on: first.id, zone: .club, snapshot: base, hostID: host, generation: 7
        ))
        XCTAssertNil(SpotlightLayoutReducer.dropping(
            payload: SpotlightDragPayload(hostID: host, generation: 7, subject: .position(third.id)),
            on: second.id, zone: .club, snapshot: clubbed, hostID: host, generation: 7
        ))
    }

    func testDropZonesUseQuarterHalfQuarterPolicy() {
        XCTAssertEqual(SpotlightDropZone.resolve(x: 0, width: 100), .before)
        XCTAssertEqual(SpotlightDropZone.resolve(x: 24.9, width: 100), .before)
        XCTAssertEqual(SpotlightDropZone.resolve(x: 25, width: 100), .club)
        XCTAssertEqual(SpotlightDropZone.resolve(x: 75, width: 100), .club)
        XCTAssertEqual(SpotlightDropZone.resolve(x: 75.1, width: 100), .after)
    }

    func testOrientationToggleOnlyAppliesToCombo() throws {
        let combo = SpotlightPositionSnapshot(members: [terminalA, terminalB])
        let single = SpotlightPositionSnapshot(members: [file])
        let snapshot = SpotlightLayoutSnapshot(positions: [combo, single])

        let toggled = try XCTUnwrap(SpotlightLayoutReducer.togglingOrientation(
            positionID: combo.id,
            snapshot: snapshot
        ))
        XCTAssertEqual(toggled.positions[0].orientation, .stacked)
        XCTAssertNil(SpotlightLayoutReducer.togglingOrientation(positionID: single.id, snapshot: snapshot))
    }
}

@MainActor
final class SpotlightComboNavigationAndScrollTests: XCTestCase {
    func testComboIsOneCarouselStepAndDirectMemberSelectionFocusesWithoutStep() throws {
        let first = SpotlightItem.file(tileID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/a.md"))
        let second = SpotlightItem.browser(tileID: UUID(), url: URL(string: "https://example.com")!)
        let third = SpotlightItem.file(tileID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/c.md"))
        let snapshot = SpotlightLayoutSnapshot(positions: [
            SpotlightPositionSnapshot(members: [first.persistentID, second.persistentID]),
            SpotlightPositionSnapshot(members: [third.persistentID]),
        ])

        let next = try XCTUnwrap(SpotlightPositionNavigationResolver.relativeSelection(
            offset: 1,
            currentIdentity: second.navigationIdentity,
            snapshot: snapshot,
            items: [first, second, third]
        ))
        XCTAssertEqual(next.targetIdentity, third.navigationIdentity)

        let focus = try XCTUnwrap(SpotlightPositionNavigationResolver.selection(
            targetIdentity: first.navigationIdentity,
            currentIdentity: second.navigationIdentity,
            snapshot: snapshot,
            items: [first, second, third]
        ))
        XCTAssertEqual(focus.direction, 0)
        XCTAssertEqual(focus.targetIdentity, first.navigationIdentity)
    }

    func testShelfScrollSequenceRemainsLatchedThroughLeaveEndAndMomentumWithoutCarouselOffset() {
        var tracker = SpotlightScrollGestureTracker()
        XCTAssertEqual(tracker.handle(sample(.began, overShelf: true), carouselEnabled: true, terminalReservesScroll: false), .passThrough(resetOffset: true))
        XCTAssertEqual(tracker.handle(sample(.changed, x: -80), carouselEnabled: true, terminalReservesScroll: false), .routeToShelf)
        XCTAssertEqual(tracker.handle(sample(.ended), carouselEnabled: true, terminalReservesScroll: false), .routeToShelf)
        XCTAssertEqual(tracker.handle(sample([], momentum: .changed, x: -20), carouselEnabled: true, terminalReservesScroll: false), .routeToShelf)
        XCTAssertEqual(tracker.handle(sample([], momentum: .ended), carouselEnabled: true, terminalReservesScroll: false), .routeToShelf)
    }

    func testShelfOwnershipDoesNotRequireOverflowOrCarouselAvailability() {
        var tracker = SpotlightScrollGestureTracker()
        XCTAssertEqual(tracker.handle(sample(.began, overShelf: true), carouselEnabled: false, terminalReservesScroll: false), .passThrough(resetOffset: true))
        XCTAssertEqual(tracker.handle(sample(.changed, x: 120), carouselEnabled: false, terminalReservesScroll: false), .routeToShelf)
        XCTAssertEqual(tracker.handle(sample(.cancelled), carouselEnabled: false, terminalReservesScroll: false), .routeToShelf)
        XCTAssertEqual(tracker.handle(sample([], momentum: .changed, x: 40), carouselEnabled: true, terminalReservesScroll: false), .routeToShelf)
        XCTAssertEqual(tracker.handle(sample([], momentum: .ended), carouselEnabled: true, terminalReservesScroll: false), .routeToShelf)
    }

    func testShelfRegistrationNilAndReplacementInvalidateOwnershipGeneration() {
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        let first = NSScrollView()
        let second = NSScrollView()
        let initial = coordinator.scrollOwnershipGeneration

        coordinator.registerShelfScrollView(first)
        XCTAssertEqual(coordinator.scrollOwnershipGeneration, initial + 1)
        coordinator.registerShelfScrollView(first)
        XCTAssertEqual(coordinator.scrollOwnershipGeneration, initial + 1)
        coordinator.registerShelfScrollView(second)
        XCTAssertEqual(coordinator.scrollOwnershipGeneration, initial + 2)
        coordinator.registerShelfScrollView(nil)
        XCTAssertEqual(coordinator.scrollOwnershipGeneration, initial + 3)
    }

    func testNonShelfHorizontalGestureRetainsCarouselAndTerminalArbitration() {
        var tracker = SpotlightScrollGestureTracker()
        _ = tracker.handle(sample(.began), carouselEnabled: true, terminalReservesScroll: false)
        XCTAssertEqual(
            tracker.handle(sample(.changed, x: -60), carouselEnabled: true, terminalReservesScroll: false),
            .updateOffset(-21)
        )
        XCTAssertEqual(
            tracker.handle(sample(.ended), carouselEnabled: true, terminalReservesScroll: false),
            .finishSwitch(1)
        )

        _ = tracker.handle(sample(.began), carouselEnabled: true, terminalReservesScroll: false)
        XCTAssertEqual(
            tracker.handle(sample(.changed, x: -60), carouselEnabled: true, terminalReservesScroll: true),
            .passThrough(resetOffset: true)
        )
    }

    private func sample(
        _ phase: NSEvent.Phase,
        momentum: NSEvent.Phase = [],
        x: CGFloat = 0,
        overShelf: Bool = false
    ) -> SpotlightScrollGestureSample {
        SpotlightScrollGestureSample(
            phase: phase,
            momentumPhase: momentum,
            deltaX: x,
            deltaY: 0,
            isPrecise: true,
            beginsOverShelf: overShelf
        )
    }
}

@MainActor
final class SpotlightHostPersistenceAndPolicyTests: XCTestCase {
    private var root: URL!
    private var persistence: VibeSpacePersistenceStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("spotlight-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        persistence = VibeSpacePersistenceStore(
            store: AppPersistenceDataStore(fileManager: .default, appDirectoryURL: root)
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        persistence = nil
    }

    func testMainHostSnapshotRoundTripsAndMirrorsLegacyTerminalOrder() {
        let vibespaceID = UUID()
        let terminal = SpotlightPersistentItemID.terminal(projectPath: "/tmp/project", tabID: UUID())
        let file = SpotlightPersistentItemID.file(tileID: UUID())
        let expected = SpotlightLayoutSnapshot(positions: [
            SpotlightPositionSnapshot(members: [terminal, file], orientation: .stacked)
        ])
        let sut = makeService()
        sut.setSpotlightLayout(expected, liveIDs: [terminal, file], for: vibespaceID)

        let reloaded = makeService()
        let restored = reloaded.spotlightLayout(liveIDs: [terminal, file], for: vibespaceID)
        XCTAssertEqual(restored, expected)
        guard case let .terminal(projectPath, tabID) = terminal else { return }
        XCTAssertEqual(
            reloaded.vibespaceSpotlightTerminalOrder(
                liveIdentities: [VibeSpaceSpotlightTerminalOrderEntry(projectPath: projectPath, tabID: tabID)],
                for: vibespaceID
            ).map(\.tabID),
            [tabID]
        )
    }

    func testMainOverlayCommitPathMirrorsPrimaryTileOrderAndPreservesEnrichedBrowserState() throws {
        let vibespaceID = UUID()
        let projectPathA = "/tmp/main-a"
        let projectPathB = "/tmp/main-b"
        let tabA = UUID()
        let tabB = UUID()
        let staleBrowserSnapshot = BrowserSessionSnapshot(
            urlString: "https://one.example/stale",
            backHistoryURLStrings: ["https://one.example/old"],
            pageZoom: 0.8
        )
        let currentBrowserURL = try XCTUnwrap(URL(string: "https://one.example/current"))
        let currentBrowserSnapshot = BrowserSessionSnapshot(
            urlString: currentBrowserURL.absoluteString,
            backHistoryURLStrings: ["https://one.example/start", "https://one.example/middle"],
            forwardHistoryURLStrings: ["https://one.example/future"],
            pageZoom: 1.6,
            themeMode: "dark"
        )
        let primaryTiles = [
            VibeSpaceTerminalBoardTile(
                heightWeight: 0.8,
                projectPath: projectPathA,
                terminalTabID: tabA,
                workingDirectoryPath: projectPathA
            ),
            VibeSpaceTerminalBoardTile(
                heightWeight: 0.2,
                workingDirectoryPath: "",
                contentKind: .browser(try XCTUnwrap(URL(string: "https://one.example/stale"))),
                browserSession: staleBrowserSnapshot
            ),
            VibeSpaceTerminalBoardTile(
                heightWeight: 0.3,
                projectPath: projectPathB,
                terminalTabID: tabB,
                workingDirectoryPath: projectPathB
            ),
            VibeSpaceTerminalBoardTile(
                heightWeight: 0.7,
                workingDirectoryPath: "",
                contentKind: .browser(try XCTUnwrap(URL(string: "https://four.example")))
            ),
        ]
        let minimized = VibeSpaceTerminalBoardTile(
            workingDirectoryPath: "",
            contentKind: .browser(try XCTUnwrap(URL(string: "https://minimized.example")))
        )
        let primaryLayout = VibeSpaceTerminalBoardLayout(
            columns: [
                VibeSpaceTerminalBoardColumn(id: UUID(), widthWeight: 0.2, tiles: Array(primaryTiles[0...1])),
                VibeSpaceTerminalBoardColumn(id: UUID(), widthWeight: 0.8, tiles: Array(primaryTiles[2...3])),
            ],
            activeTileID: primaryTiles[2].id,
            minimizedTiles: [minimized]
        ).normalized()
        let detachedID = UUID()
        let detachedTile = VibeSpaceTerminalBoardTile(
            projectPath: "/tmp/detached",
            terminalTabID: UUID(),
            workingDirectoryPath: "/tmp/detached"
        )
        let detachedSurface = VibeSpaceTerminalBoardSurface(
            id: detachedID,
            kind: .detached,
            layout: VibeSpaceTerminalBoardLayout(
                columns: [VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [detachedTile])],
                activeTileID: detachedTile.id
            ),
            title: "Detached",
            spotlightLayout: SpotlightLayoutSnapshot(positions: [
                SpotlightPositionSnapshot(members: [
                    .terminal(projectPath: "/tmp/detached", tabID: try XCTUnwrap(detachedTile.terminalTabID))
                ])
            ])
        )
        let initialState = VibeSpaceTerminalBoardState(surfaces: [
            VibeSpaceTerminalBoardSurface(
                id: VibeSpaceTerminalBoardState.primarySurfaceID,
                kind: .primary,
                layout: primaryLayout,
                title: "Primary"
            ),
            detachedSurface,
        ]).normalized()
        let service = makeService()
        service.setTerminalBoardState(initialState, for: vibespaceID)
        let container = AppContainer.makeDefault()
        let enrichedBrowserTileID = primaryTiles[1].id
        let boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: vibespaceID,
            layoutPersistence: service,
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry,
            snapshotProviders: BoardSnapshotProviders(
                browserCurrentURL: { tileID in
                    tileID == enrichedBrowserTileID ? currentBrowserURL : nil
                },
                browserSession: { tileID in
                    tileID == enrichedBrowserTileID ? currentBrowserSnapshot : nil
                }
            )
        )
        defer { boardStore.standaloneTerminalViewModel.shutdown() }

        let identities: [SpotlightPersistentItemID] = [
            .terminal(projectPath: projectPathA, tabID: tabA),
            .browser(tileID: primaryTiles[1].id),
            .terminal(projectPath: projectPathB, tabID: tabB),
            .browser(tileID: primaryTiles[3].id),
            .browser(tileID: minimized.id),
        ]
        let expected = SpotlightLayoutSnapshot(positions: [
            SpotlightPositionSnapshot(
                members: [identities[3], identities[1]],
                orientation: .stacked
            ),
            SpotlightPositionSnapshot(members: [identities[2]]),
            SpotlightPositionSnapshot(members: [identities[0]]),
            SpotlightPositionSnapshot(members: [identities[4]]),
        ])

        boardStore.commit()
        XCTAssertEqual(boardStore.layout.tile(for: enrichedBrowserTileID)?.browserSession, staleBrowserSnapshot)
        XCTAssertTrue(boardStore.commitMainSpotlightLayout(expected, liveIDs: identities))
        let changed = boardStore.layout(for: boardStore.primarySurfaceID)
        XCTAssertEqual(changed.tiles.map(\.id), [
            primaryTiles[3].id,
            primaryTiles[1].id,
            primaryTiles[2].id,
            primaryTiles[0].id,
        ])
        XCTAssertEqual(changed.columns.map(\.id), primaryLayout.columns.map(\.id))
        XCTAssertEqual(changed.columns.map(\.widthWeight), primaryLayout.columns.map(\.widthWeight))
        XCTAssertEqual(changed.columns.map { $0.tiles.count }, primaryLayout.columns.map { $0.tiles.count })
        XCTAssertEqual(
            changed.columns.map { $0.tiles.map(\.heightWeight) },
            primaryLayout.columns.map { $0.tiles.map(\.heightWeight) }
        )
        XCTAssertEqual(changed.activeTileID, primaryLayout.activeTileID)
        XCTAssertEqual(changed.tileCount, primaryLayout.tileCount)
        XCTAssertEqual(changed.minimizedTiles, primaryLayout.minimizedTiles)
        for originalTile in primaryLayout.tiles {
            let movedTile = try XCTUnwrap(changed.tile(for: originalTile.id))
            XCTAssertEqual(movedTile.projectPath, originalTile.projectPath)
            XCTAssertEqual(movedTile.terminalTabID, originalTile.terminalTabID)
            XCTAssertEqual(movedTile.workingDirectoryPath, originalTile.workingDirectoryPath)
            XCTAssertEqual(movedTile.contentKind, originalTile.contentKind)
            XCTAssertEqual(movedTile.browserSession, originalTile.browserSession)
        }
        XCTAssertEqual(boardStore.boardState.surface(id: detachedID), detachedSurface.normalized())
        XCTAssertEqual(
            boardStore.boardState.surface(id: boardStore.primarySurfaceID)?.spotlightLayout,
            expected
        )

        let reloadedService = makeService()
        let reloadedState = reloadedService.terminalBoardState(for: vibespaceID)
        let reloadedPrimary = reloadedState.primaryLayout
        XCTAssertEqual(reloadedPrimary.tiles.map(\.id), changed.tiles.map(\.id))
        XCTAssertEqual(reloadedPrimary.columns.map(\.id), changed.columns.map(\.id))
        XCTAssertEqual(reloadedPrimary.columns.map(\.widthWeight), changed.columns.map(\.widthWeight))
        XCTAssertEqual(reloadedPrimary.columns.map { $0.tiles.count }, changed.columns.map { $0.tiles.count })
        XCTAssertEqual(
            reloadedPrimary.columns.map { $0.tiles.map(\.heightWeight) },
            changed.columns.map { $0.tiles.map(\.heightWeight) }
        )
        XCTAssertEqual(reloadedPrimary.activeTileID, primaryLayout.activeTileID)
        XCTAssertEqual(reloadedPrimary.tileCount, primaryLayout.tileCount)
        XCTAssertEqual(reloadedPrimary.minimizedTiles, primaryLayout.minimizedTiles)
        let reloadedBrowserTile = try XCTUnwrap(reloadedPrimary.tile(for: enrichedBrowserTileID))
        XCTAssertEqual(reloadedBrowserTile.browserURL, currentBrowserURL)
        XCTAssertEqual(reloadedBrowserTile.browserSession, currentBrowserSnapshot)
        XCTAssertEqual(reloadedState.surface(id: detachedID), detachedSurface.normalized())
        XCTAssertEqual(
            reloadedState.surface(id: reloadedState.primarySurfaceID)?.spotlightLayout,
            expected
        )
        XCTAssertEqual(
            reloadedService.spotlightLayout(liveIDs: identities, for: vibespaceID),
            expected
        )
        XCTAssertEqual(
            reloadedService.vibespaceSpotlightTerminalOrder(
                liveIdentities: [
                    VibeSpaceSpotlightTerminalOrderEntry(projectPath: projectPathA, tabID: tabA),
                    VibeSpaceSpotlightTerminalOrderEntry(projectPath: projectPathB, tabID: tabB),
                ],
                for: vibespaceID
            ).map(\.tabID),
            [tabB, tabA]
        )
        XCTAssertEqual(Set(reloadedPrimary.allTileIDs), Set(primaryLayout.allTileIDs))
    }

    func testLegacyTerminalOrderMigratesIntoSpotlightSnapshot() {
        let vibespaceID = UUID()
        let first = VibeSpaceSpotlightTerminalOrderEntry(projectPath: "/tmp/a", tabID: UUID())
        let second = VibeSpaceSpotlightTerminalOrderEntry(projectPath: "/tmp/b", tabID: UUID())
        let sut = makeService()
        sut.setVibeSpaceSpotlightTerminalOrder([second, first], for: vibespaceID)

        let live: [SpotlightPersistentItemID] = [
            .terminal(projectPath: first.projectPath, tabID: first.tabID),
            .terminal(projectPath: second.projectPath, tabID: second.tabID),
        ]
        XCTAssertEqual(sut.spotlightLayout(liveIDs: live, for: vibespaceID).flattenedMembers, [live[1], live[0]])
    }

    func testLegacyLayoutWithActuallyAbsentSpotlightKeyDecodesFromTerminalOrder() throws {
        let vibespaceID = UUID()
        let tabID = UUID()
        let layoutURL = persistence.vibespaceLayoutURL(for: vibespaceID)
        try FileManager.default.createDirectory(
            at: layoutURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyJSON = """
        {
          "vibespaceSpotlightTerminalOrder": [
            {"projectPath":"/tmp/legacy-project","tabID":"\(tabID.uuidString)"}
          ]
        }
        """
        try Data(legacyJSON.utf8).write(to: layoutURL)

        let live = SpotlightPersistentItemID.terminal(
            projectPath: "/tmp/legacy-project",
            tabID: tabID
        )
        XCTAssertEqual(
            makeService().spotlightLayout(liveIDs: [live], for: vibespaceID).flattenedMembers,
            [live]
        )
    }

    func testBoardSurfaceReorderPreservesUnequalDestinationGeometryAndOtherSurfaceThroughReload() {
        let vibespaceID = UUID()
        let primaryTile = VibeSpaceTerminalBoardTile(
            workingDirectoryPath: "",
            contentKind: .browser(URL(string: "https://primary.example")!)
        )
        let detachedTiles = (0..<4).map { index in
            VibeSpaceTerminalBoardTile(
                heightWeight: [0.8, 0.2, 0.3, 0.7][index],
                workingDirectoryPath: "",
                contentKind: .browser(URL(string: "https://detached-\(index).example")!)
            )
        }
        let detachedID = UUID()
        let originalDetachedLayout = VibeSpaceTerminalBoardLayout(
            columns: [
                VibeSpaceTerminalBoardColumn(
                    id: UUID(), widthWeight: 0.25,
                    tiles: Array(detachedTiles[0...1])
                ),
                VibeSpaceTerminalBoardColumn(
                    id: UUID(), widthWeight: 0.75,
                    tiles: Array(detachedTiles[2...3])
                ),
            ],
            activeTileID: detachedTiles[0].id
        ).normalized()
        let state = VibeSpaceTerminalBoardState(surfaces: [
            VibeSpaceTerminalBoardSurface(
                id: VibeSpaceTerminalBoardState.primarySurfaceID,
                kind: .primary,
                layout: VibeSpaceTerminalBoardLayout(
                    columns: [VibeSpaceTerminalBoardColumn(tiles: [primaryTile])],
                    activeTileID: primaryTile.id
                ),
                title: "Primary"
            ),
            VibeSpaceTerminalBoardSurface(
                id: detachedID,
                kind: .detached,
                layout: originalDetachedLayout,
                title: "Detached"
            ),
        ])
        let service = makeService()
        service.setTerminalBoardState(state, for: vibespaceID)
        let container = AppContainer.makeDefault()
        let boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: vibespaceID,
            layoutPersistence: service,
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )
        let liveIDs = detachedTiles.map { SpotlightPersistentItemID.browser(tileID: $0.id) }
        let reordered = SpotlightLayoutSnapshot(positions: [
            SpotlightPositionSnapshot(members: [liveIDs[3]]),
            SpotlightPositionSnapshot(members: [liveIDs[1]]),
            SpotlightPositionSnapshot(members: [liveIDs[2]]),
            SpotlightPositionSnapshot(members: [liveIDs[0]]),
        ])

        XCTAssertTrue(boardStore.setSpotlightLayout(reordered, liveIDs: liveIDs, surfaceID: detachedID))
        let changed = boardStore.layout(for: detachedID)
        XCTAssertEqual(changed.columns.map(\.id), originalDetachedLayout.columns.map(\.id))
        XCTAssertEqual(changed.columns.map(\.widthWeight), originalDetachedLayout.columns.map(\.widthWeight))
        XCTAssertEqual(changed.columns.map { $0.tiles.map(\.heightWeight) }, originalDetachedLayout.columns.map { $0.tiles.map(\.heightWeight) })
        XCTAssertEqual(changed.columns.map { $0.tiles.count }, [2, 2])
        XCTAssertEqual(changed.tiles.map(\.id), [detachedTiles[3].id, detachedTiles[1].id, detachedTiles[2].id, detachedTiles[0].id])
        XCTAssertEqual(boardStore.layout.tiles.map(\.id), [primaryTile.id])

        let restoredState = makeService().terminalBoardState(for: vibespaceID)
        XCTAssertEqual(restoredState.layout(for: detachedID), changed)
        XCTAssertEqual(restoredState.primaryLayout.tiles.map(\.id), [primaryTile.id])
    }

    func testDetachedSurfaceSnapshotCodableKeepsComboWithoutChangingGeometry() throws {
        let firstTile = VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/a")
        let secondTile = VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/b")
        let layout = VibeSpaceTerminalBoardLayout(columns: [
            VibeSpaceTerminalBoardColumn(widthWeight: 0.3, tiles: [firstTile]),
            VibeSpaceTerminalBoardColumn(widthWeight: 0.7, tiles: [secondTile]),
        ])
        let combo = SpotlightLayoutSnapshot(positions: [
            SpotlightPositionSnapshot(members: [
                .file(tileID: firstTile.id),
                .browser(tileID: secondTile.id),
            ], orientation: .stacked)
        ])
        let surface = VibeSpaceTerminalBoardSurface(
            kind: .detached,
            layout: layout,
            title: "Detached",
            spotlightLayout: combo
        )

        let restored = try JSONDecoder().decode(
            VibeSpaceTerminalBoardSurface.self,
            from: JSONEncoder().encode(surface)
        )
        XCTAssertEqual(restored.spotlightLayout, combo)
        XCTAssertEqual(restored.layout.columns.map(\.widthWeight), [0.3, 0.7])
        XCTAssertEqual(restored.layout.columns.map { $0.tiles.count }, [1, 1])
    }

    func testCoordinatorOverviewAndLayoutTransitionsAreNamedAndResetOwnershipState() {
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        let state = TerminalSpotlightState(
            id: UUID(), source: .vibeCast, title: "VibeCast", accentColor: nil,
            workingDirectoryURL: root, onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil, isTemporary: false, owningProjectRootURL: nil
        )
        coordinator.setSpotlight(state, animated: false)
        coordinator.presentOverview()
        XCTAssertTrue(coordinator.isOverviewPresented)
        let generation = coordinator.layoutGeneration
        coordinator.noteLayoutCommitted()
        XCTAssertEqual(coordinator.layoutGeneration, generation + 1)
        coordinator.dismissOverview()
        XCTAssertFalse(coordinator.isOverviewPresented)
        coordinator.dismiss(animated: false)
    }

    func testReconciliationChangeAdvancesGenerationAndRejectsStaleDragPayload() throws {
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        let live = SpotlightPersistentItemID.file(tileID: UUID())
        let otherLive = SpotlightPersistentItemID.browser(tileID: UUID())
        let stale = SpotlightPersistentItemID.file(tileID: UUID())
        let livePosition = SpotlightPositionSnapshot(members: [live])
        let stalePosition = SpotlightPositionSnapshot(members: [stale])
        let otherLivePosition = SpotlightPositionSnapshot(members: [otherLive])
        let original = SpotlightLayoutSnapshot(positions: [livePosition, stalePosition, otherLivePosition])
        let payload = SpotlightDragPayload(
            hostID: "main",
            generation: coordinator.layoutGeneration,
            subject: .position(livePosition.id)
        )
        let reconciled = SpotlightLayoutReconciler.reconcile(
            snapshot: original,
            liveIDs: [live, otherLive],
            currentID: live
        )
        XCTAssertNotEqual(reconciled.snapshot, original)

        coordinator.noteLayoutCommitted()
        XCTAssertNil(SpotlightLayoutReducer.dropping(
            payload: payload,
            on: otherLivePosition.id,
            zone: .after,
            snapshot: reconciled.snapshot,
            hostID: "main",
            generation: coordinator.layoutGeneration
        ))
    }

    func testReconciledReplacementRetainsSplitActionAndSurfaceAffinity() throws {
        let surfaceID = UUID()
        let missing = SpotlightPersistentItemID.file(tileID: UUID())
        let surviving = SpotlightPersistentItemID.browser(tileID: UUID())
        let result = SpotlightLayoutReconciler.reconcile(
            snapshot: SpotlightLayoutSnapshot(positions: [
                SpotlightPositionSnapshot(members: [missing]),
                SpotlightPositionSnapshot(members: [surviving]),
            ]),
            liveIDs: [surviving],
            currentID: missing
        )
        XCTAssertEqual(result.replacementForCurrent, surviving)
        guard case let .browser(survivingTileID) = surviving else {
            return XCTFail("Expected browser identity")
        }
        var splitCount = 0
        let replacement = TerminalSpotlightState(
            id: UUID(),
            source: .browser(tileID: survivingTileID, url: URL(string: "https://example.com")!),
            title: "Browser",
            accentColor: nil,
            workingDirectoryURL: root,
            onSplitTerminalRequested: { splitCount += 1 },
            onTemporaryTerminalRequested: {},
            isTemporary: false,
            owningProjectRootURL: nil,
            surfaceID: surfaceID
        )
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        coordinator.setSpotlight(replacement, animated: false)

        XCTAssertEqual(coordinator.spotlight?.persistentItemID, surviving)
        XCTAssertEqual(coordinator.spotlight?.surfaceID, surfaceID)
        coordinator.spotlight?.onSplitTerminalRequested?()
        XCTAssertEqual(splitCount, 1)
        coordinator.dismiss(animated: false)
    }

    func testBrowserMetadataStripsUserInfoQueryAndFragment() throws {
        let url = try XCTUnwrap(URL(string: "https://user:secret@example.com/private/path?token=secret#fragment"))
        let location = SpotlightSafeMetadata.browserLocation(url)
        XCTAssertEqual(location.host, "example.com")
        XCTAssertEqual(location.display, "example.com/private/path")
        XCTAssertFalse(location.display.contains("secret"))
        XCTAssertFalse(location.display.contains("token"))
        XCTAssertFalse(location.display.contains("fragment"))
    }

    func testSafeAccessibilityTokensNeverContainRawProjectPath() {
        let raw = "/Users/example/private/project"
        let id = SpotlightPersistentItemID.terminal(projectPath: raw, tabID: UUID())
        XCTAssertFalse(id.safeToken.contains(raw))
        XCTAssertTrue(id.safeToken.contains("terminal:"))
        XCTAssertFalse(AppStrings.Spotlight.allTabs.isEmpty)
        XCTAssertFalse(AppStrings.Spotlight.searchPlaceholder.isEmpty)
    }

    func testSpotlightTerminalIDCodablePreservesSSHIdentifierVerbatim() throws {
        let identifier = "ssh://dev@example.com:2222/srv/My%20Project"
        let expected = SpotlightPersistentItemID.terminal(
            projectPath: identifier,
            tabID: UUID()
        )

        let decoded = try JSONDecoder().decode(
            SpotlightPersistentItemID.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(decoded, expected)
        XCTAssertEqual(decoded.navigationIdentity, expected.navigationIdentity)
    }

    private func makeService() -> LayoutPersistenceService {
        let service = LayoutPersistenceService(fileManager: .default)
        service.setVibeSpacePersistenceStore(persistence)
        return service
    }
}


@MainActor
final class SpotlightStandaloneAndRestoreTests: XCTestCase {
    private var container: AppContainer!
    private var store: VibeSpaceTerminalBoardStore!
    private var root: URL!

    override func setUpWithError() throws {
        container = AppContainer.makeDefault()
        root = try makeTempDirectory(prefix: "crispy-spotlight-standalone")
        store = VibeSpaceTerminalBoardStore(
            vibespaceID: UUID(),
            layoutPersistence: LayoutPersistenceService(
                fileManager: .default,
                stateFileURL: root.appendingPathComponent("layout.json")
            ),
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )
    }

    override func tearDownWithError() throws {
        store?.standaloneTerminalViewModel.shutdown()
        store = nil
        container = nil
        try? FileManager.default.removeItem(at: root)
    }

    func testCanonicalBoardItemsIncludeVisibleAndMinimizedStandaloneWithSurfaceTileIdentityOnMainAndDetached() throws {
        XCTAssertTrue(store.addTile(projectPath: nil, directoryURL: root, preferStandalone: true))
        XCTAssertTrue(store.addTile(projectPath: nil, directoryURL: root, preferStandalone: true))
        XCTAssertTrue(store.addTile(projectPath: nil, directoryURL: root, preferStandalone: true))
        let primaryIDs = store.layout.tiles.map(\.id)
        store.minimizeTile(primaryIDs[1])

        let minimizedTabID = try XCTUnwrap(
            store.tile(for: primaryIDs[1], includeMinimized: true)?.terminalTabID
        )
        XCTAssertEqual(
            SpotlightTerminalPresentationWiring.standaloneIdentity(
                terminalViewModel: store.standaloneTerminalViewModel,
                tabID: minimizedTabID,
                surfaceID: store.primarySurfaceID,
                boardStore: store
            ),
            .terminal(projectScope: .unscoped(primaryIDs[1]), tabID: minimizedTabID)
        )

        let mainItems = store.spotlightTerminalItems(
            surfaceID: store.primarySurfaceID,
            projects: [],
            includeProjectTerminals: false
        )
        XCTAssertEqual(mainItems.count, 3)
        XCTAssertEqual(mainItems.map(\.persistentID), [
            .standaloneTerminal(
                surfaceID: store.primarySurfaceID,
                tileID: primaryIDs[0],
                tabID: try XCTUnwrap(store.tile(for: primaryIDs[0])?.terminalTabID)
            ),
            .standaloneTerminal(
                surfaceID: store.primarySurfaceID,
                tileID: primaryIDs[2],
                tabID: try XCTUnwrap(store.tile(for: primaryIDs[2])?.terminalTabID)
            ),
            .standaloneTerminal(
                surfaceID: store.primarySurfaceID,
                tileID: primaryIDs[1],
                tabID: try XCTUnwrap(store.tile(for: primaryIDs[1], includeMinimized: true)?.terminalTabID)
            ),
        ])

        let moved = try XCTUnwrap(store.detachTile(primaryIDs[2]))
        let detachedID = store.createDetachedSurface(with: moved, title: "Detached")
        store.minimizeTile(moved.id, surfaceID: detachedID)
        let detachedItems = store.spotlightTerminalItems(
            surfaceID: detachedID,
            projects: [],
            includeProjectTerminals: true
        )
        let detachedItem = try XCTUnwrap(detachedItems.first)
        XCTAssertEqual(
            detachedItem.persistentID,
            .standaloneTerminal(
                surfaceID: detachedID,
                tileID: moved.id,
                tabID: try XCTUnwrap(moved.terminalTabID)
            )
        )
        XCTAssertEqual(detachedItem.navigationIdentity, detachedItem.persistentID.navigationIdentity)

        let state = TerminalSpotlightState(
            id: UUID(),
            source: .persistent(
                terminalViewModel: store.standaloneTerminalViewModel,
                tabID: try XCTUnwrap(moved.terminalTabID)
            ),
            title: "Standalone",
            accentColor: nil,
            workingDirectoryURL: root,
            onSplitTerminalRequested: {},
            onTemporaryTerminalRequested: {},
            isTemporary: false,
            owningProjectRootURL: nil,
            surfaceID: detachedID,
            navigationIdentityOverride: detachedItem.navigationIdentity
        )
        XCTAssertEqual(state.persistentItemID, detachedItem.persistentID)
        XCTAssertEqual(state.navigationIdentity, detachedItem.navigationIdentity)
    }

    func testNestedTemporaryRestorePreservesExactStandaloneStateCallbacksSurfaceAndIDs() throws {
        XCTAssertTrue(store.addTile(projectPath: nil, directoryURL: root, preferStandalone: true))
        let tile = try XCTUnwrap(store.layout.tiles.first)
        let tabID = try XCTUnwrap(tile.terminalTabID)
        var splitCount = 0
        let base = TerminalSpotlightState(
            id: UUID(),
            source: .persistent(terminalViewModel: store.standaloneTerminalViewModel, tabID: tabID),
            title: "Standalone",
            accentColor: nil,
            workingDirectoryURL: root,
            onSplitTerminalRequested: { splitCount += 1 },
            onTemporaryTerminalRequested: {},
            isTemporary: false,
            owningProjectRootURL: nil,
            surfaceID: store.primarySurfaceID,
            navigationIdentityOverride: .terminal(projectScope: .unscoped(tile.id), tabID: tabID)
        )
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        coordinator.setSpotlight(base, animated: false)
        let firstTemporary = temporaryState(id: UUID(), surfaceID: store.primarySurfaceID)
        let secondTemporary = temporaryState(id: UUID(), surfaceID: store.primarySurfaceID)

        coordinator.setSpotlight(firstTemporary, animated: false)
        coordinator.setSpotlight(secondTemporary, animated: false)
        XCTAssertEqual(coordinator.restoreStack.map { $0.spotlight.id }, [base.id, firstTemporary.id])

        XCTAssertTrue(coordinator.restorePreviousSpotlight(resolve: { $0.spotlight }))
        XCTAssertEqual(coordinator.spotlight?.id, firstTemporary.id)
        XCTAssertEqual(coordinator.spotlight?.surfaceID, store.primarySurfaceID)
        XCTAssertTrue(coordinator.restorePreviousSpotlight(resolve: { $0.spotlight }))
        XCTAssertEqual(coordinator.spotlight?.id, base.id)
        XCTAssertEqual(coordinator.spotlight?.persistentItemID, base.persistentItemID)
        XCTAssertEqual(coordinator.spotlight?.surfaceID, store.primarySurfaceID)
        coordinator.spotlight?.onSplitTerminalRequested?()
        XCTAssertEqual(splitCount, 1)
        coordinator.dismiss(animated: false)
    }

    func testCloseEscapeAndBackdropRoutesRestorePriorSpotlight() {
        for trigger in ["close", "escape", "backdrop"] {
            let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
            let base = TerminalSpotlightState(
                id: UUID(), source: .vibeCast, title: trigger, accentColor: nil,
                workingDirectoryURL: root, onSplitTerminalRequested: nil,
                onTemporaryTerminalRequested: nil, isTemporary: false,
                owningProjectRootURL: nil, surfaceID: store.primarySurfaceID
            )
            let temporary = temporaryState(id: UUID(), surfaceID: store.primarySurfaceID)
            coordinator.setSpotlight(base, animated: false)
            coordinator.setSpotlight(temporary, animated: false)

            let sharedDismissRoute = {
                if !coordinator.restorePreviousSpotlight(animated: false, resolve: { $0.spotlight }) {
                    coordinator.dismiss(animated: false)
                }
            }
            sharedDismissRoute()
            XCTAssertEqual(coordinator.spotlight?.id, base.id, "\(trigger) must restore the prior Spotlight")
            coordinator.dismiss(animated: false)
        }
    }

    func testTemporaryProcessExitRestoresPriorSurfaceStateAndIgnoresStaleExit() {
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        let base = TerminalSpotlightState(
            id: UUID(), source: .vibeCast, title: "Base", accentColor: nil,
            workingDirectoryURL: root, onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil, isTemporary: false,
            owningProjectRootURL: nil, surfaceID: store.primarySurfaceID
        )
        let temporary = temporaryState(id: UUID(), surfaceID: store.primarySurfaceID)
        coordinator.setSpotlight(base, animated: false)
        coordinator.setSpotlight(temporary, animated: false)

        coordinator.temporaryProcessDidTerminate(spotlightID: UUID()) {
            XCTFail("A stale process exit must not request restoration")
        }
        XCTAssertEqual(coordinator.spotlight?.id, temporary.id)
        coordinator.temporaryProcessDidTerminate(spotlightID: temporary.id) {
            _ = coordinator.restorePreviousSpotlight(animated: false, resolve: { $0.spotlight })
        }
        XCTAssertEqual(coordinator.spotlight?.id, base.id)
        XCTAssertEqual(coordinator.spotlight?.surfaceID, store.primarySurfaceID)
        coordinator.dismiss(animated: false)
    }

    func testProductionMainStandaloneFactoryPreservesIdentityAndWiresPresetAction() throws {
        let viewModel = container.makeTerminalViewModel()
        defer { viewModel.shutdown() }
        viewModel.createTab(directoryURL: root, startImmediately: false)
        let tab = try XCTUnwrap(viewModel.activeTab)
        let tileID = UUID()
        let surfaceID = VibeSpaceTerminalBoardState.primarySurfaceID
        let item = SpotlightItem.standaloneTerminal(
            surfaceID: surfaceID,
            tileID: tileID,
            terminalViewModel: viewModel,
            tab: tab
        )

        let state = try XCTUnwrap(ContentView(container: container).spotlightState(for: item))

        XCTAssertEqual(state.surfaceID, surfaceID)
        XCTAssertEqual(state.navigationIdentity, item.navigationIdentity)
        XCTAssertEqual(state.persistentItemID, item.persistentID)
        XCTAssertNotNil(state.onAgentPresetSelected)
        XCTAssertEqual(
            SpotlightTerminalPresentationWiring.identityAfterSelectingTab(tab.id, from: state),
            item.navigationIdentity
        )
    }

    func testMainNativeDoubleClickProductionRouteRestoresNestedTemporaryChainToExactCombo() throws {
        XCTAssertTrue(store.addTile(projectPath: nil, directoryURL: root, preferStandalone: true))
        XCTAssertTrue(store.addTile(projectPath: nil, directoryURL: root, preferStandalone: true))
        let items = store.spotlightTerminalItems(
            surfaceID: store.primarySurfaceID,
            projects: [],
            includeProjectTerminals: false
        )
        let firstItem = try XCTUnwrap(items.first)
        let secondItem = try XCTUnwrap(items.dropFirst().first)
        let contentView = ContentView(container: container)
        let firstState = try XCTUnwrap(contentView.spotlightState(
            for: firstItem,
            inheritingSurfaceID: store.primarySurfaceID
        ))
        let secondState = try XCTUnwrap(contentView.spotlightState(
            for: secondItem,
            inheritingSurfaceID: store.primarySurfaceID
        ))
        let combo = SpotlightPositionSnapshot(
            members: [firstItem.persistentID, secondItem.persistentID],
            orientation: .stacked
        )
        _ = contentView.layoutPersistence.setSpotlightLayout(
            SpotlightLayoutSnapshot(positions: [combo]),
            liveIDs: items.map(\.persistentID),
            for: contentView.activeVibeSpaceID
        )

        contentView.terminalSpotlightCoordinator.setSpotlight(firstState, animated: false)
        let firstTemporary = temporaryState(id: UUID(), surfaceID: store.primarySurfaceID)
        let secondTemporary = temporaryState(id: UUID(), surfaceID: store.primarySurfaceID)
        contentView.terminalSpotlightCoordinator.setSpotlight(firstTemporary, animated: false)
        contentView.terminalSpotlightCoordinator.setSpotlight(secondTemporary, animated: false)

        contentView.handleTerminalSpotlightSessionDoubleClick(UUID())
        XCTAssertEqual(contentView.terminalSpotlightCoordinator.spotlight?.id, firstTemporary.id)
        contentView.handleTerminalSpotlightSessionDoubleClick(UUID())

        let restored = try XCTUnwrap(contentView.terminalSpotlightCoordinator.spotlight)
        XCTAssertEqual(restored.id, firstState.id)
        XCTAssertEqual(restored.navigationIdentity, firstItem.navigationIdentity)
        XCTAssertEqual(restored.persistentItemID, firstItem.persistentID)
        XCTAssertEqual(restored.surfaceID, store.primarySurfaceID)
        XCTAssertNotNil(restored.onSplitTerminalRequested)
        XCTAssertNotNil(restored.onTemporaryTerminalRequested)
        XCTAssertNotNil(restored.onShortcutSelected)
        XCTAssertNotNil(restored.onAgentPresetSelected)
        guard case let .persistent(firstOwner, firstTabID) = restored.source,
              case let .persistent(secondOwner, secondTabID) = secondState.source else {
            return XCTFail("Expected both restored combo members to retain terminal owners")
        }
        guard case let .standaloneTerminal(_, _, expectedFirstOwner, expectedFirstTab) = firstItem,
              case let .standaloneTerminal(_, _, expectedSecondOwner, expectedSecondTab) = secondItem else {
            return XCTFail("Expected standalone combo items")
        }
        XCTAssertTrue(firstOwner === expectedFirstOwner)
        XCTAssertTrue(secondOwner === expectedSecondOwner)
        XCTAssertEqual(firstTabID, expectedFirstTab.id)
        XCTAssertEqual(secondTabID, expectedSecondTab.id)

        let restoredLayout = contentView.layoutPersistence.spotlightLayout(
            liveIDs: items.map(\.persistentID),
            for: contentView.activeVibeSpaceID
        )
        XCTAssertEqual(restoredLayout.positions.count, 1)
        XCTAssertEqual(restoredLayout.positions.first?.id, combo.id)
        XCTAssertEqual(restoredLayout.positions.first?.members, combo.members)
        XCTAssertEqual(restoredLayout.positions.first?.orientation, .stacked)
        contentView.terminalSpotlightCoordinator.dismiss(animated: false)
    }

    func testMainCarouselProductionRoutePreservesPrimarySurfaceAcrossEveryNonTerminalKind() throws {
        XCTAssertTrue(store.addTile(projectPath: nil, directoryURL: root, preferStandalone: true))
        let standalone = try XCTUnwrap(store.spotlightTerminalItems(
            surfaceID: store.primarySurfaceID,
            projects: [],
            includeProjectTerminals: false
        ).first)
        let contentView = ContentView(container: container)
        let fileURL = root.appendingPathComponent("surface.md")
        let nonTerminalItems: [SpotlightItem] = [
            .vibeCast,
            .vibeLanes,
            .acp(tileID: UUID(), storeID: UUID(), title: "Agent", accentColor: nil),
            .file(tileID: UUID(), fileURL: fileURL),
            .browser(tileID: UUID(), url: URL(string: "https://example.com/surface")!),
        ]

        for item in nonTerminalItems {
            let base = try XCTUnwrap(contentView.spotlightState(
                for: standalone,
                inheritingSurfaceID: store.primarySurfaceID
            ))
            contentView.terminalSpotlightCoordinator.setSpotlight(base, animated: false)
            contentView.performSpotlightSwitch(SpotlightNavigationSelection(
                item: item,
                sourceIdentity: try XCTUnwrap(base.navigationIdentity),
                targetIdentity: item.navigationIdentity,
                direction: 1
            ))

            let nonTerminal = try XCTUnwrap(contentView.terminalSpotlightCoordinator.spotlight)
            XCTAssertEqual(nonTerminal.surfaceID, store.primarySurfaceID)
            XCTAssertEqual(nonTerminal.navigationIdentity, item.navigationIdentity)
            XCTAssertEqual(nonTerminal.persistentItemID, item.persistentID)

            contentView.performSpotlightSwitch(SpotlightNavigationSelection(
                item: standalone,
                sourceIdentity: item.navigationIdentity,
                targetIdentity: standalone.navigationIdentity,
                direction: 1
            ))
            let returned = try XCTUnwrap(contentView.terminalSpotlightCoordinator.spotlight)
            XCTAssertEqual(returned.surfaceID, store.primarySurfaceID)
            XCTAssertEqual(returned.navigationIdentity, standalone.navigationIdentity)
            XCTAssertEqual(returned.persistentItemID, standalone.persistentID)
            XCTAssertNotNil(returned.onSplitTerminalRequested)
            XCTAssertNotNil(returned.onTemporaryTerminalRequested)
            XCTAssertNotNil(returned.onShortcutSelected)
            XCTAssertNotNil(returned.onAgentPresetSelected)
        }

        let returned = try XCTUnwrap(contentView.terminalSpotlightCoordinator.spotlight)
        returned.onTemporaryTerminalRequested?()
        let temporary = try XCTUnwrap(contentView.terminalSpotlightCoordinator.spotlight)
        XCTAssertTrue(temporary.isTemporary)
        XCTAssertEqual(temporary.surfaceID, store.primarySurfaceID)
        contentView.closeTerminalSpotlight()
        XCTAssertEqual(contentView.terminalSpotlightCoordinator.spotlight?.persistentItemID, standalone.persistentID)

        XCTAssertNotNil(contentView.terminalSpotlightCoordinator.spotlight?.onSplitTerminalRequested)
        contentView.terminalSpotlightCoordinator.dismiss(animated: false)
    }

    func testDetachedFactoryAttachesEveryDirectKindAndRetainsCanonicalCallbacksAndIdentity() throws {
        let surfaceID = UUID()
        let tileID = UUID()
        let tabID = UUID()

        let storeID = UUID()
        let group = container.makeEditorGroupStore(bufferStore: DocumentBufferStore())
        var splitCount = 0
        var temporaryCount = 0
        var shortcutCount = 0
        var presetCount = 0
        let shortcut = TerminalShortcutDefinition(name: "Run", command: "echo run")
        let preset = TerminalPresetDefinition(
            id: "test", title: "Test", shortLabel: "Test", symbolName: "terminal",
            defaultCommand: "agent"
        )
        let sources: [TerminalSpotlightState.Source] = [
            .vibeCast,
            .vibeLanes,
            .acp(tileID: tileID, storeID: storeID),
            .filePreview(
                target: TerminalFileSystemTarget(
                    url: root.appendingPathComponent("preview.md"),
                    line: nil,
                    column: nil
                ),
                group: group
            ),
            .file(tileID: tileID, fileURL: root.appendingPathComponent("file.md"), group: group),
            .browser(tileID: tileID, url: URL(string: "https://example.com")!),
            .persistent(terminalViewModel: store.standaloneTerminalViewModel, tabID: tabID),
        ]

        for source in sources {
            let original = TerminalSpotlightState(
                id: UUID(), source: source, title: "State", accentColor: nil,
                workingDirectoryURL: root,
                onSplitTerminalRequested: { splitCount += 1 },
                onTemporaryTerminalRequested: { temporaryCount += 1 },
                shortcutDefinitions: [shortcut],
                onShortcutSelected: { _ in shortcutCount += 1 },
                onManageShortcutsRequested: {},
                agentPresets: [preset],
                onAgentPresetSelected: { _, _ in presetCount += 1 },
                isTemporary: false,
                owningProjectRootURL: root,
                owningProjectIdentifier: "ssh://dev@example.com:22/srv/app",
                navigationIdentityOverride: .terminal(projectScope: .unscoped(tileID), tabID: tabID)
            )
            let attached = DetachedSpotlightStateFactory.attach(original, to: surfaceID)
            XCTAssertEqual(attached.id, original.id)
            XCTAssertEqual(attached.surfaceID, surfaceID)
            XCTAssertEqual(attached.navigationIdentityOverride, original.navigationIdentityOverride)
            XCTAssertEqual(attached.owningProjectIdentifier, original.owningProjectIdentifier)
            XCTAssertEqual(attached.shortcutDefinitions, [shortcut])
            attached.onSplitTerminalRequested?()
            attached.onTemporaryTerminalRequested?()
            attached.onShortcutSelected?(shortcut)
            attached.onAgentPresetSelected?(preset, .standard)
        }

        XCTAssertEqual(splitCount, sources.count)
        XCTAssertEqual(temporaryCount, sources.count)
        XCTAssertEqual(shortcutCount, sources.count)
        XCTAssertEqual(presetCount, sources.count)
    }

    func testDetachedTemporaryShortcutRouterDispatchesCurrentNestedAndPermanentExactlyOnce() {
        var current = 0
        var temporary = 0
        var permanent = 0
        let callbacks = (
            current: { current += 1 },
            temporary: { temporary += 1 },
            permanent: { permanent += 1 }
        )

        for behavior in TerminalShortcutLaunchBehavior.allCases {
            SpotlightTransientShortcutRouter.route(
                TerminalShortcutDefinition(name: "Route", command: "echo route", launchBehavior: behavior),
                current: callbacks.current,
                temporary: callbacks.temporary,
                permanent: callbacks.permanent
            )
        }

        XCTAssertEqual(current, 1)
        XCTAssertEqual(temporary, 1)
        XCTAssertEqual(permanent, 1)
    }

    func testDetachedPermanentStandaloneShortcutCreatesTileOnlyOnOriginatingSurface() throws {
        XCTAssertTrue(store.addTile(projectPath: nil, directoryURL: root, preferStandalone: true))
        let seed = try XCTUnwrap(store.layout.tiles.first)
        let detachedID = store.createDetachedSurface(
            with: try XCTUnwrap(store.detachTile(seed.id)),
            title: "Detached"
        )
        let primaryCount = store.layout(for: store.primarySurfaceID).tileCount
        let detachedCount = store.layout(for: detachedID).tileCount
        let shortcut = TerminalShortcutDefinition(
            name: "Permanent",
            command: "echo permanent",
            launchBehavior: .newPermanentTerminal
        )

        XCTAssertTrue(DetachedPermanentShortcutTileLauncher.launch(
            shortcut,
            directoryURL: root,
            owningProjectRootURL: nil,
            surfaceID: detachedID,
            boardStore: store
        ))
        XCTAssertEqual(store.layout(for: detachedID).tileCount, detachedCount + 1)
        XCTAssertEqual(store.layout(for: store.primarySurfaceID).tileCount, primaryCount)
        XCTAssertEqual(
            store.spotlightTerminalItems(
                surfaceID: detachedID,
                projects: [],
                includeProjectTerminals: true
            ).count,
            detachedCount + 1
        )
    }

    private func temporaryState(id: UUID, surfaceID: UUID) -> TerminalSpotlightState {
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: root,
            terminalServices: container.terminalServices,
            shellResolutionProvider: { TerminalShellResolver.resolve(context: .init()) }
        )
        return TerminalSpotlightState(
            id: id,
            source: .transient(session: session),
            title: "Temporary",
            accentColor: nil,
            workingDirectoryURL: root,
            onSplitTerminalRequested: {},
            onTemporaryTerminalRequested: {},
            isTemporary: true,
            owningProjectRootURL: nil,
            surfaceID: surfaceID
        )
    }
}
