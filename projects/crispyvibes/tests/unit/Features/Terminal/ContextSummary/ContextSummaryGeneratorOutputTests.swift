@testable import CrispyVibes
import XCTest

@MainActor
final class ContextSummaryGeneratorOutputTests: XCTestCase {

    func test_printRealOutput() async throws {
        let generator = ContextSummaryGenerator(timeoutSeconds: 10)

        let input = ContextSummaryInput(
            recentInput: ["cd crispyvibes-ide", "swift build", "swift test"],
        )

        let result = await generator.generate(input: input)

        guard let result else {
            throw XCTSkip("Foundation Models not available")
        }

        // Force print to test output
        print("========================================")
        print("HEADLINE: \(result.headline)")
        print("PHASE:    \(result.phase)")
        print("========================================")

        XCTAssertFalse(result.headline.isEmpty)
    }
}
