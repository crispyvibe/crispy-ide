import Combine
import Foundation

/// Per-mount projection over a `TerminalContextSummarySession`. Owns only ephemeral
/// presentation state (currently `isExpanded`); the durable summary state, persistent
/// LLM session, and full timeline live on the per-terminal `TerminalContextSummarySession`
/// that survives view-tree changes (board ↔ spotlight ↔ rail). F041-R11.
///
/// Layering note: this view model intentionally does not generate summaries, hold a
/// `LanguageModelSession`, or store the recent-commands buffer. Its only job is to
/// translate the session's domain state into something a SwiftUI view can render and
/// to absorb mount-local UI state.
@MainActor
final class TerminalContextSummaryViewModel: ObservableObject {
    /// Per-mount UI state — multiple presentations (spotlight + board tile of the same
    /// terminal) keep independent expansion state.
    @Published var isExpanded: Bool = false

    let session: TerminalContextSummarySession

    private var sessionCancellable: AnyCancellable?

    init(session: TerminalContextSummarySession) {
        self.session = session
        // Re-publish session changes so views observing only the view model still
        // invalidate. Views that observe the session directly don't need this, but
        // re-publishing keeps the public surface simple.
        sessionCancellable = session.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
    }

    deinit {
        sessionCancellable?.cancel()
    }

    // MARK: - Projected State

    var headline: String? { session.headline }
    var phase: String { session.phase }
    var isGenerating: Bool { session.isGenerating }

    /// Newest-first projection of the session timeline for display in the expanded
    /// overlay. F041-R03.
    var timelineEntries: [TimelineEntry] {
        Array(session.timeline.reversed())
    }

    // MARK: - Expand / Collapse

    func expand() { isExpanded = true }

    func collapse() { isExpanded = false }

    func toggle() { isExpanded.toggle() }

    /// Dismisses the expanded state. Headline is preserved for next hover (F041-R09).
    func dismiss() { isExpanded = false }
}
