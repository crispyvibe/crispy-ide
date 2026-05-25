import Foundation

/// One trace entry for a single Foundation Models generation. Captures the three
/// things the developer wants to see: what came in, what went to the LLM, and
/// what came back. F041 developer-tools surface.
struct ContextSummaryTrace: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    /// Whether this generation came from a live terminal or the developer-tools sandbox.
    let source: Source
    /// Trimmed input that triggered this generation (the most recent visible
    /// command from `TerminalContextSummarySession.visibleCommands`). Empty
    /// for sandbox runs (the user message is the only input) and for sensitive
    /// classifications (the typed bytes are deliberately not stored).
    let received: String
    /// Assembled prompt sent to the model. `nil` for sensitive classifications,
    /// which never reach the LLM.
    let sent: Sent?
    /// What the model produced, or why it didn't.
    let result: Outcome
    /// Wall-clock duration of the `respond(to:)` call. Zero for sensitive
    /// classifications (no LLM call).
    let latency: TimeInterval

    enum Source: Equatable {
        case live
        case sandbox
    }

    struct Sent: Equatable {
        let systemInstruction: String
        let userMessage: String
    }

    enum Outcome: Equatable {
        case success(headline: String, phase: String)
        case timeout
        case unavailable
        case error(String)
        /// The keystroke classifier never observed the typed text on the
        /// surface within the configured budget — the input was treated as
        /// sensitive. The screen snapshot here is the last visible-surface
        /// content checked; it does NOT contain the typed text by definition.
        /// `typedText` is the actual line the user submitted, kept *only* for
        /// the in-memory developer-tools trace so the developer can see what
        /// triggered the classification. It does not reach the LLM, compose
        /// history, or the user-facing timeline. `attempts` is the total
        /// number of visibility checks performed (immediate + retries).
        /// F041-T07 diagnostic.
        case classifiedSensitive(screenSnapshot: String, typedText: String, attempts: Int)

        var label: String {
            switch self {
            case .success: return "success"
            case .timeout: return "timeout"
            case .unavailable: return "unavailable"
            case .error: return "error"
            case .classifiedSensitive: return "sensitive"
            }
        }
    }

    init(
        source: Source = .live,
        received: String,
        sent: Sent?,
        result: Outcome,
        latency: TimeInterval,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.source = source
        self.received = received
        self.sent = sent
        self.result = result
        self.latency = latency
    }
}

/// In-memory ring buffer of recent context-summary generations, surfaced in the
/// Developer Tools window. Cleared on app exit; capped to avoid unbounded
/// growth on long sessions.
final class ContextSummaryObservabilityStore: @unchecked Sendable {
    static let defaultCapacity = 50

    private let lock = NSLock()
    private let capacity: Int
    private var buffer: [ContextSummaryTrace] = []

    init(capacity: Int = ContextSummaryObservabilityStore.defaultCapacity) {
        self.capacity = capacity
        self.buffer.reserveCapacity(capacity)
    }

    func record(_ trace: ContextSummaryTrace) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(trace)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
    }

    /// Snapshot of all retained traces, oldest-first. Callers reverse for newest-first display.
    func snapshot() -> [ContextSummaryTrace] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
    }
}
