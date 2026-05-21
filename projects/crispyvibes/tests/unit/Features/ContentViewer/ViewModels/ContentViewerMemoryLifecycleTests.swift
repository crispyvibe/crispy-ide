import Combine
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class ContentViewerMemoryLifecycleTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-cv-memory")
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }

    // MARK: - EditorGroupStore

    func testEditorGroupStoreDeallocatesWhenReleased() {
        var group: EditorGroupStore? = container.makeEditorGroupStore(bufferStore: DocumentBufferStore())
        let fileURL = tempRoot.appendingPathComponent("test.md")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("# Hello".utf8))
        group!.openFileInTab(at: fileURL)
        weak var weakGroup = group

        group = nil

        XCTAssertNil(weakGroup, "EditorGroupStore should deallocate when released")
    }

    func testMarkdownViewModelDeallocatesWithEditorGroup() {
        var group: EditorGroupStore? = container.makeEditorGroupStore(bufferStore: DocumentBufferStore())
        weak var weakMD = group!.markdownViewModel

        group = nil

        XCTAssertNil(weakMD, "MarkdownViewModel should deallocate with its EditorGroupStore")
    }

    // MARK: - SplitViewStore

    func testSplitViewStoreDeallocatesWhenReleased() {
        var store: SplitViewStore? = container.makeSplitViewStore()
        store!.split(paneID: store!.root.id, orientation: .horizontal)
        weak var weakStore = store

        store = nil

        XCTAssertNil(weakStore, "SplitViewStore should deallocate when released")
    }

    func testSplitViewStorePrunesGroupsOnPaneClose() {
        let store = container.makeSplitViewStore()
        let originalPaneID = store.root.id
        guard let newPaneID = store.split(paneID: originalPaneID, orientation: .horizontal) else {
            XCTFail("Split should succeed")
            return
        }
        weak var weakGroup = store.editorGroups[newPaneID]

        store.closePane(paneID: newPaneID)

        XCTAssertNil(store.editorGroups[newPaneID], "Group should be removed from dictionary after pane close")
        XCTAssertNil(weakGroup, "EditorGroupStore should deallocate after pane close")
    }

    func testSplitViewStoreResetReleasesAllGroups() {
        let store = container.makeSplitViewStore()
        let originalPaneID = store.root.id
        store.split(paneID: originalPaneID, orientation: .horizontal)
        let groupRefs = store.editorGroups.values.map { WeakRef($0) }

        store.reset()

        let leakedCount = groupRefs.filter { $0.value != nil }.count
        XCTAssertEqual(leakedCount, 0, "\(leakedCount) EditorGroupStore(s) leaked after reset")
    }

    // MARK: - ContentViewerStore

    func testContentViewerStoreDeallocatesWhenReleased() {
        var store: ContentViewerStore? = container.makeContentViewerStore()
        weak var weakStore = store

        store = nil

        XCTAssertNil(weakStore, "ContentViewerStore should deallocate when released")
    }

    func testContentViewerStoreOnActiveFileClearedDoesNotRetain() {
        var store: ContentViewerStore? = container.makeContentViewerStore()
        weak var weakStore = store

        store!.onActiveFileCleared = { [weak store] in
            _ = store?.tabs
        }

        store = nil

        XCTAssertNil(weakStore, "ContentViewerStore should deallocate even with onActiveFileCleared set (weak capture)")
    }

    func testContentViewerStoreOnActiveFileClearedStrongCaptureRetains() {
        var store: ContentViewerStore? = container.makeContentViewerStore()
        weak var weakStore = store

        // Intentionally capture strongly to prove the test catches it
        store!.onActiveFileCleared = {
            _ = store?.tabs
        }

        let retained = store
        store = nil

        // store is still held by the closure AND by `retained`
        XCTAssertNotNil(weakStore, "Strong capture should keep store alive (control test)")
        _ = retained
    }

    // MARK: - VibeCastStore

    func testVibeCastStoreDeallocatesWithContentViewerStore() {
        var cvStore: ContentViewerStore? = container.makeContentViewerStore()
        weak var weakVibeCast = cvStore!.vibeCastStore

        cvStore = nil

        XCTAssertNil(weakVibeCast, "VibeCastStore should deallocate with ContentViewerStore")
    }

    // MARK: - DirectoryWatcher

    func testDirectoryWatcherDeallocatesAfterInvalidate() {
        var watcher: DirectoryWatcher? = DirectoryWatcher()
        watcher!.setOnChange { _ in }
        watcher!.updateWatchedPaths([tempRoot.path])
        weak var weakWatcher = watcher

        watcher!.invalidate()
        watcher = nil

        XCTAssertNil(weakWatcher, "DirectoryWatcher should deallocate after invalidate")
    }

    func testDirectoryWatcherOnChangeDoesNotRetainWatcher() {
        var watcher: DirectoryWatcher? = DirectoryWatcher()
        weak var weakWatcher = watcher

        watcher!.setOnChange { [weak watcher] path in
            _ = watcher
            _ = path
        }
        watcher!.updateWatchedPaths([tempRoot.path])
        watcher!.invalidate()
        watcher = nil

        XCTAssertNil(weakWatcher, "DirectoryWatcher should deallocate with weak onChange capture")
    }

    // MARK: - FolderExplorerViewModel

    func testFolderExplorerViewModelDeallocatesWhenReleased() {
        var explorer: FolderExplorerViewModel? = container.makeFolderExplorerViewModel()
        explorer!.setRootFolder(tempRoot)
        weak var weakExplorer = explorer

        explorer = nil
        drainRunLoop()

        XCTAssertNil(weakExplorer, "FolderExplorerViewModel should deallocate when released")
    }

    // MARK: - VibeSpaceState multiple project add/remove cycles

    func testVibeSpaceStateRepeatedAddRemoveDoesNotAccumulate() throws {
        var vibespace = container.makeVibeSpaceState(id: UUID(), name: "Test", projectURLs: [])

        var weakRefs: [WeakRef<AnyProjectSession>] = []
        for i in 0..<5 {
            let dir = tempRoot.appendingPathComponent("proj-\(i)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let session = vibespace.addProjects(from: [dir]) {
                weakRefs.append(WeakRef(session))
                vibespace.removeProject(id: session.id)
            }
        }

        let leakedCount = weakRefs.filter { $0.value != nil }.count
        XCTAssertEqual(leakedCount, 0, "\(leakedCount) ProjectSession(s) leaked across 5 add/remove cycles")
    }

    // MARK: - VibeSpaceState.resetSession full teardown

    func testResetSessionReleasesOldProjectSessions() throws {
        let projectDir = tempRoot.appendingPathComponent("proj", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(id: UUID(), name: "Test", projectURLs: [projectDir])
        vibespace.projects[0].activateIfNeeded()
        vibespace.projects[0].terminalViewModel.createTab(directoryURL: projectDir, startImmediately: false)
        vibespace.projects[0].terminalViewModel.createTab(directoryURL: projectDir, startImmediately: false)

        weak var weakOldProject = vibespace.projects[0]
        weak var weakOldVM = vibespace.projects[0].terminalViewModel
        let weakOldSessions = vibespace.projects[0].terminalViewModel.tabs.compactMap {
            vibespace.projects[0].terminalViewModel.session(for: $0.id)
        }.map { WeakRef($0) }
        weak var weakOldExplorer = vibespace.projects[0].folderExplorerViewModel

        vibespace.resetSession()

        XCTAssertNil(weakOldProject, "Old ProjectSession should deallocate after resetSession")
        XCTAssertNil(weakOldVM, "Old TerminalViewModel should deallocate after resetSession")
        XCTAssertNil(weakOldExplorer, "Old FolderExplorerViewModel should deallocate after resetSession")
        for (i, ref) in weakOldSessions.enumerated() {
            XCTAssertNil(ref.value, "Old TerminalSession[\(i)] should deallocate after resetSession")
        }

        // Projects should be empty after resetSession (recreated on reopen)
        XCTAssertEqual(vibespace.projects.count, 0)
    }

    func testResetSessionWithMultipleProjectsReleasesAll() throws {
        let proj1 = tempRoot.appendingPathComponent("p1", isDirectory: true)
        let proj2 = tempRoot.appendingPathComponent("p2", isDirectory: true)
        try FileManager.default.createDirectory(at: proj1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: proj2, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(id: UUID(), name: "Multi", projectURLs: [proj1, proj2])
        for project in vibespace.projects {
            project.activateIfNeeded()
            project.terminalViewModel.createTab(directoryURL: project.rootURL, startImmediately: false)
        }

        let weakRefs = vibespace.projects.map { WeakRef($0) }

        vibespace.resetSession()

        let leakedCount = weakRefs.filter { $0.value != nil }.count
        XCTAssertEqual(leakedCount, 0, "\(leakedCount) old ProjectSession(s) leaked after resetSession")
        XCTAssertEqual(vibespace.projects.count, 0, "Projects should be empty after resetSession (recreated on reopen)")
    }

    func testCloseVibeSpaceSessionFullFlow() throws {
        let projectDir = tempRoot.appendingPathComponent("ws-proj", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(id: UUID(), name: "WS", projectURLs: [projectDir])
        vibespace.projects[0].activateIfNeeded()
        vibespace.projects[0].terminalViewModel.createTab(directoryURL: projectDir, startImmediately: false)
        vibespace.projects[0].terminalViewModel.createTab(directoryURL: projectDir, startImmediately: false)
        vibespace.projects[0].ensureExplorerLoadedIfNeeded()

        weak var weakProject = vibespace.projects[0]
        weak var weakVM = vibespace.projects[0].terminalViewModel
        weak var weakExplorer = vibespace.projects[0].folderExplorerViewModel
        let weakSessions = vibespace.projects[0].terminalViewModel.tabs.compactMap {
            vibespace.projects[0].terminalViewModel.session(for: $0.id)
        }.map { WeakRef($0) }

        // Simulate closeActiveVibeSpaceSession:
        vibespace.resetSession()
        container.terminalBoardStandaloneRegistry.release(vibespaceID: vibespace.id)

        XCTAssertNil(weakProject, "ProjectSession should deallocate after close vibespace flow")
        XCTAssertNil(weakVM, "TerminalViewModel should deallocate after close vibespace flow")
        XCTAssertNil(weakExplorer, "FolderExplorerViewModel should deallocate after close vibespace flow")
        for (i, ref) in weakSessions.enumerated() {
            XCTAssertNil(ref.value, "TerminalSession[\(i)] should deallocate after close vibespace flow")
        }
    }

    // MARK: - VibeSpaceSourceControlViewModel

    func testSourceControlViewModelDeallocatesWhenReleased() {
        var vm: VibeSpaceSourceControlViewModel? = container.makeVibeSpaceSourceControlViewModel()
        weak var weakVM = vm

        vm = nil

        XCTAssertNil(weakVM, "VibeSpaceSourceControlViewModel should deallocate when released")
    }

    func testSourceControlViewModelReleasesProjectWatchersOnUpdate() {
        let vm = container.makeVibeSpaceSourceControlViewModel()
        var project: AnyProjectSession? = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)
        project!.activateIfNeeded()
        project!.ensureExplorerLoadedIfNeeded()
        weak var weakProject = project

        vm.updateVibeSpace(projects: [project!], focusedProject: project, selectedFileURL: nil)
        // Remove project
        vm.updateVibeSpace(projects: [], focusedProject: nil, selectedFileURL: nil)
        project!.shutdown()
        project = nil

        XCTAssertNil(weakProject, "ProjectSession should deallocate after being removed from source control VM")
    }
}

// MARK: - Helpers

private final class WeakRef<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

@MainActor
private func drainRunLoop(cycles: Int = 3) {
    for _ in 0..<cycles {
        autoreleasepool {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
}
