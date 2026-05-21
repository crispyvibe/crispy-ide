import Foundation

// MARK: - Shelf handlers

extension CLICommandRouter {

    func handleShelfAdd(_ request: CLIRequest) -> CLIResponse {
        guard let pathParam = request.params?["path"]?.stringValue,
              !pathParam.isEmpty else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "path is required")
        }
        let url = resolvedURL(forPath: pathParam, env: request._env ?? .empty)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else {
            return .error(id: request.id, code: CLIErrorCode.fileNotFound, message: "Path does not exist: \(url.path)")
        }
        let select = request.params?["select"]?.boolValue ?? false

        let added = shelfStore.addFileIfAbsent(url, select: select)

        return .ok(id: request.id, result: [
            "path": .string(url.path),
            "kind": .string(isDirectory.boolValue ? "folder" : "file"),
            "added": .bool(added),
            "selected": .bool(shelfStore.selectedFilePath == url.path),
        ])
    }

    /// Resolves a request path against the channel client's project path when
    /// it is relative; absolute paths are returned standardized as-is.
    func resolvedURL(forPath path: String, env: CLIChannelClientEnv) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardized
        }
        let base = env.project_path.flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: base, isDirectory: true))
            .standardized
    }

    func handleShelfList(_ request: CLIRequest) -> CLIResponse {
        let items: [CLIJSONValue] = shelfStore.filePaths.map { path in
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return .object([
                "path": .string(path),
                "kind": .string(isDir.boolValue ? "folder" : "file"),
                "exists": .bool(exists),
                "selected": .bool(shelfStore.selectedFilePath == path),
            ])
        }
        return .ok(id: request.id, result: [
            "items": .array(items),
            "selected_path": shelfStore.selectedFilePath.map { .string($0) } ?? .null,
        ])
    }

    func handleShelfRemove(_ request: CLIRequest) -> CLIResponse {
        guard let pathParam = request.params?["path"]?.stringValue, !pathParam.isEmpty else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "path is required")
        }
        let url = resolvedURL(forPath: pathParam, env: request._env ?? .empty)
        let wasShelved = shelfStore.filePaths.contains(url.path)
        if wasShelved {
            _ = shelfStore.removeFile(at: url.path)
        }
        return .ok(id: request.id, result: [
            "removed": .bool(wasShelved),
        ])
    }
}
