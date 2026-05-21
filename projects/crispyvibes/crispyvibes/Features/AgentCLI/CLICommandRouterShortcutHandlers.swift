import Foundation

extension CLICommandRouter {
    func handleShortcutList(_ request: CLIRequest) -> CLIResponse {
        guard let vibespace = vibespaceCatalogStore?.vibespaces.first else {
            return .ok(id: request.id, result: ["shortcuts": .array([])])
        }
        let env = request._env ?? .empty
        let projectPath = env.project_path ?? ""

        var entries: [CLIJSONValue] = []

        // Vibespace-scoped shortcuts
        for shortcut in vibespace.vibespaceShortcuts {
            entries.append(.object([
                "id": .string(shortcut.id.uuidString),
                "name": .string(shortcut.name),
                "command": .string(shortcut.command),
                "launch_behavior": .string(shortcut.launchBehavior.rawValue),
                "scope": .string("vibespace"),
            ]))
        }

        // Project-scoped shortcuts
        if !projectPath.isEmpty,
           let mgmt = vibespaceManagement {
            let projectShortcuts = mgmt.projectShortcuts(
                vibespaceID: vibespace.id,
                projectPath: projectPath
            )
            for shortcut in projectShortcuts {
                entries.append(.object([
                    "id": .string(shortcut.id.uuidString),
                    "name": .string(shortcut.name),
                    "command": .string(shortcut.command),
                    "launch_behavior": .string(shortcut.launchBehavior.rawValue),
                    "scope": .string("project"),
                ]))
            }
        }

        return .ok(id: request.id, result: ["shortcuts": .array(entries)])
    }

    func handleShortcutAdd(_ request: CLIRequest) -> CLIResponse {
        guard let name = request.params?["name"]?.stringValue?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "name is required")
        }
        guard let command = request.params?["command"]?.stringValue?.trimmingCharacters(in: .whitespaces),
              !command.isEmpty else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "command is required")
        }
        guard let launchBehaviorRaw = request.params?["launch_behavior"]?.stringValue,
              let launchBehavior = TerminalShortcutLaunchBehavior(rawValue: launchBehaviorRaw) else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "launch_behavior is required. Must be one of: currentTerminal, newPermanentTerminal, newTemporaryTerminal")
        }

        let scope = request.params?["scope"]?.stringValue ?? "vibespace"
        guard scope == "vibespace" || scope == "project" else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "scope must be 'vibespace' or 'project'")
        }

        guard let catalogStore = vibespaceCatalogStore,
              let vibespace = catalogStore.vibespaces.first,
              let mgmt = vibespaceManagement else {
            return .error(id: request.id, code: CLIErrorCode.notConnected, message: "No vibespace open")
        }

        let definition = TerminalShortcutDefinition(
            name: name,
            command: command,
            launchBehavior: launchBehavior
        )

        if scope == "project" {
            let env = request._env ?? .empty
            guard let projectPath = env.project_path, !projectPath.isEmpty else {
                return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "project scope requires CRISPY_PROJECT_PATH to be set")
            }
            var updated = mgmt.projectShortcuts(vibespaceID: vibespace.id, projectPath: projectPath)
            updated.append(definition)
            mgmt.setProjectShortcuts(updated, vibespaceID: vibespace.id, projectPath: projectPath)
        } else {
            var updated = vibespace.vibespaceShortcuts
            updated.append(definition)
            catalogStore.mutateVibeSpace(id: vibespace.id) { vs in
                vs.vibespaceShortcuts = updated
            }
            mgmt.setVibeSpaceShortcuts(updated, vibespaceID: vibespace.id)
        }

        return .ok(id: request.id, result: [
            "id": .string(definition.id.uuidString),
            "name": .string(name),
            "command": .string(command),
            "launch_behavior": .string(launchBehavior.rawValue),
            "scope": .string(scope),
        ])
    }

    func handleShortcutRemove(_ request: CLIRequest) -> CLIResponse {
        guard let idParam = request.params?["id"]?.stringValue, !idParam.isEmpty else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "id is required")
        }
        guard let uuid = UUID(uuidString: idParam) else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "id must be a valid UUID")
        }
        guard let catalogStore = vibespaceCatalogStore,
              let vibespace = catalogStore.vibespaces.first,
              let mgmt = vibespaceManagement else {
            return .error(id: request.id, code: CLIErrorCode.notConnected, message: "No vibespace open")
        }

        // Try vibespace-scoped first
        if vibespace.vibespaceShortcuts.contains(where: { $0.id == uuid }) {
            var updated = vibespace.vibespaceShortcuts.filter { $0.id != uuid }
            catalogStore.mutateVibeSpace(id: vibespace.id) { vs in
                vs.vibespaceShortcuts = updated
            }
            mgmt.setVibeSpaceShortcuts(updated, vibespaceID: vibespace.id)
            return .ok(id: request.id, result: ["removed": .bool(true)])
        }

        // Try project-scoped
        let env = request._env ?? .empty
        if let projectPath = env.project_path, !projectPath.isEmpty {
            var projectShortcuts = mgmt.projectShortcuts(vibespaceID: vibespace.id, projectPath: projectPath)
            if projectShortcuts.contains(where: { $0.id == uuid }) {
                projectShortcuts.removeAll { $0.id == uuid }
                mgmt.setProjectShortcuts(projectShortcuts, vibespaceID: vibespace.id, projectPath: projectPath)
                return .ok(id: request.id, result: ["removed": .bool(true)])
            }
        }

        return .ok(id: request.id, result: ["removed": .bool(false)])
    }
}
