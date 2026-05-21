@testable import CrispyVibes
import XCTest

@MainActor
final class ContextSummaryGeneratorIntegrationTests: XCTestCase {

    func test_realGenerator_producesHeadlineAndPhase() async throws {
        let generator = ContextSummaryGenerator(timeoutSeconds: 10)

        let input = ContextSummaryInput(
            recentInput: ["cd crispyvibes-ide", "swift build", "swift test"],
        )

        let result = await generator.generate(input: input)

        // On macOS 26+ with Apple Intelligence enabled, we get a real summary.
        // On older OS or CI without Apple Intelligence, result is nil — skip.
        guard let result else {
            throw XCTSkip("Foundation Models not available on this machine")
        }

        XCTAssertFalse(result.headline.isEmpty, "Headline should not be empty")
        XCTAssertFalse(result.phase.isEmpty, "Phase should not be empty")

        let validPhases = ["idle", "building", "testing", "debugging", "deploying", "reviewing", "editing", "searching"]
        XCTAssertTrue(
            validPhases.contains(result.phase),
            "Phase '\(result.phase)' should be one of \(validPhases)"
        )

        // The headline should be a short sentence, not a novel
        XCTAssertLessThan(result.headline.count, 200, "Headline should be concise")
    }
}
