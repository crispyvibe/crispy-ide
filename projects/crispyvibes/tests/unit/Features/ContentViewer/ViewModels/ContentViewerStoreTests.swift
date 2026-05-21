import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

private actor TestRecordingPaneWorker: PaneWorkerExecuting {
    private let readFileContents: [String: String]
    private let gitFileContents: [String: String]
    private var invocations: [(PaneWorkerMethod, [String: String])] = []

    init(
        readFileContents: [String: String] = [:],
        gitFileContents: [String: String] = [:]
    ) {
        self.readFileContents = readFileContents
        self.gitFileContents = gitFileContents
    }

    func restart() async {}

    func execute(
        _ method: PaneWorkerMethod,
        arguments: [String: String],
        timeout: TimeInterval
    ) async throws -> String? {
        invocations.append((method, arguments))
        switch method {
        case .readFile:
            let path = arguments["filePath"] ?? ""
            guard let content = readFileContents[path] else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            return content
        case .gitFileContent:
            let path = arguments["relativePath"] ?? ""
            guard let content = gitFileContents[path] else {
                throw PaneWorkerError.workerFailure("No git content for \(path)")
            }
            return content
        case .gitDiff:
            return "diff"
        default:
            return nil
        }
    }

    func recordedInvocations() -> [(PaneWorkerMethod, [String: String])] {
        invocations
    }
}

@MainActor
final class ContentViewerStoreTests: XCTestCase {
    private var container: AppContainer!

    override func setUpWithError() throws {
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    private func makeSUT() -> (ContentViewerStore, SplitViewStore) {
        let store = container.makeContentViewerStore()
        let splitStore = container.makeSplitViewStore()
        store.splitStore = splitStore
        return (store, splitStore)
    }

    private func makeSUT(worker: any PaneWorkerExecuting) -> (ContentViewerStore, SplitViewStore) {
        let store = ContentViewerStore(
            conversationStore: container.agentConversationStore,
            editorGroupFactory: { _ in
            EditorGroupStore(markdownViewModel: MarkdownViewModel(worker: worker, bufferStore: DocumentBufferStore()))
            },
            sessionRegistry: container.acpSessionRegistry
        )
        let splitStore = SplitViewStore { _ in
            EditorGroupStore(markdownViewModel: MarkdownViewModel(worker: worker, bufferStore: DocumentBufferStore()))
        }
        store.splitStore = splitStore
        return (store, splitStore)
    }

    func testRetargetFileSystemLocationUpdatesActivePreviewAndPersistentTabs() {
        let (store, splitStore) = makeSUT()
        let group = splitStore.activeGroup
        let oldURL = URL(fileURLWithPath: "/tmp/project/docs/readme.md")
        let newURL = URL(fileURLWithPath: "/tmp/project/docs/guide.md")

        group.openFileInTab(at: oldURL)
        group.markdownViewModel.markupViewModeByDocumentID = [oldURL.standardizedFileURL.path: .source]

        store.retargetFileSystemLocation(from: oldURL, to: newURL)

        XCTAssertEqual(group.tabs, [.file(url: newURL)])
        XCTAssertEqual(group.activeTabID, ContentViewerTab.file(url: newURL).id)
        XCTAssertEqual(group.markdownViewModel.fileURL?.standardizedFileURL, newURL.standardizedFileURL)
    }

    func testRetargetFileSystemLocationUpdatesFilesInsideRenamedFolder() {
        let (store, splitStore) = makeSUT()
        let group = splitStore.activeGroup
        let oldFolder = URL(fileURLWithPath: "/tmp/project/docs")
        let newFolder = URL(fileURLWithPath: "/tmp/project/guides")
        let oldFile = oldFolder.appendingPathComponent("readme.md")
        let newFile = newFolder.appendingPathComponent("readme.md")

        group.openFileInTab(at: oldFile)
        store.retargetFileSystemLocation(from: oldFolder, to: newFolder)

        XCTAssertEqual(group.tabs, [.file(url: newFile)])
        XCTAssertEqual(group.activeTabID, ContentViewerTab.file(url: newFile).id)
    }

    func testCloseTabFallbackSelectionStaysInSync() {
        let (_, splitStore) = makeSUT()
        let group = splitStore.activeGroup
        let urlA = URL(fileURLWithPath: "/tmp/a.md")
        let urlB = URL(fileURLWithPath: "/tmp/b.md")
        let urlC = URL(fileURLWithPath: "/tmp/c.md")

        group.openFileInTab(at: urlA)
        group.openFileInTab(at: urlB)
        group.openFileInTab(at: urlC)
        group.activateTab(ContentViewerTab.file(url: urlB).id)
        group.closeTab(ContentViewerTab.file(url: urlB).id)

        let activeFile: URL? = {
            guard let activeTab = group.activeTab else { return nil }
            guard case .file(let reference) = activeTab.kind else { return nil }
            return reference.url
        }()
        XCTAssertNotNil(activeFile)
        XCTAssertEqual(activeFile, group.markdownViewModel.fileURL?.standardizedFileURL)
    }

    func testCloseLastTabClearsDocumentAndFiresCallback() {
        let (store, splitStore) = makeSUT()
        let group = splitStore.activeGroup
        group.openFileInTab(at: URL(fileURLWithPath: "/tmp/only.md"))

        var callCount = 0
        store.onActiveFileCleared = { callCount += 1 }
        store.closeTab(ContentViewerTab.file(url: URL(fileURLWithPath: "/tmp/only.md")).id)

        XCTAssertTrue(group.tabs.isEmpty)
        XCTAssertNil(group.activeTabID)
        XCTAssertNil(group.markdownViewModel.fileURL)
        XCTAssertEqual(callCount, 1)
    }

    func testCloseWebTabInvokesBrowserCleanupHandler() {
        let (store, splitStore) = makeSUT()
        let browserID = UUID()
        let tab = ContentViewerTab.webPage(
            url: URL(string: "https://example.com")!,
            browserID: browserID
        )
        splitStore.activeGroup.openTab(tab)

        var closedBrowserIDs: [UUID] = []
        store.browserTabCloseHandler = { reference in
            closedBrowserIDs.append(reference.browserID)
        }

        store.closeTab(tab)

        XCTAssertEqual(closedBrowserIDs, [browserID])
        XCTAssertFalse(splitStore.activeGroup.tabs.contains(where: { $0.id == tab.id }))
    }

    func testClosePaneInvokesBrowserCleanupForContainedWebTabs() {
        let (_, splitStore) = makeSUT()
        let browserID = UUID()
        let tab = ContentViewerTab.webPage(
            url: URL(string: "https://example.com")!,
            browserID: browserID
        )
        splitStore.activeGroup.openTab(tab)
        let paneID = splitStore.activeGroup.id
        let newPaneID = try? XCTUnwrap(splitStore.split(paneID: paneID, orientation: .horizontal))
        XCTAssertNotNil(newPaneID)

        var closedBrowserIDs: [UUID] = []
        splitStore.browserTabCloseHandler = { reference in
            closedBrowserIDs.append(reference.browserID)
        }

        splitStore.closePane(paneID: paneID)

        XCTAssertEqual(closedBrowserIDs, [browserID])
    }

    func testActiveFileClearedTargetsCurrentFocusedProject() throws {
        let (contentViewerStore, splitViewStore) = makeSUT()
        let appShellStore = AppShellStore()
        let vibespaceCatalogStore = VibeSpaceCatalogStore(
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry,
            terminalBoardDetachedWindowManager: container.terminalBoardDetachedWindowManager
        )
        let useCase = VibeSpaceCanvasFileOpenUseCase()
        let tempRoot = try makeTempDirectory(prefix: "crispyvibes-content-viewer-clear")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let firstProjectRoot = tempRoot.appendingPathComponent("first", isDirectory: true)
        let secondProjectRoot = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstProjectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondProjectRoot, withIntermediateDirectories: true)

        let vibespaceID = UUID()
        var vibespace = container.makeVibeSpaceState(
            id: vibespaceID,
            name: "VibeSpace",
            projectURLs: [firstProjectRoot, secondProjectRoot]
        )
        let firstProject = try XCTUnwrap(vibespace.projects.first)
        let secondProject = try XCTUnwrap(vibespace.projects.last)
        vibespace.focusedProjectID = firstProject.id
        vibespaceCatalogStore.replaceDisplayedVibeSpace(with: vibespace)
        appShellStore.showVibeSpace(vibespaceID)

        useCase.wireProjectFileOpenHandler(
            firstProject,
            contentViewerStore: contentViewerStore,
            splitViewStore: splitViewStore,
            appShellStore: appShellStore,
            vibespaceCatalogStore: vibespaceCatalogStore
        )
        useCase.wireProjectFileOpenHandler(
            secondProject,
            contentViewerStore: contentViewerStore,
            splitViewStore: splitViewStore,
            appShellStore: appShellStore,
            vibespaceCatalogStore: vibespaceCatalogStore
        )

        let firstExplorer = try XCTUnwrap(firstProject.folderExplorerViewModel)
        let secondExplorer = try XCTUnwrap(secondProject.folderExplorerViewModel)
        firstExplorer.selectedFileURL = firstProjectRoot.appendingPathComponent("a.swift")
        secondExplorer.selectedFileURL = secondProjectRoot.appendingPathComponent("b.swift")

        vibespaceCatalogStore.mutateVibeSpace(id: vibespaceID) { persistedVibeSpace in
            persistedVibeSpace.focusedProjectID = secondProject.id
        }

        contentViewerStore.onActiveFileCleared?()

        XCTAssertNotNil(firstExplorer.selectedFileURL)
        XCTAssertNil(secondExplorer.selectedFileURL)
    }

    func testResolveFileSystemTargetFromTerminalPreviewsVibeSpaceFilesWithLineAndColumn() throws {
        let useCase = VibeSpaceCanvasFileOpenUseCase()
        let tempRoot = try makeTempDirectory(prefix: "crispyvibes-terminal-file-target")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let sourceDirectory = projectRoot.appendingPathComponent("Sources", isDirectory: true)
        let fileURL = sourceDirectory.appendingPathComponent("Example.swift", isDirectory: false)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try Data("print(\"ok\")\n".utf8).write(to: fileURL)

        let vibespaceID = UUID()
        let project = container.makeProjectSession(rootURL: projectRoot, vibespaceID: vibespaceID)
        let target = TerminalFileSystemTarget(url: fileURL, line: 18, column: 6)

        let resolution = useCase.resolveFileSystemTargetFromTerminal(
            target,
            preferredProjectRootURL: nil,
            candidates: [(vibespaceID: vibespaceID, project: project)]
        )

        guard case let .previewFile(resolvedTarget, owningProjectRootURL) = resolution else {
            return XCTFail("Expected file preview resolution")
        }
        XCTAssertEqual(resolvedTarget, TerminalFileSystemTarget(url: fileURL.standardizedFileURL, line: 18, column: 6))
        XCTAssertEqual(owningProjectRootURL, projectRoot.standardizedFileURL)
    }

    func testResolveFileSystemTargetFromTerminalRevealsDirectoriesInFinder() throws {
        let useCase = VibeSpaceCanvasFileOpenUseCase()
        let tempRoot = try makeTempDirectory(prefix: "crispyvibes-terminal-directory-target")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let nestedDirectory = projectRoot.appendingPathComponent("Sources/Feature", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)

        let vibespaceID = UUID()
        let project = container.makeProjectSession(rootURL: projectRoot, vibespaceID: vibespaceID)
        let target = TerminalFileSystemTarget(url: nestedDirectory, line: nil, column: nil)

        let resolution = useCase.resolveFileSystemTargetFromTerminal(
            target,
            preferredProjectRootURL: nil,
            candidates: [(vibespaceID: vibespaceID, project: project)]
        )

        guard case let .revealDirectoryInFinder(directoryURL) = resolution else {
            return XCTFail("Expected directory reveal resolution")
        }
        XCTAssertEqual(directoryURL, nestedDirectory.standardizedFileURL)
    }

    func testDeletedGitPreviewTabReactivatesViaGitContentInsteadOfDiskRead() async throws {
        let deletedURL = URL(fileURLWithPath: "/tmp/deleted.swift")
        let otherURL = URL(fileURLWithPath: "/tmp/other.swift")
        let worker = TestRecordingPaneWorker(
            readFileContents: [otherURL.path: "other"],
            gitFileContents: ["Sources/deleted.swift": "previous revision"]
        )
        let (store, splitStore) = makeSUT(worker: worker)

        store.previewGitFileContent(
            rootURL: URL(fileURLWithPath: "/tmp/repo"),
            fileURL: deletedURL,
            relativePath: "Sources/deleted.swift",
            titleSuffix: "Deleted"
        )
        let initialLoaded = await waitForCondition(timeout: 2) {
            splitStore.activeGroup.markdownViewModel.workerStatus == .ready &&
            splitStore.activeGroup.markdownViewModel.rawContent == "previous revision"
        }
        XCTAssertTrue(initialLoaded)

        store.openFileInTab(at: otherURL)
        let otherFileLoaded = await waitForCondition(timeout: 2) {
            splitStore.activeGroup.markdownViewModel.workerStatus == .ready &&
            splitStore.activeGroup.markdownViewModel.rawContent == "other"
        }
        XCTAssertTrue(otherFileLoaded)

        store.activateTab(ContentViewerTab.file(url: deletedURL).id)
        let deletedReloaded = await waitForCondition(timeout: 2) {
            splitStore.activeGroup.markdownViewModel.workerStatus == .ready &&
            splitStore.activeGroup.markdownViewModel.rawContent == "previous revision" &&
            splitStore.activeGroup.markdownViewModel.errorMessage == nil
        }
        XCTAssertTrue(deletedReloaded)

        let deletedReadAttempts = await worker.recordedInvocations().filter {
            $0.0 == .readFile && $0.1["filePath"] == deletedURL.path
        }
        let deletedGitLoads = await worker.recordedInvocations().filter {
            $0.0 == .gitFileContent && $0.1["relativePath"] == "Sources/deleted.swift"
        }

        XCTAssertTrue(deletedReadAttempts.isEmpty)
        XCTAssertEqual(deletedGitLoads.count, 2)
    }

    func testSplitCreatesIndependentEditorGroups() {
        let (_, splitStore) = makeSUT()
        let urlA = URL(fileURLWithPath: "/tmp/a.swift")
        let urlB = URL(fileURLWithPath: "/tmp/b.swift")

        splitStore.activeGroup.openFileInTab(at: urlA)
        splitStore.splitActiveWithTab(.file(url: urlB), orientation: .horizontal)

        XCTAssertTrue(splitStore.isSplit)
        XCTAssertEqual(splitStore.root.leafCount, 2)
        let paneIDs = splitStore.root.allLeafIDs
        let group1 = splitStore.group(for: paneIDs[0])
        let group2 = splitStore.group(for: paneIDs[1])
        XCTAssertEqual(group1.tabs.count, 1)
        XCTAssertEqual(group2.tabs.count, 1)
        XCTAssertNotEqual(group1.tabs.first?.id, group2.tabs.first?.id)
    }

    func testTabDragPayloadRoundTrip() {
        let fileTab = ContentViewerTab.file(url: URL(fileURLWithPath: "/tmp/test.swift"))
        let vibeCastTab = ContentViewerTab.vibeCast
        let webReference = BrowserTabReference(
            browserID: UUID(),
            url: URL(string: "https://example.com/path")!,
            projectPath: "/tmp/project",
            linkedTileID: UUID()
        )
        let webTab = ContentViewerTab.webPage(reference: webReference, customTitle: "Example")

        for tab in [fileTab, vibeCastTab, webTab] {
            let provider = ContentViewerTabDragSupport.makeItemProvider(for: tab)
            let expectation = expectation(description: "Load drag payload for \(tab.id)")

            let didStartLoad = ContentViewerTabDragSupport.loadDropItem(from: [provider]) { item in
                guard case .tab(let decodedTab) = item else {
                    XCTFail("Expected a decoded tab payload for \(tab.id)")
                    expectation.fulfill()
                    return
                }
                XCTAssertEqual(decodedTab.kind, tab.kind)
                XCTAssertEqual(decodedTab.customTitle, tab.customTitle)
                expectation.fulfill()
            }

            XCTAssertTrue(didStartLoad)
            wait(for: [expectation], timeout: 2.0)
        }
    }

    func testTabDragPasteboardRoundTrip() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("crispyvibes-tests-tab-drag-\(UUID().uuidString)"))
        pasteboard.clearContents()

        let payload = #"{"kind":"file","value":"/tmp/pasteboard.swift"}"#
        let didWrite = pasteboard.setData(
            Data(payload.utf8),
            forType: NSPasteboard.PasteboardType(ContentViewerTabDragSupport.contentViewerTabType.identifier)
        )

        XCTAssertTrue(didWrite)
        XCTAssertEqual(
            ContentViewerTabDragSupport.readDropItem(from: pasteboard),
            .tab(.file(url: URL(fileURLWithPath: "/tmp/pasteboard.swift")))
        )
    }

    func testContentAreaDropTypesExcludeFileURLsForTerminalTabs() {
        XCTAssertEqual(
            ContentViewerTabDragSupport.contentAreaDropTypes(for: .terminal(projectID: UUID(), tabID: UUID())),
            [ContentViewerTabDragSupport.contentViewerTabType]
        )
        XCTAssertEqual(
            ContentViewerTabDragSupport.contentAreaDropTypes(for: .file(FileDocumentReference(url: URL(fileURLWithPath: "/tmp/test.swift")))),
            ContentViewerTabDragSupport.dropTypes
        )
    }
}

// MARK: - Editor Session Persistence Tests

@MainActor
final class EditorSessionPersistenceTests: XCTestCase {
    private var container: AppContainer!

    override func setUpWithError() throws {
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    func testSnapshotCapturesSplitTreeAndPerPaneTabs() {
        let splitStore = container.makeSplitViewStore()
        let urlA = URL(fileURLWithPath: "/tmp/a.swift")
        let urlB = URL(fileURLWithPath: "/tmp/b.swift")

        splitStore.activeGroup.openFileInTab(at: urlA)
        splitStore.splitActiveWithTab(.file(url: urlB), orientation: .vertical)

        let snapshot = splitStore.snapshot()
        XCTAssertEqual(snapshot.panes.count, 2)
        XCTAssertEqual(snapshot.panes[0].openFilePaths, [urlA.standardizedFileURL.path])
        XCTAssertEqual(snapshot.panes[1].openFilePaths, [urlB.standardizedFileURL.path])
        XCTAssertNotNil(snapshot.activePaneID)
    }

    func testSnapshotRestorePersistsBrowserTabs() {
        let splitStore = container.makeSplitViewStore()
        let browserReference = BrowserTabReference(
            browserID: UUID(),
            url: URL(string: "https://example.com/app")!,
            projectPath: "/tmp/project"
        )
        let expectedSnapshot = BrowserSessionSnapshot(
            urlString: "https://example.com/app/dashboard",
            backHistoryURLStrings: ["https://example.com/app"],
            pageZoom: 1.4
        )
        splitStore.browserSessionSnapshotProvider = { reference in
            guard reference.browserID == browserReference.browserID else { return nil }
            return expectedSnapshot
        }
        splitStore.activeGroup.openTab(.webPage(reference: browserReference, customTitle: "Dashboard"))

        let snapshot = splitStore.snapshot()
        XCTAssertEqual(snapshot.panes.count, 1)
        XCTAssertEqual(snapshot.panes[0].browserTabs?.first?.reference, browserReference)
        XCTAssertEqual(snapshot.panes[0].browserTabs?.first?.sessionSnapshot, expectedSnapshot)
        XCTAssertEqual(snapshot.panes[0].activeTabID, "web:\(browserReference.browserID.uuidString)")

        let restored = container.makeSplitViewStore()
        var restoredReference: BrowserTabReference?
        var restoredSession: BrowserSessionSnapshot?
        restored.browserTabRestoreHandler = { reference, session in
            restoredReference = reference
            restoredSession = session
        }
        restored.restore(from: snapshot)

        XCTAssertEqual(restoredReference, browserReference)
        XCTAssertEqual(restoredSession, expectedSnapshot)
        XCTAssertEqual(restored.activeGroup.activeTabID, "web:\(browserReference.browserID.uuidString)")
        XCTAssertEqual(restored.activeGroup.activeTab?.customTitle, "Dashboard")
    }

    func testFocusedProjectFilteringHidesBrowsersOwnedByOtherProjects() {
        let splitStore = container.makeSplitViewStore()
        let activeGroup = splitStore.activeGroup
        activeGroup.openTab(
            .webPage(
                url: URL(string: "https://first.example.com")!,
                projectPath: "/tmp/first"
            )
        )
        activeGroup.openTab(
            .webPage(
                url: URL(string: "https://second.example.com")!,
                projectPath: "/tmp/second"
            )
        )

        let visibleTabs = activeGroup.filteredTabs(scope: .focusedProject, focusedProjectRootPath: "/tmp/first")

        XCTAssertEqual(visibleTabs.count, 1)
        if case .webPage(let reference) = visibleTabs[0].kind {
            XCTAssertEqual(reference.projectPath, "/tmp/first")
        } else {
            XCTFail("Expected browser tab")
        }
    }

    func testBrowserTabTitleUsesBareDomainName() {
        let tab = ContentViewerTab.webPage(url: URL(string: "https://google.com/hjhj/kkj")!)

        XCTAssertEqual(tab.title, "google")
    }

    func testBrowserTabTitleUsesRegistrantForCoUkDomains() {
        let tab = ContentViewerTab.webPage(url: URL(string: "https://news.bbc.co.uk/world")!)

        XCTAssertEqual(tab.title, "bbc")
    }

    func testFocusedProjectFilteringRestoresBrowserVisibilityWhenSwitchingProjects() {
        let splitStore = container.makeSplitViewStore()
        let activeGroup = splitStore.activeGroup
        let firstTab = ContentViewerTab.webPage(
            url: URL(string: "https://first.example.com")!,
            projectPath: "/tmp/first"
        )
        let secondTab = ContentViewerTab.webPage(
            url: URL(string: "https://second.example.com")!,
            projectPath: "/tmp/second"
        )
        activeGroup.openTab(firstTab)
        activeGroup.openTab(secondTab)

        let firstVisible = activeGroup.filteredTabs(scope: .focusedProject, focusedProjectRootPath: "/tmp/first")
        XCTAssertEqual(firstVisible.count, 1)
        XCTAssertEqual(firstVisible.first?.id, firstTab.id)

        let secondVisible = activeGroup.filteredTabs(scope: .focusedProject, focusedProjectRootPath: "/tmp/second")
        XCTAssertEqual(secondVisible.count, 1)
        XCTAssertEqual(secondVisible.first?.id, secondTab.id)

        let allVisible = activeGroup.filteredTabs(scope: .allProjects, focusedProjectRootPath: "/tmp/first")
        XCTAssertEqual(allVisible.map(\.id), activeGroup.tabs.map(\.id))

        let firstVisibleAgain = activeGroup.filteredTabs(scope: .focusedProject, focusedProjectRootPath: "/tmp/first")
        XCTAssertEqual(firstVisibleAgain.count, 1)
        XCTAssertEqual(firstVisibleAgain.first?.id, firstTab.id)
    }

    func testRestoreRebuildsSplitTreeAndReopensFiles() throws {
        let tempDir = try makeTempDirectory(prefix: "crispyvibes-editor-persist")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileA = tempDir.appendingPathComponent("a.swift")
        let fileB = tempDir.appendingPathComponent("b.swift")
        try Data("let a = 1".utf8).write(to: fileA)
        try Data("let b = 2".utf8).write(to: fileB)

        let original = container.makeSplitViewStore()
        original.activeGroup.openFileInTab(at: fileA)
        original.splitActiveWithTab(.file(url: fileB), orientation: .vertical)
        let snapshot = original.snapshot()

        let restored = container.makeSplitViewStore()
        restored.restore(from: snapshot)

        XCTAssertTrue(restored.isSplit)
        XCTAssertEqual(restored.root.leafCount, 2)
        let g1 = restored.group(for: restored.root.allLeafIDs[0])
        let g2 = restored.group(for: restored.root.allLeafIDs[1])
        XCTAssertEqual(g1.tabs.count, 1)
        XCTAssertEqual(g2.tabs.count, 1)
    }

    func testRestoreSkipsDeletedFiles() throws {
        let tempDir = try makeTempDirectory(prefix: "crispyvibes-editor-del")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let existing = tempDir.appendingPathComponent("exists.swift")
        let deleted = tempDir.appendingPathComponent("gone.swift")
        try Data("ok".utf8).write(to: existing)
        try Data("bye".utf8).write(to: deleted)

        let original = container.makeSplitViewStore()
        original.activeGroup.openFileInTab(at: existing)
        original.activeGroup.openFileInTab(at: deleted)
        let snapshot = original.snapshot()

        try FileManager.default.removeItem(at: deleted)

        let restored = container.makeSplitViewStore()
        restored.restore(from: snapshot)
        XCTAssertEqual(restored.activeGroup.tabs.count, 1)
    }

    func testRestoreCollapsesEmptyPanes() throws {
        let tempDir = try makeTempDirectory(prefix: "crispyvibes-editor-collapse")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileA = tempDir.appendingPathComponent("a.swift")
        let fileB = tempDir.appendingPathComponent("b.swift")
        try Data("a".utf8).write(to: fileA)
        try Data("b".utf8).write(to: fileB)

        let original = container.makeSplitViewStore()
        original.activeGroup.openFileInTab(at: fileA)
        original.splitActiveWithTab(.file(url: fileB), orientation: .horizontal)
        let snapshot = original.snapshot()

        // Delete file B so the second pane becomes empty
        try FileManager.default.removeItem(at: fileB)

        let restored = container.makeSplitViewStore()
        restored.restore(from: snapshot)
        XCTAssertFalse(restored.isSplit, "Empty pane should be collapsed")
        XCTAssertEqual(restored.root.leafCount, 1)
        XCTAssertEqual(restored.activeGroup.tabs.count, 1)
    }

    func testSnapshotRestoreRoundTripPreservesRatios() throws {
        let tempDir = try makeTempDirectory(prefix: "crispyvibes-editor-rt")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileA = tempDir.appendingPathComponent("a.swift")
        let fileB = tempDir.appendingPathComponent("b.swift")
        try Data("a".utf8).write(to: fileA)
        try Data("b".utf8).write(to: fileB)

        let splitStore = container.makeSplitViewStore()
        splitStore.activeGroup.openFileInTab(at: fileA)
        splitStore.splitActiveWithTab(.file(url: fileB), orientation: .horizontal)
        if case .split(let id, _, _, _, _) = splitStore.root { splitStore.setRatio(0.35, for: id) }
        let originalActive = splitStore.activePaneID

        let snapshot = splitStore.snapshot()
        let restored = container.makeSplitViewStore()
        restored.restore(from: snapshot)

        XCTAssertEqual(restored.activePaneID, originalActive)
        if case .split(let id, _, _, _, _) = restored.root {
            XCTAssertEqual(restored.ratioBinding(for: id), 0.35, accuracy: 0.01)
        } else { XCTFail("Expected split") }
    }

    func testEditorSessionStateCodableRoundTrip() throws {
        let p1 = UUID(), p2 = UUID(), s = UUID()
        let state = EditorSessionState(
            splitTree: .split(id: s, orientation: .vertical, first: .leaf(id: p1), second: .leaf(id: p2), ratio: 0.6),
            panes: [
                EditorPaneSnapshot(paneID: p1, openFilePaths: ["/tmp/a.swift"], activeFilePath: "/tmp/a.swift"),
                EditorPaneSnapshot(paneID: p2, openFilePaths: ["/tmp/b.swift"], activeFilePath: "/tmp/b.swift")
            ],
            activePaneID: p2, splitRatios: [s.uuidString: 0.6]
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(EditorSessionState.self, from: data)
        XCTAssertEqual(state, decoded)
    }
}
