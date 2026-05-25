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

    /// Compressed classification policy for fast deterministic tests:
    /// 5 ms retry interval, 4 retries, 25 ms budget.
    private static let testPolicy = InsightClassificationPolicy(
        retryInterval: 0.005,
        maxRetries: 4,
        timeBudget: 0.025
    )

    private func makeSUT(
        generator: MockGenerator,
        screenReader: (() -> String)? = nil
    ) -> (
        viewModel: TerminalContextSummaryViewModel,
        session: TerminalContextSummarySession,
        observer: TerminalInsightObserver,
        generator: MockGenerator
    ) {
        let observer = TerminalInsightObserver()
        observer.classificationPolicy = Self.testPolicy
        if let screenReader {
            observer.readVisibleScreen = screenReader
        }
        let session = TerminalContextSummarySession(
            insightObserver: observer,
            summaryGenerator: generator
        )
        session.start()
        let vm = TerminalContextSummaryViewModel(session: session)
        return (vm, session, observer, generator)
    }

    /// Wait for the observer to publish a classification (visible or sensitive)
    /// for the current line. Used after `recordTypedKeystroke`.
    private func waitForClassification(
        observer: TerminalInsightObserver,
        timeout: TimeInterval = 1.0
    ) async -> Bool {
        await waitForCondition(timeout: timeout) {
            observer.lastRecordedInput != nil
        }
    }

    // MARK: - View Model Initial State

    func test_initialState_headlineIsNil() {
        let sut = makeSUT(generator: MockGenerator())
        XCTAssertNil(sut.viewModel.headline)
        XCTAssertEqual(sut.viewModel.phase, "idle")
        XCTAssertFalse(sut.viewModel.isExpanded)
        XCTAssertTrue(sut.viewModel.timelineEntries.isEmpty)
    }

    // MARK: - Keystroke Path: Generation Triggering

    func test_typedKeystroke_visibleImmediately_triggersGeneration() async {
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Building the project", phase: "building")
        let sut = makeSUT(
            generator: generator,
            screenReader: { "user@host:~$ swift build" }
        )

        sut.observer.recordTypedKeystroke("swift build\n")

        let generated = await waitForCondition(timeout: 2) {
            sut.viewModel.headline == "Building the project"
        }
        XCTAssertTrue(generated)
        XCTAssertEqual(sut.viewModel.phase, "building")
        XCTAssertEqual(generator.generateCallCount, 1)
        XCTAssertEqual(generator.lastInput?.recentInput, ["swift build"])
    }

    func test_typedKeystroke_visibleAfterRetry_classifiedVisible() async {
        // Screen reader becomes "echoed" only after a delay — simulates render lag.
        var renderedText: String = "user@host:~$ "
        let observer = TerminalInsightObserver()
        observer.classificationPolicy = Self.testPolicy
        observer.readVisibleScreen = { renderedText }

        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Listing", phase: "idle")
        let session = TerminalContextSummarySession(
            insightObserver: observer,
            summaryGenerator: generator
        )
        session.start()

        observer.recordTypedKeystroke("ls -la\n")

        // After ~12 ms the echo "lands" — well within the 25 ms budget.
        try? await Task.sleep(for: .milliseconds(12))
        renderedText = "user@host:~$ ls -la\nfile1\nfile2"

        let resolved = await waitForCondition(timeout: 1) {
            if case .visible(let text) = observer.lastRecordedInput { return text == "ls -la" }
            return false
        }
        XCTAssertTrue(resolved, "Input that becomes visible during retries must be classified visible")
    }

    func test_typedKeystroke_neverVisible_classifiedSensitive() async {
        // Screen reader never contains the typed text — simulates an echo-disabled
        // password prompt.
        let observer = TerminalInsightObserver()
        observer.classificationPolicy = Self.testPolicy
        observer.readVisibleScreen = { "Password: " }

        observer.recordTypedKeystroke("hunter2-secret\n")

        let resolved = await waitForCondition(timeout: 1) {
            observer.lastRecordedInput == .sensitive
        }
        XCTAssertTrue(resolved, "Input that the surface never echoes must be classified sensitive")
    }

    func test_typedKeystroke_wrappedOnSurface_classifiedVisible() async {
        // A long command echoed across a wrap boundary appears in the surface
        // buffer with a newline at the wrap column. The visibility check
        // must tolerate that by normalizing whitespace before comparing.
        let observer = TerminalInsightObserver()
        observer.classificationPolicy = Self.testPolicy
        observer.readVisibleScreen = {
            // Surface representation: typed string split across two rows.
            "$ echo a really long string that wraps at the\nterminal column boundary"
        }

        observer.recordTypedKeystroke(
            "echo a really long string that wraps at the terminal column boundary\n"
        )

        let resolved = await waitForCondition(timeout: 1) {
            if case .visible(let text) = observer.lastRecordedInput {
                return text == "echo a really long string that wraps at the terminal column boundary"
            }
            return false
        }
        XCTAssertTrue(
            resolved,
            "Soft-wrapped echo (newline inserted at wrap column) must classify as visible"
        )
    }

    func test_typedKeystroke_backspaceCorrection_classifiedVisible() async {
        // The user typed "shooes" (extra 'o'), backspaced once to correct to
        // "shoes", then pressed Enter. The terminal echoed the corrected line.
        // The keystroke observer must honour backspace so the reconstructed
        // buffer matches the surface — otherwise the contains-check
        // misclassifies a benign correction as sensitive.
        let observer = TerminalInsightObserver()
        observer.classificationPolicy = Self.testPolicy
        observer.readVisibleScreen = { "$ shoes" }

        observer.recordTypedKeystroke("shoo")
        observer.recordTypedKeystroke("\u{7f}")  // backspace removes one 'o'
        observer.recordTypedKeystroke("es\n")

        let resolved = await waitForCondition(timeout: 1) {
            if case .visible(let text) = observer.lastRecordedInput {
                return text == "shoes"
            }
            return false
        }
        XCTAssertTrue(
            resolved,
            "Backspace must correct the buffer so the contains-check matches the screen"
        )
    }

    func test_typedKeystroke_newLineCancelsPreviousClassification() async {
        // First line: never echoed → would eventually resolve as sensitive.
        // Before the budget elapses, a second line is typed and IS echoed →
        // the previous classification is cancelled, only the new one publishes.
        var rendered: String = "Password: "
        let observer = TerminalInsightObserver()
        observer.classificationPolicy = Self.testPolicy
        observer.readVisibleScreen = { rendered }

        observer.recordTypedKeystroke("first-secret\n")
        // Immediately type a second line BEFORE the first has resolved.
        rendered = "user@host:~$ ls"
        observer.recordTypedKeystroke("ls\n")

        let resolved = await waitForCondition(timeout: 1) {
            if case .visible(let text) = observer.lastRecordedInput { return text == "ls" }
            return false
        }
        XCTAssertTrue(resolved, "New keystroke line supersedes previous in-flight classification")
    }

    func test_typedKeystroke_shutdownCancelsPendingClassification() async {
        let observer = TerminalInsightObserver()
        observer.classificationPolicy = Self.testPolicy
        observer.readVisibleScreen = { "Password: " }

        observer.recordTypedKeystroke("secret-text\n")
        observer.shutdown()

        // Wait past the budget — sensitive must NOT be published.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(observer.lastRecordedInput)
    }

    // MARK: - Compose-UI Path

    func test_composeUISubmission_classifiedVisibleImmediately() {
        let observer = TerminalInsightObserver()
        // Compose-UI path must NOT consult the screen reader.
        observer.readVisibleScreen = { "Password: " }

        observer.recordSubmittedFromComposeUI("rm -rf node_modules")

        if case .visible(let text) = observer.lastRecordedInput {
            XCTAssertEqual(text, "rm -rf node_modules")
        } else {
            XCTFail("Compose-UI submissions must be classified .visible by trust boundary")
        }
    }

    func test_composeUISubmission_supersedesInFlightKeystrokeClassification() async {
        let observer = TerminalInsightObserver()
        observer.classificationPolicy = Self.testPolicy
        observer.readVisibleScreen = { "Password: " }

        // Start a keystroke classification that won't resolve quickly.
        observer.recordTypedKeystroke("typed-text\n")

        // Compose-UI submission arrives — it should immediately publish .visible
        // and cancel any in-flight keystroke classification.
        observer.recordSubmittedFromComposeUI("compose-text")

        if case .visible(let text) = observer.lastRecordedInput {
            XCTAssertEqual(text, "compose-text")
        } else {
            XCTFail("Compose-UI submission must override any pending keystroke classification")
        }

        // Wait past the budget — the keystroke classification must NOT
        // overwrite the compose-UI publish with .sensitive.
        try? await Task.sleep(for: .milliseconds(50))
        if case .visible(let text) = observer.lastRecordedInput {
            XCTAssertEqual(text, "compose-text", "Pending keystroke work must not resurface")
        } else {
            XCTFail("Compose-UI publish must remain after budget elapses")
        }
    }

    func test_composeUISubmission_emptyOrTooShort_isIgnored() {
        let observer = TerminalInsightObserver()
        observer.recordSubmittedFromComposeUI("")
        XCTAssertNil(observer.lastRecordedInput)

        observer.recordSubmittedFromComposeUI("a")  // too short
        XCTAssertNil(observer.lastRecordedInput)

        observer.recordSubmittedFromComposeUI("ok")
        if case .visible(let text) = observer.lastRecordedInput {
            XCTAssertEqual(text, "ok")
        } else {
            XCTFail("Two-character submissions must be classified visible")
        }
    }

    // MARK: - Generation Behaviour

    func test_generatorReturnsNil_fallsBackToLastInput() async {
        let generator = MockGenerator()
        generator.result = nil
        let sut = makeSUT(
            generator: generator,
            screenReader: { "user@host:~$ cargo test" }
        )

        sut.observer.recordTypedKeystroke("cargo test\n")

        let fellBack = await waitForCondition(timeout: 2) {
            sut.viewModel.headline == "cargo test"
        }
        XCTAssertTrue(fellBack)
        XCTAssertEqual(sut.viewModel.phase, "idle")
    }

    func test_multipleVisibleCommands_persistedAndForwardedToLLM() async {
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Testing", phase: "testing")
        var rendered = "user@host:~$ "
        let sut = makeSUT(
            generator: generator,
            screenReader: { rendered }
        )

        rendered = "user@host:~$ cd project"
        sut.observer.recordTypedKeystroke("cd project\n")
        let cdResolved = await waitForClassification(observer: sut.observer)
        XCTAssertTrue(cdResolved)

        rendered = "user@host:~$ swift test"
        sut.observer.recordTypedKeystroke("swift test\n")

        let generated = await waitForCondition(timeout: 2) {
            sut.viewModel.headline == "Testing"
        }
        XCTAssertTrue(generated)
        XCTAssertEqual(generator.lastInput?.recentInput, ["cd project", "swift test"])
    }

    func test_allUserMessagesPersistedAcrossWindow() async {
        let generator = MockGenerator()
        generator.result = nil
        var rendered = ""
        let sut = makeSUT(
            generator: generator,
            screenReader: { rendered }
        )

        for i in 1...30 {
            rendered = "user@host:~$ cmd\(i)"
            sut.observer.recordTypedKeystroke("cmd\(i)\n")
            // Allow each classification to resolve before the next.
            _ = await waitForClassification(observer: sut.observer, timeout: 0.2)
        }

        _ = await waitForCondition(timeout: 2) {
            sut.viewModel.timelineEntries.count >= 30
        }

        let commandEntries = sut.viewModel.timelineEntries.filter { $0.kind == .command }
        XCTAssertEqual(commandEntries.count, 30)
        XCTAssertEqual(commandEntries.first?.text, "cmd30")
        XCTAssertEqual(commandEntries.last?.text, "cmd1")
    }

    // MARK: - Timeline

    func test_expand_assemblesTimelineFromAllRecordedCommands() async {
        let generator = MockGenerator()
        var rendered = ""
        let sut = makeSUT(
            generator: generator,
            screenReader: { rendered }
        )

        rendered = "user@host:~$ git status"
        sut.observer.recordTypedKeystroke("git status\n")
        _ = await waitForClassification(observer: sut.observer)

        rendered = "user@host:~$ git add ."
        sut.observer.recordTypedKeystroke("git add .\n")
        _ = await waitForClassification(observer: sut.observer)

        sut.viewModel.expand()

        XCTAssertTrue(sut.viewModel.isExpanded)
        XCTAssertFalse(sut.viewModel.timelineEntries.isEmpty)
        XCTAssertTrue(
            sut.viewModel.timelineEntries.allSatisfy { $0.kind == .command || $0.kind == .message }
        )
    }

    func test_generationAddsCopyableSummaryEntry() async {
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Building the project", phase: "building")
        let sut = makeSUT(
            generator: generator,
            screenReader: { "user@host:~$ swift build" }
        )

        sut.observer.recordTypedKeystroke("swift build\n")

        let generated = await waitForCondition(timeout: 2) {
            sut.viewModel.headline == "Building the project"
        }
        XCTAssertTrue(generated)

        sut.viewModel.expand()

        let entry = sut.viewModel.timelineEntries.first { $0.kind == .message }
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

    // MARK: - Expand / Collapse / Dismiss

    func test_collapse_setsExpandedFalse() {
        let sut = makeSUT(generator: MockGenerator())
        sut.viewModel.expand()
        XCTAssertTrue(sut.viewModel.isExpanded)
        sut.viewModel.collapse()
        XCTAssertFalse(sut.viewModel.isExpanded)
    }

    func test_dismiss_collapsesButKeepsHeadline() async {
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Working", phase: "editing")
        let sut = makeSUT(
            generator: generator,
            screenReader: { "user@host:~$ vim file.swift" }
        )

        sut.observer.recordTypedKeystroke("vim file.swift\n")

        let generated = await waitForCondition(timeout: 2) {
            sut.viewModel.headline == "Working"
        }
        XCTAssertTrue(generated)

        sut.viewModel.expand()
        sut.viewModel.dismiss()
        XCTAssertFalse(sut.viewModel.isExpanded)
        XCTAssertEqual(sut.viewModel.headline, "Working")
    }

    func test_toggle_expandsAndCollapses() {
        let sut = makeSUT(generator: MockGenerator())
        XCTAssertFalse(sut.viewModel.isExpanded)
        sut.viewModel.toggle()
        XCTAssertTrue(sut.viewModel.isExpanded)
        sut.viewModel.toggle()
        XCTAssertFalse(sut.viewModel.isExpanded)
    }

    // MARK: - Cross-Surface Persistence

    func test_secondViewModelOnSameSessionSeesExistingHeadline() async {
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Already running tests", phase: "testing")
        let sut = makeSUT(
            generator: generator,
            screenReader: { "user@host:~$ swift test" }
        )

        sut.observer.recordTypedKeystroke("swift test\n")
        let generated = await waitForCondition(timeout: 2) {
            sut.viewModel.headline == "Already running tests"
        }
        XCTAssertTrue(generated)

        let secondViewModel = TerminalContextSummaryViewModel(session: sut.session)
        XCTAssertEqual(secondViewModel.headline, "Already running tests")
        XCTAssertEqual(secondViewModel.phase, "testing")
        XCTAssertFalse(secondViewModel.timelineEntries.isEmpty)
    }

    // MARK: - Sensitive Input Handling (F041-R17)

    func test_sensitiveInput_addsPlaceholderTimelineEntry() async {
        let generator = MockGenerator()
        let sut = makeSUT(
            generator: generator,
            screenReader: { "Password: " }  // input never appears
        )

        sut.observer.recordTypedKeystroke("hunter2-secret\n")

        let resolved = await waitForCondition(timeout: 1) {
            sut.observer.lastRecordedInput == .sensitive
        }
        XCTAssertTrue(resolved)

        let placeholder = AppStrings.Terminal.ContextSummary.sensitiveInformationPlaceholder
        XCTAssertEqual(sut.viewModel.headline, placeholder)
        XCTAssertEqual(sut.viewModel.phase, "idle")

        let entry = sut.viewModel.timelineEntries.first
        XCTAssertEqual(entry?.text, placeholder)
        XCTAssertEqual(entry?.isSensitivePlaceholder, true)
    }

    func test_sensitiveInput_doesNotInvokeLLM() async {
        let generator = MockGenerator()
        let sut = makeSUT(
            generator: generator,
            screenReader: { "Password: " }
        )

        sut.observer.recordTypedKeystroke("hunter2-secret\n")
        _ = await waitForClassification(observer: sut.observer)

        // Allow more than the LLM debounce window — there must be no LLM call.
        try? await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(generator.generateCallCount, 0)
        XCTAssertNil(generator.lastInput)
    }

    func test_sensitiveInput_isExcludedFromSubsequentLLMPrompt() async {
        var rendered = ""
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Editing", phase: "editing")
        let sut = makeSUT(
            generator: generator,
            screenReader: { rendered }
        )

        // Visible command #1.
        rendered = "user@host:~$ vim notes.md"
        sut.observer.recordTypedKeystroke("vim notes.md\n")
        let editingResolved = await waitForCondition(timeout: 2) {
            sut.viewModel.headline == "Editing"
        }
        XCTAssertTrue(editingResolved)

        // Sensitive input — never appears on screen.
        rendered = "Password: "
        sut.observer.recordTypedKeystroke("hunter2-secret\n")
        _ = await waitForCondition(timeout: 1) {
            sut.observer.lastRecordedInput == .sensitive
        }

        // Visible command #2 — triggers regeneration whose prompt window must
        // exclude the sensitive content.
        rendered = "user@host:~$ git push"
        sut.observer.recordTypedKeystroke("git push\n")

        let pushGenerated = await waitForCondition(timeout: 2) {
            generator.lastInput?.recentInput.contains("git push") == true
        }
        XCTAssertTrue(pushGenerated)

        XCTAssertEqual(generator.lastInput?.recentInput, ["vim notes.md", "git push"])
        XCTAssertFalse(
            (generator.lastInput?.recentInput ?? []).contains(where: { $0.contains("hunter2") }),
            "Sensitive input must never reach the LLM prompt"
        )
    }

    // MARK: - Compose-UI path: end-to-end through the summary session

    func test_composeUISubmission_appearsInTimelineAndLLMPrompt() async {
        let generator = MockGenerator()
        generator.result = TerminalContextSummary(headline: "Pasted", phase: "idle")
        let sut = makeSUT(
            generator: generator,
            screenReader: { "Password: " }  // would mark sensitive on keystroke path
        )

        sut.observer.recordSubmittedFromComposeUI("echo from-compose")

        let generated = await waitForCondition(timeout: 2) {
            sut.viewModel.headline == "Pasted"
        }
        XCTAssertTrue(generated, "Compose-UI submissions bypass screen check and reach the LLM")
        XCTAssertEqual(generator.lastInput?.recentInput, ["echo from-compose"])
    }
}
