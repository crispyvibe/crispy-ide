import Foundation

/// F053 — a single rich-text (markdown) message in a todo's thread.
struct TodoMessage: Identifiable, Hashable, Sendable {
    let id: String
    let todoID: String
    var body: String
    /// "user" or "agent".
    let authorKind: String
    let createdAt: String
    var updatedAt: String

    var isAgent: Bool { authorKind == "agent" }
}

extension TodoMessage {
    /// Decode from the persistence helper's camelCase JSON object.
    init?(json: [String: Any]) {
        guard
            let id = json["id"] as? String,
            let todoID = json["todoId"] as? String,
            let body = json["body"] as? String,
            let createdAt = json["createdAt"] as? String,
            let updatedAt = json["updatedAt"] as? String
        else { return nil }
        self.id = id
        self.todoID = todoID
        self.body = body
        self.authorKind = (json["authorKind"] as? String) ?? "user"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
