import Foundation
import XCTest

final class VibeSpaceAndNavigationUITests: CrispyVibesUIBaseTestCase {
    func testSwitchProjectFromRailAndKeyboardShortcut() throws {
        let fixture = try makeFixture(projectCount: 2)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        let project1File = projectSpecificFile(in: app, index: 1)
        XCTAssertTrue(project1File.waitForExistence(timeout: 15))

        let stackedProjectCard = identifiedElement(in: app, identifier: "project.stacked.card")
        XCTAssertTrue(stackedProjectCard.waitForExistence(timeout: 10))
        stackedProjectCard.tap()

        XCTAssertTrue(waitForCondition(timeout: 8) {
            projectSpecificFile(in: app, index: 2).exists
        })

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(waitForCondition(timeout: 8) {
            projectSpecificFile(in: app, index: 1).exists
        })
    }

    func testKeyboardShortcutFocusesSecondProjectDirectly() throws {
        let fixture = try makeFixture(projectCount: 2)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(projectSpecificFile(in: app, index: 1).waitForExistence(timeout: 15))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(waitForCondition(timeout: 8) {
            projectSpecificFile(in: app, index: 2).exists
        })

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(waitForCondition(timeout: 8) {
            projectSpecificFile(in: app, index: 1).exists
        })
    }

    func testProjectRailCardFocusUpdatesFocusedProjectTitle() throws {
        let fixture = try makeFixture(projectCount: 2)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        let stackedProjectCard = identifiedElement(in: app, identifier: "project.stacked.card")
        XCTAssertTrue(stackedProjectCard.waitForExistence(timeout: 10))
        stackedProjectCard.tap()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 2, timeout: 12))
    }

    func testVibeSpaceWithNoProjectsShowsAddProjectsCallToAction() throws {
        let fixture = try makeFixture(projectCount: 0)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(
            identifiedElement(in: app, identifier: "vibespace.empty.add-projects")
                .waitForExistence(timeout: 10)
        )
    }

    func testDetailedVibeSpaceSidebarRenameFieldStaysEditableWhileTyping() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        XCTAssertTrue(openDetailedVibeSpaceView(in: app, timeout: 12))

        let sidebar = identifiedElement(in: app, identifier: "vibespace.sidebar.files")
        XCTAssertTrue(sidebar.waitForExistence(timeout: 8))

        let sourcesRow = sidebar
            .descendants(matching: .any)
            .matching(identifier: "explorer.row")
            .matching(NSPredicate(format: "label == %@ OR value == %@", "Sources", "Sources"))
            .firstMatch
        XCTAssertTrue(sourcesRow.waitForExistence(timeout: 8))
        XCTAssertFalse(identifiedElement(in: app, identifier: "explorer.rename.field").exists)
        sourcesRow.tap()

        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        let renameField = identifiedElement(in: app, identifier: "explorer.rename.field")
        XCTAssertTrue(renameField.waitForExistence(timeout: 6))

        renameField.tap()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Sources Renamed")

        XCTAssertTrue(waitForCondition(timeout: 4) {
            guard renameField.exists else { return false }
            let value = (renameField.value as? String) ?? renameField.label
            return value == "Sources Renamed"
        })
    }
}
