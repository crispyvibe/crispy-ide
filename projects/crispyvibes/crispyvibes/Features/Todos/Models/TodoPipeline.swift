import Foundation

// F060 — todo-side pipeline models: file links (live references, never copies)
// and the structured triage result. Both mirror persistence-helper rows/JSON;
// missing-path state is computed at render time, never stored.

/// A live file reference on a todo: `{path, line?}`. The target may move or
/// vanish independently — a dangling link renders as "missing", it is never
/// silently dropped (F060-R02).
struct TodoFileLink: Identifiable, Hashable, Sendable {
    let id: String
    let todoID: String
    let path: String
    let line: Int?
    let createdAt: String

    /// Display name: last path component, with the line anchor when present.
    var displayName: String {
        let name = (path as NSString).lastPathComponent
        guard let line else { return name }
        return "\(name):\(line)"
    }
}

extension TodoFileLink {
    init?(json: [String: Any]) {
        guard
            let id = json["id"] as? String,
            let todoID = json["todoId"] as? String,
            let path = json["path"] as? String,
            let createdAt = json["createdAt"] as? String
        else { return nil }
        self.id = id
        self.todoID = todoID
        self.path = path
        self.line = json["line"] as? Int
        self.createdAt = createdAt
    }

    /// Parse a `path[:line]` CLI/UI token. A trailing `:NN` (NN ≥ 1) becomes
    /// the line anchor; anything else stays part of the path.
    static func parsePathToken(_ token: String) -> (path: String, line: Int?) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = trimmed.lastIndex(of: ":"),
              idx != trimmed.startIndex,
              let line = Int(trimmed[trimmed.index(after: idx)...]),
              line >= 1 else {
            return (trimmed, nil)
        }
        return (String(trimmed[..<idx]), line)
    }
}

// MARK: - Triage

/// The structured result of one background triage run (F060-R06). Stored as
/// `triage_json` on the todo; shape-validated on decode — malformed blobs are
/// treated as absent rather than rendered.
struct TodoTriage: Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending, done, skipped, failed
    }

    struct ContextFile: Codable, Hashable, Sendable {
        var path: String
        var line: Int?
        var note: String?
    }

    struct Question: Codable, Hashable, Sendable {
        var text: String
        /// The lane input key this question would fill, when known.
        var carryForwardKey: String?
    }

    struct LaneSuggestion: Codable, Hashable, Sendable {
        var laneID: UUID
        var name: String
        var reason: String?
        var score: Double?
    }

    var status: Status
    var startedAt: String?
    var finishedAt: String?
    /// The todo `updatedAt` this run analyzed — the generation guard: a result
    /// whose snapshot no longer matches the todo is stale and must be discarded.
    var todoUpdatedAtSnapshot: String?
    var context: [ContextFile]?
    var questions: [Question]?
    var lanes: [LaneSuggestion]?
    /// false = explicitly judged not lane-shaped ("buy milk").
    var laneShaped: Bool?
    /// Carry-forward keys the triage agent could already determine.
    var prefill: [String: String]?

    var suggestedLane: LaneSuggestion? {
        lanes?.max { ($0.score ?? 0) < ($1.score ?? 0) }
    }

    var openQuestionCount: Int { questions?.count ?? 0 }
}

extension TodoTriage {
    /// Decode from the persisted `triage_json` string. Returns nil for absent,
    /// malformed, or shape-invalid content (F060-T02: invalid = dropped).
    static func decode(from json: String?) -> TodoTriage? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TodoTriage.self, from: data)
    }

    func encodedJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
