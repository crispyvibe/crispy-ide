import Foundation

// F060 — pipeline extensions on the todo store: file links (live references)
// and the pipeline fields (laneTaskID / refinementSessionID / triage). Same
// RPC + refresh + change-bump discipline as the F053 methods; file links are
// cached per-todo like thread messages.

extension VibeSpaceTodoStore {

    // MARK: - File links

    func fileLinks(forTodo todoID: String) -> [TodoFileLink] {
        fileLinksByTodo[todoID] ?? []
    }

    @discardableResult
    func addFileLink(todoID: String, path: String, line: Int? = nil) async -> TodoFileLink? {
        var params: [String: Any] = [
            "id": UUID().uuidString,
            "todoId": todoID,
            "path": path,
        ]
        if let line { params["line"] = line }
        guard let result = await sendPipeline(method: "todo.file.add", params: params) else { return nil }
        let created = TodoFileLink(json: result)
        await refreshFileLinks(todoID: todoID)
        noteChanged()
        return created
    }

    @discardableResult
    func removeFileLink(todoID: String, path: String) async -> Bool {
        guard await sendPipeline(method: "todo.file.remove", params: ["todoId": todoID, "path": path]) != nil else {
            return false
        }
        await refreshFileLinks(todoID: todoID)
        noteChanged()
        return true
    }

    func refreshFileLinks(todoID: String) async {
        guard let value = await sendPipeline(method: "todo.file.list", params: ["todoId": todoID]) else { return }
        let rows = value["files"] as? [[String: Any]] ?? []
        var links = rows.compactMap(TodoFileLink.init(json:))
        // Legacy single filePath surfaces as link index 0 when not already linked
        // (read-side merge — no destructive migration; F060-R01).
        if let legacy = todo(withID: todoID)?.filePath,
           !legacy.isEmpty,
           !links.contains(where: { $0.path == legacy }) {
            links.insert(
                TodoFileLink(id: "legacy:\(todoID)", todoID: todoID, path: legacy, line: nil, createdAt: ""),
                at: 0
            )
        }
        fileLinksByTodo[todoID] = links
    }

    // MARK: - Pipeline fields

    /// Partial update of the pipeline fields. `.some(nil)` clears a field,
    /// `nil` leaves it untouched (mirrors `todo.update` semantics).
    @discardableResult
    func setPipelineFields(
        id: String,
        laneTaskID: String?? = nil,
        refinementSessionID: String?? = nil,
        triage: TodoTriage?? = nil
    ) async -> Bool {
        var params: [String: Any] = ["id": id]
        if let laneTaskID { params["laneTaskId"] = laneTaskID ?? NSNull() }
        if let refinementSessionID { params["refinementSessionId"] = refinementSessionID ?? NSNull() }
        if let triage {
            if let triage {
                guard let encoded = triage.encodedJSON() else { return false }
                params["triageJson"] = encoded
            } else {
                params["triageJson"] = NSNull()
            }
        }
        guard params.count > 1 else { return true }
        guard await sendPipeline(method: "todo.pipeline.set", params: params) != nil else { return false }
        await refresh()
        noteChanged()
        return true
    }
}
