import Foundation
import XCTest

/// UI tests for REQ-P8-TERM-007: Vibe space creation modal
final class VibeSpaceCreationUITests: CrispyVibesUIBaseTestCase {

    private func launchAtWelcomeScreen() throws -> XCUIApplication {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        // Launch with the fixture but override to NOT start in vibespace
        let app = makeApplication(
            fixture: fixture,
            extraLaunchEnvironment: ["CRISPYVIBES_UI_TEST_START_IN_VIBESPACE": "0"]
        )
        app.launch()
        return app
    }

    private func launchAtWelcomeScreenWithProjects() throws -> XCUIApplication {
        let fixture = try makeFixture(projectCount: 2)
        fixtureRoot = fixture.root
        let app = makeApplication(
            fixture: fixture,
            extraLaunchEnvironment: [
                "CRISPYVIBES_UI_TEST_START_IN_VIBESPACE": "0",
                "CRISPYVIBES_UI_TEST_VIBESPACE_FOLDERS": fixture.projects.map(\.path).joined(separator: "\n")
            ]
        )
        app.launch()
        return app
    }

    @discardableResult
    private func advanceToAgentStep(_ app: XCUIApplication) throws -> XCUIApplication {
        let createButton = identifiedElement(in: app, identifier: "welcome.action.create-vibespace")
        XCTAssertTrue(createButton.waitForExistence(timeout: 15))
        createButton.tap()

        let nameField = identifiedElement(in: app, identifier: "vibespace.creation.name")
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("Test VibeSpace")

        let nextButton = identifiedElement(in: app, identifier: "vibespace.creation.next")
        nextButton.tap()

        let addFoldersButton = identifiedElement(in: app, identifier: "vibespace.creation.add-folders")
        XCTAssertTrue(addFoldersButton.waitForExistence(timeout: 5))
        addFoldersButton.tap()
        nextButton.tap()

        let customCard = app.buttons["Custom"]
        XCTAssertTrue(customCard.waitForExistence(timeout: 5))
        return app
    }

    // REQ-P8-TERM-007: Create button opens the creation modal sheet
    func testCreateVibeSpaceButtonOpensModal() throws {
        let app = try launchAtWelcomeScreen()

        let createButton = identifiedElement(in: app, identifier: "welcome.action.create-vibespace")
        XCTAssertTrue(createButton.waitForExistence(timeout: 15),
            "Create vibespace button should exist on welcome screen")
        createButton.tap()

        let nameField = identifiedElement(in: app, identifier: "vibespace.creation.name")
        XCTAssertTrue(nameField.waitForExistence(timeout: 5),
            "Creation modal should appear with name field")
    }

    // REQ-P8-TERM-007: Modal shows step-by-step wizard — name step has Next and Cancel buttons
    func testCreationModalShowsNameStepWithNavigation() throws {
        let app = try launchAtWelcomeScreen()

        let createButton = identifiedElement(in: app, identifier: "welcome.action.create-vibespace")
        XCTAssertTrue(createButton.waitForExistence(timeout: 15))
        createButton.tap()

        let nameField = identifiedElement(in: app, identifier: "vibespace.creation.name")
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))

        let nextButton = identifiedElement(in: app, identifier: "vibespace.creation.next")
        XCTAssertTrue(nextButton.exists, "Next button should be visible on name step")

        let backButton = identifiedElement(in: app, identifier: "vibespace.creation.back")
        XCTAssertTrue(backButton.exists, "Cancel button should be visible on name step")
    }

    // REQ-P8-TERM-007: Cancel on name step dismisses the modal
    func testCancelOnNameStepDismissesModal() throws {
        let app = try launchAtWelcomeScreen()

        let createButton = identifiedElement(in: app, identifier: "welcome.action.create-vibespace")
        XCTAssertTrue(createButton.waitForExistence(timeout: 15))
        createButton.tap()

        let nameField = identifiedElement(in: app, identifier: "vibespace.creation.name")
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))

        let backButton = identifiedElement(in: app, identifier: "vibespace.creation.back")
        backButton.tap()

        XCTAssertTrue(waitForCondition(timeout: 5) {
            !nameField.exists
        }, "Modal should dismiss after cancel")
    }

    // REQ-P8-TERM-007: Advancing from name step shows projects step with Add Projects button
    func testAdvancingFromNameStepShowsProjectsStep() throws {
        let app = try launchAtWelcomeScreen()

        let createButton = identifiedElement(in: app, identifier: "welcome.action.create-vibespace")
        XCTAssertTrue(createButton.waitForExistence(timeout: 15))
        createButton.tap()

        let nameField = identifiedElement(in: app, identifier: "vibespace.creation.name")
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))

        nameField.tap()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("Test VibeSpace")

        let nextButton = identifiedElement(in: app, identifier: "vibespace.creation.next")
        nextButton.tap()

        let addFoldersButton = identifiedElement(in: app, identifier: "vibespace.creation.add-folders")
        XCTAssertTrue(addFoldersButton.waitForExistence(timeout: 5),
            "Projects step should show Add Projects button after advancing from name step")
    }

    func testSelectingCustomVibeSpaceCLIShowsCommandField() throws {
        let app = try launchAtWelcomeScreenWithProjects()
        try advanceToAgentStep(app)

        app.buttons["Custom"].tap()

        let customCommandField = identifiedElement(
            in: app,
            identifier: "vibespace.creation.custom-command.vibespace"
        )
        XCTAssertTrue(customCommandField.waitForExistence(timeout: 5))
    }

    func testSelectingCustomProjectOverrideShowsCommandField() throws {
        let app = try launchAtWelcomeScreenWithProjects()
        try advanceToAgentStep(app)

        let overrideMenus = app.popUpButtons.allElementsBoundByIndex
            .filter { $0.exists && $0.identifier != "vibespace.creation.next" && $0.identifier != "vibespace.creation.back" }
        XCTAssertGreaterThanOrEqual(overrideMenus.count, 1)

        let firstOverrideMenu = overrideMenus[0]
        firstOverrideMenu.tap()
        app.menuItems["Custom"].tap()

        let customProjectCommandField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "vibespace.creation.custom-command.project.")
        ).firstMatch
        XCTAssertTrue(customProjectCommandField.waitForExistence(timeout: 5))
    }
}
