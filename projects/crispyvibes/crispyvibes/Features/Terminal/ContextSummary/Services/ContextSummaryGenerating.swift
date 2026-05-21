import Foundation

/// Input collected from terminal activity for summary generation.
struct ContextSummaryInput {
    let recentInput: [String]
}

/// Generates AI-powered context summaries from terminal activity.
@MainActor
protocol ContextSummaryGenerating {
    func generate(input: ContextSummaryInput) async -> TerminalContextSummary?
}
