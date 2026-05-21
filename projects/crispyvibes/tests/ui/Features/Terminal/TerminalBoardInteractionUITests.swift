import Foundation
import XCTest

/// UI tests for REQ-P8-BUG-006 and REQ-P8-TBI-027: Terminal board interactions.
///
/// NOTE: Terminal board UI tests require board hydration which has timing
/// dependencies on vibespace terminal startup. These tests verify the board
/// can be opened and basic elements are present. Active tile state assertions
/// are covered by unit tests (BoardInteractionControllerTests, BoardSpatialNavigationTests).
final class TerminalBoardInteractionUITests: CrispyVibesUIBaseTestCase {
    // REQ-P8-TBI-027: Terminal board canvas appears after ⌘T shortcut
    func testTerminalBoardCanvasAppearsAfterShortcut() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))

        // Switch to terminal board via ⌘T
        app.typeKey("t", modifierFlags: .command)

        let boardCanvas = identifiedElement(in: app, identifier: "vibespace.terminal-only")
        XCTAssertTrue(boardCanvas.waitForExistence(timeout: 10),
            "Terminal board canvas should appear after ⌘T")
    }

    // REQ-P8-TBI-027: Switching back to detailed view via ⌘D works after board
    func testSwitchBackToDetailedViewFromBoard() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))

        // Switch to board
        app.typeKey("t", modifierFlags: .command)
        let boardCanvas = identifiedElement(in: app, identifier: "vibespace.terminal-only")
        XCTAssertTrue(boardCanvas.waitForExistence(timeout: 10))

        // Switch back to detailed
        app.typeKey("d", modifierFlags: .command)
        let focusedProject = identifiedElement(in: app, identifier: "project.focused")
        XCTAssertTrue(focusedProject.waitForExistence(timeout: 10),
            "Detailed view should restore after ⌘D")
    }
}
