import Foundation

extension CLICommandRouter {
    func handleFileOpen(_ request: CLIRequest) -> CLIResponse {
        guard let pathParam = request.params?["path"]?.stringValue, !pathParam.isEmpty else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "path is required")
        }
        let env = request._env ?? .empty
        let url = resolvedURL(forPath: pathParam, env: env)

        // F051-R07: a file inside a REMOTE project lives on the remote host
        // (reachable via the project's SFTP content provider), not the local
        // filesystem — so skip the local existence check and let the
        // (already remote-aware) open path resolve it through the owning
        // project. Local files keep the existence check.
        if !owningProjectIsRemote(forPath: url.path) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .error(id: request.id, code: CLIErrorCode.fileNotFound, message: "File not found: \(url.path)")
            }
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

    /// F051-R07: returns `true` when `path` falls under a remote project's root.
    /// Such files can't be validated against the local filesystem; the open
    /// path resolves them through the owning project's SFTP content provider.
    private func owningProjectIsRemote(forPath path: String) -> Bool {
        guard let store = vibespaceCatalogStore else { return false }
        let owner = store.vibespaces
            .flatMap { $0.projects }
            .filter { project in
                let root = project.rootURL.standardizedFileURL.path
                return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
            }
            .max(by: { $0.rootURL.standardizedFileURL.path.count < $1.rootURL.standardizedFileURL.path.count })
        return owner?.sshConnection != nil
    }
}
