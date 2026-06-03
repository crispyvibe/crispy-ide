import XCTest
@testable import CrispyVibes

@MainActor
final class TerminalBehavioralTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
        tempRoot = base.appendingPathComponent("crispyvibes-behavioral-terminal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }

    func testProjectSessionTerminalPersistenceRoundTripFlow() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let appStore = AppPersistenceDataStore(fileManager: .default, appDirectoryURL: tempRoot)
        let persistenceStore = VibeSpacePersistenceStore(store: appStore)
        let vibespaceManagement = VibeSpaceManagementService(persistenceStore: persistenceStore)
        let vibespaceID = UUID()

        let layoutStore = LayoutPersistenceService(fileManager: .default)
        layoutStore.setVibeSpacePersistenceStore(persistenceStore)

        let defaultsSuite = "crispyvibes.behavioral.terminal.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let terminalDeps = TerminalViewModelDependencies(
            presetDiagnostics: TerminalPresetAvailabilityDiagnostics(defaults: defaults),
            shortcutStore: TerminalShortcutStore(defaults: defaults),
            terminalServices: TerminalServices()
        )
        let sessionDeps = ProjectSessionDependencies(
            layoutPersistence: layoutStore,
            vibespaceManagement: vibespaceManagement,
            vibespaceID: vibespaceID,
            folderExplorerViewModelFactory: {
                FolderExplorerViewModel(worker: self.container.makePaneWorker(pane: .explorer))
            },
            terminalViewModelFactory: {
                TerminalViewModel(
                    dependencies: terminalDeps,
                    worker: self.container.makePaneWorker(pane: .terminal)
                )
            },
            detachedWindowManager: container.detachedWindowManager,
            directoryWatcher: DirectoryWatcher()
        )

        let firstSession = ProjectSession(rootURL: projectRoot, dependencies: sessionDeps)
        firstSession.activateIfNeeded()
        _ = firstSession.terminalViewModel.createUserTab(defaultDirectory: projectRoot)

        let persistExpectation = expectation(description: "terminal state persisted")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let loaded = vibespaceManagement.loadProjectSession(forProject: projectRoot.path, in: vibespaceID)
            XCTAssertNotNil(loaded)
            XCTAssertGreaterThanOrEqual(loaded?.entries.count ?? 0, 1)
            persistExpectation.fulfill()
        }
        wait(for: [persistExpectation], timeout: 1.5)

        let restoredSession = ProjectSession(rootURL: projectRoot, dependencies: sessionDeps)
        restoredSession.activateIfNeeded()
        XCTAssertGreaterThanOrEqual(restoredSession.terminalViewModel.tabs.count, 1)
        XCTAssertNotNil(restoredSession.terminalViewModel.activeTab)
    }
}
