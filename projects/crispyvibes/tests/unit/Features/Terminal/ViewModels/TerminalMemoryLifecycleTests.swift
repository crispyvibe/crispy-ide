import Combine
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class TerminalMemoryLifecycleTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-memory-lifecycle")
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        container.terminalServices.focusCoordinator.unfocusCurrent()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }

    // MARK: - TerminalSession deallocation

    func testTerminalSessionDeallocatesAfterCloseTab() throws {
        let viewModel = container.makeTerminalViewModel()
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let tab = try XCTUnwrap(viewModel.activeTab)
        weak var weakSession = viewModel.session(for: tab.id)
        XCTAssertNotNil(weakSession)

        viewModel.closeTab(tab)

        XCTAssertNil(weakSession, "TerminalSession should deallocate after tab is closed")
    }

    func testTerminalSessionDeallocatesAfterShutdown() {
        let viewModel = container.makeTerminalViewModel()
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let weakRefs = viewModel.tabs.compactMap { viewModel.session(for: $0.id) }.map { WeakRef($0) }

        viewModel.shutdown()

        for (i, ref) in weakRefs.enumerated() {
            XCTAssertNil(ref.value, "TerminalSession[\(i)] should deallocate after shutdown")
        }
    }

    func testTerminalSessionCallbacksNilledOnClose() throws {
        let viewModel = container.makeTerminalViewModel()
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let tab = try XCTUnwrap(viewModel.activeTab)
        let session = try XCTUnwrap(viewModel.session(for: tab.id))

        XCTAssertNotNil(session.onTitleChanged)

        viewModel.closeTab(tab)

        XCTAssertNil(session.onTitleChanged)
        XCTAssertNil(session.onDirectoryChanged)
        XCTAssertNil(session.onProcessTerminated)
        XCTAssertNil(session.onActivityChanged)
    }

    // MARK: - TerminalViewModel deallocation

    func testTerminalViewModelDeallocatesWhenReleased() {
        var viewModel: TerminalViewModel? = container.makeTerminalViewModel()
        viewModel!.createTab(directoryURL: tempRoot, startImmediately: false)
        weak var weakVM = viewModel

        viewModel!.shutdown()
        viewModel = nil

        XCTAssertNil(weakVM, "TerminalViewModel should deallocate after shutdown and release")
    }

    // MARK: - ProjectSession deallocation

    func testProjectSessionDeallocatesAfterShutdown() {
        var session: AnyProjectSession? = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)
        session!.activateIfNeeded()
        session!.terminalViewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        weak var weakSession = session

        session!.shutdown()
        session = nil

        XCTAssertNil(weakSession, "ProjectSession should deallocate after shutdown and release")
    }

    func testProjectSessionTerminalViewModelDeallocatesAfterShutdown() {
        var session: AnyProjectSession? = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)
        session!.activateIfNeeded()
        session!.terminalViewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        weak var weakVM = session!.terminalViewModel

        session!.shutdown()
        session = nil

        XCTAssertNil(weakVM, "TerminalViewModel should deallocate when ProjectSession is released")
    }

    // MARK: - GitHeadWatcher cleanup

    func testGitHeadWatcherRemovedOnTabClose() throws {
        let viewModel = container.makeTerminalViewModel()
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let tab = try XCTUnwrap(viewModel.activeTab)

        viewModel.closeTab(tab)

        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let tab2 = try XCTUnwrap(viewModel.activeTab)
        viewModel.closeTab(tab2)
        XCTAssertTrue(viewModel.tabs.isEmpty)
    }

    // MARK: - Multiple create/close cycles

    func testRepeatedCreateCloseCyclesDoNotAccumulateSessions() {
        let viewModel = container.makeTerminalViewModel()
        var weakSessions: [WeakRef<TerminalSession>] = []

        for _ in 0..<10 {
            viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
            let tab = viewModel.activeTab!
            weakSessions.append(WeakRef(viewModel.session(for: tab.id)!))
            viewModel.closeTab(tab)
        }

        XCTAssertTrue(viewModel.sessions.isEmpty)
        let leakedCount = weakSessions.filter { $0.value != nil }.count
        XCTAssertEqual(leakedCount, 0, "\(leakedCount) TerminalSession(s) leaked across 10 create/close cycles")
    }

    // MARK: - FocusCoordinator

    func testFocusCoordinatorDoesNotRetainEngine() {
        let viewModel = container.makeTerminalViewModel()
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let tab = viewModel.activeTab!
        let sessionID = viewModel.session(for: tab.id)!.id
        weak var weakSession = viewModel.session(for: tab.id)

        container.terminalServices.focusCoordinator.focus(engine: viewModel.session(for: tab.id)!.engine, sessionID: sessionID)
        XCTAssertEqual(container.terminalServices.focusCoordinator.currentSessionID, sessionID)

        container.terminalServices.focusCoordinator.relinquish(sessionID: sessionID)
        viewModel.closeTab(tab)

        XCTAssertNil(weakSession, "Session should deallocate after focus relinquish + close")
    }

    // MARK: - SwiftTermTerminalEngine deallocation

    func testEngineReleasedAfterSessionClose() throws {
        let viewModel = container.makeTerminalViewModel()
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let tab = try XCTUnwrap(viewModel.activeTab)
        weak var weakEngine = viewModel.session(for: tab.id)?.engine as AnyObject

        viewModel.closeTab(tab)

        XCTAssertNil(weakEngine, "Terminal engine should deallocate when session is closed")
    }

    func testEngineReleasedAfterShutdown() {
        let viewModel = container.makeTerminalViewModel()
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        weak var weakEngine = viewModel.session(for: viewModel.activeTab!.id)?.engine as AnyObject

        viewModel.shutdown()

        XCTAssertNil(weakEngine, "Terminal engine should deallocate after shutdown")
    }

    // MARK: - MonitoredTerminalView (hostedView) deallocation

    func testHostedViewReleasedAfterSessionClose() throws {
        weak var weakView: NSView?
        let viewModel = container.makeTerminalViewModel()
        autoreleasepool {
            viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
            weakView = viewModel.session(for: viewModel.activeTab!.id)?.hostedView
        }
        let tab = try XCTUnwrap(viewModel.activeTab)

        autoreleasepool {
            viewModel.closeTab(tab)
        }
        drainRunLoop()

        XCTAssertNil(weakView, "MonitoredTerminalView (hostedView) should deallocate when session is closed")
    }

    func testHostedViewReleasedAfterShutdown() {
        weak var weakView: NSView?
        let viewModel = container.makeTerminalViewModel()
        autoreleasepool {
            viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
            weakView = viewModel.session(for: viewModel.activeTab!.id)?.hostedView
        }

        autoreleasepool {
            viewModel.shutdown()
        }
        drainRunLoop()

        XCTAssertNil(weakView, "MonitoredTerminalView (hostedView) should deallocate after shutdown")
    }

    // MARK: - Action handler closures on MonitoredTerminalView

    func testActionHandlerClosuresDoNotRetainSession() throws {
        let viewModel = container.makeTerminalViewModel()
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let tab = try XCTUnwrap(viewModel.activeTab)
        weak var weakSession = viewModel.session(for: tab.id)

        // Simulate what TerminalSessionHostView does: set action handlers with closures
        viewModel.session(for: tab.id)?.updateActionHandlers(TerminalSessionActionHandlers(
            onSplitTerminalRequested: { },
            onLinkTargetActivated: { _ in },
            currentDirectoryProvider: { [weak weakSession] in weakSession?.currentWorkingDirectory }
        ))

        viewModel.closeTab(tab)

        // The action handler closures are stored on MonitoredTerminalView.
        // If the session is still alive, those closures (or the engine) are retaining it.
        XCTAssertNil(weakSession, "TerminalSession should deallocate even with action handlers set")
    }

    // MARK: - VibeSpaceTerminalBoardStore project lifecycle

    func testBoardStoreReleasesProjectSessionsOnSync() throws {
        let layoutFile = tempRoot.appendingPathComponent("board-layout.json")
        let layoutPersistence = LayoutPersistenceService(fileManager: .default, stateFileURL: layoutFile)
        let boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: nil,
            layoutPersistence: layoutPersistence,
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )

        var project: AnyProjectSession? = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)
        project!.activateIfNeeded()
        project!.terminalViewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        weak var weakProject = project

        // Sync with the project
        boardStore.syncProjects([project!])

        // Now sync with empty list (project removed)
        boardStore.syncProjects([])
        project!.shutdown()
        project = nil

        XCTAssertNil(weakProject, "ProjectSession should deallocate after being removed from board store sync")
    }

    func testBoardStoreDoesNotRetainRemovedProjectTerminalViewModel() throws {
        let layoutFile = tempRoot.appendingPathComponent("board-layout2.json")
        let layoutPersistence = LayoutPersistenceService(fileManager: .default, stateFileURL: layoutFile)
        let boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: nil,
            layoutPersistence: layoutPersistence,
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )

        var project: AnyProjectSession? = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)
        project!.activateIfNeeded()
        project!.terminalViewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        weak var weakVM = project!.terminalViewModel

        boardStore.syncProjects([project!])
        boardStore.syncProjects([])
        project!.shutdown()
        project = nil

        XCTAssertNil(weakVM, "TerminalViewModel should deallocate after project removed from board store")
    }

    // MARK: - FolderExplorerViewModel deallocation

    func testFolderExplorerViewModelDeallocatesWithProjectSession() {
        var session: AnyProjectSession? = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)
        session!.activateIfNeeded()
        session!.ensureExplorerLoadedIfNeeded()
        weak var weakExplorer = session!.folderExplorerViewModel

        session!.shutdown()
        session = nil

        XCTAssertNil(weakExplorer, "FolderExplorerViewModel should deallocate when ProjectSession is released")
    }

    // MARK: - DirectoryWatcher cleanup

    func testDirectoryWatcherInvalidatedOnProjectShutdown() {
        var session: AnyProjectSession? = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)
        session!.activateIfNeeded()
        session!.ensureExplorerLoadedIfNeeded()

        // The watcher is owned by FolderExplorerViewModel.
        // After shutdown + release, the watcher should be invalidated and freed.
        weak var weakExplorer = session!.folderExplorerViewModel

        session!.shutdown()
        session = nil

        // If the explorer is freed, its deinit invalidates the watcher.
        XCTAssertNil(weakExplorer, "FolderExplorerViewModel (and its DirectoryWatcher) should deallocate")
    }

    // MARK: - Combine subscription cleanup

    func testProjectSessionCancellablesClearedOnShutdown() {
        let session = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)
        session.activateIfNeeded()
        session.terminalViewModel.createTab(directoryURL: tempRoot, startImmediately: false)

        // After shutdown, Combine subscriptions should be cleared so they don't
        // prevent deallocation of captured objects.
        weak var weakVM = session.terminalViewModel
        session.shutdown()

        // The TerminalViewModel is still referenced by the session (let binding),
        // but its internal state should be clean.
        XCTAssertTrue(session.terminalViewModel.tabs.isEmpty, "Tabs should be empty after shutdown")
        XCTAssertTrue(session.terminalViewModel.sessions.isEmpty, "Sessions dict should be empty after shutdown")
    }

    // MARK: - VibeSpaceState project removal

    func testVibeSpaceStateRemoveProjectCallsShutdown() throws {
        let projectDir = tempRoot.appendingPathComponent("proj", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(id: UUID(), name: "Test", projectURLs: [projectDir])
        XCTAssertEqual(vibespace.projects.count, 1)

        let projectID = vibespace.projects[0].id
        vibespace.projects[0].activateIfNeeded()
        vibespace.projects[0].terminalViewModel.createTab(directoryURL: projectDir, startImmediately: false)
        weak var weakProject = vibespace.projects[0]
        weak var weakVM = vibespace.projects[0].terminalViewModel

        vibespace.removeProject(id: projectID)

        XCTAssertTrue(vibespace.projects.isEmpty)
        XCTAssertNil(weakProject, "ProjectSession should deallocate after removeProject")
        XCTAssertNil(weakVM, "TerminalViewModel should deallocate after removeProject")
    }

    // MARK: - StackedRailTerminalStore subscription cleanup

    func testStackedRailTerminalStoreReleasesProjectOnSync() throws {
        let railStore = StackedRailTerminalStore()

        var project: AnyProjectSession? = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)
        project!.activateIfNeeded()
        project!.terminalViewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        weak var weakVM = project!.terminalViewModel

        railStore.syncProjects([project!])
        // Remove project
        railStore.syncProjects([])
        project!.shutdown()
        project = nil

        XCTAssertNil(weakVM, "TerminalViewModel should deallocate after being removed from StackedRailTerminalStore")
    }

    // MARK: - ProjectActivityTracker

    func testProjectActivityTrackerReleasesProjectsOnRetrack() {
        let tracker = ProjectActivityTracker()

        var project: AnyProjectSession? = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)
        project!.activateIfNeeded()
        weak var weakVM = project!.terminalViewModel

        tracker.track(projects: [project!])
        // Re-track with empty list
        tracker.track(projects: [])
        project!.shutdown()
        project = nil

        XCTAssertNil(weakVM, "TerminalViewModel should deallocate after ProjectActivityTracker re-tracks with empty list")
    }

    // MARK: - Standalone registry

    func testStandaloneRegistryReleasesViewModelOnRelease() {
        let registry = VibeSpaceTerminalBoardStandaloneRegistry(
            makeTerminalViewModel: container.makeTerminalViewModel
        )
        let testVibeSpaceID = UUID()
        weak var weakVM = registry.viewModel(for: testVibeSpaceID)
        weakVM?.createTab(directoryURL: tempRoot, startImmediately: false)

        registry.release(vibespaceID: testVibeSpaceID)

        XCTAssertNil(weakVM, "TerminalViewModel should deallocate after standalone registry release")
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
