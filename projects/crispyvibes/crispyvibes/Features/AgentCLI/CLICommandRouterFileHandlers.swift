import Foundation

extension CLICommandRouter {
    func handleFileOpen(_ request: CLIRequest) -> CLIResponse {
        guard let pathParam = request.params?["path"]?.stringValue, !pathParam.isEmpty else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "path is required")
        }
        let env = request._env ?? .empty
        let url = resolvedURL(forPath: pathParam, env: env)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .error(id: request.id, code: CLIErrorCode.fileNotFound, message: "File not found: \(url.path)")
        }

        let line = request.params?["line"]?.intValue
        let column = request.params?["column"]?.intValue

        if let line, line < 1 {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "line must be >= 1")
        }
        if column != nil && line == nil {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "column requires line")
        }

        // Use the existing notification that ContentView already observes
        // for opening files from terminal link clicks.
        var userInfo: [String: Any] = [AppCommandUserInfoKey.url: url]
        if let line { userInfo[AppCommandUserInfoKey.line] = line }
        if let column { userInfo[AppCommandUserInfoKey.column] = column }

        NotificationCenter.default.post(
            name: .ghosttyOpenFileSystemTargetRequested,
            object: nil,
            userInfo: userInfo
        )

        var result: [String: CLIJSONValue] = ["path": .string(url.path)]
        if let line { result["line"] = .int(line) }
        return .ok(id: request.id, result: result)
    }
}
