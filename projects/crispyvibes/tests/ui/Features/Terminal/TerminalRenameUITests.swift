import Foundation
import XCTest

/// UI tests for REQ-P8-TERM-001: Terminal tab rename via double-click
/// and REQ-P8-TERM-002: Terminal auto-naming
final class TerminalRenameUITests: CrispyVibesUIBaseTestCase {

    // REQ-P8-TERM-001: Double-click terminal tab shows inline rename field
    func testDoubleClickTerminalTabShowsRenameField() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))

        let tabs = terminalTabs(in: app)
        XCTAssertTrue(waitForCondition(timeout: 10) { tabs.count >= 1 })

        let tab = tabs.firstMatch
        // Double-click the tab to enter rename mode
        tab.doubleClick()

        // A text field should appear for editing
        XCTAssertTrue(waitForCondition(timeout: 5) {
            app.textFields.count > 0
        }, "Rename text field should appear after double-click")
    }

    // REQ-P8-TERM-001: Committing rename updates the tab title
    func testRenameTerminalTabUpdatesTitle() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))

        let tabs = terminalTabs(in: app)
        XCTAssertTrue(waitForCondition(timeout: 10) { tabs.count >= 1 })

        tabs.firstMatch.doubleClick()

        let textField = app.textFields.firstMatch
        XCTAssertTrue(waitForCondition(timeout: 5) { textField.exists })

        // Click to focus, then select all and type new name
        textField.click()
        textField.typeKey("a", modifierFlags: .command)
        textField.typeText("My Custom Terminal")
        textField.typeKey(.return, modifierFlags: [])

        // The renamed title should appear as a static text
        XCTAssertTrue(waitForCondition(timeout: 5) {
            app.staticTexts["My Custom Terminal"].exists
        }, "Tab should display the renamed title after commit")

        // The text field should be gone
        XCTAssertTrue(waitForCondition(timeout: 3) {
            app.textFields.count == 0
        }, "Rename field should disappear after commit")
    }

    // REQ-P8-TERM-001: Escape cancels rename without changing the title
    func testEscapeCancelsRenameWithoutChangingTitle() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))

        let tabs = terminalTabs(in: app)
        XCTAssertTrue(waitForCondition(timeout: 10) { tabs.count >= 1 })

        tabs.firstMatch.doubleClick()

        let textField = app.textFields.firstMatch
        XCTAssertTrue(waitForCondition(timeout: 5) { textField.exists })

        textField.click()
        textField.typeKey("a", modifierFlags: .command)
        textField.typeText("ShouldNotAppear")
        textField.typeKey(.escape, modifierFlags: [])

        // The cancelled text should NOT appear as a tab title
        XCTAssertTrue(waitForCondition(timeout: 3) {
            !app.staticTexts["ShouldNotAppear"].exists
        }, "Cancelled rename text should not become the tab title")

        // Rename field should be gone
        XCTAssertTrue(waitForCondition(timeout: 3) {
            app.textFields.count == 0
        }, "Rename field should disappear after escape")
    }

    // REQ-P8-TERM-002: Terminal shows meaningful name instead of bare shell name
    func testTerminalTabShowsDirectoryNameNotShellName() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))

        let tabs = terminalTabs(in: app)
        XCTAssertTrue(waitForCondition(timeout: 10) { tabs.count >= 1 })

        // Check that no visible tab label is a bare shell name
        let tabElements = tabs.allElementsBoundByIndex
        for tab in tabElements where tab.exists {
            let label = tab.label.lowercased()
            XCTAssertFalse(
                label == "zsh" || label == "-zsh" || label == "bash" || label == "-bash",
                "Terminal tab should show directory name, not bare shell name '\(tab.label)'"
            )
        }
    }
}
