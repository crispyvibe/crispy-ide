import Combine
import Foundation

/// Per-terminal service that owns persistent context-summary state across UI surface
/// transitions (board → spotlight → rail, etc.). Created once per `TerminalSession`
/// and stored on it; presentation view models project from this service.
///
/// Layering: this is a Service in the sense of `coding-guidelines.md` —
/// long-lived domain state with an explicit `shutdown()`. Views never reach it
/// directly; `TerminalContextSummaryViewModel` mediates.
@MainActor
final class TerminalContextSummarySession: ObservableObject {
    /// Most recent generated headline (or sensitive-information placeholder, or raw
    /// command fallback when LLM is unavailable). F041-R01, F041-R06, F041-R17.
    @Published private(set) var headline: String?

    /// Last known activity phase. Defaults to `"idle"` and persists across surfaces.
    @Published private(set) var phase: String = "idle"

    /// True while an LLM generation task is in flight.
    @Published private(set) var isGenerating: Bool = false

    /// Full timeline of recorded inputs and generated summaries for this terminal,
    /// in chronological order (oldest first). All visible commands AND sensitive
    /// placeholders are persisted here so every surface shows the same content.
    /// F041-R03.
    @Published private(set) var timeline: [TimelineEntry] = []

    /// Soft upper bound on persisted timeline entries to prevent unbounded growth in
    /// extremely long-lived sessions. Generously sized — typical sessions stay well
    /// below this. When exceeded the oldest entries are dropped (sliding window).
    static let maxPersistedEntries = 1_000

    private let insightObserver: TerminalInsightObserver
    private let summaryGenerator: any ContextSummaryGenerating
    private let debounceInterval: TimeInterval

    /// All visible commands seen in this session, ordered oldest → newest. Persisted
    /// for the lifetime of the session and used to build the LLM prompt window.
    private var visibleCommands: [String] = []

    /// Indices into `timeline` for the most recent message-kind entries (used for
    /// pairing the latest summary back to its originating command).
    private var lastVisibleCommand: String?

    private var generationTask: Task<Void, Never>?
    private var debounceWorkItem: DispatchWorkItem?
    private var observerCancellable: AnyCancellable?
    private var hasSubscribed = false

    init(
        insightObserver: TerminalInsightObserver,
        summaryGenerator: any ContextSummaryGenerating,
        debounceInterval: TimeInterval = 0.5
    ) {
        self.insightObserver = insightObserver
        self.summaryGenerator = summaryGenerator
        self.debounceInterval = debounceInterval
    }

    /// Start observing the insight observer. Idempotent — safe to call once at
    /// session-construction time.
    func start() {
        guard !hasSubscribed else { return }
        hasSubscribed = true
        observerCancellable = insightObserver.$lastRecordedInput
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.handleRecordedInput(event)
            }
    }

    /// Cancel all in-flight work and release subscriptions. Called from
    /// `TerminalSession.terminate()`.
    func shutdown() {
        generationTask?.cancel()
        generationTask = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        observerCancellable?.cancel()
        observerCancellable = nil
        hasSubscribed = false
    }

    deinit {
        // `cancel()` is nonisolated on Combine cancellables and DispatchWorkItem.
        generationTask?.cancel()
        debounceWorkItem?.cancel()
        observerCancellable?.cancel()
    }

    // MARK: - Input Handling

    private func handleRecordedInput(_ event: RecordedInput) {
        switch event {
        case .visible(let command):
            visibleCommands.append(command)
            lastVisibleCommand = command
            appendTimelineEntry(
                TimelineEntry(
                    kind: .command,
                    text: command,
                    originalText: command,
                    generatedText: nil
                )
            )
            scheduleRegeneration()

        case .sensitive:
            // Persist a placeholder entry so every surface sees the input occurred,
            // but do NOT include it in `visibleCommands` (LLM prompt feed) and do
            // NOT regenerate the summary on its account. F041-R17.
            let placeholder = AppStrings.Terminal.ContextSummary.sensitiveInformationPlaceholder
            appendTimelineEntry(
                TimelineEntry(
                    kind: .command,
                    text: placeholder,
                    originalText: placeholder,
                    generatedText: nil,
                    isSensitivePlaceholder: true
                )
            )
            // Reflect the most recent activity in the headline without invoking the
            // LLM — the user wanted "sensitive information" surfaced rather than
            // silence.
            headline = placeholder
            phase = "idle"
        }
    }

    // MARK: - Summary Generation

    func scheduleRegeneration() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.regenerateSummary()
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    private func regenerateSummary() {
        // No visible commands to summarise — keep current headline as-is.
        guard !visibleCommands.isEmpty else { return }

        generationTask?.cancel()
        let snapshot = visibleCommands
        let originatingCommand = lastVisibleCommand
        generationTask = Task { [weak self] in
            guard let self else { return }
            self.isGenerating = true
            defer { self.isGenerating = false }

            let input = ContextSummaryInput(recentInput: snapshot)
            let result = await self.summaryGenerator.generate(input: input)
            guard !Task.isCancelled else { return }

            if let result {
                self.headline = result.headline
                self.phase = result.phase
                self.appendSummaryHistory(
                    original: originatingCommand,
                    generated: result.headline
                )
            } else {
                // LLM unavailable / timed out — fall back to the originating command.
                let fallback = originatingCommand
                self.headline = fallback
                self.phase = "idle"
                self.appendSummaryHistory(
                    original: originatingCommand,
                    generated: fallback
                )
            }
        }
    }

    private func appendSummaryHistory(original: String?, generated: String?) {
        guard let generated, !generated.isEmpty else { return }
        appendTimelineEntry(
            TimelineEntry(
                kind: .message,
                text: generated,
                originalText: original,
                generatedText: generated
            )
        )
    }

    private func appendTimelineEntry(_ entry: TimelineEntry) {
        timeline.append(entry)
        if timeline.count > Self.maxPersistedEntries {
            timeline.removeFirst(timeline.count - Self.maxPersistedEntries)
        }
    }
}
