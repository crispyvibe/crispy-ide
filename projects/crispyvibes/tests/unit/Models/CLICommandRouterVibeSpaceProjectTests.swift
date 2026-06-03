import Foundation
import XCTest
@testable import CrispyVibes

/// F044-R80 / R81 / R82: handler-level tests for `vibespace.addProject`,
/// `vibespace.removeProject`, `vibespace.parkProject`.
///
/// Each test wires a fresh `CLICommandRouter` + `VibeSpaceCatalogStore` +
/// `VibeSpaceCanvasActionsCoordinator` against a temp project directory.
/// Behavior asserts on the response payload AND on observable state in the
/// catalog store, so we catch breakages in either layer.
@MainActor
final class CLICommandRouterVibeSpaceProjectTests: XCTestCase {
    var container: AppContainer!
    var tempRoot: URL!
    var router: CLICommandRouter!
    var catalog: VibeSpaceCatalogStore!
    var actions: VibeSpaceCanvasActionsCoordinator!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-cli-vibespace")
        container = AppContainer.makeDefault()
        router = CLICommandRouter(shelfStore: container.shelfStore)
        catalog = container.makeVibeSpaceCatalogStore()
        let projectURL = tempRoot.appendingPathComponent("seed", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [projectURL])
        catalog.replaceDisplayedVibeSpace(with: vibespace)
        router.attachVibeSpaceCatalogStore(catalog)
        actions = makeActionsCoordinator()
        router.attachVibeSpaceActionsCoordinator(actions)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        actions = nil
        catalog?.clearDisplayedVibeSpaces()
        catalog = nil
        router = nil
        container?.terminalServices.focusCoordinator.unfocusCurrent()
        container = nil
    }

    // MARK: - Helpers

    private func makeActionsCoordinator() -> VibeSpaceCanvasActionsCoordinator {
        let appShellStore = container.makeAppShellStore()
        // The coordinator's parkProject reads vibespaceID from
        // appShellStore.activeVibeSpaceID; without this the guard short-circuits.
        appShellStore.showVibeSpace(catalog.vibespaces.first!.id)
        let splitViewStore = container.makeSplitViewStore()
        let contentViewerStore = container.makeContentViewerStore()
        let hydration = VibeSpaceHydrationCoordinator(
            appShellStore: appShellStore,
            vibespaceCatalogStore: catalog,
            layoutPersistence: container.layoutPersistence,
            splitViewStore: splitViewStore,
            contentViewerStore: contentViewerStore
        )
        let coordinator = VibeSpaceCanvasActionsCoordinator(
            appShellStore: appShellStore,
            vibespaceCatalogStore: catalog,
            vibespaceManagement: container.vibespaceManagement,
            vibespaceHydrationCoordinator: hydration,
            vibespaceInteraction: container.vibespaceInteraction,
            splitViewStore: splitViewStore,
            contentViewerStore: contentViewerStore,
            layoutPersistence: container.layoutPersistence
        )
        // The test coordinator is constructed without dockedBrowserCoordinator.
        // remove/park flows tolerate a nil weak ref (no browsers to close).
        return coordinator
    }

    private func request(_ method: String, params: [String: CLIJSONValue]) -> CLIRequest {
        CLIRequest(
            id: UUID().uuidString,
            method: method,
            params: params,
            _env: .empty
        )
    }

    private func successResult(_ response: CLIResponse) -> [String: CLIJSONValue]? {
        guard case let .ok(_, result) = response else { return nil }
        return result
    }

    private func errorCode(_ response: CLIResponse) -> String? {
        guard case let .error(_, code, _) = response else { return nil }
        return code
    }

    // MARK: - F044-R80: addProject

    func testAddProjectAddsAndFocuses() throws {
        let newProjectURL = tempRoot.appendingPathComponent("new", isDirectory: true)
        try FileManager.default.createDirectory(at: newProjectURL, withIntermediateDirectories: true)

        let response = router.handleVibeSpaceAddProject(request(
            "vibespace.addProject",
            params: ["path": .string(newProjectURL.path)]
        ))

        let result = try XCTUnwrap(successResult(response))
        XCTAssertEqual(result["project_path"]?.stringValue, newProjectURL.standardizedFileURL.path)
        XCTAssertEqual(result["focused"]?.boolValue, true)

        // Catalog state reflects the addition.
        let projects = try XCTUnwrap(catalog.vibespaces.first).projects
        XCTAssertEqual(projects.count, 2, "expected the seed + newly added project")
        XCTAssertTrue(projects.contains(where: { $0.projectIdentifier == newProjectURL.standardizedFileURL.path }))
    }

    func testAddProjectRejectsMissingPath() {
        let response = router.handleVibeSpaceAddProject(request(
            "vibespace.addProject",
            params: [:]
        ))
        XCTAssertEqual(errorCode(response), CLIErrorCode.invalidParams)
    }

    func testAddProjectRejectsNonexistentDirectory() {
        let nonexistent = tempRoot.appendingPathComponent("nope", isDirectory: true).path
        let response = router.handleVibeSpaceAddProject(request(
            "vibespace.addProject",
            params: ["path": .string(nonexistent)]
        ))
        XCTAssertEqual(errorCode(response), CLIErrorCode.fileNotFound)
    }

    func testAddProjectRejectsDuplicate() {
        // Seed project is already in the vibespace.
        let seedPath = tempRoot.appendingPathComponent("seed", isDirectory: true).path
        let response = router.handleVibeSpaceAddProject(request(
            "vibespace.addProject",
            params: ["path": .string(seedPath)]
        ))
        XCTAssertEqual(errorCode(response), CLIErrorCode.invalidParams)
    }

    // MARK: - F044-R81: removeProject

    func testRemoveProjectRemovesByPath() throws {
        let extraURL = tempRoot.appendingPathComponent("extra", isDirectory: true)
        try FileManager.default.createDirectory(at: extraURL, withIntermediateDirectories: true)
        _ = router.handleVibeSpaceAddProject(request(
            "vibespace.addProject",
            params: ["path": .string(extraURL.path)]
        ))
        XCTAssertEqual(catalog.vibespaces.first?.projects.count, 2)

        let response = router.handleVibeSpaceRemoveProject(request(
            "vibespace.removeProject",
            params: ["path": .string(extraURL.path)]
        ))

        let result = try XCTUnwrap(successResult(response))
        XCTAssertEqual(result["removed_project_path"]?.stringValue, extraURL.standardizedFileURL.path)
        let remaining = try XCTUnwrap(catalog.vibespaces.first).projects
        XCTAssertEqual(remaining.count, 1)
        XCTAssertFalse(remaining.contains(where: { $0.projectIdentifier == extraURL.standardizedFileURL.path }))
    }

    func testRemoveProjectErrorsForUnknownPath() {
        let response = router.handleVibeSpaceRemoveProject(request(
            "vibespace.removeProject",
            params: ["path": .string("/totally/not/here")]
        ))
        XCTAssertEqual(errorCode(response), CLIErrorCode.fileNotFound)
    }

    // MARK: - F044-R82: parkProject

    func testParkProjectMovesPathToParked() throws {
        let extraURL = tempRoot.appendingPathComponent("extra-park", isDirectory: true)
        try FileManager.default.createDirectory(at: extraURL, withIntermediateDirectories: true)
        _ = router.handleVibeSpaceAddProject(request(
            "vibespace.addProject",
            params: ["path": .string(extraURL.path)]
        ))

        let response = router.handleVibeSpaceParkProject(request(
            "vibespace.parkProject",
            params: ["path": .string(extraURL.path)]
        ))

        let result = try XCTUnwrap(successResult(response))
        XCTAssertEqual(result["parked_project_path"]?.stringValue, extraURL.standardizedFileURL.path)

        let vibespace = try XCTUnwrap(catalog.vibespaces.first)
        XCTAssertFalse(vibespace.projects.contains(where: { $0.projectIdentifier == extraURL.standardizedFileURL.path }))
        XCTAssertTrue(vibespace.parkedProjectPaths.contains(extraURL.standardizedFileURL.path))
    }

    func testParkProjectErrorsForUnknownPath() {
        let response = router.handleVibeSpaceParkProject(request(
            "vibespace.parkProject",
            params: ["path": .string("/totally/not/here")]
        ))
        XCTAssertEqual(errorCode(response), CLIErrorCode.fileNotFound)
    }

    // MARK: - F044-R83: activateProject

    func testActivateProjectUnparksAndFocuses() throws {
        let extraURL = tempRoot.appendingPathComponent("extra-activate", isDirectory: true)
        try FileManager.default.createDirectory(at: extraURL, withIntermediateDirectories: true)
        _ = router.handleVibeSpaceAddProject(request(
            "vibespace.addProject", params: ["path": .string(extraURL.path)]
        ))
        _ = router.handleVibeSpaceParkProject(request(
            "vibespace.parkProject", params: ["path": .string(extraURL.path)]
        ))
        XCTAssertTrue(try XCTUnwrap(catalog.vibespaces.first).parkedProjectPaths.contains(extraURL.standardizedFileURL.path))

        let response = router.handleVibeSpaceActivateProject(request(
            "vibespace.activateProject", params: ["path": .string(extraURL.path)]
        ))

        let result = try XCTUnwrap(successResult(response))
        XCTAssertEqual(result["activated_project_path"]?.stringValue, extraURL.standardizedFileURL.path)
        let vibespace = try XCTUnwrap(catalog.vibespaces.first)
        XCTAssertFalse(vibespace.parkedProjectPaths.contains(extraURL.standardizedFileURL.path))
        XCTAssertTrue(vibespace.projects.contains(where: { $0.projectIdentifier == extraURL.standardizedFileURL.path }))
    }

    func testActivateProjectErrorsForNonParkedPath() {
        // Seed is a live (not parked) project.
        let seedPath = tempRoot.appendingPathComponent("seed", isDirectory: true).path
        let response = router.handleVibeSpaceActivateProject(request(
            "vibespace.activateProject", params: ["path": .string(seedPath)]
        ))
        XCTAssertEqual(errorCode(response), CLIErrorCode.fileNotFound)
    }

    // MARK: - F044-R84: listProjects

    func testListProjectsReportsActiveAndParked() throws {
        let extraURL = tempRoot.appendingPathComponent("extra-list", isDirectory: true)
        try FileManager.default.createDirectory(at: extraURL, withIntermediateDirectories: true)
        _ = router.handleVibeSpaceAddProject(request(
            "vibespace.addProject", params: ["path": .string(extraURL.path)]
        ))
        _ = router.handleVibeSpaceParkProject(request(
            "vibespace.parkProject", params: ["path": .string(extraURL.path)]
        ))

        let response = router.handleVibeSpaceListProjects(request(
            "vibespace.listProjects", params: [:]
        ))

        let result = try XCTUnwrap(successResult(response))
        let active = try XCTUnwrap(result["active"]?.arrayValue)
        let parked = try XCTUnwrap(result["parked"]?.arrayValue)
        XCTAssertEqual(active.count, 1, "only the seed project remains live")
        XCTAssertEqual(
            active.first?.objectValue?["path"]?.stringValue,
            tempRoot.appendingPathComponent("seed", isDirectory: true).standardizedFileURL.path
        )
        XCTAssertEqual(parked.compactMap { $0.stringValue }, [extraURL.standardizedFileURL.path])
    }

    // MARK: - F021-R19: removeParkedProject (coordinator)

    func testCoordinatorRemoveParkedProjectDropsPath() throws {
        let extraURL = tempRoot.appendingPathComponent("extra-remove-parked", isDirectory: true)
        try FileManager.default.createDirectory(at: extraURL, withIntermediateDirectories: true)
        _ = router.handleVibeSpaceAddProject(request(
            "vibespace.addProject", params: ["path": .string(extraURL.path)]
        ))
        _ = router.handleVibeSpaceParkProject(request(
            "vibespace.parkProject", params: ["path": .string(extraURL.path)]
        ))
        XCTAssertTrue(try XCTUnwrap(catalog.vibespaces.first).parkedProjectPaths.contains(extraURL.standardizedFileURL.path))

        actions.removeParkedProject(path: extraURL.path)

        let vibespace = try XCTUnwrap(catalog.vibespaces.first)
        XCTAssertFalse(vibespace.parkedProjectPaths.contains(extraURL.standardizedFileURL.path))
        XCTAssertFalse(vibespace.projects.contains(where: { $0.projectIdentifier == extraURL.standardizedFileURL.path }))
    }

    // MARK: - Coordinator-not-attached fallback

    func testHandlersRequireActionsCoordinator() throws {
        // Build a fresh router with no actions coordinator wired.
        let bareRouter = CLICommandRouter(shelfStore: container.shelfStore)
        bareRouter.attachVibeSpaceCatalogStore(catalog)
        let extraURL = tempRoot.appendingPathComponent("bare", isDirectory: true)
        try FileManager.default.createDirectory(at: extraURL, withIntermediateDirectories: true)

        for method in ["vibespace.addProject", "vibespace.removeProject", "vibespace.parkProject"] {
            let req = request(method, params: ["path": .string(extraURL.path)])
            let response: CLIResponse
            switch method {
            case "vibespace.addProject":
                response = bareRouter.handleVibeSpaceAddProject(req)
            case "vibespace.removeProject":
                response = bareRouter.handleVibeSpaceRemoveProject(req)
            default:
                response = bareRouter.handleVibeSpaceParkProject(req)
            }
            XCTAssertEqual(errorCode(response), CLIErrorCode.notConnected, "for method \(method)")
        }
    }
}
