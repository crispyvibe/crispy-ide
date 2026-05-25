import Foundation

extension CLICommandRouter {

    // MARK: - Management Commands

    func handleBrowserList(_ request: CLIRequest) -> CLIResponse {
        guard let coordinator = dockedBrowserCoordinator else {
            return .ok(id: request.id, result: ["tabs": .array([])])
        }

        // F012-R19 / scope filtering: default `project` returns only browsers
        // owned by the caller's project (resolved from `_env.project_path` or
        // the focused project — same precedence as `browser.open`). This is
        // the safer default for agents — they get their own project's context
        // without leaking cross-project state. `vibespace` is an explicit
        // opt-in for cross-project listings.
        let scopeParam = request.params?["scope"]?.stringValue ?? "project"
        let env = request._env ?? .empty
        let envProjectPath = env.project_path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let callerProjectPath: String?
        if let envProjectPath, !envProjectPath.isEmpty {
            callerProjectPath = envProjectPath
        } else if let focused = vibespaceCatalogStore?.vibespaces.first?.focusedProject {
            callerProjectPath = focused.projectIdentifier
        } else {
            callerProjectPath = nil
        }

        let scopeFilter: (String?) -> Bool
        switch scopeParam {
        case "project":
            // Project scope requires a resolvable caller project; otherwise
            // surface the failure so the agent doesn't get an empty result it
            // can't explain.
            guard let callerProjectPath else {
                return .error(
                    id: request.id,
                    code: CLIErrorCode.noFocusedProject,
                    message: "browser.list scope=project requires CRISPY_PROJECT_PATH or a focused project — pass scope=vibespace to list across projects"
                )
            }
            scopeFilter = { $0 == callerProjectPath }
        case "vibespace":
            scopeFilter = { _ in true }
        default:
            return .error(
                id: request.id,
                code: CLIErrorCode.invalidParams,
                message: "scope must be \"project\" (default) or \"vibespace\""
            )
        }

        var seenIDs = Set<UUID>()
        var entries: [CLIJSONValue] = []
        let allTabs = coordinator.searchTabs(query: "") + coordinator.searchDetailedTabs(query: "")
        for tab in allTabs {
            guard seenIDs.insert(tab.id).inserted else { continue }
            guard scopeFilter(tab.projectPath) else { continue }
            var fields: [String: CLIJSONValue] = [
                "browser_id": .string("browser.\(tab.id.uuidString)"),
                "title": .string(tab.title),
                "url": .string(tab.url?.absoluteString ?? ""),
            ]
            if let projectPath = tab.projectPath {
                fields["project_path"] = .string(projectPath)
            } else {
                fields["project_path"] = .null
            }
            entries.append(.object(fields))
        }

        return .ok(id: request.id, result: ["tabs": .array(entries)])
    }

    func handleBrowserOpen(_ request: CLIRequest) -> CLIResponse {
        let urlString = request.params?["url"]?.stringValue ?? ""
        let url = URL(string: urlString) ?? URL(string: "about:blank")!
        let env = request._env ?? .empty

        // F012-R17: each browser MUST be owned by exactly one project. Resolve
        // an owning project path before dispatching: prefer the caller's
        // CRISPY_PROJECT_PATH (set by terminals spawned with project context),
        // then fall back to the active vibespace's focused project. If neither
        // resolves, surface the failure to the caller as a structured error
        // rather than silently dropping the request in the notification handler.
        let envProjectPath = env.project_path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedProjectPath: String?
        if let envProjectPath, !envProjectPath.isEmpty {
            resolvedProjectPath = envProjectPath
        } else if let focused = vibespaceCatalogStore?.vibespaces.first?.focusedProject {
            resolvedProjectPath = focused.projectIdentifier
        } else {
            resolvedProjectPath = nil
        }

        guard let projectPath = resolvedProjectPath else {
            return .error(
                id: request.id,
                code: CLIErrorCode.noFocusedProject,
                message: "browser open requires an owning project: set CRISPY_PROJECT_PATH or focus a project in the active vibespace"
            )
        }

        let browserID = UUID()
        let userInfo: [String: Any] = [
            "url": url,
            "browserID": browserID,
            "projectPath": projectPath
        ]

        NotificationCenter.default.post(
            name: .openNewBrowserRequested,
            object: nil,
            userInfo: userInfo
        )

        return .ok(id: request.id, result: [
            "browser_id": .string("browser.\(browserID.uuidString)"),
            "url": .string(url.absoluteString),
            "project_path": .string(projectPath),
        ])
    }

    func handleBrowserClose(_ request: CLIRequest) -> CLIResponse {
        guard let browserID = request.params?["browser_id"]?.stringValue,
              let uuid = resolveBrowserUUID(browserID) else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "browser_id is required")
        }
        // Post a notification so ContentView can do the FULL close: remove the
        // board tile or content-viewer tab AND drop the view-model. Calling only
        // `coordinator.removeViewModel(for:)` here would be silently undone — the
        // tile/tab is still in the layout state, SwiftUI re-renders it, and
        // `coordinator.viewModel(for:url:)` recreates the VM on every body
        // evaluation, so the user sees no visible change.
        NotificationCenter.default.post(
            name: .closeBrowserRequested,
            object: nil,
            userInfo: ["browserID": uuid]
        )
        return .ok(id: request.id, result: ["closed": .bool(true)])
    }

    // MARK: - Generic Per-Tab Dispatch

    func handleBrowserDispatch(_ request: CLIRequest) async -> CLIResponse {
        guard let coordinator = dockedBrowserCoordinator else {
            return .error(id: request.id, code: CLIErrorCode.notConnected, message: "No browser coordinator")
        }
        guard let browserID = request.params?["browser_id"]?.stringValue,
              let uuid = resolveBrowserUUID(browserID) else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "browser_id is required")
        }
        guard let api = coordinator.agentAPI(for: uuid) else {
            return .error(id: request.id, code: "browser_not_found", message: "Browser not found")
        }

        var forwardParams: [String: Any] = ["surface_id": uuid.uuidString]
        if let params = request.params {
            for (key, value) in params where key != "browser_id" {
                forwardParams[key] = value.toAny()
            }
        }

        let result = await api.dispatch(method: request.method, params: forwardParams)
        switch result {
        case .ok(let dict):
            return .ok(id: request.id, result: Self.convertToJSON(dict))
        case .err(let code, let message):
            return .error(id: request.id, code: code, message: message)
        }
    }

    // MARK: - Helpers

    private func resolveBrowserUUID(_ raw: String) -> UUID? {
        let idString = CLITaggedID.extractID(from: raw, expectedKind: "browser")
        return UUID(uuidString: idString)
    }

    static func convertToJSON(_ dict: [String: Any]) -> [String: CLIJSONValue] {
        var result: [String: CLIJSONValue] = [:]
        for (key, value) in dict {
            result[key] = anyToCLIJSON(value)
        }
        return result
    }

    private static func anyToCLIJSON(_ value: Any) -> CLIJSONValue {
        if value is NSNull { return .null }
        if let b = value as? Bool { return .bool(b) }
        if let i = value as? Int { return .int(i) }
        if let d = value as? Double { return .double(d) }
        if let s = value as? String { return .string(s) }
        if let arr = value as? [Any] { return .array(arr.map { anyToCLIJSON($0) }) }
        if let dict = value as? [String: Any] { return .object(convertToJSON(dict)) }
        return .string(String(describing: value))
    }
}

// MARK: - CLIJSONValue → Any conversion

extension CLIJSONValue {
    func toAny() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let arr): return arr.map { $0.toAny() }
        case .object(let dict): return dict.mapValues { $0.toAny() }
        }
    }
}
