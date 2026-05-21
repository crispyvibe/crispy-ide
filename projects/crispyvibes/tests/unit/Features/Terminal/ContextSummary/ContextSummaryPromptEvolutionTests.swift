@testable import CrispyVibes
import XCTest

@MainActor
final class ContextSummaryPromptEvolutionTests: XCTestCase {

    func test_evolvingSummaries() async throws {
        let generator = ContextSummaryGenerator(timeoutSeconds: 10)

        let scenarios: [(name: String, input: ContextSummaryInput)] = [
            ("Starting work", ContextSummaryInput(
                recentInput: ["cd crispyvibes-ide", "git checkout -b feature/document-buffer"],
            )),
            ("Writing code", ContextSummaryInput(
                        recentInput: ["cd crispyvibes-ide", "git checkout -b feature/document-buffer", "open crispyvibes.xcodeproj"]
                    )),
            ("Building", ContextSummaryInput(
                recentInput: ["open crispyvibes.xcodeproj", "xcodebuild build -scheme crispyvibes-local"],
            )),
            ("Testing", ContextSummaryInput(
                recentInput: ["xcodebuild build -scheme crispyvibes-local", "xcodebuild test -only-testing:CrispyVibesUnitTests/DocumentBufferTests"],
            )),
            ("Switching context", ContextSummaryInput(
                recentInput: ["git stash", "cd ../other-project", "ls apps/server/src/persistence"],
            )),
        ]

        for scenario in scenarios {
            let result = await generator.generate(input: scenario.input)
            guard let result else {
                throw XCTSkip("Foundation Models not available")
            }
            print("[\(scenario.name)]")
            print("  HEADLINE: \(result.headline)")
            print("  PHASE:    \(result.phase)")
            print("")

            XCTAssertFalse(result.headline.isEmpty, "\(scenario.name): headline should not be empty")
            XCTAssertLessThan(result.headline.count, 100, "\(scenario.name): headline should be concise")
        }
    }
}
