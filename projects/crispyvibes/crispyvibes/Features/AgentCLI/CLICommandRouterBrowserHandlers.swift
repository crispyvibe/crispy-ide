import Foundation

extension CLICommandRouter {

    // MARK: - Management Commands

    func handleBrowserList(_ request: CLIRequest) -> CLIResponse {
        guard let coordinator = dockedBrowserCoordinator else {
            return .ok(id: request.id, result: ["tabs": .array([])])
        }

        var entries: [CLIJSONValue] = []
        for tab in coordinator.searchTabs(query: "") {
            entries.append(.object([
                "browser_id": .string("browser.\(tab.id.uuidString)"),
                "title": .string(tab.title),
                "url": .string(tab.url?.absoluteString ?? ""),
            ]))
        }
        for tab in coordinator.searchDetailedTabs(query: "") {
            entries.append(.object([
                "browser_id": .string("browser.\(tab.id.uuidString)"),
                "title": .string(tab.title),
                "url": .string(tab.url?.absoluteString ?? ""),
            ]))
        }

        return .ok(id: request.id, result: ["tabs": .array(entries)])
    }

    func handleBrowserOpen(_ request: CLIRequest) -> CLIResponse {
        let urlString = request.params?["url"]?.stringValue ?? ""
        let url = URL(string: urlString) ?? URL(string: "about:blank")!
        let env = request._env ?? .empty
        let projectPath = env.project_path

        let browserID = UUID()
        var userInfo: [String: Any] = ["url": url, "browserID": browserID]
        if let projectPath { userInfo["projectPath"] = projectPath }

        NotificationCenter.default.post(
            name: .openNewBrowserRequested,
            object: nil,
            userInfo: userInfo
        )

        return .ok(id: request.id, result: [
            "browser_id": .string("browser.\(browserID.uuidString)"),
            "url": .string(url.absoluteString),
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
