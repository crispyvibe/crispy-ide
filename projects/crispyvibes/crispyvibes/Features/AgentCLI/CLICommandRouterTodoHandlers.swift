import Foundation

/// F053 — handlers for `todo.*` JSON-RPC methods over the agent CLI socket.
/// Resolves the active vibespace from the attached `VibeSpaceTodoStore` and the
/// project scope from the `project` param or the caller's `_env.project_path`,
/// then delegates to the store (the same path the UI uses).
extension CLICommandRouter {

    // MARK: - todo.add

    func handleTodoAdd(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceTodoStore else { return todoNotConnected(request) }
        guard store.currentVibeSpaceID() != nil else {
            return .error(id: request.id, code: CLIErrorCode.vibespaceNotFound, message: "no active vibespace")
        }
        guard let title = request.params?["text"]?.stringValue,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return todoInvalidParams(request, "`text` is required")
        }
        let created = await store.add(
            title: title,
            body: request.params?["body"]?.stringValue,
            projectPath: resolvedTodoProjectPath(request),
            colorTag: request.params?["color"]?.stringValue,
            filePath: request.params?["file"]?.stringValue
        )
        guard let created else {
            return .error(id: request.id, code: CLIErrorCode.internalError,
                          message: store.lastErrorMessage ?? "todo.add failed")
        }
        return .ok(id: request.id, result: ["id": .string(created.id), "title": .string(created.title)])
    }

    // MARK: - todo.list

    func handleTodoList(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceTodoStore else { return todoNotConnected(request) }
        guard store.currentVibeSpaceID() != nil else {
            return .error(id: request.id, code: CLIErrorCode.vibespaceNotFound, message: "no active vibespace")
        }
        let status = request.params?["status"]?.stringValue ?? "active"
        guard ["active", "completed", "all"].contains(status) else {
            return todoInvalidParams(request, "status must be active, completed, or all")
        }

        // Scope filtering (parallels `browser.list`): `project` (default) lists
        // todos for the caller's project; `vibespace` lists every todo across
        // all projects in the active vibespace. An explicit `project` param is
        // honored under project scope even when the caller's env project differs.
        let scope = request.params?["scope"]?.stringValue ?? "project"
        let projectFilter: String?
        switch scope {
        case "vibespace":
            projectFilter = nil
        case "project":
            guard let resolved = resolvedTodoProjectPath(request) else {
                return todoInvalidParams(
                    request,
                    "todo.list scope=project requires CRISPY_PROJECT_PATH or a `project` param — pass scope=vibespace to list across projects"
                )
            }
            projectFilter = resolved
        default:
            return todoInvalidParams(request, "scope must be \"project\" (default) or \"vibespace\"")
        }

        await store.refresh()
        let items = store.filtered(byProject: projectFilter).filter { todo in
            switch status {
            case "active": return !todo.isCompleted
            case "completed": return todo.isCompleted
            default: return true
            }
        }
        return .ok(id: request.id, result: ["todos": .array(items.map { encodeTodo($0) })])
    }

    // MARK: - todo.complete / todo.reopen

    func handleTodoComplete(_ request: CLIRequest) async -> CLIResponse {
        await setTodoCompleted(request, completed: true)
    }

    func handleTodoReopen(_ request: CLIRequest) async -> CLIResponse {
        await setTodoCompleted(request, completed: false)
    }

    private func setTodoCompleted(_ request: CLIRequest, completed: Bool) async -> CLIResponse {
        guard let store = vibespaceTodoStore else { return todoNotConnected(request) }
        guard let id = request.params?["id"]?.stringValue, !id.isEmpty else {
            return todoInvalidParams(request, "`id` is required")
        }
        guard await store.setCompleted(id: id, completed: completed) else {
            return .error(id: request.id, code: CLIErrorCode.internalError,
                          message: store.lastErrorMessage ?? "todo.complete failed")
        }
        return .ok(id: request.id, result: [
            "id": .string(id),
            "status": .string(completed ? "completed" : "active"),
        ])
    }

    // MARK: - todo.update

    func handleTodoUpdate(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceTodoStore else { return todoNotConnected(request) }
        guard let id = request.params?["id"]?.stringValue, !id.isEmpty else {
            return todoInvalidParams(request, "`id` is required")
        }
        let title = request.params?["text"]?.stringValue
        let body = request.params?["body"]?.stringValue
        let color = request.params?["color"]?.stringValue
        guard title != nil || body != nil || color != nil else {
            return todoInvalidParams(request, "provide at least one of: text, body, color")
        }
        guard await store.update(id: id, title: title, body: body, colorTag: color) else {
            return .error(id: request.id, code: CLIErrorCode.internalError,
                          message: store.lastErrorMessage ?? "todo.update failed")
        }
        return .ok(id: request.id, result: ["id": .string(id)])
    }

    // MARK: - todo.remove

    func handleTodoRemove(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceTodoStore else { return todoNotConnected(request) }
        guard let id = request.params?["id"]?.stringValue, !id.isEmpty else {
            return todoInvalidParams(request, "`id` is required")
        }
        guard await store.delete(id: id) else {
            return .error(id: request.id, code: CLIErrorCode.internalError,
                          message: store.lastErrorMessage ?? "todo.remove failed")
        }
        return .ok(id: request.id, result: ["id": .string(id), "removed": .bool(true)])
    }

    // MARK: - todo.show / todo.message.add

    func handleTodoShow(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceTodoStore else { return todoNotConnected(request) }
        guard let id = request.params?["id"]?.stringValue, !id.isEmpty else {
            return todoInvalidParams(request, "`id` is required")
        }
        await store.refresh()
        await store.refreshMessages(todoID: id)
        guard let todo = store.todo(withID: id) else {
            return .error(id: request.id, code: CLIErrorCode.internalError, message: "todo not found: \(id)")
        }
        var obj = encodeTodoFields(todo)
        obj["messages"] = .array(store.messages(forTodo: id).map { encodeMessage($0) })
        return .ok(id: request.id, result: obj)
    }

    func handleTodoMessageAdd(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceTodoStore else { return todoNotConnected(request) }
        guard let todoID = request.params?["id"]?.stringValue, !todoID.isEmpty else {
            return todoInvalidParams(request, "`id` is required")
        }
        guard let body = request.params?["text"]?.stringValue,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return todoInvalidParams(request, "`text` is required")
        }
        // CLI callers are agents, so messages they post are agent-authored.
        guard let created = await store.addMessage(todoID: todoID, body: body, authorKind: "agent") else {
            return .error(id: request.id, code: CLIErrorCode.internalError,
                          message: store.lastErrorMessage ?? "todo.message.add failed")
        }
        return .ok(id: request.id, result: ["id": .string(created.id), "todoId": .string(created.todoID)])
    }

    // MARK: - Helpers

    private func encodeTodo(_ t: Todo) -> CLIJSONValue {
        .object(encodeTodoFields(t))
    }

    private func encodeTodoFields(_ t: Todo) -> [String: CLIJSONValue] {
        var obj: [String: CLIJSONValue] = [
            "id": .string(t.id),
            "title": .string(t.title),
            "status": .string(t.status.rawValue),
            "createdAt": .string(t.createdAt),
            "updatedAt": .string(t.updatedAt),
        ]
        if let p = t.projectPath { obj["projectPath"] = .string(p) }
        if let b = t.body { obj["body"] = .string(b) }
        if let c = t.colorTag { obj["colorTag"] = .string(c) }
        if let f = t.filePath { obj["filePath"] = .string(f) }
        if let c = t.completedAt { obj["completedAt"] = .string(c) }
        return obj
    }

    private func encodeMessage(_ m: TodoMessage) -> CLIJSONValue {
        .object([
            "id": .string(m.id),
            "todoId": .string(m.todoID),
            "body": .string(m.body),
            "authorKind": .string(m.authorKind),
            "createdAt": .string(m.createdAt),
            "updatedAt": .string(m.updatedAt),
        ])
    }

    /// Explicit `project` param wins; otherwise fall back to the caller's
    /// `_env.project_path`; `nil` means a vibespace-level todo.
    private func resolvedTodoProjectPath(_ request: CLIRequest) -> String? {
        if let explicit = request.params?["project"]?.stringValue.flatMap({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
           !explicit.isEmpty {
            return URL(fileURLWithPath: explicit).standardizedFileURL.path
        }
        if let env = request._env?.project_path?.trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            return URL(fileURLWithPath: env).standardizedFileURL.path
        }
        return nil
    }

    private func todoInvalidParams(_ request: CLIRequest, _ message: String) -> CLIResponse {
        .error(id: request.id, code: CLIErrorCode.invalidParams, message: message)
    }

    private func todoNotConnected(_ request: CLIRequest) -> CLIResponse {
        .error(id: request.id, code: CLIErrorCode.notConnected, message: "todo store not attached")
    }
}
