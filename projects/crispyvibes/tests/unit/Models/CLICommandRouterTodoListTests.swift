import Foundation
import XCTest
@testable import CrispyVibes

/// F053: covers `todo.list` scope routing. Before this, the CLI silently
/// filtered to the caller's project with no way to list across the vibespace —
/// `crispy todo list` from a terminal (where CRISPY_PROJECT_PATH is always set)
/// could never see sibling-project or vibespace-level todos, unlike the app's
/// Project/All toggle. `scope=vibespace` is the explicit opt-in that reaches
/// the "all" path; `scope=project` (default) still requires a resolvable
/// project so missing context surfaces as an error instead of silent scope
/// widening.
///
/// These exercise the handler's scope→filter decision without the persistence
/// helper: the store's conversation store is never started, so `refresh()` is a
/// no-op (no subprocess, DB, or keychain), and the meaningful assertion is the
/// ok/error routing per scope.
@MainActor
final class CLICommandRouterTodoListTests: XCTestCase {
    private var router: CLICommandRouter!
    private var store: VibeSpaceTodoStore!
    private var vibespaceProvider: NSObject!
    private var container: AppContainer!

    override func setUpWithError() throws {
        container = AppContainer.makeDefault()
        router = CLICommandRouter(shelfStore: container.shelfStore)
        // Unstarted conversation store → send() returns nil → refresh() no-ops.
        store = VibeSpaceTodoStore(conversationStore: AgentConversationStore())
        vibespaceProvider = NSObject()
        store.bindActiveVibeSpace(provider: vibespaceProvider) { "vibespace.test" }
        router.attachVibeSpaceTodoStore(store)
    }

    override func tearDownWithError() throws {
        router = nil
        store = nil
        vibespaceProvider = nil
        container?.terminalServices.focusCoordinator.unfocusCurrent()
        container = nil
    }

    // MARK: - Helpers

    private func listRequest(scope: String? = nil, project: String? = nil, envProjectPath: String? = nil) -> CLIRequest {
        var params: [String: CLIJSONValue] = [:]
        if let scope { params["scope"] = .string(scope) }
        if let project { params["project"] = .string(project) }
        params["status"] = .string("all")
        return CLIRequest(
            id: UUID().uuidString,
            method: "todo.list",
            params: params,
            _env: CLIChannelClientEnv(context: nil, vibespace: nil, project_path: envProjectPath)
        )
    }

    private func errorCode(_ response: CLIResponse) -> String? {
        guard case let .error(_, code, _) = response else { return nil }
        return code
    }

    private func isOK(_ response: CLIResponse) -> Bool {
        if case .ok = response { return true }
        return false
    }

    // MARK: - Scope routing

    func testVibespaceScopeDoesNotRequireProject() async {
        // The core fix: vibespace scope lists across projects and must succeed
        // even when the caller has no project context.
        let response = await router.handleTodoList(listRequest(scope: "vibespace", envProjectPath: nil))
        XCTAssertTrue(isOK(response), "scope=vibespace must not require a project")
    }

    func testDefaultProjectScopeWithoutProjectErrors() async {
        // Default scope=project with no explicit project and no env project must
        // surface missing context rather than silently widening to the vibespace.
        let response = await router.handleTodoList(listRequest(scope: nil, envProjectPath: nil))
        XCTAssertEqual(errorCode(response), CLIErrorCode.invalidParams)
    }

    func testProjectScopeWithEnvProjectSucceeds() async {
        let response = await router.handleTodoList(listRequest(scope: "project", envProjectPath: "/p/alpha"))
        XCTAssertTrue(isOK(response), "scope=project resolves the caller's env project")
    }

    func testExplicitProjectSucceedsUnderDefaultScope() async {
        let response = await router.handleTodoList(listRequest(project: "/p/beta"))
        XCTAssertTrue(isOK(response), "an explicit project param resolves under the default project scope")
    }

    func testInvalidScopeReturnsInvalidParams() async {
        let response = await router.handleTodoList(listRequest(scope: "weird", envProjectPath: "/p/alpha"))
        XCTAssertEqual(errorCode(response), CLIErrorCode.invalidParams)
    }

    func testInvalidStatusReturnsInvalidParams() async {
        let params: [String: CLIJSONValue] = ["status": .string("bogus"), "scope": .string("vibespace")]
        let request = CLIRequest(
            id: UUID().uuidString,
            method: "todo.list",
            params: params,
            _env: CLIChannelClientEnv(context: nil, vibespace: nil, project_path: nil)
        )
        let response = await router.handleTodoList(request)
        XCTAssertEqual(errorCode(response), CLIErrorCode.invalidParams)
    }
}
