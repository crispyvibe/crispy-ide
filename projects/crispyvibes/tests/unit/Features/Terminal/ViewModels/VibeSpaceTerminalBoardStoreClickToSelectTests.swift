import Combine
import Foundation
import XCTest
@testable import CrispyVibes

/// F021-R17: verifies that `VibeSpaceTerminalBoardStore.activateTile` surfaces
/// tile activation as a `.boardTileActivated` notification carrying the tile's
/// project path, which the click-to-select listener consumes to switch focused
/// project. Idempotency at the listener level is covered by the parking tests
/// against the actions coordinator.
@MainActor
final class VibeSpaceTerminalBoardStoreClickToSelectTests: XCTestCase {
    var container: AppContainer!
    var boardStore: VibeSpaceTerminalBoardStore!
    var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-board-click-to-select")
        container = AppContainer.makeDefault()
        boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: nil,
            layoutPersistence: container.layoutPersistence,
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        boardStore = nil
        container = nil
    }

    func testActivateTilePostsBoardTileActivatedWithProjectPath() throws {
        // Wire a real project session so the board store can resolve the tile's
        // owning project path (otherwise addTile falls through to standalone).
        let projectURL = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let projectPath = projectURL.standardizedFileURL.path
        let session = AnyProjectSession(ProjectSession(
            rootURL: projectURL,
            dependencies: ProjectSessionDependencies(
                layoutPersistence: container.layoutPersistence,
                vibespaceManagement: container.vibespaceManagement,
                folderExplorerViewModelFactory: container.makeFolderExplorerViewModel,
                terminalViewModelFactory: container.makeTerminalViewModel,
                detachedWindowManager: container.detachedWindowManager
            )
        ))
        boardStore.syncProjects([session])

        // Add two tiles owned by the project. The second is the active one
        // after addTile, so activating the first will mutate state and trigger
        // the notification.
        _ = boardStore.addTile(projectPath: projectPath, directoryURL: projectURL, preferStandalone: false)
        _ = boardStore.addTile(projectPath: projectPath, directoryURL: projectURL, preferStandalone: false)
        let firstTile = try XCTUnwrap(boardStore.layout.tiles.first)
        XCTAssertEqual(firstTile.projectPath, projectPath, "tile must be created with projectPath set")

        let expectation = expectation(description: ".boardTileActivated posted")
        var capturedProjectPath: String?
        let observer = NotificationCenter.default.addObserver(
            forName: .boardTileActivated,
            object: nil,
            queue: .main
        ) { notification in
            capturedProjectPath = notification.userInfo?["projectPath"] as? String
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        boardStore.activateTile(firstTile.id, requestFocus: false)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(capturedProjectPath, projectPath)

        session.shutdown()
    }

    func testActivateTileWithoutProjectPathOmitsKey() throws {
        // A tile with no project association (e.g., a standalone terminal not
        // tied to a project) should still post the notification, but with an
        // empty userInfo so the listener can ignore it.
        _ = boardStore.addTile(projectPath: nil, directoryURL: tempRoot, preferStandalone: true)
        _ = boardStore.addTile(projectPath: nil, directoryURL: tempRoot, preferStandalone: true)
        let firstTile = try XCTUnwrap(boardStore.layout.tiles.first)

        let expectation = expectation(description: ".boardTileActivated posted")
        var capturedUserInfo: [AnyHashable: Any]?
        let observer = NotificationCenter.default.addObserver(
            forName: .boardTileActivated,
            object: nil,
            queue: .main
        ) { notification in
            capturedUserInfo = notification.userInfo
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        boardStore.activateTile(firstTile.id, requestFocus: false)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertNil(capturedUserInfo?["projectPath"])
    }
}
