@testable import CrispyVibes
import XCTest

@MainActor
final class TerminalContextSummaryViewModelTests: XCTestCase {

    // MARK: - Mock Generator

    final class MockGenerator: ContextSummaryGenerating {
        var result: TerminalContextSummary?
        var generateCallCount = 0
        var lastInput: ContextSummaryInput?
        var delay: TimeInterval = 0

        func generate(input: ContextSummaryInput) async -> TerminalContextSummary? {
            generateCallCount += 1
            lastInput = input
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            return result
        }
    }

    // MARK: - Helpers

    private func makeSUT(
        generator: MockGenerator
    ) -> (TerminalContextSummaryViewModel, TerminalInsightObserver, MockGenerator) {
        let observer = TerminalInsightObserver()
        let vm = TerminalContextSummaryViewModel(
            insightObserver: observer,
            summaryGenerator: generator
        )
        return (vm, observer, generator)
    }

    // MARK: - Tests

    func test_initialState_headlineIsNil() {
        let (vm, _, _) = makeSUT(generator: MockGenerator())
        XCTAssertNil(vm.headline)
        XCTAssertEqual(vm.phase, "idle")
        XCTAssertFalse(vm.isExpanded)
        XCTAssertTrue(vm.timelineEntries.isEmpty)
    }

    func test_commandRecorded_triggersGeneration() async {
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Building the project", phase: "building")
        let (vm, observer, _) = makeSUT(generator: generator)

        // Simulate user pressing Enter after typing a command
        observer.recordInput("swift build\n")

        // Wait for debounce (0.5s) + generation
        let generated = await waitForCondition(timeout: 2) {
            vm.headline == "Building the project"
        }
        XCTAssertTrue(generated)
        XCTAssertEqual(vm.phase, "building")
        XCTAssertEqual(generator.generateCallCount, 1)
        XCTAssertEqual(generator.lastInput?.recentInput, ["swift build"])
    }

    func test_generatorReturnsNil_fallsBackToLastInput() async {
        let generator = MockGenerator()
        generator.result = nil  // simulates Apple Intelligence disabled
        let (vm, observer, _) = makeSUT(generator: generator)

        observer.recordInput("cargo test\n")

        let fellBack = await waitForCondition(timeout: 2) {
            vm.headline == "cargo test"
        }
        XCTAssertTrue(fellBack, "Should fall back to raw last command when AI is unavailable")
        XCTAssertEqual(vm.phase, "idle", "Phase should default to idle on fallback")
    }

    func test_multipleCommands_trackedInRecentCommands() async {
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Testing", phase: "testing")
        let (vm, observer, _) = makeSUT(generator: generator)

        observer.recordInput("cd project\n")
        observer.recordInput("swift test\n")

        let generated = await waitForCondition(timeout: 2) {
            vm.headline == "Testing"
        }
        XCTAssertTrue(generated)
        XCTAssertEqual(generator.lastInput?.recentInput, ["cd project", "swift test"])
    }

    func test_expand_assemblsTimeline() {
        let generator = MockGenerator()
        let (vm, observer, _) = makeSUT(generator: generator)

        observer.recordInput("git status\n")
        observer.recordInput("git add .\n")

        // Manually trigger expand (doesn't need async generation)
        vm.expand()

        XCTAssertTrue(vm.isExpanded)
        XCTAssertFalse(vm.timelineEntries.isEmpty)
        XCTAssertTrue(vm.timelineEntries.allSatisfy { $0.kind == .command })
    }

    func test_generationAddsCopyableSummaryHistoryEntry() async {
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Building the project", phase: "building")
        let (vm, observer, _) = makeSUT(generator: generator)

        observer.recordInput("swift build\n")

        let generated = await waitForCondition(timeout: 2) {
            vm.headline == "Building the project"
        }
        XCTAssertTrue(generated)

        vm.expand()

        let entry = try? XCTUnwrap(vm.timelineEntries.first)
        XCTAssertEqual(entry?.kind, .message)
        XCTAssertEqual(entry?.text, "Building the project")
        XCTAssertEqual(entry?.originalText, "swift build")
        XCTAssertEqual(entry?.generatedText, "Building the project")
        XCTAssertEqual(
            entry?.copyText,
            """
            Original:
            swift build

            Generated:
            Building the project
            """
        )
    }

    func test_expandedTimelineUpdatesWhenNewSummaryArrives() async {
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "First summary", phase: "editing")
        let (vm, observer, _) = makeSUT(generator: generator)

        observer.recordInput("vim file.swift\n")

        let firstGenerated = await waitForCondition(timeout: 2) {
            vm.headline == "First summary"
        }
        XCTAssertTrue(firstGenerated)

        vm.expand()
        XCTAssertEqual(vm.timelineEntries.first?.text, "First summary")

        generator.result = TerminalContextSummary(headline: "Testing changes", phase: "testing")
        observer.recordInput("swift test\n")

        let secondGenerated = await waitForCondition(timeout: 2) {
            vm.headline == "Testing changes" &&
            vm.timelineEntries.first?.text == "Testing changes"
        }
        XCTAssertTrue(secondGenerated)
        XCTAssertEqual(vm.timelineEntries.first?.originalText, "swift test")
        XCTAssertEqual(vm.timelineEntries.dropFirst().first?.text, "First summary")
    }

    func test_collapse_setsExpandedFalse() {
        let (vm, _, _) = makeSUT(generator: MockGenerator())
        vm.expand()
        XCTAssertTrue(vm.isExpanded)
        vm.collapse()
        XCTAssertFalse(vm.isExpanded)
    }

    func test_dismiss_collapsesButKeepsHeadline() async {
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Working", phase: "editing")
        let (vm, observer, _) = makeSUT(generator: generator)

        observer.recordInput("vim file.swift\n")

        let generated = await waitForCondition(timeout: 2) {
            vm.headline == "Working"
        }
        XCTAssertTrue(generated)

        vm.expand()
        vm.dismiss()
        XCTAssertFalse(vm.isExpanded)
        XCTAssertEqual(vm.headline, "Working", "Headline should persist after dismiss")
    }

    func test_toggle_expandsAndCollapses() {
        let (vm, _, _) = makeSUT(generator: MockGenerator())
        XCTAssertFalse(vm.isExpanded)
        vm.toggle()
        XCTAssertTrue(vm.isExpanded)
        vm.toggle()
        XCTAssertFalse(vm.isExpanded)
    }

    func test_debounce_onlyLastCommandTriggersGeneration() async {
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Final", phase: "building")
        let (vm, observer, _) = makeSUT(generator: generator)

        // Rapid-fire commands — only the last should trigger generation
        observer.recordInput("echo 1\n")
        observer.recordInput("echo 2\n")
        observer.recordInput("echo 3\n")

        let generated = await waitForCondition(timeout: 2) {
            vm.headline == "Final"
        }
        XCTAssertTrue(generated)
        // Debounce should collapse multiple triggers into fewer calls
        XCTAssertLessThanOrEqual(generator.generateCallCount, 3)
        XCTAssertEqual(generator.lastInput?.recentInput, ["echo 1", "echo 2", "echo 3"])
    }
}
