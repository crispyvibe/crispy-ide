import Foundation
import OSLog

// F060 — the bridge between Todos (F053) and Vibe Lanes (F059). Owns dispatch
// (todo → lane task), carry-forward mapping, and task-lifecycle fan-in to the
// todo thread. Todos and VibeLanes never import each other; all cross-feature
// behavior lives here, and either feature functions fully with the bridge
// absent (F060-R10).

/// Outcome of a dispatch attempt. `unresolvedInputs` fails the attempt unless
/// the caller passed `allowUnresolved` (UI shows them in the sheet; the CLI
/// requires an explicit flag — F060-R04).
enum TodoLaneDispatchOutcome: Equatable {
    case dispatched(taskID: UUID)
    case unresolvedInputs([String])
    case activeTaskExists(taskID: String)
    case laneAmbiguous([String])
    case laneNotFound
    case todoNotFound
    case creationFailed
}

/// The slice of the todo store the bridge needs — a seam so bridge tests run
/// against a deterministic fake instead of the RPC-backed store, and so the
/// bridge depends on capabilities, not the concrete F053 class.
@MainActor
protocol TodoPipelineTodoStoring: AnyObject {
    var todos: [Todo] { get }
    func todo(withID id: String) -> Todo?
    func fileLinks(forTodo todoID: String) -> [TodoFileLink]
    @discardableResult
    func setPipelineFields(
        id: String,
        laneTaskID: String??,
        refinementSessionID: String??,
        triage: TodoTriage??
    ) async -> Bool
    @discardableResult
    func addMessage(todoID: String, body: String, authorKind: String) async -> TodoMessage?
    @discardableResult
    func setCompleted(id: String, completed: Bool) async -> Bool
    func refreshFileLinks(todoID: String) async
}

extension VibeSpaceTodoStore: TodoPipelineTodoStoring {}

@MainActor
final class TodoLanePipelineBridge: ObservableObject {

    // Internal (not private) so same-module extensions (+Refine) can reach them.
    let todoStore: any TodoPipelineTodoStoring
    let laneManager: VibeLaneTaskManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app",
                                category: "todo-lane-pipeline")

    /// Fan-in dedupe: one thread message per (taskID, state, requestID) —
    /// crash-safe enough for v1 because replays re-post at most one message
    /// per open request, and re-registration reconciles from persisted state.
    private var fannedIn: Set<String> = []

    init(todoStore: any TodoPipelineTodoStoring, laneManager: VibeLaneTaskManager) {
        self.todoStore = todoStore
        self.laneManager = laneManager
        laneManager.onTaskStateChanged = { [weak self] taskID, _, newState in
            self?.taskChanged(taskID: taskID, newState: newState)
        }
    }

    /// The lane catalog for pickers and triage prompts (pass-through so views
    /// depend on the bridge, not on the lane manager).
    func laneCatalog() -> [VibeLaneCatalogEntry] { laneManager.catalogSummary() }

    // MARK: - Dispatch (one method, two callers: UI sheet and `todo dispatch` CLI)

    /// Map a todo onto a lane's first-checkpoint contract and create the task.
    /// Mapping priority: explicit overrides (CLI --input) > dispatch-block
    /// sections > triage prefill > file links (F060-R04).
    func dispatch(
        todoID: String,
        laneReference: String,
        overrides: [String: String] = [:],
        allowUnresolved: Bool = false,
        projectPathFallback: String? = nil,
        agentID: String? = nil
    ) async -> TodoLaneDispatchOutcome {
        guard let todo = todoStore.todo(withID: todoID) else { return .todoNotFound }

        // One linked non-terminal task per todo (F060-R03).
        if let linked = todo.laneTaskID,
           let existing = UUID(uuidString: linked).flatMap({ laneManager.task(withID: $0) }),
           !existing.isTerminal {
            return .activeTaskExists(taskID: linked)
        }

        let laneID: UUID
        switch laneManager.resolveLaneReference(laneReference) {
        case .resolved(let id): laneID = id
        case .ambiguous(let names): return .laneAmbiguous(names)
        case .notFound: return .laneNotFound
        }
        guard let entry = laneManager.catalogSummary().first(where: { $0.laneID == laneID }) else {
            return .laneNotFound
        }

        let seed = seededInputs(for: todo, overrides: overrides)
        let unresolved = entry.firstCheckpointRequires.keys.filter { seed[$0] == nil }.sorted()
        if !unresolved.isEmpty, !allowUnresolved {
            return .unresolvedInputs(unresolved)
        }

        guard let projectPath = todo.projectPath ?? projectPathFallback else {
            // Vibespace-level todo with no chosen project: the UI preselects one;
            // the CLI falls back to _env.project_path. Reaching here is caller error.
            return .creationFailed
        }
        guard let task = await laneManager.createTask(
            laneID: laneID,
            title: todo.title,
            projectPath: projectPath,
            agentID: agentID,
            initialCarryForward: seed.isEmpty ? nil : seed
        ) else { return .creationFailed }

        await todoStore.setPipelineFields(
            id: todoID,
            laneTaskID: .some(task.id.uuidString),
            refinementSessionID: nil,
            triage: nil
        )
        await postThreadMessage(
            todoID: todoID,
            body: AppStrings.TodoPipeline.threadDispatched(laneName: entry.name)
        )
        return .dispatched(taskID: task.id)
    }

    /// The seeded carry-forward for a todo: overrides > dispatch-block >
    /// triage prefill > contextFiles from links. Values are capped to the
    /// F053 body limit upstream (persistence validates), trimmed here.
    func seededInputs(for todo: Todo, overrides: [String: String] = [:]) -> [String: String] {
        var seed: [String: String] = [:]
        let links = todoStore.fileLinks(forTodo: todo.id)
        if !links.isEmpty {
            seed["contextFiles"] = links.map { link in
                let missing = !FileManager.default.fileExists(atPath: link.path)
                let anchor = link.line.map { ":\($0)" } ?? ""
                return missing ? "\(link.path)\(anchor) (missing)" : "\(link.path)\(anchor)"
            }.joined(separator: ", ")
        }
        for (key, value) in todo.triage?.prefill ?? [:] {
            seed[key] = value
        }
        for (key, value) in TodoDispatchBlock.parse(body: todo.body) {
            seed[key] = value
        }
        for (key, value) in overrides {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { seed[key] = trimmed }
        }
        return seed
    }

    // MARK: - Lifecycle fan-in (F060-R05)

    private func taskChanged(taskID: UUID, newState: VibeLaneTaskState) {
        guard let todo = todoStore.todos.first(where: { $0.laneTaskID == taskID.uuidString }) else { return }
        let task = laneManager.task(withID: taskID)
        let dedupeKey = "\(taskID.uuidString)|\(newState.rawValue)|\(task?.openInputRequest?.id.uuidString ?? "")"
        guard !fannedIn.contains(dedupeKey) else { return }
        fannedIn.insert(dedupeKey)

        let body: String
        switch newState {
        case .running:
            return // resumes are visible on the lanes dashboard; keep threads quiet
        case .needsInput:
            body = AppStrings.TodoPipeline.threadNeedsInput(
                requestKind: task?.openInputRequest?.kind.rawValue ?? ""
            )
        case .stopped:
            body = AppStrings.TodoPipeline.threadStopped(
                reason: task?.stopReason?.rawValue ?? ""
            )
        case .done:
            // Carry the task's actual outcome report into the thread — a bare
            // "finished" line tells the user nothing they can act on.
            if let outcome = task?.outcomeSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !outcome.isEmpty {
                body = "\(AppStrings.TodoPipeline.threadDone)\n\n\(outcome)"
            } else {
                body = AppStrings.TodoPipeline.threadDone
            }
        }
        let todoID = todo.id
        let autoComplete = newState == .done && AppPreferences.todoAutoCompleteOnDone()
        _Concurrency.Task { @MainActor [weak self] in
            await self?.postThreadMessage(todoID: todoID, body: body)
            if autoComplete {
                await self?.completeTodo(todoID: todoID)
            }
        }
    }

    /// Complete the todo when its task finished and the auto-complete setting
    /// is on (F060-R05: done may complete; stopped never does).
    private func completeTodo(todoID: String) async {
        _ = await todoStore.setCompleted(id: todoID, completed: true)
    }

    private func postThreadMessage(todoID: String, body: String) async {
        _ = await todoStore.addMessage(todoID: todoID, body: body, authorKind: "agent")
    }
}

// MARK: - Dispatch block parsing

/// Parses the refine-produced "dispatch block" out of a todo body: markdown
/// sections whose headings name carry-forward keys. `## Goal` → key `goal`,
/// `## Done when` → `doneWhen` (camelCased words). Section content is the
/// lines until the next heading, trimmed; empty sections are dropped.
enum TodoDispatchBlock {
    static func parse(body: String?) -> [String: String] {
        guard let body, !body.isEmpty else { return [:] }
        var result: [String: String] = [:]
        var currentKey: String?
        var currentLines: [String] = []

        func flush() {
            if let key = currentKey {
                let value = currentLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { result[key] = value }
            }
            currentLines = []
        }

        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                flush()
                let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                currentKey = camelCaseKey(title)
            } else if currentKey != nil {
                currentLines.append(line)
            }
        }
        flush()
        return result
    }

    /// "Done when" → "doneWhen"; "Context files" → "contextFiles"; "GOAL" → "goal".
    static func camelCaseKey(_ title: String) -> String? {
        let words = title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let head = words[0].lowercased()
        let tail = words.dropFirst().map { $0.lowercased().capitalized }
        return ([head] + tail).joined()
    }
}
