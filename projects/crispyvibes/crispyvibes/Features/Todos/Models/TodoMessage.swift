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

/// Consecutive same-author messages within a 5-minute window collapse under a
/// single author header (spec F053-R06). Pure and testable.
struct TodoMessageGroup: Identifiable, Equatable {
    let id: String
    let authorKind: String
    var messages: [TodoMessage]

    static func group(
        _ messages: [TodoMessage],
        window: TimeInterval = 300,
        parseDate: (String) -> Date?
    ) -> [TodoMessageGroup] {
        var groups: [TodoMessageGroup] = []
        for message in messages {
            if var last = groups.last,
               last.authorKind == message.authorKind,
               let lastDate = parseDate(last.messages.last?.createdAt ?? ""),
               let thisDate = parseDate(message.createdAt),
               thisDate.timeIntervalSince(lastDate) < window {
                last.messages.append(message)
                groups[groups.count - 1] = last
            } else {
                groups.append(TodoMessageGroup(id: message.id, authorKind: message.authorKind, messages: [message]))
            }
        }
        return groups
    }
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
