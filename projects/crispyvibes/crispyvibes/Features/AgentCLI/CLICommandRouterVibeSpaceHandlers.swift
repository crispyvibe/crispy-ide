import Foundation

/// F044-R80 / R81 / R82: CLI handlers for `vibespace.addProject`,
/// `vibespace.removeProject`, `vibespace.parkProject`.
///
/// All three target the active vibespace (the first vibespace in the catalog,
/// matching the convention used by `terminal.*` and `shortcut.*` handlers).
/// Mutations route through `VibeSpaceCanvasActionsCoordinator` so behavior is
/// identical to user-driven UI actions: state mutation, persistence,
/// browser-close pipeline, hydration flag clearing, and catalog persist.
extension CLICommandRouter {

    // MARK: - F044-R80: Add Project

    func handleVibeSpaceAddProject(_ request: CLIRequest) -> CLIResponse {
        guard let pathParam = request.params?["path"]?.stringValue,
              !pathParam.isEmpty else {
            return .error(
                id: request.id,
                code: CLIErrorCode.invalidParams,
                message: "path is required"
            )
        }
        guard let coordinator = vibespaceActionsCoordinator else {
            return .error(
                id: request.id,
                code: CLIErrorCode.notConnected,
                message: "vibespace actions coordinator is not attached"
            )
        }
        guard vibespaceCatalogStore?.vibespaces.first != nil else {
            return .error(
                id: request.id,
                code: CLIErrorCode.vibespaceNotFound,
                message: "no focused vibespace"
            )
        }

        let url = URL(fileURLWithPath: pathParam).standardizedFileURL
        let normalizedPath = url.path

        // Validate: directory must exist.
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDir)
        guard exists, isDir.boolValue else {
            return .error(
                id: request.id,
                code: CLIErrorCode.fileNotFound,
                message: "path does not exist or is not a directory: \(normalizedPath)"
            )
        }

        // Validate: not already in the vibespace as a live project (parked
        // projects auto-unpark via VibeSpaceState.addProjects, so skipping the
        // duplicate guard there is intentional — only block live duplicates).
        if let live = vibespaceCatalogStore?.vibespaces.first?.projects.first(where: {
            $0.projectIdentifier == normalizedPath
        }) {
            return .error(
                id: request.id,
                code: CLIErrorCode.invalidParams,
                message: "project already in vibespace: \(live.projectIdentifier)"
            )
        }

        let added = coordinator.addProjectsViaCLI(urls: [url])
        guard let added else {
            return .error(
                id: request.id,
                code: CLIErrorCode.internalError,
                message: "addProjects produced no project (path may have been rejected)"
            )
        }

        return .ok(id: request.id, result: [
            "project_path": .string(added.projectIdentifier),
            "project_name": .string(URL(fileURLWithPath: added.projectIdentifier).lastPathComponent),
            "focused": .bool(true),
        ])
    }

    // MARK: - F044-R81: Remove Project

    func handleVibeSpaceRemoveProject(_ request: CLIRequest) -> CLIResponse {
        guard let pathParam = request.params?["path"]?.stringValue,
              !pathParam.isEmpty else {
            return .error(
                id: request.id,
                code: CLIErrorCode.invalidParams,
                message: "path is required"
            )
        }
        guard let coordinator = vibespaceActionsCoordinator else {
            return .error(
                id: request.id,
                code: CLIErrorCode.notConnected,
                message: "vibespace actions coordinator is not attached"
            )
        }
        guard let vibespace = vibespaceCatalogStore?.vibespaces.first else {
            return .error(
                id: request.id,
                code: CLIErrorCode.vibespaceNotFound,
                message: "no focused vibespace"
            )
        }

        let normalizedPath = URL(fileURLWithPath: pathParam).standardizedFileURL.path
        guard let project = vibespace.projects.first(where: {
            $0.projectIdentifier == normalizedPath
        }) else {
            return .error(
                id: request.id,
                code: CLIErrorCode.fileNotFound,
                message: "project not in vibespace: \(normalizedPath)"
            )
        }

        coordinator.removeProject(id: project.id)
        return .ok(id: request.id, result: [
            "removed_project_path": .string(normalizedPath),
        ])
    }

    // MARK: - F044-R82: Park Project

    func handleVibeSpaceParkProject(_ request: CLIRequest) -> CLIResponse {
        guard let pathParam = request.params?["path"]?.stringValue,
              !pathParam.isEmpty else {
            return .error(
                id: request.id,
                code: CLIErrorCode.invalidParams,
                message: "path is required"
            )
        }
        guard let coordinator = vibespaceActionsCoordinator else {
            return .error(
                id: request.id,
                code: CLIErrorCode.notConnected,
                message: "vibespace actions coordinator is not attached"
            )
        }
        guard let vibespace = vibespaceCatalogStore?.vibespaces.first else {
            return .error(
                id: request.id,
                code: CLIErrorCode.vibespaceNotFound,
                message: "no focused vibespace"
            )
        }

        let normalizedPath = URL(fileURLWithPath: pathParam).standardizedFileURL.path
        guard let project = vibespace.projects.first(where: {
            $0.projectIdentifier == normalizedPath
        }) else {
            return .error(
                id: request.id,
                code: CLIErrorCode.fileNotFound,
                message: "project not in vibespace (or already parked): \(normalizedPath)"
            )
        }

        coordinator.parkProject(id: project.id)
        return .ok(id: request.id, result: [
            "parked_project_path": .string(normalizedPath),
        ])
    }
}
