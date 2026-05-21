import Foundation
import XCTest

final class BrowserUITests: CrispyVibesUIBaseTestCase {
    private func firstExistingElement(_ candidates: [XCUIElement]) -> XCUIElement {
        for candidate in candidates where candidate.exists {
            return candidate
        }
        return candidates[0]
    }

    private func waitForAnyVisibleElement(
        _ candidates: [XCUIElement],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in candidates where candidate.exists && !candidate.frame.isEmpty && candidate.isHittable {
                return candidate
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return nil
    }

    private func browserAddressFieldCandidates(in app: XCUIApplication) -> [XCUIElement] {
        [
            identifiedElement(in: app, identifier: "browser.address-field"),
            app.textFields["Browser Address"].firstMatch,
            app.textFields["URL or search"].firstMatch,
            app.textFields.firstMatch
        ]
    }

    private func browserPinButtonCandidates(in app: XCUIApplication) -> [XCUIElement] {
        [
            identifiedElement(in: app, identifier: "terminal.spotlight.pin"),
            app.buttons["Pin to Dock"].firstMatch
        ]
    }

    private func browserOverflowMenuCandidates(in app: XCUIApplication) -> [XCUIElement] {
        [
            identifiedElement(in: app, identifier: "browser.overflow-menu"),
            app.menuButtons["browser.overflow-menu"].firstMatch,
            app.menuButtons.firstMatch,
            app.buttons.firstMatch
        ]
    }

    private func openBrowserButtonCandidates(in app: XCUIApplication) -> [XCUIElement] {
        [
            identifiedElement(in: app, identifier: "toolbar.open-browser"),
            app.buttons["Open Browser"].firstMatch
        ]
    }

    private func browserBoardTileCandidates(in app: XCUIApplication) -> [XCUIElement] {
        [
            identifiedElement(in: app, identifier: "vibespace.terminal-board.browser-tile"),
            app.otherElements["Browser Tile"].firstMatch,
            app.staticTexts["Board Browser Fixture"].firstMatch
        ]
    }

    private func browserAddressField(in app: XCUIApplication) -> XCUIElement {
        firstExistingElement(browserAddressFieldCandidates(in: app))
    }

    private func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func openBrowserOverflowMenu(in app: XCUIApplication) {
        guard let menu = waitForAnyVisibleElement(browserOverflowMenuCandidates(in: app), timeout: 8) else {
            XCTFail("Browser overflow menu not found")
            return
        }
        tapElement(menu)
    }

    private func selectBrowserOverflowMenuItem(
        _ title: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 6
    ) {
        openBrowserOverflowMenu(in: app)
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            let candidates = [
                app.menuItems[title].firstMatch,
                app.buttons[title].firstMatch,
                app.staticTexts[title].firstMatch
            ]

            if let target = waitForAnyVisibleElement(candidates, timeout: 0.2) {
                tapElement(target)
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        print("BROWSER OVERFLOW MENU DEBUG START")
        print(app.debugDescription)
        print("BROWSER OVERFLOW MENU DEBUG END")
        XCTFail("Expected browser menu item '\(title)'")
    }

    private func openBrowser(from app: XCUIApplication) {
        guard let button = waitForAnyVisibleElement(openBrowserButtonCandidates(in: app), timeout: 8) else {
            XCTFail("Open Browser button not found")
            return
        }
        button.tap()
    }

    private func createBrowserFixtureHTML(in projectURL: URL, title: String) throws -> URL {
        let fileURL = projectURL.appendingPathComponent("browser-fixture.html")
        try Data(
            """
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8">
              <title>\(title)</title>
            </head>
            <body>
              <main>
                <h1>\(title)</h1>
                <p>Browser fixture content.</p>
              </main>
            </body>
            </html>
            """.utf8
        ).write(to: fileURL)
        return fileURL
    }

    private func setBrowserAddress(
        _ value: String,
        in app: XCUIApplication
    ) {
        guard let field = waitForAnyVisibleElement(browserAddressFieldCandidates(in: app), timeout: 8) else {
            XCTFail("Browser address field not found")
            return
        }
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
        field.typeKey(.return, modifierFlags: [])
    }

    private func waitForBrowserChrome(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        waitForAnyVisibleElement(browserAddressFieldCandidates(in: app), timeout: timeout) != nil
    }

    private func browserAddressValue(in app: XCUIApplication) -> String {
        let field = browserAddressField(in: app)
        return (field.value as? String) ?? field.label
    }

    private func waitForBrowserAddress(
        containing expectedValue: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 12
    ) -> Bool {
        waitForCondition(timeout: timeout) {
            browserAddressValue(in: app).contains(expectedValue)
        }
    }

    private func waitForBrowserPageContent(
        title expectedTitle: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 12
    ) -> Bool {
        let titleText = app.staticTexts[expectedTitle].firstMatch
        return waitForCondition(timeout: timeout) {
            titleText.exists && !titleText.frame.isEmpty
        }
    }

    func testDetailedBrowserCanNavigateLocalFixtureAndZoom() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let htmlURL = try createBrowserFixtureHTML(in: fixture.projects[0], title: "Detailed Browser Fixture")

        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        XCTAssertTrue(openDetailedVibeSpaceView(in: app, timeout: 12))

        openBrowser(from: app)

        XCTAssertTrue(waitForBrowserChrome(in: app, timeout: 10))

        setBrowserAddress(htmlURL.absoluteString, in: app)
        XCTAssertTrue(waitForBrowserPageContent(title: "Detailed Browser Fixture", in: app))

        selectBrowserOverflowMenuItem("Zoom In", in: app)
        selectBrowserOverflowMenuItem("Zoom In", in: app)

        XCTAssertTrue(waitForBrowserPageContent(title: "Detailed Browser Fixture", in: app))
    }

    func testTerminalBoardBrowserSpotlightCanBePinnedToDock() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let htmlURL = try createBrowserFixtureHTML(in: fixture.projects[0], title: "Board Browser Fixture")

        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        XCTAssertTrue(openTerminalOnlyVibeSpaceView(in: app, timeout: 12))

        openBrowser(from: app)

        let spotlight = identifiedElement(in: app, identifier: "terminal.spotlight.overlay")
        XCTAssertTrue(spotlight.waitForExistence(timeout: 10))

        setBrowserAddress(htmlURL.absoluteString, in: app)
        XCTAssertTrue(waitForBrowserPageContent(title: "Board Browser Fixture", in: app))

        guard let pinButton = waitForAnyVisibleElement(browserPinButtonCandidates(in: app), timeout: 6) else {
            XCTFail("Pin to Dock button not found")
            return
        }
        pinButton.tap()

        XCTAssertTrue(waitForCondition(timeout: 12) {
            !spotlight.exists
        })
        XCTAssertNotNil(waitForAnyVisibleElement(browserBoardTileCandidates(in: app), timeout: 12))
        XCTAssertTrue(waitForBrowserPageContent(title: "Board Browser Fixture", in: app))
    }

    func testDetailedBrowserPersistsAcrossRelaunch() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let htmlURL = try createBrowserFixtureHTML(in: fixture.projects[0], title: "Persistent Browser Fixture")

        let firstLaunch = makeApplication(fixture: fixture, resetState: true)
        firstLaunch.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: firstLaunch, index: 1, timeout: 20))
        XCTAssertTrue(openDetailedVibeSpaceView(in: firstLaunch, timeout: 12))

        openBrowser(from: firstLaunch)

        XCTAssertTrue(waitForBrowserChrome(in: firstLaunch, timeout: 10))

        setBrowserAddress(htmlURL.absoluteString, in: firstLaunch)
        XCTAssertTrue(waitForBrowserPageContent(title: "Persistent Browser Fixture", in: firstLaunch))

        selectBrowserOverflowMenuItem("Zoom In", in: firstLaunch)
        selectBrowserOverflowMenuItem("Zoom In", in: firstLaunch)

        Thread.sleep(forTimeInterval: 3)
        firstLaunch.terminate()

        let secondLaunch = makeApplication(fixture: fixture, resetState: false)
        secondLaunch.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: secondLaunch, index: 1, timeout: 20))
        XCTAssertTrue(openDetailedVibeSpaceView(in: secondLaunch, timeout: 12))
        XCTAssertTrue(waitForBrowserChrome(in: secondLaunch, timeout: 12))
        XCTAssertTrue(waitForBrowserPageContent(title: "Persistent Browser Fixture", in: secondLaunch))
    }
}
