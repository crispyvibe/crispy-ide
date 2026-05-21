import Foundation

/// A single prompt turn: user message → agent processing → response.
struct ACPTurnEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let userMessage: String
    var thinking: String = ""
    var toolCalls: [ACPToolCallState] = []
    var responseText: String = ""
    var errorText: String?
    /// Number of images attached to this turn's user message.
    var attachedImageCount: Int = 0
    /// Indices into responseText where approval pauses occurred, splitting the response into segments.
    var approvalPauseOffsets: [Int] = []
    var isStreaming: Bool = true
    var completedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, userMessage, thinking, toolCalls, responseText, errorText, attachedImageCount, approvalPauseOffsets, isStreaming, completedAt
    }

    /// Splits responseText into segments around approval pauses.
    var responseSegments: [String] {
        guard !approvalPauseOffsets.isEmpty, !responseText.isEmpty else {
            return responseText.isEmpty ? [] : [responseText]
        }
        var segments: [String] = []
        var start = responseText.startIndex
        for offset in approvalPauseOffsets {
            let idx = responseText.index(responseText.startIndex, offsetBy: min(offset, responseText.count))
            let segment = String(responseText[start..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty { segments.append(segment) }
            start = idx
        }
        let tail = String(responseText[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { segments.append(tail) }
        return segments.isEmpty && !responseText.isEmpty ? [responseText] : segments
    }

    var changedFiles: [ACPDiffSummaryRow] {
        var rows: [ACPDiffSummaryRow] = []
        for call in toolCalls {
            for (i, content) in call.content.enumerated() {
                if case .diff(let diff) = content {
                    let stats = ACPDiffStats(diff: diff)
                    rows.append(ACPDiffSummaryRow(
                        id: "\(call.id):\(i):\(diff.path)",
                        diff: diff,
                        additions: stats.additions,
                        deletions: stats.deletions
                    ))
                }
            }
        }
        return rows
    }
}

struct ACPTimelineEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var kind: Kind
    var completedAt: Date?

    enum Kind: Codable {
        case userMessage(String)
        case assistantMessage(text: String, streaming: Bool)
        case thought(String)
        case toolCallGroup([ACPToolCallState])
        case turn(ACPTurnEntry)

        private enum CodingKeys: String, CodingKey { case type, text, streaming, calls, turn }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .userMessage(let t):
                try container.encode("userMessage", forKey: .type)
                try container.encode(t, forKey: .text)
            case .assistantMessage(let t, let s):
                try container.encode("assistantMessage", forKey: .type)
                try container.encode(t, forKey: .text)
                try container.encode(s, forKey: .streaming)
            case .thought(let t):
                try container.encode("thought", forKey: .type)
                try container.encode(t, forKey: .text)
            case .toolCallGroup(let c):
                try container.encode("toolCallGroup", forKey: .type)
                try container.encode(c, forKey: .calls)
            case .turn(let t):
                try container.encode("turn", forKey: .type)
                try container.encode(t, forKey: .turn)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "userMessage":
                self = .userMessage(try container.decode(String.self, forKey: .text))
            case "assistantMessage":
                let text = try container.decode(String.self, forKey: .text)
                let streaming = try container.decodeIfPresent(Bool.self, forKey: .streaming) ?? false
                self = .assistantMessage(text: text, streaming: streaming)
            case "thought":
                self = .thought(try container.decode(String.self, forKey: .text))
            case "toolCallGroup":
                self = .toolCallGroup(try container.decode([ACPToolCallState].self, forKey: .calls))
            case "turn":
                self = .turn(try container.decode(ACPTurnEntry.self, forKey: .turn))
            default:
                self = .userMessage("")
            }
        }
    }

    static func user(_ text: String) -> Self {
        .init(id: UUID(), timestamp: Date(), kind: .userMessage(text))
    }

    static func assistant(_ text: String, streaming: Bool) -> Self {
        .init(id: UUID(), timestamp: Date(), kind: .assistantMessage(text: text, streaming: streaming))
    }

    static func thought(_ text: String) -> Self {
        .init(id: UUID(), timestamp: Date(), kind: .thought(text))
    }

    static func toolCalls(_ calls: [ACPToolCallState]) -> Self {
        .init(id: UUID(), timestamp: Date(), kind: .toolCallGroup(calls))
    }

    static func turn(_ turn: ACPTurnEntry) -> Self {
        .init(id: turn.id, timestamp: turn.timestamp, kind: .turn(turn))
    }
}

struct ACPSlashCommand: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let description: String
}

/// Token usage from the agent's context window.
struct ACPContextWindowUsage {
    var usedTokens: Int
    var maxTokens: Int?
    var fraction: Double {
        guard let max = maxTokens, max > 0 else { return 0 }
        return Double(usedTokens) / Double(max)
    }

    /// Parses token usage from a sessionInfoUpdate payload.
    static func parse(from info: [String: Any]) -> ACPContextWindowUsage? {
        if let tokenUsage = info["tokenUsage"] as? [String: Any] {
            let used = tokenUsage["usedTokens"] as? Int ?? tokenUsage["used_tokens"] as? Int ?? 0
            let max = tokenUsage["maxTokens"] as? Int ?? tokenUsage["max_tokens"] as? Int
                ?? tokenUsage["modelContextWindow"] as? Int
            if used > 0 { return ACPContextWindowUsage(usedTokens: used, maxTokens: max) }
        }
        return nil
    }
}

/// Classifies a tool call into an itemType for type-specific rendering.
enum ACPToolCallClassifier {
    static func classify(_ toolCall: ACPToolCallState) -> String {
        let kind = (toolCall.kind ?? "").lowercased()
        let title = toolCall.title.lowercased()
        if toolCall.content.contains(where: { if case .diff = $0 { return true }; return false }) {
            return "file_change"
        }
        if kind.contains("command") || kind.contains("terminal") || kind.contains("exec")
            || title.contains("ran command") || title.contains("terminal") {
            return "command_execution"
        }
        if kind.contains("read") || title.contains("read file") || title.contains("read_file") {
            return "file_read"
        }
        if kind.contains("search") || kind.contains("web") || title.contains("search") {
            return "web_search"
        }
        if kind.contains("mcp") { return "mcp_tool_call" }
        return "unknown"
    }
}

/// Generates a concise thread title from the first user message.
enum ACPTitleGenerator {
    /// Quick seed title from the user message (used immediately on first send).
    static func summary(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet(charactersIn: ".!?\n")
        let firstSentence = trimmed.components(separatedBy: separators).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        if firstSentence.count <= 60 { return firstSentence }
        let truncated = String(firstSentence.prefix(57))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[truncated.startIndex..<lastSpace]) + "…"
        }
        return truncated + "…"
    }

    /// Improved title using both user message and assistant response.
    /// Extracts the core action/topic for a more descriptive title.
    static func titleFromTurn(userMessage: String, responseText: String) -> String {
        // Try to extract a concise action from the user message
        let cleaned = userMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "can you ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "please ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "i want to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "i need to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "help me ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize first letter
        let capitalized: String
        if let first = cleaned.first {
            capitalized = first.uppercased() + cleaned.dropFirst()
        } else {
            capitalized = cleaned
        }

        return summary(from: capitalized)
    }
}

/// Formats a time interval for display.
enum ACPDurationFormatter {
    static func format(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "<1s" }
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return secs == 0 ? "\(minutes)m" : "\(minutes)m \(secs)s"
    }
}

struct ACPToolCallState: Identifiable, Equatable, Codable {
    let id: String
    var title: String
    var kind: String?
    var status: ACPToolCallStatus
    var content: [ACPToolCallContent]
    var locations: [ACPToolCallLocation]
}
