import Foundation
import FoundationModels

/// Generates terminal context summaries using a persistent on-device LLM chat session.
/// Each terminal gets its own generator with a long-lived session that accumulates context.
@MainActor
final class ContextSummaryGenerator: ContextSummaryGenerating {
    private let timeoutSeconds: TimeInterval
    private var _session: LanguageModelSession?

    private var session: LanguageModelSession {
        if let existing = _session { return existing }
        let s = LanguageModelSession(instructions: """
            You are observing a developer's terminal session in an IDE. \
            Each message contains what the user recently typed. Based on the \
            evolving activity, write a short status update (under 12 words) \
            describing what they are actively doing right now. \
            Build on your previous understanding — if the activity progresses \
            (e.g., editing → building → testing), reflect the current stage. \
            Do not include file paths, secrets, tokens, or passwords. \
            Use plain language a teammate would understand at a glance.
            """)
        _session = s
        return s
    }

    init(timeoutSeconds: TimeInterval = 2.0) {
        self.timeoutSeconds = timeoutSeconds
    }

    func generate(input: ContextSummaryInput) async -> TerminalContextSummary? {
        guard !input.recentInput.isEmpty else { return nil }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        return await generateWithSession(input: input)
    }

    private func generateWithSession(input: ContextSummaryInput) async -> TerminalContextSummary? {
        let message = "Recent input:\n  " + input.recentInput.suffix(10).joined(separator: "\n  ")

        do {
            return try await withThrowingTaskGroup(of: TerminalContextSummary?.self) { group in
                group.addTask {
                    let response = try await self.session.respond(
                        to: message,
                        generating: GeneratedContextSummary.self
                    )
                    return TerminalContextSummary(
                        headline: response.content.headline,
                        phase: response.content.phase
                    )
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(self.timeoutSeconds))
                    return nil
                }
                if let first = try await group.next() {
                    group.cancelAll()
                    return first
                }
                return nil
            }
        } catch {
            // If session gets into a bad state, reset it
            _session = nil
            return nil
        }
    }
}
