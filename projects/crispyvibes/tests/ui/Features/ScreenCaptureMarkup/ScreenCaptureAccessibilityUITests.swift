import XCTest

/// Hardware/TCC coverage for F062. Run with CRISPY_F062_HARDWARE_UI=1 on a signed local build.
@MainActor
final class ScreenCaptureAccessibilityUITests: CrispyVibesUIBaseTestCase {
    private func launchHardwareApp() throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["CRISPY_F062_HARDWARE_UI"] == "1" else {
            throw XCTSkip("Requires an interactive Mac with Screen Recording permission; set CRISPY_F062_HARDWARE_UI=1")
        }
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()
        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        return app
    }

    private func element(in app: XCUIApplication, identifierPrefix prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .firstMatch
    }

    private func invokeCapture(_ app: XCUIApplication) {
        app.menuBars.menuBarItems["File"].click()
        app.menuItems.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Capture Screenshot…")
        ).firstMatch.click()
        XCTAssertTrue(element(
            in: app,
            identifierPrefix: "screenCapture.selection.overlay."
        ).waitForExistence(timeout: 10))
    }

    private func captureDisplay(_ app: XCUIApplication) {
        invokeCapture(app)
        app.typeKey("d", modifierFlags: [])
        let target = element(in: app, identifierPrefix: "screenCapture.selection.display.")
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.click()
        XCTAssertTrue(app.otherElements["screenCapture.studio.window"].waitForExistence(timeout: 10))
    }

    func test_windowAndDisplayCaptureUseTheSingleStudioRoute() throws {
        let app = try launchHardwareApp()
        invokeCapture(app)
        app.typeKey("w", modifierFlags: [])
        let window = element(in: app, identifierPrefix: "screenCapture.selection.window.")
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        window.click()
        XCTAssertTrue(app.otherElements["screenCapture.studio.window"].waitForExistence(timeout: 10))
    }

    func test_studioShowsCurrentAndRecentHistoryRailWithCopyRemainingOpen() throws {
        let app = try launchHardwareApp()
        captureDisplay(app)

        XCTAssertTrue(app.otherElements["screenCapture.studio.historyRail"].exists)
        XCTAssertTrue(app.buttons["screenCapture.studio.history.current"].exists)
        let copy = app.buttons["screenCapture.studio.copy"]
        let copyAndDismiss = app.buttons["screenCapture.studio.copyAndDismiss"]
        XCTAssertTrue(copy.exists)
        XCTAssertTrue(copyAndDismiss.exists)
        copy.click()
        XCTAssertTrue(app.otherElements["screenCapture.studio.window"].exists)
    }

    func test_newCaptureReusesStudioAndKeepsHistoryAvailable() throws {
        let app = try launchHardwareApp()
        captureDisplay(app)
        invokeCapture(app)
        app.typeKey("d", modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        XCTAssertTrue(app.otherElements["screenCapture.studio.window"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["screenCapture.studio.historyRail"].exists)
    }

    func test_keyboardCancelRestoresWithoutPresentingStudio() throws {
        let app = try launchHardwareApp()
        invokeCapture(app)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        XCTAssertFalse(element(
            in: app,
            identifierPrefix: "screenCapture.selection.overlay."
        ).waitForExistence(timeout: 2))
        XCTAssertFalse(app.otherElements["screenCapture.studio.window"].exists)
    }

    func test_studioStartsInMarkupWithPenAndExposesHistoryControls() throws {
        let app = try launchHardwareApp()
        captureDisplay(app)

        XCTAssertTrue(app.buttons["screenCapture.markup.mode.markup"].exists)
        XCTAssertTrue(app.buttons["screenCapture.markup.tool.pen"].exists)
        XCTAssertTrue(app.buttons["screenCapture.studio.clearHistory"].exists)
        XCTAssertTrue(app.buttons["screenCapture.studio.close"].exists)
    }
}
