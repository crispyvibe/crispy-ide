import Foundation
import FoundationModels

/// AI-generated summary via guided generation.
@Generable
struct GeneratedContextSummary {
    @Guide(description: "A concise one-line summary of what the developer is currently doing in the terminal")
    var headline: String

    @Guide(description: "The current activity phase. Must be one of: idle, building, testing, debugging, deploying, reviewing, editing, searching")
    var phase: String
}

/// Summary result used by the view model.
struct TerminalContextSummary {
    var headline: String
    var phase: String
}
