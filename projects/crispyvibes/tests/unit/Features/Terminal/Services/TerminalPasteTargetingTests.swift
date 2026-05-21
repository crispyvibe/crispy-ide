import XCTest
@testable import CrispyVibes

@MainActor
final class TerminalPasteTargetingTests: XCTestCase {

    private var coordinator: TerminalFocusCoordinator!
    private var engineA: MockClipboardEngine!
    private var engineB: MockClipboardEngine!
    private let sessionA = UUID()
    private let sessionB = UUID()

    override func setUp() {
        super.setUp()
        coordinator = TerminalFocusCoordinator()
        coordinator.unfocusCurrent()

        engineA = MockClipboardEngine()
        engineA.sessionID = sessionA

        engineB = MockClipboardEngine()
        engineB.sessionID = sessionB
    }

    override func tearDown() {
        coordinator.unfocusCurrent()
        super.tearDown()
    }

    // MARK: - Focus coordinator state

    func testNoSessionFocusedByDefault() {
        XCTAssertNil(coordinator.currentSessionID, "No session should be focused after setup")
    }

    func testFocusSetsCurrentSession() {
        coordinator.focus(engine: engineA, sessionID: sessionA)
        XCTAssertEqual(coordinator.currentSessionID, sessionA)
    }

    func testFocusReplacesCurrentSession() {
        coordinator.focus(engine: engineA, sessionID: sessionA)
        coordinator.focus(engine: engineB, sessionID: sessionB)
        XCTAssertEqual(coordinator.currentSessionID, sessionB, "Focus should move to session B")
        XCTAssertFalse(engineA.isSurfaceFocused, "Session A surface should be unfocused")
        XCTAssertTrue(engineB.isSurfaceFocused, "Session B surface should be focused")
    }

    func testRelinquishClearsCurrentSession() {
        coordinator.focus(engine: engineA, sessionID: sessionA)
        coordinator.relinquish(sessionID: sessionA)
        XCTAssertNil(coordinator.currentSessionID, "Relinquish should clear focused session")
    }

    func testRelinquishIgnoresNonFocusedSession() {
        coordinator.focus(engine: engineA, sessionID: sessionA)
        coordinator.relinquish(sessionID: sessionB)
        XCTAssertEqual(coordinator.currentSessionID, sessionA, "Relinquishing non-focused session should be a no-op")
    }

    // MARK: - Paste targeting: only focused session receives paste

    func testPasteGoesToFocusedSession() {
        coordinator.focus(engine: engineA, sessionID: sessionA)

        XCTAssertTrue(coordinator.currentSessionID == sessionA, "Focused session should handle paste")
        XCTAssertFalse(coordinator.currentSessionID == sessionB, "Non-focused session must NOT handle paste")
    }

    func testPasteBlockedWhenNoSessionFocused() {
        XCTAssertFalse(coordinator.currentSessionID == sessionA, "Session A must not handle paste when nothing is focused")
        XCTAssertFalse(coordinator.currentSessionID == sessionB, "Session B must not handle paste when nothing is focused")
    }

    func testPasteTargetUpdatesAfterFocusSwitch() {
        coordinator.focus(engine: engineA, sessionID: sessionA)
        XCTAssertEqual(coordinator.currentSessionID, sessionA)

        coordinator.focus(engine: engineB, sessionID: sessionB)
        XCTAssertNotEqual(coordinator.currentSessionID, sessionA, "Session A must not receive paste after focus switch")
        XCTAssertEqual(coordinator.currentSessionID, sessionB, "Session B should receive paste after focus switch")
    }

    func testPasteTargetClearedAfterRelinquish() {
        coordinator.focus(engine: engineA, sessionID: sessionA)
        coordinator.relinquish(sessionID: sessionA)

        XCTAssertNil(coordinator.currentSessionID, "No session should receive paste after relinquish")
    }

    // MARK: - Surface focus mutual exclusion

    func testOnlyOneEngineFocusedAtATime() {
        coordinator.focus(engine: engineA, sessionID: sessionA)
        XCTAssertTrue(engineA.isSurfaceFocused)
        XCTAssertFalse(engineB.isSurfaceFocused)

        coordinator.focus(engine: engineB, sessionID: sessionB)
        XCTAssertFalse(engineA.isSurfaceFocused, "Previous engine must be unfocused")
        XCTAssertTrue(engineB.isSurfaceFocused, "New engine must be focused")
    }

    func testUnfocusCurrentClearsBothEngineAndSession() {
        coordinator.focus(engine: engineA, sessionID: sessionA)
        coordinator.unfocusCurrent()

        XCTAssertNil(coordinator.currentSessionID)
        XCTAssertFalse(engineA.isSurfaceFocused)
    }

    // MARK: - Rapid focus switching

    func testRapidFocusSwitchingSettlesOnLastSession() {
        for _ in 0..<10 {
            coordinator.focus(engine: engineA, sessionID: sessionA)
            coordinator.focus(engine: engineB, sessionID: sessionB)
        }
        XCTAssertEqual(coordinator.currentSessionID, sessionB, "Must settle on last focused session")
        XCTAssertFalse(engineA.isSurfaceFocused)
        XCTAssertTrue(engineB.isSurfaceFocused)
    }

    func testFocusSameSessionTwiceIsIdempotent() {
        coordinator.focus(engine: engineA, sessionID: sessionA)
        engineA.setSurfaceFocusCallCount = 0

        coordinator.focus(engine: engineA, sessionID: sessionA)
        XCTAssertEqual(engineA.setSurfaceFocusCallCount, 0, "Re-focusing same session should be a no-op")
    }
}

// MARK: - Mock

@MainActor
private final class MockClipboardEngine: TerminalSessionEngine {
    var sessionID: UUID?
    var isSurfaceFocused = false
    var setSurfaceFocusCallCount = 0
    var copyCallCount = 0
    var pasteCallCount = 0

    let hostedView: NSView = NSView(frame: .zero)
    var effectiveAppearance: NSAppearance { NSAppearance.current }
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    var processIsRunning: Bool { false }
    var shellProcessID: Int32 { 0 }
    var debugIdentifier: String { "mock-clipboard" }

    func configure(delegate: any TerminalSessionEngineDelegate, initialFont: NSFont, optionAsMetaKey: Bool, historySize: Int) {}
    func startProcess(executable: String, args: [String], environment: [String], currentDirectory: String) {}
    func send(text: String) {}
    func typeCharacters(_ text: String) {}
    func registerOscHandler(code: Int, handler: @escaping (ArraySlice<UInt8>) -> Void) {}
    func currentDimensions() -> (cols: Int, rows: Int) { (80, 24) }
    func resize(cols: Int, rows: Int) {}
    func terminate() {}
    func updateActionHandlers(_ handlers: TerminalSessionActionHandlers) {}
    func applyThemePalette(_ palette: AppThemePalette) {}

    func setSurfaceFocus(_ focused: Bool) {
        isSurfaceFocused = focused
        setSurfaceFocusCallCount += 1
    }

    func copySelection() {
        copyCallCount += 1
    }

    func pasteFromClipboard() {
        pasteCallCount += 1
    }
}
