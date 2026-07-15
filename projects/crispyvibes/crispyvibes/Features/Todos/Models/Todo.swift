import Foundation

/// F053 — a quick todo / sticky note, scoped to a vibespace and optionally a
/// project (`projectPath == nil` ⇒ vibespace-level). Mirrors the persistence
/// helper's `todos` row; `dueAt`/`reminderAt` are reserved for the later
/// reminders phase and are surfaced read-only for now.
struct Todo: Identifiable, Hashable, Sendable {
    enum Status: String, Sendable {
        case active
        case completed
    }

    let id: String
    let vibespaceID: String
    let projectPath: String?
    var title: String
    var body: String?
    var colorTag: String?
    var filePath: String?
    var status: Status
    var dueAt: String?
    var reminderAt: String?
    let createdAt: String
    var updatedAt: String
    var completedAt: String?
    // F060 pipeline fields. laneTaskID links the todo to at most one Vibe Lane
    // task; triage is the structured background-triage result. All optional —
    // a todo with none of them is exactly an F053 todo.
    var laneTaskID: String? = nil
    var refinementSessionID: String? = nil
    var triage: TodoTriage? = nil

    var isCompleted: Bool { status == .completed }
}

// MARK: - Sticky colors

/// The authorable sticky-note color tags (F053). Raw values are the persisted
/// `colorTag` strings shared with the CLI (`crispy todo add --color yellow`).
enum TodoStickyColor: String, CaseIterable, Sendable {
    case yellow, green, blue, pink, purple, orange
}

extension Todo {
    var stickyColor: TodoStickyColor? {
        colorTag.flatMap(TodoStickyColor.init(rawValue:))
    }
}

// MARK: - List sections

/// Pure list shaping for the Todos panel: scope → search → stable split into
/// active/completed. Sorting is stable across edits — active by creation
/// (newest first), completed by completion time — so cards never jump around
/// under the user when a title is renamed or a message lands.
enum TodoListSections {
    static func shape(
        _ todos: [Todo],
        projectPath: String?,
        includeAllProjects: Bool,
        query: String
    ) -> (active: [Todo], completed: [Todo]) {
        let scoped = includeAllProjects ? todos : todos.filter { $0.projectPath == projectPath }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = trimmedQuery.isEmpty ? scoped : scoped.filter { todo in
            todo.title.localizedCaseInsensitiveContains(trimmedQuery)
                || (todo.body?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
        let active = matched.filter { !$0.isCompleted }
            .sorted { $0.createdAt > $1.createdAt }
        let completed = matched.filter(\.isCompleted)
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
        return (active, completed)
    }
}

extension Todo {
    /// Decode from the persistence helper's camelCase JSON object
    /// (`RPCResult.value`). Returns `nil` if required fields are missing.
    init?(json: [String: Any]) {
        guard
            let id = json["id"] as? String,
            let vibespaceID = json["vibespaceId"] as? String,
            let title = json["title"] as? String,
            let statusRaw = json["status"] as? String,
            let status = Status(rawValue: statusRaw),
            let createdAt = json["createdAt"] as? String,
            let updatedAt = json["updatedAt"] as? String
        else { return nil }
        self.id = id
        self.vibespaceID = vibespaceID
        self.projectPath = json["projectPath"] as? String
        self.title = title
        self.body = json["body"] as? String
        self.colorTag = json["colorTag"] as? String
        self.filePath = json["filePath"] as? String
        self.status = status
        self.dueAt = json["dueAt"] as? String
        self.reminderAt = json["reminderAt"] as? String
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = json["completedAt"] as? String
        self.laneTaskID = json["laneTaskId"] as? String
        self.refinementSessionID = json["refinementSessionId"] as? String
        self.triage = TodoTriage.decode(from: json["triageJson"] as? String)
    }
}
