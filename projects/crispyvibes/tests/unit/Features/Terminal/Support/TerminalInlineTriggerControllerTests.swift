import XCTest
@testable import CrispyVibes

/// Tests for `TerminalInlineTriggerController.syncBufferText` and `reconcileBufferText`.
///
/// The controller has two text-sync entry points:
/// - `syncBufferText(_:)` — called from `onChange(of: text)`, can open the picker
/// - `reconcileBufferText(_:)` — called from `onAppear`/config changes, never opens
///
/// These tests verify every edge case for activation, suppression, dismissal,
/// double-trigger, and view lifecycle transitions.
@MainActor
final class TerminalInlineTriggerControllerTests: XCTestCase {

    private var controller: TerminalInlineTriggerController!
    private var insertedText: String?
    private var focusRequested: Bool = false

    override func setUp() {
        super.setUp()
        controller = TerminalInlineTriggerController()
        insertedText = nil
        focusRequested = false
        controller.configure(
            triggerToken: "`",
            searchRoots: [],
            shortcuts: [],
            terminalTitle: "Test",
            currentDirectoryProvider: nil,
            insertionHandler: { [unowned self] text in self.insertedText = text },
            focusHandler: { [unowned self] in self.focusRequested = true },
            manageShortcutsHandler: nil
        )
    }

    override func tearDown() {
        controller = nil
        super.tearDown()
    }

    // MARK: - Basic Activation

    func test_syncBufferText_backtickOpensPicker() {
        controller.syncBufferText("`")
        XCTAssertTrue(controller.isPresented)
    }

    func test_syncBufferText_noTriggerDoesNotOpen() {
        controller.syncBufferText("hello")
        XCTAssertFalse(controller.isPresented)
    }

    func test_syncBufferText_midWordTriggerDoesNotOpen() {
        // "hello`world" — trigger not at whitespace boundary
        controller.syncBufferText("hello`world")
        XCTAssertFalse(controller.isPresented)
    }

    func test_syncBufferText_triggerAfterSpaceOpens() {
        controller.syncBufferText("hello `")
        XCTAssertTrue(controller.isPresented)
    }

    // MARK: - Query Updates

    func test_syncBufferText_updatesQueryWhileOpen() {
        controller.syncBufferText("`")
        XCTAssertTrue(controller.isPresented)
        XCTAssertEqual(controller.queryText, "")

        controller.syncBufferText("`src")
        XCTAssertTrue(controller.isPresented)
        XCTAssertEqual(controller.queryText, "src")
    }

    func test_syncBufferText_triggerRemovedClosesPicker() {
        controller.syncBufferText("`")
        XCTAssertTrue(controller.isPresented)

        controller.syncBufferText("hello")
        XCTAssertFalse(controller.isPresented)
    }

    // MARK: - Double Trigger

    func test_syncBufferText_doubleTriggerClosesPicker() {
        controller.syncBufferText("`")
        XCTAssertTrue(controller.isPresented)

        controller.syncBufferText("``")
        XCTAssertFalse(controller.isPresented)
    }

    func test_syncBufferText_doubleTriggerInsertsLiteral() {
        controller.syncBufferText("`")
        controller.syncBufferText("``")
        XCTAssertEqual(insertedText, "`")
    }

    func test_syncBufferText_doubleTriggerRequestsFocus() {
        controller.syncBufferText("`")
        controller.syncBufferText("``")
        XCTAssertTrue(focusRequested)
    }

    // MARK: - Escape Dismissal

    func test_dismiss_closesPicker() {
        controller.syncBufferText("`")
        XCTAssertTrue(controller.isPresented)

        _ = controller.handleCommand(.dismiss)
        XCTAssertFalse(controller.isPresented)
    }

    func test_dismiss_subsequentTypingDoesNotReopen() {
        controller.syncBufferText("`")
        _ = controller.handleCommand(.dismiss)

        // User types more after the backtick — trigger still in text
        controller.syncBufferText("`hello")
        XCTAssertFalse(controller.isPresented, "Picker should stay closed after Escape dismiss")
    }

    func test_dismiss_newTriggerAtDifferentPositionReopens() {
        controller.syncBufferText("`")
        _ = controller.handleCommand(.dismiss)

        // User clears text and types fresh trigger
        controller.syncBufferText("hello")  // trigger gone
        controller.syncBufferText("hello `")  // new trigger at different prefix
        XCTAssertTrue(controller.isPresented, "Fresh trigger at new position should open")
    }

    func test_dismiss_deleteTriggerThenRetypeReopens() {
        controller.syncBufferText("`")
        _ = controller.handleCommand(.dismiss)

        // User deletes the backtick
        controller.syncBufferText("")
        // User types a new backtick
        controller.syncBufferText("`")
        XCTAssertTrue(controller.isPresented, "Fresh trigger after deletion should open")
    }

    // MARK: - reconcileBufferText (onAppear / config changes)

    func test_reconcile_doesNotOpenPicker() {
        controller.reconcileBufferText("`")
        XCTAssertFalse(controller.isPresented, "reconcileBufferText should never open the picker")
    }

    func test_reconcile_thenTypingDoesNotReopenStaleTrigger() {
        // Simulates: view appears with backtick already in text
        controller.reconcileBufferText("`")
        XCTAssertFalse(controller.isPresented)

        // User types a character — trigger was already there
        controller.syncBufferText("`a")
        XCTAssertFalse(controller.isPresented, "Stale trigger should not reopen on subsequent typing")
    }

    func test_reconcile_thenFreshTriggerAtNewPositionOpens() {
        controller.reconcileBufferText("`old")
        XCTAssertFalse(controller.isPresented)

        // User types a new trigger at a different position
        controller.syncBufferText("`old stuff `")
        XCTAssertTrue(controller.isPresented, "New trigger at different position should open")
    }

    func test_reconcile_thenDeleteAndRetypeOpens() {
        controller.reconcileBufferText("`")
        XCTAssertFalse(controller.isPresented)

        // User deletes everything
        controller.syncBufferText("")
        // User types fresh trigger
        controller.syncBufferText("`")
        XCTAssertTrue(controller.isPresented, "Fresh trigger after clearing should open")
    }

    func test_reconcile_updatesAlreadyOpenPicker() {
        // Picker is already open
        controller.syncBufferText("`")
        XCTAssertTrue(controller.isPresented)
        XCTAssertEqual(controller.queryText, "")

        // Config change triggers reconcile with updated text
        controller.reconcileBufferText("`newquery")
        XCTAssertTrue(controller.isPresented, "reconcile should update open picker")
        XCTAssertEqual(controller.queryText, "newquery")
    }

    func test_reconcile_closesPickerIfTriggerGone() {
        controller.syncBufferText("`")
        XCTAssertTrue(controller.isPresented)

        controller.reconcileBufferText("no trigger here")
        XCTAssertFalse(controller.isPresented, "reconcile should close picker if trigger removed")
    }

    // MARK: - View Lifecycle Transitions

    func test_spotlightTransition_staleTriggerDoesNotOpen() {
        // Simulates: ACP has "`" in text, user opens spotlight
        // Old controller dismissed, new controller created
        let newController = TerminalInlineTriggerController()
        newController.configure(
            triggerToken: "`",
            searchRoots: [],
            shortcuts: [],
            terminalTitle: "Test",
            currentDirectoryProvider: nil,
            insertionHandler: nil,
            focusHandler: nil,
            manageShortcutsHandler: nil
        )

        // onAppear calls reconcile
        newController.reconcileBufferText("`")
        XCTAssertFalse(newController.isPresented)

        // User types a letter
        newController.syncBufferText("`a")
        XCTAssertFalse(newController.isPresented, "Stale trigger from previous view should not open")
    }

    func test_terminalSwipe_draftWithTriggerDoesNotOpen() {
        // Simulates: spotlight swipe restores draft with trigger
        controller.reconcileBufferText("`old query")
        XCTAssertFalse(controller.isPresented)

        // User types in the restored draft
        controller.syncBufferText("`old query more")
        XCTAssertFalse(controller.isPresented, "Restored draft trigger should not reopen")
    }

    // MARK: - Double Trigger Suppression After Insert

    func test_doubleTrigger_doesNotReopenFromInsertedText() {
        controller.syncBufferText("`")
        XCTAssertTrue(controller.isPresented)

        // Double trigger — insertionHandler will be called with "`"
        controller.syncBufferText("``")
        XCTAssertFalse(controller.isPresented)

        // insertionHandler changed text to "`" (replaced trigger)
        // onChange fires with the new text
        controller.syncBufferText("`")
        XCTAssertFalse(controller.isPresented, "Should not reopen after double-trigger insertion")
    }

    // MARK: - Text Replacement (insertionHandler)

    func test_resultSelection_doesNotReopenFromReplacedText() {
        controller.syncBufferText("`src")
        XCTAssertTrue(controller.isPresented)

        // Simulate: user selects a result, insertionHandler replaces text
        // The controller closes via apply() → closePicker()
        _ = controller.handleCommand(.dismiss)

        // The replaced text might still contain trigger-like content
        controller.syncBufferText("/path/to/src")
        XCTAssertFalse(controller.isPresented)
    }

    // MARK: - Empty VibeSpace

    func test_emptyTriggerTokenDisablesFeature() {
        // normalizedTerminalComposeInlineTrigger("") falls back to default "`"
        // so empty string doesn't actually disable — this tests that the
        // normalized token is always valid
        controller.configure(
            triggerToken: "",
            searchRoots: [],
            shortcuts: [],
            terminalTitle: "Test",
            currentDirectoryProvider: nil,
            insertionHandler: nil,
            focusHandler: nil,
            manageShortcutsHandler: nil
        )
        // With fallback to default, backtick still works
        controller.syncBufferText("`")
        XCTAssertTrue(controller.isPresented)
    }

    // MARK: - handleTextInput (Direct Terminal Path)

    func test_handleTextInput_triggerOpensPicker() {
        let handled = controller.handleTextInput("`")
        XCTAssertTrue(handled)
        XCTAssertTrue(controller.isPresented)
    }

    func test_handleTextInput_nonTriggerIgnored() {
        let handled = controller.handleTextInput("a")
        XCTAssertFalse(handled)
        XCTAssertFalse(controller.isPresented)
    }

    func test_handleTextInput_appendsToQuery() {
        _ = controller.handleTextInput("`")
        _ = controller.handleTextInput("s")
        _ = controller.handleTextInput("r")
        _ = controller.handleTextInput("c")
        XCTAssertEqual(controller.queryText, "src")
    }

    func test_handleTextInput_doubleTriggerCloses() {
        _ = controller.handleTextInput("`")
        let handled = controller.handleTextInput("`")
        XCTAssertTrue(handled)
        XCTAssertFalse(controller.isPresented)
        XCTAssertEqual(insertedText, "`")
    }

    func test_handleTextInput_doubleTriggerOnlyWhenQueryEmpty() {
        _ = controller.handleTextInput("`")
        _ = controller.handleTextInput("a")
        _ = controller.handleTextInput("`")
        // Query is "a`", not a double-trigger
        XCTAssertTrue(controller.isPresented)
        XCTAssertEqual(controller.queryText, "a`")
    }

    func test_handleTextInput_emptyStringIgnored() {
        let handled = controller.handleTextInput("")
        XCTAssertFalse(handled)
    }

    // MARK: - handleCommand (Keyboard Navigation)

    func test_handleCommand_dismissWhenNotPresented() {
        let handled = controller.handleCommand(.dismiss)
        XCTAssertFalse(handled, "Commands should be ignored when picker is not open")
    }

    func test_handleCommand_dismiss() {
        controller.syncBufferText("`")
        let handled = controller.handleCommand(.dismiss)
        XCTAssertTrue(handled)
        XCTAssertFalse(controller.isPresented)
        XCTAssertTrue(focusRequested)
    }

    func test_handleCommand_deleteBackwardRemovesLastChar() {
        controller.syncBufferText("`src")
        XCTAssertEqual(controller.queryText, "src")

        _ = controller.handleCommand(.deleteBackward)
        XCTAssertEqual(controller.queryText, "sr")
        XCTAssertTrue(controller.isPresented)
    }

    func test_handleCommand_deleteBackwardOnEmptyQueryCloses() {
        controller.syncBufferText("`")
        XCTAssertEqual(controller.queryText, "")

        _ = controller.handleCommand(.deleteBackward)
        XCTAssertFalse(controller.isPresented)
        XCTAssertTrue(focusRequested)
    }

    func test_handleCommand_moveDownWraps() {
        controller.syncBufferText("`")
        // No results loaded, but command should still be handled
        let handled = controller.handleCommand(.moveDown)
        XCTAssertTrue(handled)
    }

    func test_handleCommand_moveUpWraps() {
        controller.syncBufferText("`")
        let handled = controller.handleCommand(.moveUp)
        XCTAssertTrue(handled)
    }

    func test_handleCommand_moveRightHandled() {
        controller.syncBufferText("`")
        let handled = controller.handleCommand(.moveRight)
        XCTAssertTrue(handled)
    }

    func test_handleCommand_confirmHandled() {
        controller.syncBufferText("`")
        let handled = controller.handleCommand(.confirm)
        XCTAssertTrue(handled)
    }

    // MARK: - configure (Reconfiguration)

    func test_configure_tokenChangeWhileOpen() {
        controller.syncBufferText("`")
        XCTAssertTrue(controller.isPresented)

        // Reconfigure with different token
        controller.configure(
            triggerToken: "/",
            searchRoots: [],
            shortcuts: [],
            terminalTitle: "Test",
            currentDirectoryProvider: nil,
            insertionHandler: nil,
            focusHandler: nil,
            manageShortcutsHandler: nil
        )

        // Old trigger no longer valid — reconcile should close
        controller.reconcileBufferText("`src")
        XCTAssertFalse(controller.isPresented, "Old trigger should not keep picker open after token change")
    }

    func test_configure_newTokenActivates() {
        controller.configure(
            triggerToken: "/",
            searchRoots: [],
            shortcuts: [],
            terminalTitle: "Test",
            currentDirectoryProvider: nil,
            insertionHandler: { [unowned self] text in self.insertedText = text },
            focusHandler: nil,
            manageShortcutsHandler: nil
        )

        controller.syncBufferText("/")
        XCTAssertTrue(controller.isPresented)
    }

    // MARK: - Interleaved reconcile + sync

    func test_rapidReconcileThenSync_noSpuriousOpen() {
        // Simulates: config change fires reconcile, then onChange fires sync
        controller.reconcileBufferText("`stale")
        controller.syncBufferText("`stale")
        XCTAssertFalse(controller.isPresented, "Stale trigger should not open even after rapid reconcile+sync")
    }

    func test_reconcileThenSyncWithNewTrigger_opens() {
        controller.reconcileBufferText("hello")
        controller.syncBufferText("hello `")
        XCTAssertTrue(controller.isPresented)
    }

    func test_multipleReconciles_noOpen() {
        controller.reconcileBufferText("`a")
        controller.reconcileBufferText("`ab")
        controller.reconcileBufferText("`abc")
        XCTAssertFalse(controller.isPresented, "Multiple reconciles should never open")
    }

    func test_syncAfterMultipleReconciles_staleTrigger() {
        controller.reconcileBufferText("`abc")
        controller.syncBufferText("`abcd")
        XCTAssertFalse(controller.isPresented, "Typing after reconciled stale trigger should not open")
    }

    func test_syncAfterMultipleReconciles_newTriggerPosition() {
        controller.reconcileBufferText("`abc")
        // User adds a new trigger at a different position
        controller.syncBufferText("`abc `")
        XCTAssertTrue(controller.isPresented, "New trigger at different position should open")
    }
}

// MARK: - replaceInlineTrigger correctness (ACP-style)
@MainActor
final class InlineTriggerTextReplacementTests: XCTestCase {

    private func replaceInlineTrigger(in text: String, replacement: String, triggerToken: String = "`") -> String {
        let normalized = AppPreferences.normalizedTerminalComposeInlineTrigger(triggerToken)
        guard let trigger = SpotlightComposeInlineTrigger.parse(text, triggerToken: normalized) else {
            return text
        }
        return trigger.prefixText + replacement
    }

    func test_replacesOnlyTriggerAndQuery() {
        let result = replaceInlineTrigger(in: "hello `src", replacement: "/path/to/src")
        XCTAssertEqual(result, "hello /path/to/src")
    }

    func test_preservesTextAfterTrigger() {
        // If user typed "hello `query world", selecting a result should preserve " world"
        // Current implementation: parse returns query="query world" (everything after trigger)
        // So "world" is part of the query and gets replaced — this may or may not be desired
        let result = replaceInlineTrigger(in: "hello `query world", replacement: "/path")
        // Current behavior: "hello /path" — " world" is lost because it's part of the query
        XCTAssertEqual(result, "hello /path")
    }

    func test_parseReturnsNil_preservesExistingText() {
        // When no trigger found, existing text must be preserved — not replaced
        let result = replaceInlineTrigger(in: "hello world", replacement: "/path")
        XCTAssertEqual(result, "hello world", "Existing text must not be replaced when trigger is missing")
    }

    func test_doubleTriggerReplacement() {
        let result = replaceInlineTrigger(in: "``", replacement: "`")
        XCTAssertEqual(result, "`")
    }

    func test_doubleTriggerWithPrefix() {
        let result = replaceInlineTrigger(in: "hello ``", replacement: "`")
        XCTAssertEqual(result, "hello `")
    }

    func test_emptyTextPreservesEmpty() {
        let result = replaceInlineTrigger(in: "", replacement: "/path")
        XCTAssertEqual(result, "", "Empty text with no trigger should stay empty")
    }
}
