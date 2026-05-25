import Foundation
import XCTest
@testable import CrispyVibes

/// F012-R17 / F012-R19: covers `browser.list` scope filtering and the
/// project_path field per entry. Without these, an agent can't tell which
/// project owns each browser, and `crispy browser list` returned every browser
/// in the vibespace regardless of the caller's project context.
@MainActor
final class CLICommandRouterBrowserListTests: XCTestCase {
    var container: AppContainer!
    var tempRoot: URL!
    var router: CLICommandRouter!
    var coordinator: DockedBrowserCoordinator!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-cli-browser-list")
        container = AppContainer.makeDefault()
        router = CLICommandRouter(shelfStore: container.shelfStore)
        coordinator = DockedBrowserCoordinator()
        router.attachDockedBrowserCoordinator(coordinator)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        coordinator.removeAll()
        coordinator = nil
        router = nil
        container?.terminalServices.focusCoordinator.unfocusCurrent()
        container = nil
    }

    // MARK: - Helpers

    private func registerBrowser(projectPath: String?, url: String) -> UUID {
        // The simplest path to seed a browser into the coordinator's
        // detailed-view groups dictionary is to call viewModel(for:) with a
        // BrowserTabReference, which inserts the VM into the detailed view
        // dictionary and returns it. We don't need a live tab — just a VM
        // whose projectPath we can assert on.
        let browserID = UUID()
        let reference = BrowserTabReference(
            browserID: browserID,
            url: URL(string: url),
            projectPath: projectPath,
            linkedTileID: nil
        )
        _ = coordinator.viewModel(for: reference)
        return browserID
    }

    private func request(envProjectPath: String? = nil, scope: String? = nil) -> CLIRequest {
        var params: [String: CLIJSONValue] = [:]
        if let scope { params["scope"] = .string(scope) }
        return CLIRequest(
            id: UUID().uuidString,
            method: "browser.list",
            params: params,
            _env: CLIChannelClientEnv(
                context: nil,
                vibespace: nil,
                project_path: envProjectPath
            )
        )
    }

    private func tabsArray(_ response: CLIResponse) -> [CLIJSONValue]? {
        guard case let .ok(_, result) = response,
              case let .array(tabs) = result["tabs"] else {
            return nil
        }
        return tabs
    }

    private func errorCode(_ response: CLIResponse) -> String? {
        guard case let .error(_, code, _) = response else { return nil }
        return code
    }

    private func projectPaths(in tabs: [CLIJSONValue]) -> [String?] {
        tabs.compactMap { tab -> String? in
            guard case let .object(fields) = tab else { return nil }
            switch fields["project_path"] {
            case .some(.null), .none: return nil
            case let .some(.string(s)): return s
            default: return nil
            }
        }
    }

    // MARK: - F012-R19: scope filtering

    func testListDefaultsToProjectScopeFiltersToCallerProject() throws {
        _ = registerBrowser(projectPath: "/p/alpha", url: "https://a.com")
        _ = registerBrowser(projectPath: "/p/beta", url: "https://b.com")
        _ = registerBrowser(projectPath: nil, url: "https://orphan.com")

        let tabs = try XCTUnwrap(tabsArray(
            router.handleBrowserList(request(envProjectPath: "/p/alpha"))
        ))
        XCTAssertEqual(tabs.count, 1, "default scope=project filters to caller's project")
        XCTAssertEqual(projectPaths(in: tabs), ["/p/alpha"])
    }

    func testListDefaultProjectScopeWithoutCallerProjectErrors() {
        _ = registerBrowser(projectPath: "/p/alpha", url: "https://a.com")
        // No env project, no focused project; default scope=project still
        // requires a resolvable caller — surfaces the missing context rather
        // than silently returning empty.
        let response = router.handleBrowserList(request(envProjectPath: nil))
        XCTAssertEqual(errorCode(response), CLIErrorCode.noFocusedProject)
    }

    func testListVibespaceScopeReturnsAllBrowsers() throws {
        _ = registerBrowser(projectPath: "/p/alpha", url: "https://a.com")
        _ = registerBrowser(projectPath: "/p/beta", url: "https://b.com")
        _ = registerBrowser(projectPath: nil, url: "https://orphan.com")

        let tabs = try XCTUnwrap(tabsArray(
            router.handleBrowserList(request(scope: "vibespace"))
        ))
        XCTAssertEqual(tabs.count, 3, "scope=vibespace is the explicit opt-in for cross-project listing")
    }

    func testListInvalidScopeReturnsInvalidParams() {
        let response = router.handleBrowserList(request(scope: "weird"))
        XCTAssertEqual(errorCode(response), CLIErrorCode.invalidParams)
    }

    // MARK: - F012-R17: project_path in result

    func testListIncludesProjectPathPerEntry() throws {
        _ = registerBrowser(projectPath: "/p/alpha", url: "https://a.com")
        _ = registerBrowser(projectPath: nil, url: "https://orphan.com")

        // Use vibespace scope so orphan browsers (no project owner) are included
        // and we can verify the null project_path branch.
        let tabs = try XCTUnwrap(tabsArray(router.handleBrowserList(request(scope: "vibespace"))))
        XCTAssertEqual(tabs.count, 2)
        // Each entry must include project_path (string or null) — verify both
        // shapes are emitted.
        var sawString = false
        var sawNull = false
        for tab in tabs {
            guard case let .object(fields) = tab else {
                XCTFail("expected object entry")
                return
            }
            switch fields["project_path"] {
            case .some(.string(let path)) where path == "/p/alpha":
                sawString = true
            case .some(.null):
                sawNull = true
            default:
                XCTFail("project_path must be string or null, got \(String(describing: fields["project_path"]))")
            }
        }
        XCTAssertTrue(sawString, "missing entry with project_path string")
        XCTAssertTrue(sawNull, "missing entry with project_path null (orphan browser)")
    }
}
