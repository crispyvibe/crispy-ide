import Foundation

/// F060 — handlers for the todo pipeline CLI: file links, triage read, and
/// `todo.dispatch`. Dispatch is a thin passthrough to the bridge — the same
/// method the UI sheet calls — so mapping priority, the one-active-task rule,
/// and thread fan-in stay one code path with two callers (F060-R09).
extension CLICommandRouter {

    // MARK: - todo.file.add / remove / list

    func handleTodoFileAdd(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceTodoStore else { return pipelineNotConnected(request) }
        guard let todoID = request.params?["id"]?.stringValue, !todoID.isEmpty else {
            return pipelineInvalidParams(request, "`id` is required")
        }
        guard let rawPath = request.params?["path"]?.stringValue,
              !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return pipelineInvalidParams(request, "`path` is required")
        }
        let parsed = TodoFileLink.parsePathToken(rawPath)
        let standardized = URL(fileURLWithPath: parsed.path).standardizedFileURL.path
        guard let link = await store.addFileLink(todoID: todoID, path: standardized, line: parsed.line) else {
            return .error(id: request.id, code: CLIErrorCode.internalError,
                          message: store.lastErrorMessage ?? "todo.file.add failed")
        }
        return .ok(id: request.id, result: [
            "id": .string(link.id),
            "todoId": .string(link.todoID),
            "path": .string(link.path),
        ])
    }

    func handleTodoFileRemove(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceTodoStore else { return pipelineNotConnected(request) }
        guard let todoID = request.params?["id"]?.stringValue, !todoID.isEmpty else {
            return pipelineInvalidParams(request, "`id` is required")
        }
        guard let rawPath = request.params?["path"]?.stringValue, !rawPath.isEmpty else {
            return pipelineInvalidParams(request, "`path` is required")
        }
        let standardized = URL(fileURLWithPath: TodoFileLink.parsePathToken(rawPath).path).standardizedFileURL.path
        guard await store.removeFileLink(todoID: todoID, path: standardized) else {
            return .error(id: request.id, code: CLIErrorCode.internalError,
                          message: store.lastErrorMessage ?? "todo.file.remove failed")
        }
        return .ok(id: request.id, result: ["id": .string(todoID), "removed": .bool(true)])
    }

    func handleTodoFileList(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceTodoStore else { return pipelineNotConnected(request) }
        guard let todoID = request.params?["id"]?.stringValue, !todoID.isEmpty else {
            return pipelineInvalidParams(request, "`id` is required")
        }
        await store.refreshFileLinks(todoID: todoID)
        let files = store.fileLinks(forTodo: todoID).map { link -> CLIJSONValue in
            var obj: [String: CLIJSONValue] = [
                "path": .string(link.path),
                "missing": .bool(!FileManager.default.fileExists(atPath: link.path)),
            ]
            if let line = link.line { obj["line"] = .int(line) }
            return .object(obj)
        }
        return .ok(id: request.id, result: ["files": .array(files)])
    }

    // MARK: - todo.triage.show

    func handleTodoTriageShow(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceTodoStore else { return pipelineNotConnected(request) }
        guard let todoID = request.params?["id"]?.stringValue, !todoID.isEmpty else {
            return pipelineInvalidParams(request, "`id` is required")
        }
        await store.refresh()
        guard let todo = store.todo(withID: todoID) else {
            return .error(id: request.id, code: CLIErrorCode.internalError, message: "todo not found: \(todoID)")
        }
        guard let triage = todo.triage, let json = triage.encodedJSON() else {
            return .ok(id: request.id, result: ["status": .string("none")])
        }
        return .ok(id: request.id, result: ["triage": .string(json)])
    }

    // MARK: - todo.dispatch

    func handleTodoDispatch(_ request: CLIRequest) async -> CLIResponse {
        guard vibespaceTodoStore != nil else { return pipelineNotConnected(request) }
        guard let bridge = todoLanePipelineBridge else {
            return .error(id: request.id, code: CLIErrorCode.notConnected,
                          message: "todo lane pipeline unavailable")
        }
        guard let todoID = request.params?["id"]?.stringValue, !todoID.isEmpty else {
            return pipelineInvalidParams(request, "`id` is required")
        }
        guard let lane = request.params?["lane"]?.stringValue,
              !lane.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return pipelineInvalidParams(request, "`lane` is required (name or id)")
        }
        var overrides: [String: String] = [:]
        if case .object(let inputObject)? = request.params?["inputs"] {
            for (key, value) in inputObject {
                if let string = value.stringValue { overrides[key] = string }
            }
        }
        let allowUnresolved = request.params?["allowUnresolved"]?.boolValue ?? false
        let envProject = request._env?.project_path?.trimmingCharacters(in: .whitespacesAndNewlines)

        let outcome = await bridge.dispatch(
            todoID: todoID,
            laneReference: lane,
            overrides: overrides,
            allowUnresolved: allowUnresolved,
            projectPathFallback: (envProject?.isEmpty == false)
                ? URL(fileURLWithPath: envProject!).standardizedFileURL.path
                : nil
        )
        switch outcome {
        case .dispatched(let taskID):
            return .ok(id: request.id, result: [
                "taskId": .string(taskID.uuidString),
                "dispatched": .bool(true),
            ])
        case .unresolvedInputs(let keys):
            return .error(id: request.id, code: CLIErrorCode.invalidParams,
                          message: "unresolved required inputs: \(keys.joined(separator: ", ")) "
                              + "(supply via --input key=value or pass --allow-unresolved)")
        case .activeTaskExists(let taskID):
            return .error(id: request.id, code: CLIErrorCode.invalidParams,
                          message: "todo already has an active lane task: \(taskID)")
        case .laneAmbiguous(let names):
            return .error(id: request.id, code: CLIErrorCode.invalidParams,
                          message: "lane name is ambiguous: \(names.joined(separator: ", "))")
        case .laneNotFound:
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "lane not found")
        case .todoNotFound:
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "todo not found: \(todoID)")
        case .creationFailed:
            return .error(id: request.id, code: CLIErrorCode.internalError,
                          message: "task creation failed (is a project path available?)")
        }
    }

    // MARK: - Helpers

    private func pipelineInvalidParams(_ request: CLIRequest, _ message: String) -> CLIResponse {
        .error(id: request.id, code: CLIErrorCode.invalidParams, message: message)
    }

    private func pipelineNotConnected(_ request: CLIRequest) -> CLIResponse {
        .error(id: request.id, code: CLIErrorCode.notConnected, message: "todo store not attached")
    }
}
