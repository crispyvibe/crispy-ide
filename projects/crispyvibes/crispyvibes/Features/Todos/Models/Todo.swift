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

    var isCompleted: Bool { status == .completed }
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
    }
}
