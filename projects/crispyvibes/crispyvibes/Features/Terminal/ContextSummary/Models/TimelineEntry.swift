import Foundation

/// A single entry in the expanded context summary timeline.
struct TimelineEntry: Identifiable {
    let id: UUID
    let kind: Kind
    let text: String
    let originalText: String?
    let generatedText: String?
    let timestamp: Date

    var copyText: String {
        guard let originalText, let generatedText else { return text }
        return """
        Original:
        \(originalText)

        Generated:
        \(generatedText)
        """
    }

    enum Kind: Equatable {
        case command
        case toolCall
        case message
        case status
    }

    init(
        kind: Kind,
        text: String,
        originalText: String? = nil,
        generatedText: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.kind = kind
        self.text = text
        self.originalText = originalText
        self.generatedText = generatedText
        self.timestamp = timestamp
    }
}
