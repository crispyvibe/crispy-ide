import XCTest
@testable import CrispyVibes

@MainActor
final class AppShellBehavioralTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
        tempRoot = base.appendingPathComponent("crispyvibes-behavioral-app-shell-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testVibeSpaceCreateAndLoadRoundTripFlow() throws {
        let project = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let store = AppPersistenceDataStore(fileManager: .default, appDirectoryURL: tempRoot)
        let persistenceStore = VibeSpacePersistenceStore(store: store)
        let service = VibeSpaceManagementService(persistenceStore: persistenceStore)

        let config = VibeSpaceConfigFile(
            id: UUID(),
            name: "Fixture",
            projectPaths: [project.path],
            unresolvedProjectPaths: [],
            focusedProjectPath: project.path,
            startupSettings: .default,
            defaultTerminalShell: nil
        )
        service.saveVibeSpaceConfig(config)
        service.touchRecent(config.id)

        let recentIDs = service.recentVibeSpaceIDs()
        XCTAssertEqual(recentIDs, [config.id])

        guard let (loaded, trusted) = service.loadVibeSpace(id: config.id) else {
            return XCTFail("VibeSpace should load")
        }
        XCTAssertEqual(loaded.name, "Fixture")
        XCTAssertEqual(loaded.projectPaths, [project.path])
        XCTAssertTrue(trusted)
    }
}
