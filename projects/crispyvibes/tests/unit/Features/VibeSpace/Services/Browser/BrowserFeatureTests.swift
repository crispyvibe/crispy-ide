import XCTest
import WebKit
@testable import CrispyVibes

final class BrowserSessionSnapshotTests: XCTestCase {

    func testSnapshotRoundTrip() throws {
        let snapshot = BrowserSessionSnapshot(
            urlString: "https://example.com",
            backHistoryURLStrings: ["https://a.com", "https://b.com"],
            forwardHistoryURLStrings: ["https://c.com"],
            pageZoom: 1.5
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(BrowserSessionSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testSnapshotDefaultValues() {
        let snapshot = BrowserSessionSnapshot()
        XCTAssertNil(snapshot.urlString)
        XCTAssertTrue(snapshot.backHistoryURLStrings.isEmpty)
        XCTAssertTrue(snapshot.forwardHistoryURLStrings.isEmpty)
        XCTAssertEqual(snapshot.pageZoom, 1.0)
    }

    func testSnapshotRoundTripPreservesThemeMode() throws {
        let snapshot = BrowserSessionSnapshot(
            urlString: "https://example.com",
            pageZoom: 1.2,
            themeMode: BrowserPanelViewModel.BrowserThemeMode.dark.rawValue
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(BrowserSessionSnapshot.self, from: data)

        XCTAssertEqual(decoded.themeMode, BrowserPanelViewModel.BrowserThemeMode.dark.rawValue)
    }
}

final class BrowserTileContentKindCodableTests: XCTestCase {

    func testBrowserTileContentKindRoundTrip() throws {
        let kind = TileContentKind.browser(URL(string: "https://example.com/path?q=1")!)
        let data = try JSONEncoder().encode(kind)
        let decoded = try JSONDecoder().decode(TileContentKind.self, from: data)
        XCTAssertEqual(decoded, kind)
    }

    func testBrowserTileContentKindDecodesURLCorrectly() throws {
        let json = #"{"type":"browser","filePath":"https://localhost:3000/api"}"#
        let decoded = try JSONDecoder().decode(TileContentKind.self, from: json.data(using: .utf8)!)
        if case .browser(let url) = decoded {
            XCTAssertEqual(url.absoluteString, "https://localhost:3000/api")
            XCTAssertEqual(url.scheme, "https")
        } else {
            XCTFail("Expected .browser, got \(decoded)")
        }
    }

    func testBrowserTileContentKindDoesNotDecodeAsFileURL() throws {
        let json = #"{"type":"browser","filePath":"https://example.com"}"#
        let decoded = try JSONDecoder().decode(TileContentKind.self, from: json.data(using: .utf8)!)
        if case .browser(let url) = decoded {
            XCTAssertFalse(url.isFileURL, "Browser URL should not be a file URL")
        } else {
            XCTFail("Expected .browser")
        }
    }

    func testBrowserTileSessionPersistsInline() throws {
        var tile = VibeSpaceTerminalBoardTile(
            workingDirectoryPath: "/tmp",
            contentKind: .browser(URL(string: "https://example.com")!)
        )
        tile.browserSession = BrowserSessionSnapshot(
            urlString: "https://example.com/page",
            backHistoryURLStrings: ["https://example.com"],
            pageZoom: 2.0
        )
        let data = try JSONEncoder().encode(tile)
        let decoded = try JSONDecoder().decode(VibeSpaceTerminalBoardTile.self, from: data)
        XCTAssertNotNil(decoded.browserSession)
        XCTAssertEqual(decoded.browserSession?.urlString, "https://example.com/page")
        XCTAssertEqual(decoded.browserSession?.pageZoom, 2.0)
        XCTAssertEqual(decoded.browserSession?.backHistoryURLStrings, ["https://example.com"])
    }

    func testMinimizedBrowserTilePreservesSession() throws {
        var layout = VibeSpaceTerminalBoardLayout.empty
        var tile = VibeSpaceTerminalBoardTile(
            workingDirectoryPath: "",
            contentKind: .browser(URL(string: "https://test.com")!)
        )
        tile.browserSession = BrowserSessionSnapshot(urlString: "https://test.com", pageZoom: 1.25)
        layout.minimizedTiles = [tile]
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(VibeSpaceTerminalBoardLayout.self, from: data)
        XCTAssertEqual(decoded.minimizedTiles.count, 1)
        XCTAssertEqual(decoded.minimizedTiles.first?.browserSession?.urlString, "https://test.com")
        XCTAssertEqual(decoded.minimizedTiles.first?.browserSession?.pageZoom, 1.25)
    }
}

final class BrowserTabReferenceTests: XCTestCase {

    func testBrowserTabReferenceRoundTripPreservesLinkedTileAndProjectPath() throws {
        let linkedTileID = UUID()
        let reference = BrowserTabReference(
            browserID: UUID(),
            url: URL(string: "https://example.com/app")!,
            projectPath: "/tmp/project",
            linkedTileID: linkedTileID
        )

        let data = try JSONEncoder().encode(reference)
        let decoded = try JSONDecoder().decode(BrowserTabReference.self, from: data)

        XCTAssertEqual(decoded, reference)
        XCTAssertEqual(decoded.seedURL?.absoluteString, "https://example.com/app")
        XCTAssertEqual(decoded.projectPath, "/tmp/project")
        XCTAssertEqual(decoded.linkedTileID, linkedTileID)
    }
}

@MainActor
final class SpotlightRestoreDescriptorTests: XCTestCase {
    func testDescriptorPreservesExactStateIdentitySurfaceAndCallbacks() {
        let surfaceID = UUID()
        var actionCount = 0
        let state = TerminalSpotlightState(
            id: UUID(),
            source: .browser(tileID: UUID(), url: URL(string: "https://example.com")!),
            title: "Browser",
            accentColor: nil,
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            onSplitTerminalRequested: { actionCount += 1 },
            onTemporaryTerminalRequested: {},
            isTemporary: false,
            owningProjectRootURL: nil,
            surfaceID: surfaceID
        )
        let descriptor = SpotlightRestoreDescriptor(spotlight: state)

        XCTAssertEqual(descriptor.spotlight.id, state.id)
        XCTAssertEqual(descriptor.spotlight.surfaceID, surfaceID)
        XCTAssertEqual(descriptor.spotlight.navigationIdentity, state.navigationIdentity)
        descriptor.spotlight.onSplitTerminalRequested?()
        XCTAssertEqual(actionCount, 1)
    }

    func testBrowserPreviewDescriptorRefreshesSnapshotWithoutDroppingStableState() throws {
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        let initial = BrowserSessionSnapshot(urlString: "https://example.com")
        let refreshed = BrowserSessionSnapshot(
            urlString: "https://example.com/current",
            backHistoryURLStrings: ["https://example.com/start"],
            pageZoom: 1.25
        )
        let state = TerminalSpotlightState(
            id: UUID(), source: .browserPreview(snapshot: initial), title: "Browser",
            accentColor: nil, workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            onSplitTerminalRequested: nil, onTemporaryTerminalRequested: nil,
            isTemporary: true, owningProjectRootURL: nil, surfaceID: UUID()
        )
        coordinator.setSpotlight(state, animated: false)
        let descriptor = try XCTUnwrap(coordinator.descriptorForCurrentSpotlight {
            refreshed
        })

        XCTAssertEqual(descriptor.spotlight.id, state.id)
        XCTAssertEqual(descriptor.spotlight.surfaceID, state.surfaceID)
        guard case let .browserPreview(snapshot) = descriptor.spotlight.source else {
            return XCTFail("Expected browser preview state")
        }
        XCTAssertEqual(snapshot, refreshed)
        coordinator.dismiss(animated: false)
    }
}

final class DockedBrowserCoordinatorTests: XCTestCase {

    @MainActor
    func testRemoveAllClearsGroupsAndPreview() {
        let coordinator = DockedBrowserCoordinator()
        let vm1 = coordinator.viewModel(for: UUID(), url: URL(string: "https://a.com")!)
        XCTAssertNotNil(vm1)
        coordinator.showPreview(for: URL(string: "https://b.com")!)
        XCTAssertTrue(coordinator.hasPreview)

        coordinator.removeAll()
        XCTAssertFalse(coordinator.hasPreview)
        XCTAssertNil(coordinator.previewURL)
        XCTAssertNil(coordinator.previewSessionSnapshot)
    }

    @MainActor
    func testPromotePreviewMovesVMToTileGroup() {
        let coordinator = DockedBrowserCoordinator()
        coordinator.showPreview(for: URL(string: "https://example.com")!)
        XCTAssertTrue(coordinator.hasPreview)
        XCTAssertTrue(coordinator.previewViewModel?.usesEphemeralDataStore == true)

        let tileID = UUID()
        coordinator.promotePreview(to: tileID)
        XCTAssertFalse(coordinator.hasPreview)

        let vm = coordinator.viewModel(for: tileID, url: URL(string: "https://example.com")!)
        XCTAssertNotNil(vm)
        XCTAssertFalse(vm.usesEphemeralDataStore)
    }

    @MainActor
    func testRestorePreviewUsesEphemeralDataStore() {
        let coordinator = DockedBrowserCoordinator()
        let snapshot = BrowserSessionSnapshot(urlString: "https://example.com/page")

        let vm = coordinator.restorePreview(from: snapshot, projectPath: "/vibespace/project")

        XCTAssertTrue(vm.usesEphemeralDataStore)
    }

    @MainActor
    func testRestorePreviewRebuildsSessionFromSnapshot() {
        let coordinator = DockedBrowserCoordinator()
        let snapshot = BrowserSessionSnapshot(
            urlString: "https://example.com/page",
            backHistoryURLStrings: ["https://example.com/start"],
            forwardHistoryURLStrings: ["https://example.com/next"],
            pageZoom: 1.75
        )

        let vm = coordinator.restorePreview(from: snapshot, projectPath: "/vibespace/project")

        XCTAssertTrue(coordinator.hasPreview)
        XCTAssertEqual(coordinator.previewProjectPath, "/vibespace/project")
        XCTAssertEqual(vm.currentURL?.absoluteString, "https://example.com/page")
        XCTAssertEqual(vm.restoredBackStack.map { $0.absoluteString }, ["https://example.com/start"])
        XCTAssertEqual(vm.restoredForwardStack.map { $0.absoluteString }, ["https://example.com/next"])
        XCTAssertEqual(coordinator.previewSessionSnapshot?.pageZoom, 1.75)
    }

    @MainActor
    func testRestorePreviewDoesNotReuseMatchingSnapshotAcrossProjectPaths() {
        let coordinator = DockedBrowserCoordinator()
        let snapshot = BrowserSessionSnapshot(
            urlString: "https://example.com/page",
            backHistoryURLStrings: ["https://example.com/start"],
            pageZoom: 1.25,
            themeMode: BrowserPanelViewModel.BrowserThemeMode.system.rawValue
        )

        let first = coordinator.restorePreview(from: snapshot, projectPath: "/vibespace/a")
        let second = coordinator.restorePreview(from: snapshot, projectPath: "/vibespace/b")

        XCTAssertFalse(first === second)
        XCTAssertEqual(second.projectPath, "/vibespace/b")
        XCTAssertEqual(coordinator.previewProjectPath, "/vibespace/b")
    }

    @MainActor
    func testPreviewSnapshotUsesLiveViewModelStateWhenAvailable() {
        let coordinator = DockedBrowserCoordinator()
        let vm = BrowserPanelViewModel()
        let snapshot = BrowserSessionSnapshot(
            urlString: "https://example.com/live",
            backHistoryURLStrings: ["https://example.com/start"]
        )
        vm.restoreSession(snapshot)
        coordinator.setPreviewViewModel(
            vm,
            url: URL(string: "https://example.com/live")!,
            projectPath: "/vibespace/project"
        )

        let liveSnapshot = coordinator.previewSnapshot()

        XCTAssertEqual(liveSnapshot?.urlString, "https://example.com/live")
        XCTAssertEqual(liveSnapshot?.backHistoryURLStrings, ["https://example.com/start"])
        XCTAssertEqual(coordinator.previewProjectPath, "/vibespace/project")
    }

    @MainActor
    func testSnapshotBrowserSessionsReturnsOnlyBrowserTiles() {
        let coordinator = DockedBrowserCoordinator()
        let tileID = UUID()
        _ = coordinator.viewModel(for: tileID, url: URL(string: "https://example.com")!)
        let otherID = UUID()

        let snapshots = coordinator.snapshotBrowserSessions(for: [tileID, otherID])
        XCTAssertNotNil(snapshots[tileID])
        XCTAssertNil(snapshots[otherID])
    }

    @MainActor
    func testSnapshotDetailedBrowserFallsBackToLinkedTileSnapshot() {
        let coordinator = DockedBrowserCoordinator()
        let tileID = UUID()
        let tileSnapshot = BrowserSessionSnapshot(
            urlString: "https://example.com/dashboard",
            pageZoom: 1.8
        )
        coordinator.restoreTile(id: tileID, snapshot: tileSnapshot)

        let reference = BrowserTabReference(
            browserID: UUID(),
            url: URL(string: "https://example.com/start")!,
            projectPath: "/vibespace/project",
            linkedTileID: tileID
        )

        let detailedSnapshot = coordinator.snapshotDetailedBrowser(for: reference)

        XCTAssertEqual(detailedSnapshot?.urlString, "https://example.com/dashboard")
        XCTAssertEqual(detailedSnapshot?.pageZoom, 1.8)
    }

    @MainActor
    func testPromotePreviewCarriesLivePreviewSessionStateIntoTile() {
        let coordinator = DockedBrowserCoordinator()
        let previewURL = URL(string: "https://example.com/persisted")!
        let snapshot = BrowserSessionSnapshot(
            urlString: previewURL.absoluteString,
            backHistoryURLStrings: ["https://example.com/start"],
            pageZoom: 1.5
        )
        let previewViewModel = BrowserPanelViewModel()
        previewViewModel.restoreSession(snapshot)
        coordinator.setPreviewViewModel(
            previewViewModel,
            url: previewURL,
            projectPath: "/vibespace/project"
        )

        let tileID = UUID()
        coordinator.promotePreview(to: tileID)
        let promotedViewModel = coordinator.viewModel(for: tileID, url: URL(string: "https://example.com/fallback")!)

        XCTAssertEqual(promotedViewModel.currentURL?.absoluteString, "https://example.com/persisted")
        XCTAssertEqual(promotedViewModel.restoredBackStack.map(\.absoluteString), ["https://example.com/start"])
        XCTAssertEqual(promotedViewModel.zoomScale, 1.5)
        XCTAssertFalse(coordinator.hasPreview)
    }

    @MainActor
    func testLinkedDetailedBrowserSnapshotFeedsTilePersistence() {
        let coordinator = DockedBrowserCoordinator()
        let tileID = UUID()
        let reference = BrowserTabReference(
            browserID: UUID(),
            url: URL(string: "https://google.com/start")!,
            projectPath: "/vibespace/project",
            linkedTileID: tileID
        )
        let snapshot = BrowserSessionSnapshot(
            urlString: "https://google.com/dashboard",
            pageZoom: 1.6
        )

        coordinator.restoreDetailedBrowser(reference: reference, snapshot: snapshot)

        let snapshots = coordinator.snapshotBrowserSessions(for: [tileID])
        XCTAssertEqual(snapshots[tileID]?.urlString, "https://google.com/dashboard")
        XCTAssertEqual(snapshots[tileID]?.pageZoom, 1.6)
    }

    @MainActor
    func testLinkedDetailedBrowserLiveZoomFeedsTilePersistence() {
        let coordinator = DockedBrowserCoordinator()
        let tileID = UUID()
        coordinator.restoreTile(
            id: tileID,
            snapshot: BrowserSessionSnapshot(
                urlString: "https://example.com/original",
                pageZoom: 1.2
            )
        )
        let reference = BrowserTabReference(
            browserID: UUID(),
            url: URL(string: "https://example.com/original")!,
            projectPath: "/vibespace/project",
            linkedTileID: tileID
        )

        let detailedViewModel = coordinator.viewModel(for: reference)
        detailedViewModel.zoomIn()

        let snapshots = coordinator.snapshotBrowserSessions(for: [tileID])
        XCTAssertEqual(snapshots[tileID]?.urlString, "https://example.com/original")
        XCTAssertEqual(snapshots[tileID]?.pageZoom ?? 0, 1.3, accuracy: 0.0001)
    }

    @MainActor
    func testPreviewNewWindowRoutingUsesPreviewProjectPath() {
        let coordinator = DockedBrowserCoordinator()
        var routedURL: URL?
        var routedProjectPath: String?
        coordinator.onOpenNewBrowser = { url, projectPath in
            routedURL = url
            routedProjectPath = projectPath
        }
        coordinator.showPreview(
            for: URL(string: "https://example.com")!,
            projectPath: "/vibespace/preview"
        )

        let childURL = URL(string: "https://example.com/new-window")!
        coordinator.previewViewModel?.onOpenNewBrowser?(childURL)

        XCTAssertEqual(routedURL, childURL)
        XCTAssertEqual(routedProjectPath, "/vibespace/preview")
    }

    @MainActor
    func testTileNewWindowRoutingUsesTileProjectPath() {
        let coordinator = DockedBrowserCoordinator()
        let tileID = UUID()
        coordinator.projectPathForTile = { requestedTileID in
            requestedTileID == tileID ? "/vibespace/tile" : nil
        }
        var routedURL: URL?
        var routedProjectPath: String?
        coordinator.onOpenNewBrowser = { url, projectPath in
            routedURL = url
            routedProjectPath = projectPath
        }

        let tileViewModel = coordinator.viewModel(for: tileID, url: URL(string: "https://example.com")!)
        let childURL = URL(string: "https://example.com/from-tile")!
        tileViewModel.onOpenNewBrowser?(childURL)

        XCTAssertEqual(routedURL, childURL)
        XCTAssertEqual(routedProjectPath, "/vibespace/tile")
    }

    @MainActor
    func testDetailedBrowserNewWindowRoutingUsesReferenceProjectPath() {
        let coordinator = DockedBrowserCoordinator()
        let reference = BrowserTabReference(
            browserID: UUID(),
            url: URL(string: "https://example.com/detail")!,
            projectPath: "/vibespace/detail"
        )
        var routedURL: URL?
        var routedProjectPath: String?
        coordinator.onOpenNewBrowser = { url, projectPath in
            routedURL = url
            routedProjectPath = projectPath
        }

        let detailedViewModel = coordinator.viewModel(for: reference)
        let childURL = URL(string: "https://example.com/from-detail")!
        detailedViewModel.onOpenNewBrowser?(childURL)

        XCTAssertEqual(routedURL, childURL)
        XCTAssertEqual(routedProjectPath, "/vibespace/detail")
    }

    @MainActor
    func testRemoveDetailedBrowserClearsCachedDetailedSnapshot() {
        let coordinator = DockedBrowserCoordinator()
        let reference = BrowserTabReference(
            browserID: UUID(),
            url: URL(string: "https://example.com/start")!,
            projectPath: "/vibespace/project"
        )
        let snapshot = BrowserSessionSnapshot(
            urlString: "https://example.com/current",
            pageZoom: 1.3
        )

        coordinator.restoreDetailedBrowser(reference: reference, snapshot: snapshot)
        coordinator.removeDetailedBrowser(browserID: reference.browserID)

        let restoredFallback = coordinator.snapshotDetailedBrowser(for: reference)
        XCTAssertEqual(restoredFallback?.urlString, "https://example.com/start")
        XCTAssertEqual(restoredFallback?.pageZoom, 1.0)
    }

    @MainActor
    func testBrowserHostOwnershipCoordinatorAllowsHigherPriorityHostToPreempt() {
        let coordinator = BrowserHostOwnershipCoordinator()
        let boardHost = BrowserOwnershipHostStub(priority: 200, canParticipate: true)
        let spotlightHost = BrowserOwnershipHostStub(priority: 300, canParticipate: true)
        coordinator.registerHost(boardHost)
        coordinator.registerHost(spotlightHost)

        XCTAssertTrue(coordinator.ensureOwnership(ownerID: boardHost.sessionOwnershipID, canParticipate: true))
        XCTAssertTrue(coordinator.ensureOwnership(ownerID: spotlightHost.sessionOwnershipID, canParticipate: true))
        XCTAssertFalse(coordinator.ensureOwnership(ownerID: boardHost.sessionOwnershipID, canParticipate: true))
    }

    @MainActor
    func testBrowserHostOwnershipCoordinatorRejectsNonParticipatingHost() {
        let coordinator = BrowserHostOwnershipCoordinator()
        let host = BrowserOwnershipHostStub(priority: 300, canParticipate: false)
        coordinator.registerHost(host)

        XCTAssertFalse(coordinator.ensureOwnership(ownerID: host.sessionOwnershipID, canParticipate: false))
    }
}

@MainActor
private final class BrowserOwnershipHostStub: BrowserSessionOwnershipHost {
    let sessionOwnershipID = UUID()
    let ownershipArbitrationPriority: Int
    let canParticipateInOwnershipArbitration: Bool

    init(priority: Int, canParticipate: Bool) {
        self.ownershipArbitrationPriority = priority
        self.canParticipateInOwnershipArbitration = canParticipate
    }

    func retryOwnershipAcquisition() {}
}


@MainActor
final class BrowserNavigationRegressionTests: XCTestCase {
    func testRestoredHistoryOrdinaryNavigationAndSyntheticTraversalKeepStackOrderingWithoutDuplicates() {
        let a = URL(string: "file:///tmp/crispy-browser-navigation/A")!
        let b = URL(string: "file:///tmp/crispy-browser-navigation/B")!
        let c = URL(string: "file:///tmp/crispy-browser-navigation/C")!
        let d = URL(string: "file:///tmp/crispy-browser-navigation/D")!
        let viewModel = BrowserPanelViewModel()
        viewModel.restoreSession(
            BrowserSessionSnapshot(
                urlString: c.absoluteString,
                backHistoryURLStrings: [a.absoluteString, b.absoluteString]
            )
        )
        viewModel.handleNavigationFinished(url: c, title: "C")

        XCTAssertTrue(viewModel.handleMainFrameNavigationAction(
            BrowserMainFrameNavigationAction(
                url: d,
                navigationType: .linkActivated,
                sourceURL: c
            )
        ))
        viewModel.handleNavigationFinished(url: d, title: "D")
        assertHistory(viewModel, current: d, back: [a, b, c], forward: [])

        viewModel.goBack()
        viewModel.handleNavigationFinished(url: c, title: "C")
        assertHistory(viewModel, current: c, back: [a, b], forward: [d])

        viewModel.goBack()
        viewModel.handleNavigationFinished(url: b, title: "B")
        assertHistory(viewModel, current: b, back: [a], forward: [c, d])

        viewModel.goForward()
        viewModel.handleNavigationFinished(url: c, title: "C")
        assertHistory(viewModel, current: c, back: [a, b], forward: [d])

        viewModel.goForward()
        viewModel.handleNavigationFinished(url: d, title: "D")
        assertHistory(viewModel, current: d, back: [a, b, c], forward: [])
        XCTAssertEqual(Set(viewModel.restoredBackStack).count, viewModel.restoredBackStack.count)
    }

    func testLinkedReferenceCanonicalizesBrowserIDToTileID() {
        let suppliedBrowserID = UUID()
        let tileID = UUID()

        let reference = BrowserTabReference(
            browserID: suppliedBrowserID,
            url: URL(string: "file:///tmp/crispy-browser-navigation")!,
            projectPath: "/projects/app",
            linkedTileID: tileID
        )

        XCTAssertEqual(reference.browserID, tileID)
        XCTAssertNotEqual(reference.browserID, suppliedBrowserID)
    }

    func testLinkedDetailUsesIdenticalTileViewModelAndClosingDetailPreservesLatestTileSession() {
        let coordinator = DockedBrowserCoordinator()
        let tileID = UUID()
        let initial = BrowserSessionSnapshot(urlString: "file:///tmp/crispy-browser-navigation/start")
        coordinator.restoreTile(id: tileID, snapshot: initial)
        let tileViewModel = coordinator.viewModel(
            for: tileID,
            url: URL(string: "file:///tmp/crispy-browser-navigation/fallback")!
        )
        let latest = BrowserSessionSnapshot(
            urlString: "file:///tmp/crispy-browser-navigation/latest",
            backHistoryURLStrings: ["file:///tmp/crispy-browser-navigation/start"],
            pageZoom: 1.4
        )
        tileViewModel.restoreSession(latest)
        let reference = BrowserTabReference(
            browserID: UUID(),
            url: URL(string: "file:///tmp/crispy-browser-navigation/start")!,
            projectPath: "/projects/app",
            linkedTileID: tileID
        )

        let detailedViewModel = coordinator.viewModel(for: reference)
        XCTAssertTrue(detailedViewModel === tileViewModel)

        coordinator.removeDetailedBrowser(browserID: reference.browserID)

        let survivingTileViewModel = coordinator.viewModel(
            for: tileID,
            url: URL(string: "file:///tmp/crispy-browser-navigation/fallback")!
        )
        XCTAssertTrue(survivingTileViewModel === tileViewModel)
        let persisted = coordinator.snapshotBrowserSessions(for: [tileID])[tileID]
        XCTAssertEqual(persisted?.urlString, latest.urlString)
        XCTAssertEqual(persisted?.backHistoryURLStrings, latest.backHistoryURLStrings)
        XCTAssertEqual(coordinator.currentURLs(for: [tileID])[tileID]?.absoluteString, latest.urlString)
    }

    func testMatchingLivePreviewContinuesAfterNavigationWithoutViewModelReplacement() {
        let coordinator = DockedBrowserCoordinator()
        let projectPath = "/projects/app"
        let initial = BrowserSessionSnapshot(urlString: "file:///tmp/crispy-browser-navigation/start")
        let live = coordinator.restorePreview(from: initial, projectPath: projectPath)
        let navigated = BrowserSessionSnapshot(
            urlString: "file:///tmp/crispy-browser-navigation/current",
            backHistoryURLStrings: ["file:///tmp/crispy-browser-navigation/start"],
            pageZoom: 1.2,
            themeMode: BrowserPanelViewModel.BrowserThemeMode.system.rawValue
        )
        live.restoreSession(navigated)

        let restored = coordinator.restorePreview(from: navigated, projectPath: projectPath)

        XCTAssertTrue(restored === live)
        XCTAssertEqual(restored.currentURL?.absoluteString, navigated.urlString)
        XCTAssertEqual(restored.sessionSnapshot(), navigated)
    }

    func testPreviewPromotionCarriesCompleteSessionAndCommentsPresentation() {
        let coordinator = DockedBrowserCoordinator()
        let snapshot = BrowserSessionSnapshot(
            urlString: "file:///tmp/crispy-browser-navigation/current",
            backHistoryURLStrings: ["file:///tmp/crispy-browser-navigation/A", "file:///tmp/crispy-browser-navigation/B"],
            forwardHistoryURLStrings: ["file:///tmp/crispy-browser-navigation/D"],
            pageZoom: 1.6,
            themeMode: BrowserPanelViewModel.BrowserThemeMode.dark.rawValue
        )
        let preview = coordinator.restorePreview(from: snapshot, projectPath: "/projects/app")
        preview.commentsPanel.reveal(threadID: "thread-1")
        preview.commentsPanel.widthFraction = 0.42
        preview.commentsPanel.statusFilter = .resolved
        preview.commentsPanel.searchQuery = "navigation"
        let tileID = UUID()

        coordinator.promotePreview(to: tileID, snapshot: snapshot)
        let promoted = coordinator.viewModel(
            for: tileID,
            url: URL(string: "file:///tmp/crispy-browser-navigation/fallback")!
        )

        XCTAssertEqual(promoted.sessionSnapshot(), snapshot)
        XCTAssertEqual(promoted.currentURL?.absoluteString, snapshot.urlString)
        XCTAssertEqual(promoted.zoomScale, 1.6, accuracy: 0.0001)
        XCTAssertTrue(promoted.commentsPanel.isOpen)
        XCTAssertEqual(promoted.commentsPanel.selectedThreadID, "thread-1")
        XCTAssertEqual(promoted.commentsPanel.widthFraction, 0.42, accuracy: 0.0001)
        XCTAssertEqual(promoted.commentsPanel.statusFilter, .resolved)
        XCTAssertEqual(promoted.commentsPanel.searchQuery, "navigation")
        XCTAssertFalse(coordinator.hasPreview)
    }

    func testBoardSnapshotEnrichmentIncludesDetachedAndMinimizedBrowserTiles() {
        let minimizedID = UUID()
        let detachedID = UUID()
        let detachedSurfaceID = UUID()
        let minimized = VibeSpaceTerminalBoardTile(
            id: minimizedID,
            workingDirectoryPath: "",
            contentKind: .browser(URL(string: "file:///tmp/crispy-browser-navigation/minimized-old")!)
        )
        let detached = VibeSpaceTerminalBoardTile(
            id: detachedID,
            workingDirectoryPath: "",
            contentKind: .browser(URL(string: "file:///tmp/crispy-browser-navigation/detached-old")!)
        )
        let primaryLayout = VibeSpaceTerminalBoardLayout(
            columns: [],
            activeTileID: nil,
            minimizedTiles: [minimized]
        )
        let state = VibeSpaceTerminalBoardState(surfaces: [
            VibeSpaceTerminalBoardSurface(
                id: VibeSpaceTerminalBoardState.primarySurfaceID,
                kind: .primary,
                layout: primaryLayout,
                title: "Primary",
                isOpen: true
            ),
            VibeSpaceTerminalBoardSurface(
                id: detachedSurfaceID,
                kind: .detached,
                layout: VibeSpaceTerminalBoardLayout(
                    columns: [VibeSpaceTerminalBoardColumn(tiles: [detached])],
                    activeTileID: detachedID
                ),
                title: "Detached",
                isOpen: true
            )
        ])
        let providers = BoardSnapshotProviders(
            browserCurrentURL: { tileID in
                URL(string: "file:///tmp/crispy-browser-navigation/\(tileID == minimizedID ? "minimized" : "detached")")
            },
            browserSession: { tileID in
                BrowserSessionSnapshot(urlString: "file:///tmp/crispy-browser-navigation/\(tileID.uuidString)")
            }
        )

        let enriched = providers.enriched(state)

        let enrichedMinimized = enriched.primaryLayout.minimizedTiles.first
        let enrichedDetached = enriched.layout(for: detachedSurfaceID).tile(for: detachedID)
        XCTAssertEqual(enrichedMinimized?.browserURL?.absoluteString, "file:///tmp/crispy-browser-navigation/minimized")
        XCTAssertEqual(enrichedMinimized?.browserSession?.urlString, "file:///tmp/crispy-browser-navigation/\(minimizedID.uuidString)")
        XCTAssertEqual(enrichedDetached?.browserURL?.absoluteString, "file:///tmp/crispy-browser-navigation/detached")
        XCTAssertEqual(enrichedDetached?.browserSession?.urlString, "file:///tmp/crispy-browser-navigation/\(detachedID.uuidString)")
    }

    func testBrowserMouseBackAndForwardCallbacksRouteThroughViewModelHistory() {
        let a = URL(string: "file:///tmp/crispy-browser-navigation/A")!
        let b = URL(string: "file:///tmp/crispy-browser-navigation/B")!
        let c = URL(string: "file:///tmp/crispy-browser-navigation/C")!
        let viewModel = BrowserPanelViewModel()
        viewModel.restoreSession(
            BrowserSessionSnapshot(
                urlString: c.absoluteString,
                backHistoryURLStrings: [a.absoluteString, b.absoluteString]
            )
        )
        XCTAssertNotNil(viewModel.webView.onNavigateBack)
        XCTAssertNotNil(viewModel.webView.onNavigateForward)

        viewModel.webView.onNavigateBack?()
        viewModel.handleNavigationFinished(url: b, title: nil)
        assertHistory(viewModel, current: b, back: [a], forward: [c])

        viewModel.webView.onNavigateForward?()
        viewModel.handleNavigationFinished(url: c, title: nil)
        assertHistory(viewModel, current: c, back: [a, b], forward: [])
    }

    func testSPAPopReconcilesMultiEntryBackAndForwardTransitions() {
        let a = URL(string: "file:///tmp/crispy-browser-navigation/A")!
        let b = URL(string: "file:///tmp/crispy-browser-navigation/B")!
        let c = URL(string: "file:///tmp/crispy-browser-navigation/C")!
        let d = URL(string: "file:///tmp/crispy-browser-navigation/D")!
        let e = URL(string: "file:///tmp/crispy-browser-navigation/E")!
        let f = URL(string: "file:///tmp/crispy-browser-navigation/F")!
        let viewModel = BrowserPanelViewModel()
        viewModel.restoreSession(BrowserSessionSnapshot(
            urlString: d.absoluteString,
            backHistoryURLStrings: [a, b, c].map(\.absoluteString),
            forwardHistoryURLStrings: [e, f].map(\.absoluteString)
        ))
        viewModel.handleNavigationFinished(url: d, title: nil)

        viewModel.handleObservedRouteChange(to: b, kind: .pop)
        assertHistory(viewModel, current: b, back: [a], forward: [c, d, e, f])

        viewModel.handleObservedRouteChange(to: e, kind: .pop)
        assertHistory(viewModel, current: e, back: [a, b, c, d], forward: [f])
    }

    func testRestoredSwipeGesturesRemainEnabledAndBackForwardActionUsesLogicalHistory() {
        let a = URL(string: "file:///tmp/crispy-browser-navigation/A")!
        let b = URL(string: "file:///tmp/crispy-browser-navigation/B")!
        let c = URL(string: "file:///tmp/crispy-browser-navigation/C")!
        let d = URL(string: "file:///tmp/crispy-browser-navigation/D")!
        let e = URL(string: "file:///tmp/crispy-browser-navigation/E")!
        let viewModel = BrowserPanelViewModel()
        viewModel.restoreSession(BrowserSessionSnapshot(
            urlString: c.absoluteString,
            backHistoryURLStrings: [a, b].map(\.absoluteString),
            forwardHistoryURLStrings: [d, e].map(\.absoluteString)
        ))
        viewModel.handleNavigationFinished(url: c, title: nil)

        XCTAssertTrue(viewModel.webView.allowsBackForwardNavigationGestures)
        XCTAssertFalse(viewModel.handleMainFrameNavigationAction(
            BrowserMainFrameNavigationAction(
                url: a,
                navigationType: .backForward,
                sourceURL: c
            )
        ))
        viewModel.handleNavigationFinished(url: a, title: nil)

        XCTAssertTrue(viewModel.webView.allowsBackForwardNavigationGestures)
        assertHistory(viewModel, current: a, back: [], forward: [b, c, d, e])
    }

    func testClosingStaleLegacyLinkedCloneCannotRevertHydratedCanonicalTile() throws {
        let coordinator = DockedBrowserCoordinator()
        let tileID = UUID()
        let staleBrowserID = UUID()
        let latestBrowserID = UUID()
        let staleReference = try legacyLinkedReference(
            browserID: staleBrowserID,
            tileID: tileID,
            url: "file:///tmp/crispy-browser-navigation/stale"
        )
        let latestReference = try legacyLinkedReference(
            browserID: latestBrowserID,
            tileID: tileID,
            url: "file:///tmp/crispy-browser-navigation/latest"
        )
        XCTAssertNotEqual(staleReference.browserID, staleReference.linkedTileID)
        XCTAssertNotEqual(latestReference.browserID, latestReference.linkedTileID)

        let staleSnapshot = BrowserSessionSnapshot(
            urlString: "file:///tmp/crispy-browser-navigation/stale",
            backHistoryURLStrings: ["file:///tmp/crispy-browser-navigation/stale-start"]
        )
        let latestSnapshot = BrowserSessionSnapshot(
            urlString: "file:///tmp/crispy-browser-navigation/latest",
            backHistoryURLStrings: [
                "file:///tmp/crispy-browser-navigation/A",
                "file:///tmp/crispy-browser-navigation/B"
            ],
            pageZoom: 1.4,
            themeMode: BrowserPanelViewModel.BrowserThemeMode.system.rawValue
        )
        coordinator.restoreDetailedBrowser(reference: staleReference, snapshot: staleSnapshot)
        coordinator.restoreDetailedBrowser(reference: latestReference, snapshot: latestSnapshot)
        coordinator.restoreTile(
            id: tileID,
            snapshot: BrowserSessionSnapshot(urlString: "file:///tmp/crispy-browser-navigation/hydrated")
        )

        let canonical = coordinator.viewModel(
            for: tileID,
            url: URL(string: "file:///tmp/crispy-browser-navigation/fallback")!
        )
        XCTAssertEqual(canonical.sessionSnapshot(), latestSnapshot)

        coordinator.removeDetailedBrowser(browserID: staleBrowserID)

        let surviving = coordinator.viewModel(
            for: tileID,
            url: URL(string: "file:///tmp/crispy-browser-navigation/fallback")!
        )
        XCTAssertTrue(surviving === canonical)
        XCTAssertEqual(surviving.sessionSnapshot(), latestSnapshot)
        XCTAssertEqual(coordinator.snapshotBrowserSessions(for: [tileID])[tileID], latestSnapshot)
    }

    func testClosingLatestLegacyLinkedDetailKeepsHydratedTileAuthoritativeOverStaleClone() throws {
        let coordinator = DockedBrowserCoordinator()
        let tileID = UUID()
        let staleBrowserID = UUID()
        let latestBrowserID = UUID()
        let staleReference = try legacyLinkedReference(
            browserID: staleBrowserID,
            tileID: tileID,
            url: "file:///tmp/crispy-browser-navigation/stale"
        )
        let latestReference = try legacyLinkedReference(
            browserID: latestBrowserID,
            tileID: tileID,
            url: "file:///tmp/crispy-browser-navigation/latest"
        )
        let staleSnapshot = BrowserSessionSnapshot(
            urlString: "file:///tmp/crispy-browser-navigation/stale",
            backHistoryURLStrings: ["file:///tmp/crispy-browser-navigation/stale-start"]
        )
        let latestSnapshot = BrowserSessionSnapshot(
            urlString: "file:///tmp/crispy-browser-navigation/latest",
            backHistoryURLStrings: ["file:///tmp/crispy-browser-navigation/latest-start"],
            pageZoom: 1.5,
            themeMode: BrowserPanelViewModel.BrowserThemeMode.dark.rawValue
        )
        XCTAssertNotEqual(staleReference.browserID, tileID)
        XCTAssertNotEqual(latestReference.browserID, tileID)

        coordinator.restoreDetailedBrowser(reference: staleReference, snapshot: staleSnapshot)
        coordinator.restoreDetailedBrowser(reference: latestReference, snapshot: latestSnapshot)
        let latestViewModel = coordinator.viewModel(for: latestReference)
        coordinator.restoreTile(
            id: tileID,
            snapshot: BrowserSessionSnapshot(urlString: "file:///tmp/crispy-browser-navigation/hydrated")
        )
        let hydratedTileViewModel = coordinator.viewModel(
            for: tileID,
            url: URL(string: "file:///tmp/crispy-browser-navigation/fallback")!
        )
        XCTAssertTrue(hydratedTileViewModel === latestViewModel)

        coordinator.removeDetailedBrowser(browserID: latestBrowserID)

        let survivingTileViewModel = coordinator.viewModel(
            for: tileID,
            url: URL(string: "file:///tmp/crispy-browser-navigation/fallback")!
        )
        XCTAssertTrue(survivingTileViewModel === latestViewModel)
        XCTAssertEqual(survivingTileViewModel.currentURL?.absoluteString, latestSnapshot.urlString)
        XCTAssertEqual(coordinator.snapshotBrowserSessions(for: [tileID])[tileID], latestSnapshot)
        XCTAssertEqual(coordinator.currentURLs(for: [tileID])[tileID]?.absoluteString, latestSnapshot.urlString)
        let parkedStaleEntry = coordinator.snapshotBrowserSessions(forProjectPath: "/projects/app")
            .first { $0.browserID == staleBrowserID }
        XCTAssertEqual(parkedStaleEntry?.snapshot, latestSnapshot)
    }

    func testAuthoritativeTileWithPendingURLDoesNotPublishStaleLegacyDetailURL() throws {
        let coordinator = DockedBrowserCoordinator()
        let tileID = UUID()
        let staleBrowserID = UUID()
        let latestBrowserID = UUID()
        let staleReference = try legacyLinkedReference(
            browserID: staleBrowserID,
            tileID: tileID,
            url: "file:///tmp/crispy-browser-navigation/stale"
        )
        let latestReference = try legacyLinkedReference(
            browserID: latestBrowserID,
            tileID: tileID,
            url: "file:///tmp/crispy-browser-navigation/latest"
        )
        coordinator.restoreDetailedBrowser(
            reference: staleReference,
            snapshot: BrowserSessionSnapshot(urlString: staleReference.seedURLString)
        )
        coordinator.restoreDetailedBrowser(
            reference: latestReference,
            snapshot: BrowserSessionSnapshot(urlString: latestReference.seedURLString)
        )
        let authoritative = coordinator.viewModel(for: latestReference)
        coordinator.restoreTile(
            id: tileID,
            snapshot: BrowserSessionSnapshot(urlString: "file:///tmp/crispy-browser-navigation/hydrated")
        )
        XCTAssertTrue(coordinator.viewModel(for: tileID, url: URL(string: "about:blank")!) === authoritative)

        authoritative.currentURL = nil
        coordinator.removeDetailedBrowser(browserID: latestBrowserID)

        XCTAssertNil(coordinator.currentURLs(for: [tileID])[tileID])
        XCTAssertTrue(coordinator.viewModel(for: tileID, url: URL(string: "about:blank")!) === authoritative)
    }

    private func legacyLinkedReference(
        browserID: UUID,
        tileID: UUID,
        url: String
    ) throws -> BrowserTabReference {
        let data = try JSONSerialization.data(withJSONObject: [
            "browserID": browserID.uuidString,
            "seedURLString": url,
            "projectPath": "/projects/app",
            "linkedTileID": tileID.uuidString
        ])
        return try JSONDecoder().decode(BrowserTabReference.self, from: data)
    }

    private func assertHistory(
        _ viewModel: BrowserPanelViewModel,
        current: URL,
        back: [URL],
        forward: [URL],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let snapshot = viewModel.sessionSnapshot()
        XCTAssertEqual(snapshot.urlString, current.absoluteString, file: file, line: line)
        XCTAssertEqual(snapshot.backHistoryURLStrings, back.map(\.absoluteString), file: file, line: line)
        XCTAssertEqual(snapshot.forwardHistoryURLStrings, forward.map(\.absoluteString), file: file, line: line)
    }
}


@MainActor
final class BrowserLogicalHistoryRaceTests: XCTestCase {
    func testRestoreAndSnapshotBoundBothStacksWithExternalForwardOrdering() {
        let limit = BrowserPanelViewModel.logicalHistoryLimit
        let back = (0..<(limit + 7)).map { url("back-\($0)") }
        let forward = (0..<(limit + 9)).map { url("forward-\($0)") }
        let current = url("current")
        let viewModel = BrowserPanelViewModel()

        viewModel.restoreSession(BrowserSessionSnapshot(
            urlString: current.absoluteString,
            backHistoryURLStrings: back.map(\.absoluteString),
            forwardHistoryURLStrings: forward.map(\.absoluteString)
        ))

        XCTAssertEqual(viewModel.restoredBackStack, Array(back.suffix(limit)))
        XCTAssertEqual(viewModel.restoredForwardStack, Array(forward.prefix(limit).reversed()))
        let snapshot = viewModel.sessionSnapshot()
        XCTAssertEqual(snapshot.backHistoryURLStrings, back.suffix(limit).map(\.absoluteString))
        XCTAssertEqual(snapshot.forwardHistoryURLStrings, forward.prefix(limit).map(\.absoluteString))
    }

    func testTypedNavigationImmediatelyAfterRestoreSupersedesSyntheticLoadAndRecordsSourceOnce() {
        let a = url("A")
        let b = url("B")
        let c = url("C")
        let d = url("D")
        let viewModel = BrowserPanelViewModel()
        viewModel.restoreSession(BrowserSessionSnapshot(
            urlString: c.absoluteString,
            backHistoryURLStrings: [a, b].map(\.absoluteString)
        ))
        let restoreGeneration = viewModel.pendingNavigationGeneration

        viewModel.navigate(to: d)
        let ordinaryGeneration = viewModel.pendingNavigationGeneration
        XCTAssertNotEqual(ordinaryGeneration, restoreGeneration)
        viewModel.handleNavigationFinished(
            url: c,
            title: "stale restore",
            navigationGeneration: restoreGeneration
        )
        viewModel.handleNavigationFinished(
            url: d,
            title: "D",
            navigationGeneration: ordinaryGeneration
        )

        assertHistory(viewModel, current: d, back: [a, b, c], forward: [])
    }

    func testTypedNavigationDuringPendingBackRollsBackTraversalAndIgnoresStaleFinish() {
        let a = url("A")
        let b = url("B")
        let c = url("C")
        let d = url("D")
        let viewModel = restoredViewModel(current: c, back: [a, b], forward: [])

        viewModel.goBack()
        let backGeneration = viewModel.pendingNavigationGeneration
        viewModel.navigate(to: d)
        let ordinaryGeneration = viewModel.pendingNavigationGeneration
        viewModel.handleNavigationFinished(
            url: b,
            title: "stale back",
            navigationGeneration: backGeneration
        )
        viewModel.handleNavigationFinished(
            url: d,
            title: "D",
            navigationGeneration: ordinaryGeneration
        )

        assertHistory(viewModel, current: d, back: [a, b, c], forward: [])
    }

    func testClickDuringPendingForwardSupersedesTraversalWithoutDuplicateOrSkippedEntries() {
        let a = url("A")
        let b = url("B")
        let c = url("C")
        let d = url("D")
        let e = url("E")
        let viewModel = restoredViewModel(current: b, back: [a], forward: [c, d])

        viewModel.goForward()
        let forwardGeneration = viewModel.pendingNavigationGeneration
        XCTAssertTrue(viewModel.handleMainFrameNavigationAction(
            BrowserMainFrameNavigationAction(
                url: e,
                navigationType: .linkActivated,
                sourceURL: b
            )
        ))
        let clickGeneration = viewModel.pendingNavigationGeneration
        viewModel.handleNavigationFinished(
            url: c,
            title: "stale forward",
            navigationGeneration: forwardGeneration
        )
        viewModel.handleNavigationFinished(
            url: e,
            title: "E",
            navigationGeneration: clickGeneration
        )

        assertHistory(viewModel, current: e, back: [a, b], forward: [])
    }

    func testOrdinaryAppendKeepsNewestBackSuffixAtLimit() {
        let limit = BrowserPanelViewModel.logicalHistoryLimit
        let back = (0..<limit).map { url("back-\($0)") }
        let current = url("current")
        let next = url("next")
        let viewModel = restoredViewModel(current: current, back: back, forward: [])

        XCTAssertTrue(viewModel.handleMainFrameNavigationAction(
            BrowserMainFrameNavigationAction(
                url: next,
                navigationType: .linkActivated,
                sourceURL: current
            )
        ))
        viewModel.handleNavigationFinished(
            url: next,
            title: nil,
            navigationGeneration: viewModel.pendingNavigationGeneration
        )

        assertHistory(viewModel, current: next, back: Array(back.dropFirst()) + [current], forward: [])
    }

    func testCancelledNavigationsRetireWeakTrackingWithoutAffectingNewerTransition() throws {
        let current = url("current")
        let firstTarget = url("first")
        let latestTarget = url("latest")
        let laterTarget = url("later")
        let viewModel = BrowserPanelViewModel()
        viewModel.usesRestoredSessionHistory = true
        viewModel.handleNavigationFinished(url: current, title: "Current")
        let navigationFactory = WKWebView()
        let delegate = try XCTUnwrap(viewModel.webView.navigationDelegate as? BrowserNavigationDelegate)

        XCTAssertTrue(viewModel.handleMainFrameNavigationAction(
            BrowserMainFrameNavigationAction(
                url: firstTarget,
                navigationType: .linkActivated,
                sourceURL: current
            )
        ))
        let firstNavigation = try XCTUnwrap(navigationFactory.load(URLRequest(url: firstTarget)))
        viewModel.handleNavigationStarted(firstNavigation)

        XCTAssertTrue(viewModel.handleMainFrameNavigationAction(
            BrowserMainFrameNavigationAction(
                url: latestTarget,
                navigationType: .linkActivated,
                sourceURL: current
            )
        ))
        let latestGeneration = try XCTUnwrap(viewModel.pendingNavigationGeneration)
        let latestNavigation = try XCTUnwrap(navigationFactory.load(URLRequest(url: latestTarget)))
        viewModel.handleNavigationStarted(latestNavigation)
        XCTAssertEqual(viewModel.trackedNavigationGenerationCount, 2)

        delegate.webView(
            viewModel.webView,
            didFailProvisionalNavigation: firstNavigation,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        )
        XCTAssertEqual(viewModel.trackedNavigationGenerationCount, 1)
        XCTAssertEqual(viewModel.pendingNavigationGeneration, latestGeneration)
        XCTAssertNil(viewModel.navigationError)
        XCTAssertEqual(viewModel.displayTitle, "Current")

        delegate.webView(
            viewModel.webView,
            didFail: latestNavigation,
            withError: NSError(domain: "WebKitErrorDomain", code: 102)
        )
        XCTAssertEqual(viewModel.trackedNavigationGenerationCount, 0)
        XCTAssertNil(viewModel.pendingNavigationGeneration)
        XCTAssertNil(viewModel.navigationError)
        XCTAssertEqual(viewModel.displayTitle, "Current")

        XCTAssertTrue(viewModel.handleMainFrameNavigationAction(
            BrowserMainFrameNavigationAction(
                url: laterTarget,
                navigationType: .linkActivated,
                sourceURL: current
            )
        ))
        let laterNavigation = try XCTUnwrap(navigationFactory.load(URLRequest(url: laterTarget)))
        viewModel.handleNavigationStarted(laterNavigation)
        XCTAssertEqual(viewModel.trackedNavigationGenerationCount, 1)

        delegate.webView(
            viewModel.webView,
            didFailProvisionalNavigation: laterNavigation,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        )
        XCTAssertEqual(viewModel.trackedNavigationGenerationCount, 0)
        XCTAssertNil(viewModel.pendingNavigationGeneration)
        XCTAssertNil(viewModel.navigationError)
    }

    func testCancellingCurrentSyntheticNavigationRollsBackHistoryWithoutSurfacingError() throws {
        let a = url("A")
        let b = url("B")
        let c = url("C")
        let viewModel = BrowserPanelViewModel()
        viewModel.usesRestoredSessionHistory = true
        viewModel.restoredBackStack = [a, b]
        viewModel.handleNavigationFinished(url: c, title: "C")
        viewModel.refreshNavigationState()

        viewModel.goBack()
        let generation = try XCTUnwrap(viewModel.pendingNavigationGeneration)
        XCTAssertEqual(viewModel.restoredBackStack, [a])
        XCTAssertEqual(viewModel.restoredForwardStack, [c])

        viewModel.handleNavigationCancellation(navigationGeneration: generation)

        XCTAssertEqual(viewModel.restoredBackStack, [a, b])
        XCTAssertTrue(viewModel.restoredForwardStack.isEmpty)
        XCTAssertNil(viewModel.pendingNavigationGeneration)
        XCTAssertNil(viewModel.navigationError)
        viewModel.resetLogicalHistoryTracking()
        XCTAssertEqual(viewModel.trackedNavigationGenerationCount, 0)
    }

    private func restoredViewModel(current: URL, back: [URL], forward: [URL]) -> BrowserPanelViewModel {
        let viewModel = BrowserPanelViewModel()
        viewModel.restoreSession(BrowserSessionSnapshot(
            urlString: current.absoluteString,
            backHistoryURLStrings: back.map(\.absoluteString),
            forwardHistoryURLStrings: forward.map(\.absoluteString)
        ))
        viewModel.handleNavigationFinished(
            url: current,
            title: nil,
            navigationGeneration: viewModel.pendingNavigationGeneration
        )
        return viewModel
    }

    private func url(_ name: String) -> URL {
        URL(string: "file:///tmp/crispy-browser-race/\(name)")!
    }

    private func assertHistory(
        _ viewModel: BrowserPanelViewModel,
        current: URL,
        back: [URL],
        forward: [URL],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let snapshot = viewModel.sessionSnapshot()
        XCTAssertEqual(snapshot.urlString, current.absoluteString, file: file, line: line)
        XCTAssertEqual(snapshot.backHistoryURLStrings, back.map(\.absoluteString), file: file, line: line)
        XCTAssertEqual(snapshot.forwardHistoryURLStrings, forward.map(\.absoluteString), file: file, line: line)
    }
}


@MainActor
final class BrowserGlobalTeardownTests: XCTestCase {
    private var container: AppContainer!
    private var boardStore: VibeSpaceTerminalBoardStore!
    private var splitStore: SplitViewStore!
    private var coordinator: DockedBrowserCoordinator!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispy-browser-global-teardown")
        container = AppContainer.makeDefault()
        let persistence = LayoutPersistenceService(
            fileManager: .default,
            stateFileURL: tempRoot.appendingPathComponent("layout.json")
        )
        boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: UUID(),
            layoutPersistence: persistence,
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )
        splitStore = container.makeSplitViewStore(bufferStore: DocumentBufferStore())
        coordinator = DockedBrowserCoordinator()
        splitStore.browserTabCloseHandler = { [weak coordinator] reference in
            coordinator?.removeDetailedBrowser(browserID: reference.browserID)
        }
    }

    override func tearDownWithError() throws {
        coordinator.removeAll()
        coordinator = nil
        splitStore = nil
        boardStore = nil
        container = nil
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
    }

    func testGlobalTeardownRemovesBoardAndEveryDirectOrLegacyLinkedTabAcrossGroups() throws {
        let requestedID = UUID()
        let directReference = BrowserTabReference(
            browserID: requestedID,
            url: URL(string: "file:///tmp/browser-direct")!,
            projectPath: "/projects/app"
        )
        let legacyA = try legacyLinkedReference(
            browserID: UUID(),
            tileID: requestedID,
            url: "file:///tmp/browser-legacy-a",
            projectPath: "/projects/app"
        )
        let legacyB = try legacyLinkedReference(
            browserID: UUID(),
            tileID: requestedID,
            url: "file:///tmp/browser-legacy-b",
            projectPath: "/projects/app"
        )
        let unrelatedReference = BrowserTabReference(
            browserID: UUID(),
            url: URL(string: "file:///tmp/browser-unrelated")!,
            projectPath: "/projects/other"
        )
        XCTAssertNotEqual(legacyA.browserID, requestedID)
        XCTAssertNotEqual(legacyB.browserID, requestedID)

        XCTAssertEqual(
            boardStore.pinBrowserToDock(
                id: requestedID,
                url: URL(string: "file:///tmp/browser-board")!,
                projectPath: "/projects/app"
            ),
            requestedID
        )
        let boardViewModel = coordinator.viewModel(
            for: requestedID,
            url: URL(string: "file:///tmp/browser-board")!
        )
        let firstGroup = splitStore.activeGroup
        firstGroup.openTab(.webPage(reference: directReference))
        firstGroup.openTab(.webPage(reference: legacyA))
        let secondPaneID = try XCTUnwrap(
            splitStore.split(paneID: firstGroup.id, orientation: .horizontal)
        )
        let secondGroup = splitStore.group(for: secondPaneID)
        secondGroup.openTab(.webPage(reference: legacyB))
        secondGroup.openTab(.webPage(reference: unrelatedReference))

        let directViewModel = coordinator.viewModel(for: directReference)
        let legacyAViewModel = coordinator.viewModel(for: legacyA)
        let legacyBViewModel = coordinator.viewModel(for: legacyB)
        let unrelatedViewModel = coordinator.viewModel(for: unrelatedReference)

        let result = BrowserGlobalTeardownCoordinator.teardown(
            requestedID: requestedID,
            boardStore: boardStore,
            splitViewStore: splitStore,
            dockedBrowserCoordinator: coordinator
        )

        XCTAssertEqual(
            result,
            BrowserGlobalTeardownResult(
                removedBoardPresentation: true,
                closedContentTabCount: 3
            )
        )
        XCTAssertNil(boardStore.surfaceID(containing: requestedID))
        XCTAssertFalse(splitStore.editorGroups.values.flatMap(\.tabs).contains { tab in
            guard case let .webPage(reference) = tab.kind else { return false }
            return BrowserGlobalTeardownCoordinator.referenceMatches(
                reference,
                requestedID: requestedID
            )
        })
        XCTAssertTrue(secondGroup.tabs.contains { $0.id == ContentViewerTab.webPage(reference: unrelatedReference).id })
        XCTAssertFalse(coordinator.viewModel(for: requestedID, url: URL(string: "about:blank")!) === boardViewModel)
        XCTAssertFalse(coordinator.viewModel(for: directReference) === directViewModel)
        XCTAssertFalse(coordinator.viewModel(for: legacyA) === legacyAViewModel)
        XCTAssertFalse(coordinator.viewModel(for: legacyB) === legacyBViewModel)
        XCTAssertTrue(coordinator.viewModel(for: unrelatedReference) === unrelatedViewModel)
    }

    func testProjectParkCollectionDispatchesEachOwnedBrowserOnceAndExcludesOtherProjects() throws {
        let directID = UUID()
        let legacyID = UUID()
        let directReference = BrowserTabReference(
            browserID: directID,
            url: URL(string: "file:///tmp/browser-project-direct")!,
            projectPath: "/projects/app"
        )
        let legacyReference = try legacyLinkedReference(
            browserID: legacyID,
            tileID: UUID(),
            url: "file:///tmp/browser-project-legacy",
            projectPath: "/projects/app"
        )
        let unrelatedID = UUID()
        let unrelatedReference = BrowserTabReference(
            browserID: unrelatedID,
            url: URL(string: "file:///tmp/browser-other")!,
            projectPath: "/projects/other"
        )
        _ = coordinator.viewModel(for: directReference)
        _ = coordinator.viewModel(for: legacyReference)
        _ = coordinator.viewModel(for: unrelatedReference)
        let parkedSnapshots = coordinator.snapshotBrowserSessions(forProjectPath: "/projects/app")
        var requestedIDs: [UUID] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .closeBrowserRequested,
            object: nil,
            queue: .main
        ) { notification in
            if let browserID = notification.userInfo?["browserID"] as? UUID {
                requestedIDs.append(browserID)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let count = coordinator.closeBrowsers(forProjectPath: "/projects/app")

        XCTAssertEqual(count, 2)
        XCTAssertEqual(Set(requestedIDs), Set([directID, legacyID]))
        XCTAssertEqual(requestedIDs.count, Set(requestedIDs).count)
        XCTAssertEqual(Set(parkedSnapshots.map(\.browserID)), Set([directID, legacyID]))
        XCTAssertFalse(requestedIDs.contains(unrelatedID))
    }

    private func legacyLinkedReference(
        browserID: UUID,
        tileID: UUID,
        url: String,
        projectPath: String
    ) throws -> BrowserTabReference {
        let data = try JSONSerialization.data(withJSONObject: [
            "browserID": browserID.uuidString,
            "seedURLString": url,
            "projectPath": projectPath,
            "linkedTileID": tileID.uuidString,
        ])
        return try JSONDecoder().decode(BrowserTabReference.self, from: data)
    }
}
