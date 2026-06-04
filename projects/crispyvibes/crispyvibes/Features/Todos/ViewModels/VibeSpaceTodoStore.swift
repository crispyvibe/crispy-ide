import Combine
import Foundation
import OSLog

/// F053 — central store for quick todos / sticky notes in the active vibespace.
///
/// Mirrors `VibeSpaceCommentStore`: wraps the `AgentConversationStore` that owns
/// the persistence-helper subprocess, sends `todo.*` JSON-RPC, and publishes the
/// vibespace's todos for the sticky-note UI. `@MainActor`; mutations go through
/// named async methods and refresh the cache before notifying observers.
@MainActor
final class VibeSpaceTodoStore: ObservableObject {

    /// All todos for the active vibespace (both project-scoped and
    /// vibespace-level), most-recently-updated first.
    @Published private(set) var todos: [Todo] = []

    /// Thread messages per todo id, fetched on demand for the detail view.
    @Published private(set) var messagesByTodo: [String: [TodoMessage]] = [:]

    /// Bumps on every successful write so views can coalesce-refresh.
    @Published private(set) var lastChangeID: UUID = UUID()

    /// Latest user-visible error from a write attempt.
    @Published private(set) var lastErrorMessage: String?

    /// Fires whenever the store mutates (parallel to the comment store).
    let changes = PassthroughSubject<Void, Never>()

    private let conversationStore: AgentConversationStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app",
                                category: "todos")
    private weak var activeVibeSpaceProvider: AnyObject?
    private var resolveActiveVibeSpaceID: (@MainActor () -> String?)?

    init(conversationStore: AgentConversationStore) {
        self.conversationStore = conversationStore
    }

    /// Late-bound binding to the active vibespace ID. Idempotent: only the
    /// first call wins (matches `VibeSpaceCommentStore`).
    func bindActiveVibeSpace(provider: AnyObject, resolver: @escaping @MainActor () -> String?) {
        guard activeVibeSpaceProvider == nil, resolveActiveVibeSpaceID == nil else { return }
        self.activeVibeSpaceProvider = provider
        self.resolveActiveVibeSpaceID = resolver
    }

    func currentVibeSpaceID() -> String? { resolveActiveVibeSpaceID?() }

    // MARK: - Reads

    /// Todos scoped to a project, or all vibespace todos when `projectPath` is nil.
    func filtered(byProject projectPath: String?) -> [Todo] {
        guard let projectPath else { return todos }
        return todos.filter { $0.projectPath == projectPath }
    }

    func todo(withID id: String) -> Todo? { todos.first { $0.id == id } }

    // MARK: - Writes

    @discardableResult
    func add(
        title: String,
        body: String? = nil,
        projectPath: String? = nil,
        colorTag: String? = nil,
        filePath: String? = nil,
        vibespaceIDOverride: String? = nil
    ) async -> Todo? {
        guard let vibespaceID = vibespaceIDOverride ?? resolveActiveVibeSpaceID?() else {
            recordError("no active vibespace"); return nil
        }
        var params: [String: Any] = [
            "id": UUID().uuidString,
            "vibespaceId": vibespaceID,
            "title": title,
        ]
        if let projectPath { params["projectPath"] = projectPath }
        if let body { params["body"] = body }
        if let colorTag { params["colorTag"] = colorTag }
        if let filePath { params["filePath"] = filePath }

        guard let result = await conversationStore.send(method: "todo.add", params: params) else {
            recordError("persistence helper unavailable"); return nil
        }
        if let err = result.errorMessage { recordError(err); return nil }
        let created = result.value.flatMap(Todo.init(json:))
        await refresh(vibespaceID: vibespaceID)
        bumpChange()
        return created
    }

    func update(
        id: String,
        title: String? = nil,
        body: String? = nil,
        colorTag: String? = nil,
        filePath: String? = nil
    ) async -> Bool {
        var params: [String: Any] = ["id": id]
        if let title { params["title"] = title }
        if let body { params["body"] = body }
        if let colorTag { params["colorTag"] = colorTag }
        if let filePath { params["filePath"] = filePath }
        return await mutate(method: "todo.update", params: params)
    }

    func setCompleted(id: String, completed: Bool) async -> Bool {
        await mutate(method: "todo.complete", params: ["id": id, "completed": completed])
    }

    @discardableResult
    func delete(id: String) async -> Bool {
        await mutate(method: "todo.delete", params: ["id": id])
    }

    // MARK: - Thread

    func messages(forTodo todoID: String) -> [TodoMessage] {
        messagesByTodo[todoID] ?? []
    }

    @discardableResult
    func addMessage(todoID: String, body: String, authorKind: String = "user") async -> TodoMessage? {
        let params: [String: Any] = [
            "id": UUID().uuidString,
            "todoId": todoID,
            "body": body,
            "authorKind": authorKind,
        ]
        guard let result = await conversationStore.send(method: "todo.message.add", params: params) else {
            recordError("persistence helper unavailable"); return nil
        }
        if let err = result.errorMessage { recordError(err); return nil }
        let created = result.value.flatMap(TodoMessage.init(json:))
        await refreshMessages(todoID: todoID)
        await refresh()
        bumpChange()
        return created
    }

    func refreshMessages(todoID: String) async {
        guard let result = await conversationStore.send(
            method: "todo.message.list",
            params: ["todoId": todoID]
        ) else { return }
        if let err = result.errorMessage { recordError(err); return }
        let rows = result.value?["messages"] as? [[String: Any]] ?? []
        messagesByTodo[todoID] = rows.compactMap(TodoMessage.init(json:))
    }

    // MARK: - Refresh

    /// Reload all todos for the active vibespace.
    func refresh() async {
        guard let vsID = resolveActiveVibeSpaceID?() else { return }
        await refresh(vibespaceID: vsID)
    }

    private func refresh(vibespaceID: String) async {
        guard let result = await conversationStore.send(
            method: "todo.list",
            params: ["vibespaceId": vibespaceID, "status": "all"]
        ) else { return }
        if let err = result.errorMessage { recordError(err); return }
        let rows = result.value?["todos"] as? [[String: Any]] ?? []
        todos = rows.compactMap(Todo.init(json:))
    }

    func clearLastError() { lastErrorMessage = nil }

    // MARK: - Helpers

    private func mutate(method: String, params: [String: Any]) async -> Bool {
        guard let result = await conversationStore.send(method: method, params: params) else {
            recordError("persistence helper unavailable"); return false
        }
        if let err = result.errorMessage { recordError(err); return false }
        await refresh()
        bumpChange()
        return true
    }

    private func bumpChange() {
        lastChangeID = UUID()
        changes.send(())
    }

    private func recordError(_ message: String) {
        logger.warning("todo op error: \(message, privacy: .public)")
        lastErrorMessage = message
    }
}
