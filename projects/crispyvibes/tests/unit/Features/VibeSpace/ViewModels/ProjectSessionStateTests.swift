import AppKit
import Foundation
import PDFKit
import SwiftUI
import XCTest
@testable import CrispyVibes

@MainActor
final class ProjectSessionStateTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!
    private var layoutStateFileURL: URL!
    private var vibespaceManagement: VibeSpaceManagementService!
    private let vibespaceID = UUID()

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-project-session-state")
        container = AppContainer.makeDefault()
        layoutStateFileURL = tempRoot.appendingPathComponent("layout.json")
        let appStore = AppPersistenceDataStore(fileManager: .default, appDirectoryURL: tempRoot)
        let persistenceStore = VibeSpacePersistenceStore(store: appStore)
        vibespaceManagement = VibeSpaceManagementService(persistenceStore: persistenceStore)
    }

    override func tearDownWithError() throws {
        container.terminalServices.focusCoordinator.unfocusCurrent()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }

    func testActivateStartsProjectRootWatchingWithoutExplorerLoad() {
        let layoutPersistence = LayoutPersistenceService(fileManager: .default, stateFileURL: layoutStateFileURL)
        let spy = SpyFileSystemWatcher()
        var deps = makeProjectSessionDependencies(layoutPersistence: layoutPersistence)
        deps.directoryWatcher = spy
        let session = ProjectSession(rootURL: tempRoot, dependencies: deps)

        // Activation (hydration) — NOT ensureExplorerLoaded — must start watching.
        session.activateIfNeeded()
        XCTAssertEqual(spy.watchedPaths, [tempRoot.standardizedFileURL.path])
        XCTAssertNotNil(spy.onEvent, "session should wire the watcher event handler at activate()")

        session.shutdown()
        XCTAssertTrue(spy.invalidated, "session.shutdown() must invalidate the watcher")
    }

    func testActivateRestoresEscapedPathsAndPaneLayoutFromPersistence() async throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let nested = projectRoot.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let layoutPersistence = LayoutPersistenceService(
            fileManager: .default,
            stateFileURL: layoutStateFileURL
        )
        let expectedLayout = ProjectPaneLayoutState(
            explorerFraction: 0.41,
            terminalFraction: 0.52,
            explorerPoints: 240,
            terminalPoints: 220
        )
        layoutPersistence.setPaneLayout(expectedLayout, for: projectRoot)

        let escapedNestedPath = nested.standardizedFileURL.path.replacingOccurrences(of: "/", with: "\\/")
        vibespaceManagement.saveProjectSession(
            entries: [TerminalSessionEntry(workingDirectoryPath: escapedNestedPath, customName: nil, origin: .adHoc)],
            activeDirectory: escapedNestedPath,
            activeIdentity: "nested-terminal",
            forProject: projectRoot.standardizedFileURL.path,
            in: vibespaceID
        )

        let session = ProjectSession(
            rootURL: projectRoot,
            dependencies: makeProjectSessionDependencies(layoutPersistence: layoutPersistence)
        )
        session.activateIfNeeded()

        XCTAssertEqual(session.paneLayout, expectedLayout.normalized())
        XCTAssertEqual(session.terminalViewModel.tabs.count, 1)
        XCTAssertEqual(
            session.terminalViewModel.activeTab?.workingDirectory.standardizedFileURL.path,
            nested.standardizedFileURL.path
        )
        XCTAssertNil(session.folderExplorerViewModel.rootURL)

        session.ensureExplorerLoadedIfNeeded()

        let explorerLoaded = await waitForCondition(timeout: 2) {
            session.folderExplorerViewModel.rootURL?.standardizedFileURL.path == projectRoot.standardizedFileURL.path
        }
        XCTAssertTrue(explorerLoaded)
    }

    func testActivateIfNeededDoesNotLoadExplorerUntilExplicitlyRequested() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let session = ProjectSession(
            rootURL: projectRoot,
            dependencies: makeProjectSessionDependencies(
                layoutPersistence: LayoutPersistenceService(fileManager: .default, stateFileURL: layoutStateFileURL)
            )
        )

        session.activateIfNeeded()

        XCTAssertNil(session.folderExplorerViewModel.rootURL)
        XCTAssertFalse(session.folderExplorerViewModel.workerStatus.level == .busy)
    }

    func testTerminalStateChangesPersistViaVibeSpaceManagement() async throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let extraDirectory = projectRoot.appendingPathComponent("extra", isDirectory: true)
        try FileManager.default.createDirectory(at: extraDirectory, withIntermediateDirectories: true)

        let layoutPersistence = LayoutPersistenceService(
            fileManager: .default,
            stateFileURL: layoutStateFileURL
        )
        let session = ProjectSession(
            rootURL: projectRoot,
            dependencies: makeProjectSessionDependencies(layoutPersistence: layoutPersistence)
        )
        session.activateIfNeeded()

        session.terminalViewModel.createTab(directoryURL: extraDirectory, startImmediately: false)

        let persisted = await waitForCondition(timeout: 2) {
            guard let loaded = self.vibespaceManagement.loadProjectSession(
                forProject: projectRoot.standardizedFileURL.path, in: self.vibespaceID
            ) else { return false }
            return loaded.entries.contains(where: { $0.workingDirectoryPath == extraDirectory.standardizedFileURL.path })
        }
        XCTAssertTrue(persisted)
    }

    func testShutdownPersistsMultipleLocalTabsImmediately() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let session = ProjectSession(
            rootURL: projectRoot,
            dependencies: makeProjectSessionDependencies(
                layoutPersistence: LayoutPersistenceService(fileManager: .default, stateFileURL: layoutStateFileURL)
            )
        )
        session.activateIfNeeded()
        session.terminalViewModel.createTab(directoryURL: projectRoot, customName: "Logs", startImmediately: false)

        session.shutdown()

        let loaded = try XCTUnwrap(
            vibespaceManagement.loadProjectSession(
                forProject: projectRoot.standardizedFileURL.path,
                in: vibespaceID
            )
        )
        XCTAssertEqual(loaded.entries.count, 2)
        XCTAssertEqual(loaded.entries.map(\.customName), [nil, "Logs"])
    }

    func testPaneLayoutChangesPersistToLayoutService() async throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let layoutPersistence = LayoutPersistenceService(
            fileManager: .default,
            stateFileURL: layoutStateFileURL
        )
        let session = ProjectSession(
            rootURL: projectRoot,
            dependencies: makeProjectSessionDependencies(layoutPersistence: layoutPersistence)
        )
        session.activateIfNeeded()

        let raw = ProjectPaneLayoutState(
            explorerFraction: -1,
            terminalFraction: 3,
            explorerPoints: 120,
            terminalPoints: 80
        )
        let expected = raw.normalized()
        session.paneLayout = raw

        let stored = await waitForCondition(timeout: 2) {
            layoutPersistence.paneLayout(for: projectRoot) == expected
        }
        XCTAssertTrue(stored)
    }

    func testActivateIfNeededIsIdempotent() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let layoutPersistence = LayoutPersistenceService(
            fileManager: .default,
            stateFileURL: layoutStateFileURL
        )
        vibespaceManagement.saveProjectSession(
            entries: [TerminalSessionEntry(workingDirectoryPath: projectRoot.standardizedFileURL.path, customName: nil, origin: .adHoc)],
            activeDirectory: projectRoot.standardizedFileURL.path,
            activeIdentity: "project-root",
            forProject: projectRoot.standardizedFileURL.path,
            in: vibespaceID
        )

        let session = ProjectSession(
            rootURL: projectRoot,
            dependencies: makeProjectSessionDependencies(layoutPersistence: layoutPersistence)
        )
        session.activateIfNeeded()
        let initialTabCount = session.terminalViewModel.tabs.count

        session.activateIfNeeded()
        XCTAssertEqual(session.terminalViewModel.tabs.count, initialTabCount)
    }

    func testShutdownClearsExplorerCallbacks() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let session = ProjectSession(
            rootURL: projectRoot,
            dependencies: makeProjectSessionDependencies(
                layoutPersistence: LayoutPersistenceService(fileManager: .default, stateFileURL: layoutStateFileURL)
            )
        )
        session.onFileOpenRequested = { _ in }
        session.onFileRenamed = { _ in }

        session.shutdown()

        XCTAssertNil(session.onFileOpenRequested)
        XCTAssertNil(session.onFileRenamed)
    }

    func testHiddenProjectTerminalIsRemovedFromBoardWithoutClosingSession() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let secondaryDirectory = projectRoot.appendingPathComponent("secondary", isDirectory: true)
        try FileManager.default.createDirectory(at: secondaryDirectory, withIntermediateDirectories: true)

        let project = container.makeProjectSession(rootURL: projectRoot, vibespaceID: nil)
        project.terminalViewModel.createTab(directoryURL: projectRoot, startImmediately: false)
        project.terminalViewModel.createTab(directoryURL: secondaryDirectory, startImmediately: false)

        let boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: vibespaceID,
            layoutPersistence: LayoutPersistenceService(
                fileManager: .default,
                stateFileURL: layoutStateFileURL
            ),
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )

        boardStore.syncProjects([project])
        XCTAssertEqual(boardStore.layout.tiles.count, 2)

        let hiddenTab = try XCTUnwrap(project.terminalViewModel.tabs.last)
        let projectPath = project.rootURL.standardizedFileURL.path
        boardStore.setHiddenTerminalIDsByProjectPath([projectPath: [hiddenTab.id]])

        XCTAssertEqual(boardStore.layout.tiles.count, 1)
        XCTAssertFalse(boardStore.layout.tiles.contains(where: { $0.terminalTabID == hiddenTab.id }))
        XCTAssertNotNil(project.terminalViewModel.session(for: hiddenTab.id))

        boardStore.setHiddenTerminalIDsByProjectPath([:])

        XCTAssertEqual(boardStore.layout.tiles.count, 2)
        XCTAssertTrue(boardStore.layout.tiles.contains(where: { $0.terminalTabID == hiddenTab.id }))
        XCTAssertNotNil(project.terminalViewModel.session(for: hiddenTab.id))
    }

    func testBoardPasteTargetsActiveTileTerminal() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let secondaryDirectory = projectRoot.appendingPathComponent("secondary", isDirectory: true)
        try FileManager.default.createDirectory(at: secondaryDirectory, withIntermediateDirectories: true)

        let project = container.makeProjectSession(rootURL: projectRoot, vibespaceID: nil)
        project.terminalViewModel.createTab(directoryURL: projectRoot, startImmediately: false)
        project.terminalViewModel.createTab(directoryURL: secondaryDirectory, startImmediately: false)

        let boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: vibespaceID,
            layoutPersistence: LayoutPersistenceService(
                fileManager: .default,
                stateFileURL: layoutStateFileURL
            ),
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )

        boardStore.syncProjects([project])
        let tileToFocus = try XCTUnwrap(
            boardStore.layout.tiles.first(where: { $0.workingDirectoryPath == secondaryDirectory.standardizedFileURL.path })
        )

        project.terminalViewModel.selectTab(try XCTUnwrap(project.terminalViewModel.tabs.first))
        XCTAssertNotEqual(project.terminalViewModel.activeTabID, tileToFocus.terminalTabID)

        boardStore.activateTile(tileToFocus.id, requestFocus: false)
        boardStore.pasteActiveTileTerminal()

        XCTAssertEqual(project.terminalViewModel.activeTabID, tileToFocus.terminalTabID)
    }

    func testBoardFocusedSessionUpdatesActiveTileSelection() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let secondaryDirectory = projectRoot.appendingPathComponent("secondary", isDirectory: true)
        try FileManager.default.createDirectory(at: secondaryDirectory, withIntermediateDirectories: true)

        let project = container.makeProjectSession(rootURL: projectRoot, vibespaceID: nil)
        project.terminalViewModel.createTab(directoryURL: projectRoot, startImmediately: false)
        project.terminalViewModel.createTab(directoryURL: secondaryDirectory, startImmediately: false)

        let boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: vibespaceID,
            layoutPersistence: LayoutPersistenceService(
                fileManager: .default,
                stateFileURL: layoutStateFileURL
            ),
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )

        boardStore.syncProjects([project])

        let firstTile = try XCTUnwrap(boardStore.layout.tiles.first(where: { $0.workingDirectoryPath == projectRoot.standardizedFileURL.path }))
        let secondTile = try XCTUnwrap(boardStore.layout.tiles.first(where: { $0.workingDirectoryPath == secondaryDirectory.standardizedFileURL.path }))
        XCTAssertEqual(boardStore.layout.activeTileID, firstTile.id)

        boardStore.focusedSessionDidChange(to: secondTile.terminalTabID)

        XCTAssertEqual(boardStore.layout.activeTileID, secondTile.id)
    }

    func testBoardSyncIncludesFocusedProjectTerminalsEvenWhenRailExcludesFocusedProject() throws {
        let focusedRoot = tempRoot.appendingPathComponent("focused", isDirectory: true)
        let stackedRoot = tempRoot.appendingPathComponent("stacked", isDirectory: true)
        try FileManager.default.createDirectory(at: focusedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stackedRoot, withIntermediateDirectories: true)

        let vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [focusedRoot, stackedRoot])
        let focusedProject = vibespace.projects[0]
        let stackedProject = vibespace.projects[1]
        focusedProject.terminalViewModel.createTab(directoryURL: focusedRoot, startImmediately: false)
        stackedProject.terminalViewModel.createTab(directoryURL: stackedRoot, startImmediately: false)

        XCTAssertEqual(vibespace.focusedProjectID, focusedProject.id)
        XCTAssertEqual(vibespace.stackedProjects.map(\.id), [stackedProject.id])

        let boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: vibespaceID,
            layoutPersistence: LayoutPersistenceService(
                fileManager: .default,
                stateFileURL: layoutStateFileURL
            ),
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )

        boardStore.syncProjects(vibespace.projects)
        boardStore.setHiddenTerminalIDsByProjectPath([:])

        XCTAssertEqual(boardStore.layout.tiles.count, 2)
        XCTAssertTrue(boardStore.layout.tiles.contains(where: { $0.projectPath == focusedRoot.standardizedFileURL.path }))
        XCTAssertTrue(boardStore.layout.tiles.contains(where: { $0.projectPath == stackedRoot.standardizedFileURL.path }))
    }

    func testBoardSyncPublishesWhenPersistedMinimizedTileContextResolvesWithoutLayoutChange() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let project = container.makeProjectSession(rootURL: projectRoot, vibespaceID: nil)
        project.terminalViewModel.createTab(directoryURL: projectRoot, startImmediately: false)
        let tab = try XCTUnwrap(project.terminalViewModel.activeTab)
        let projectPath = project.rootURL.standardizedFileURL.path

        let layoutPersistence = LayoutPersistenceService(
            fileManager: .default,
            stateFileURL: layoutStateFileURL
        )
        let persistedLayout = VibeSpaceTerminalBoardLayout(
            columns: [],
            activeTileID: nil,
            minimizedTiles: [
                VibeSpaceTerminalBoardTile(
                    projectPath: projectPath,
                    terminalTabID: tab.id,
                    workingDirectoryPath: projectRoot.standardizedFileURL.path
                )
            ]
        )
        let persistedState = VibeSpaceTerminalBoardState(
            surfaces: [
                VibeSpaceTerminalBoardSurface(
                    id: VibeSpaceTerminalBoardState.primarySurfaceID,
                    kind: .primary,
                    layout: persistedLayout,
                    title: "Primary",
                    isOpen: true
                )
            ]
        )
        layoutPersistence.setTerminalBoardState(persistedState, for: vibespaceID)

        let boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: vibespaceID,
            layoutPersistence: layoutPersistence,
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )

        let minimizedTile = try XCTUnwrap(boardStore.layout.minimizedTiles.first)
        XCTAssertNil(boardStore.tileContext(for: minimizedTile), "Context should be unresolved before project sync")

        var publishCount = 0
        let cancellable = boardStore.objectWillChange.sink { publishCount += 1 }
        defer { cancellable.cancel() }

        boardStore.syncProjects([project])

        let resolvedTile = try XCTUnwrap(boardStore.layout.minimizedTiles.first)
        XCTAssertNotNil(boardStore.tileContext(for: resolvedTile), "Project sync should resolve minimized tile context")
        XCTAssertEqual(boardStore.layout.minimizedTiles.count, 1, "Resolved minimized tile should remain minimized")
        XCTAssertGreaterThan(publishCount, 0, "Board store should publish even when layout is unchanged")
    }

    func testBoardSyncDoesNotCreateAdditionalTabsDuringRepeatedReconciliation() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let secondaryDirectory = projectRoot.appendingPathComponent("secondary", isDirectory: true)
        try FileManager.default.createDirectory(at: secondaryDirectory, withIntermediateDirectories: true)

        let project = container.makeProjectSession(rootURL: projectRoot, vibespaceID: nil)
        project.terminalViewModel.createTab(directoryURL: projectRoot, startImmediately: false)
        project.terminalViewModel.createTab(directoryURL: secondaryDirectory, startImmediately: false)
        let initialTabIDs = project.terminalViewModel.tabs.map(\.id)

        let boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: vibespaceID,
            layoutPersistence: LayoutPersistenceService(
                fileManager: .default,
                stateFileURL: layoutStateFileURL
            ),
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )

        boardStore.syncProjects([project])
        let initialTileIDs = boardStore.layout.tiles.map(\.terminalTabID)

        for _ in 0..<20 {
            boardStore.reconcileTerminalTiles()
            boardStore.syncProjects([project])
        }

        XCTAssertEqual(project.terminalViewModel.tabs.map(\.id), initialTabIDs)
        XCTAssertEqual(boardStore.layout.tiles.map(\.terminalTabID), initialTileIDs)
        XCTAssertEqual(boardStore.layout.tiles.count, initialTabIDs.count)
    }

    func testRestoredCustomBoardArrangementSurvivesReconcile() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let dirB = projectRoot.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        let fileURL = projectRoot.appendingPathComponent("TODO.md")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))
        let projectPath = projectRoot.standardizedFileURL.path

        let project = container.makeProjectSession(rootURL: projectRoot, vibespaceID: vibespaceID)
        project.terminalViewModel.createTab(directoryURL: projectRoot, startImmediately: false)
        project.terminalViewModel.createTab(directoryURL: projectRoot, startImmediately: false)
        project.terminalViewModel.createTab(directoryURL: dirB, startImmediately: false)

        // Persist a CUSTOM 2-column arrangement. Terminal tiles reference ids that
        // differ from the live tabs (as on restore) but match working directories;
        // a file tile sits at col0 row1 (not a default position).
        let layoutPersistence = LayoutPersistenceService(fileManager: .default, stateFileURL: layoutStateFileURL)
        func term(_ dir: URL) -> VibeSpaceTerminalBoardTile {
            VibeSpaceTerminalBoardTile(
                projectPath: projectPath,
                terminalTabID: UUID(),
                workingDirectoryPath: dir.standardizedFileURL.path
            )
        }
        let fileTile = VibeSpaceTerminalBoardTile(workingDirectoryPath: "", contentKind: .file(fileURL))
        let layout = VibeSpaceTerminalBoardLayout(
            columns: [
                VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [term(projectRoot), fileTile]),
                VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [term(dirB), term(projectRoot)]),
            ],
            activeTileID: nil
        )
        layoutPersistence.setTerminalBoardState(.fromLegacyLayout(layout), for: vibespaceID)

        let boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: vibespaceID,
            layoutPersistence: layoutPersistence,
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )
        func structure() -> [[String]] {
            boardStore.layout.columns.map { col in
                col.tiles.map { $0.isFile ? "file" : ($0.isTerminal ? "terminal" : "other") }
            }
        }
        let before = structure()
        XCTAssertEqual(before, [["terminal", "file"], ["terminal", "terminal"]])

        // Restore timing: the project is transiently absent from the snapshot
        // (e.g. a remote project still resolving/connecting) before it resolves.
        boardStore.syncProjects([])
        boardStore.syncProjects([project]) // triggers reconcileTerminalTiles

        XCTAssertEqual(structure(), before, "restored custom board arrangement must survive reconcile")
    }

    private func makeProjectSessionDependencies(
        layoutPersistence: LayoutPersistenceService
    ) -> ProjectSessionDependencies {
        ProjectSessionDependencies(
            layoutPersistence: layoutPersistence,
            vibespaceManagement: vibespaceManagement,
            vibespaceID: vibespaceID,
            folderExplorerViewModelFactory: container.makeFolderExplorerViewModel,
            terminalViewModelFactory: container.makeTerminalViewModel,
            detachedWindowManager: container.detachedWindowManager,
            directoryWatcher: DirectoryWatcher()
        )
    }
}

private final class SpyFileSystemWatcher: FileSystemEventWatching {
    var onEvent: ((DirectoryWatcher.Event) -> Void)?
    private(set) var watchedPaths: Set<String> = []
    private(set) var invalidated = false
    func setOnEvent(_ onEvent: @escaping (DirectoryWatcher.Event) -> Void) { self.onEvent = onEvent }
    func updateWatchedPaths(_ paths: Set<String>) { watchedPaths = paths }
    func invalidate() { invalidated = true }
}
