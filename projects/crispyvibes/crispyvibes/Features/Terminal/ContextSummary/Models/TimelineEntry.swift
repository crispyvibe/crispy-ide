import Foundation

/// A single entry in the context summary timeline.
///
/// Two main shapes:
/// - `.command` entries record what the user submitted (visible command text or a
///   sensitive-information placeholder). `isSensitivePlaceholder == true` indicates
///   the text is a non-secret stand-in for input that was not echoed to the screen.
/// - `.message` entries record an AI-generated summary, with both the original
///   originating command and the generated summary preserved for the
///   Summary/Original toggle (F041-R13).
struct TimelineEntry: Identifiable, Equatable {
    let id: UUID
    let kind: Kind
    let text: String
    let originalText: String?
    let generatedText: String?
    let timestamp: Date
    let isSensitivePlaceholder: Bool

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
        timestamp: Date = Date(),
        isSensitivePlaceholder: Bool = false
    ) {
        self.id = UUID()
        self.kind = kind
        self.text = text
        self.originalText = originalText
        self.generatedText = generatedText
        self.timestamp = timestamp
        self.isSensitivePlaceholder = isSensitivePlaceholder
    }
}
