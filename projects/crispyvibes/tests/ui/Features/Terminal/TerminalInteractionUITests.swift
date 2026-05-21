import Foundation
import XCTest

final class TerminalInteractionUITests: CrispyVibesUIBaseTestCase {
    private func firstAvailableElement(
        _ candidates: [XCUIElement],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in candidates where candidate.exists && !candidate.frame.isEmpty {
                return candidate
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return nil
    }

    private func scopedShortcutMenuCandidates(in app: XCUIApplication) -> [XCUIElement] {
        return [
            identifiedElement(in: app, identifier: "terminal.scoped.shortcuts.menu"),
            identifiedElement(in: app, identifier: "terminal.shortcuts.menu"),
            app.menuButtons["Shortcuts"].firstMatch,
            app.buttons["Shortcuts"].firstMatch
        ]
    }

    private func openScopedShortcutMenu(in app: XCUIApplication) {
        guard let menu = firstAvailableElement(scopedShortcutMenuCandidates(in: app), timeout: 8) else {
            print("SHORTCUT MENU DEBUG START")
            print(app.debugDescription)
            print("SHORTCUT MENU DEBUG END")
            XCTFail("Scoped shortcuts menu was not visible")
            return
        }
        tapElement(menu)
    }

    private func selectScopedShortcutMenuItem(
        _ title: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 6
    ) {
        openScopedShortcutMenu(in: app)
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            let candidates = [
                app.menuItems[title].firstMatch,
                app.buttons[title].firstMatch,
                app.staticTexts[title].firstMatch
            ]

            if let target = firstAvailableElement(candidates, timeout: 0.2) {
                tapElement(target)
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        print("SHORTCUT ITEM DEBUG START")
        print(app.debugDescription)
        print("SHORTCUT ITEM DEBUG END")
        XCTFail("Expected menu item '\(title)'")
    }

    private func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func waitForFile(
        at url: URL,
        timeout: TimeInterval = 20
    ) -> Bool {
        waitForCondition(timeout: timeout, pollInterval: 0.2) {
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    private func shortcutCommandCreatingMarker(at url: URL) -> String {
        "/usr/bin/touch \(shellQuoted(url.path))"
    }

    private func launchVibeSpaceApp(
        projectCount: Int = 1,
        vibespaceShortcuts: [UITestShortcut] = []
    ) throws -> (UITestFixture, XCUIApplication) {
        let fixture = try makeFixture(
            projectCount: projectCount,
            vibespaceShortcuts: vibespaceShortcuts
        )
        fixtureRoot = fixture.root

        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        return (fixture, app)
    }

    func testAddTabImmediateNoTerminalClick() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))

        let addTabButton = newTerminalTabButton(in: app)
        XCTAssertTrue(addTabButton.waitForExistence(timeout: 10))

        let beforeCount = visibleTerminalCloseButtonCount(in: app)

        // Regression guard: click + before interacting with terminal content.
        if addTabButton.isHittable {
            addTabButton.tap()
        } else {
            addTabButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        XCTAssertTrue(waitForCondition(timeout: 8) {
            visibleTerminalTabCount(in: app) >= beforeCount + 1
        })
    }

    func testScopedShortcutCurrentTerminalRunsInFocusedTerminalWithoutAddingTab() throws {
        let markerURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-shortcut-current-terminal.marker")
        let shortcutName = "Focused Shortcut"
        let shortcut = UITestShortcut(
            name: shortcutName,
            command: shortcutCommandCreatingMarker(at: markerURL),
            launchBehavior: "currentTerminal"
        )
        let (_, app) = try launchVibeSpaceApp(
            projectCount: 1,
            vibespaceShortcuts: [shortcut]
        )

        let beforeCount = visibleTerminalTabCount(in: app)
        XCTAssertGreaterThanOrEqual(beforeCount, 1, "Fixture should provide at least one terminal tab")

        selectScopedShortcutMenuItem(shortcutName, in: app)

        XCTAssertTrue(waitForFile(at: markerURL), "Focused terminal shortcut should execute and create its marker")
        XCTAssertEqual(
            visibleTerminalTabCount(in: app),
            beforeCount,
            "Running in the current terminal should not add a new terminal tab"
        )
        XCTAssertFalse(
            app.buttons[shortcutName].waitForExistence(timeout: 1.5),
            "Current-terminal launch should not create a dedicated tab named after the shortcut"
        )
    }

    func testScopedShortcutNewPermanentTerminalCreatesDedicatedTabAndRunsCommand() throws {
        let shortcutName = "Dedicated Shortcut"
        let markerURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-shortcut-new-terminal.marker")
        let shortcut = UITestShortcut(
            name: shortcutName,
            command: shortcutCommandCreatingMarker(at: markerURL),
            launchBehavior: "newPermanentTerminal"
        )
        let (_, app) = try launchVibeSpaceApp(
            projectCount: 1,
            vibespaceShortcuts: [shortcut]
        )

        selectScopedShortcutMenuItem(shortcutName, in: app)

        XCTAssertTrue(waitForFile(at: markerURL), "Permanent-terminal shortcut should execute and create its marker")
        XCTAssertTrue(
            waitForCondition(timeout: 8) {
                app.buttons[shortcutName].exists || app.staticTexts[shortcutName].exists
            },
            "Permanent-terminal launch should create a dedicated tab named after the shortcut"
        )
    }

    func testScopedShortcutTemporaryTerminalOpensSpotlightAndRunsCommand() throws {
        let shortcutName = "Temporary Shortcut"
        let markerURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-shortcut-temporary-terminal.marker")
        let shortcut = UITestShortcut(
            name: shortcutName,
            command: shortcutCommandCreatingMarker(at: markerURL),
            launchBehavior: "newTemporaryTerminal"
        )
        let (_, app) = try launchVibeSpaceApp(
            projectCount: 1,
            vibespaceShortcuts: [shortcut]
        )

        let beforeCount = visibleTerminalTabCount(in: app)
        selectScopedShortcutMenuItem(shortcutName, in: app)

        let spotlight = identifiedElement(in: app, identifier: "terminal.spotlight.overlay")
        XCTAssertTrue(spotlight.waitForExistence(timeout: 10), "Temporary-terminal launch should open the spotlight")
        XCTAssertTrue(waitForFile(at: markerURL), "Temporary-terminal shortcut should execute and create its marker")
        XCTAssertEqual(
            visibleTerminalTabCount(in: app),
            beforeCount,
            "Temporary-terminal launch should not add a persistent terminal tab"
        )
        XCTAssertFalse(
            app.buttons[shortcutName].waitForExistence(timeout: 1.5),
            "Temporary-terminal launch should not create a dedicated persistent tab"
        )
    }
}
