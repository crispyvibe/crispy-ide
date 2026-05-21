import XCTest
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

final class SpotlightRestoreDescriptorTests: XCTestCase {

    func testTerminalDescriptorCreation() {
        let descriptor = SpotlightRestoreDescriptor.terminal(
            projectRootURL: URL(fileURLWithPath: "/projects/app"),
            tabID: UUID()
        )
        if case .terminal = descriptor {} else {
            XCTFail("Expected .terminal descriptor")
        }
    }

    func testBrowserPreviewDescriptorCreation() {
        let descriptor = SpotlightRestoreDescriptor.browserPreview(
            snapshot: BrowserSessionSnapshot(
                urlString: "https://example.com",
                backHistoryURLStrings: ["https://example.com/start"],
                pageZoom: 1.25
            ),
            projectPath: nil
        )
        if case .browserPreview = descriptor {} else {
            XCTFail("Expected .browserPreview descriptor")
        }
    }

    func testBrowserDockedDescriptorCreation() {
        let descriptor = SpotlightRestoreDescriptor.browser(tileID: UUID(), url: URL(string: "https://example.com")!)
        if case .browser = descriptor {} else {
            XCTFail("Expected .browser descriptor")
        }
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
    func testRestorePreviewReusesExistingViewModelForMatchingSnapshot() {
        let coordinator = DockedBrowserCoordinator()
        let snapshot = BrowserSessionSnapshot(
            urlString: "https://example.com/page",
            backHistoryURLStrings: ["https://example.com/start"],
            pageZoom: 1.25,
            themeMode: BrowserPanelViewModel.BrowserThemeMode.system.rawValue
        )

        let first = coordinator.restorePreview(from: snapshot, projectPath: "/vibespace/a")
        let second = coordinator.restorePreview(from: snapshot, projectPath: "/vibespace/b")

        XCTAssertTrue(first === second)
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
