import Combine
import Foundation

/// Drives the terminal context summary overlay state, coordinating between
/// the terminal insight observer, AI summary generator, and agent session.
@MainActor
final class TerminalContextSummaryViewModel: ObservableObject {
    @Published private(set) var headline: String?
    @Published private(set) var phase: String = "idle"
    @Published var isExpanded = false
    @Published private(set) var timelineEntries: [TimelineEntry] = []
    @Published private(set) var isGenerating = false

    private let insightObserver: TerminalInsightObserver
    private let summaryGenerator: any ContextSummaryGenerating
    private var generationTask: Task<Void, Never>?
    private var observerCancellable: AnyCancellable?
    private let debounceInterval: TimeInterval = 0.5
    private var debounceWorkItem: DispatchWorkItem?

    /// Recent commands buffer — fed by observing insightObserver.lastInput.
    private var recentCommands: [String] = []
    private let maxRecentCommands = 10
    private var summaryHistory: [TimelineEntry] = []
    private let maxSummaryHistory = 50

    init(
        insightObserver: TerminalInsightObserver,
        summaryGenerator: any ContextSummaryGenerating
    ) {
        self.insightObserver = insightObserver
        self.summaryGenerator = summaryGenerator

        observerCancellable = insightObserver.$lastInput
            .compactMap { $0 }
            .sink { [weak self] command in
                self?.recordCommand(command)
                self?.scheduleRegeneration()
            }
    }

    deinit {
        generationTask?.cancel()
        debounceWorkItem?.cancel()
    }

    // MARK: - Command Tracking

    private func recordCommand(_ command: String) {
        recentCommands.append(command)
        if recentCommands.count > maxRecentCommands {
            recentCommands.removeFirst()
        }
    }

    // MARK: - Summary Generation

    /// Triggers a debounced summary regeneration.
    func scheduleRegeneration() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.regenerateSummary()
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    private func regenerateSummary() {
        generationTask?.cancel()
        generationTask = Task { [weak self] in
            guard let self else { return }
            self.isGenerating = true
            defer { self.isGenerating = false }

            let input = ContextSummaryInput(
                recentInput: self.recentCommands
            )

            let result = await self.summaryGenerator.generate(input: input)
            guard !Task.isCancelled else { return }

            if let result {
                self.headline = result.headline
                self.phase = result.phase
                self.recordSummaryExchange(
                    original: self.recentCommands.last,
                    generated: result.headline
                )
            } else {
                let fallback = self.insightObserver.lastInput
                self.headline = fallback
                self.phase = "idle"
                self.recordSummaryExchange(
                    original: self.recentCommands.last,
                    generated: fallback
                )
            }
        }
    }

    private func recordSummaryExchange(original: String?, generated: String?) {
        guard let generated, !generated.isEmpty else { return }
        let entry = TimelineEntry(
            kind: .message,
            text: generated,
            originalText: original,
            generatedText: generated
        )
        summaryHistory.append(entry)
        if summaryHistory.count > maxSummaryHistory {
            summaryHistory.removeFirst(summaryHistory.count - maxSummaryHistory)
        }
        if isExpanded {
            assembleTimeline()
        }
    }

    // MARK: - Timeline

    /// Assembles the expanded timeline from available sources.
    func assembleTimeline() {
        if summaryHistory.isEmpty {
            let commandEntries = recentCommands.suffix(10).map {
                TimelineEntry(kind: .command, text: $0)
            }
            timelineEntries = commandEntries.reversed()
            return
        }

        timelineEntries = summaryHistory.reversed()
    }

    // MARK: - Expand / Collapse

    func expand() {
        isExpanded = true
        assembleTimeline()
    }

    func collapse() {
        isExpanded = false
    }

    func toggle() {
        if isExpanded { collapse() } else { expand() }
    }

    /// Dismisses the expanded state. Headline is preserved for next hover.
    func dismiss() {
        isExpanded = false
    }
}
