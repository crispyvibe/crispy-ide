import Foundation
import XCTest

extension TerminalInteractionUITests {
    func testDetailedViewHydratesTerminalRailForFiveProjectsWithoutModeSwitch() throws {
        let fixture = try makeFixture(projectCount: 5)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 1))
        XCTAssertFalse(identifiedElement(in: app, identifier: "vibespace.terminal-only").exists)

        let stackedCards = app.descendants(matching: .any).matching(identifier: "project.stacked.card")
        XCTAssertTrue(waitForCondition(timeout: 1) {
            stackedCards.count >= 4
        })
        let expectedRailCount = max(fixture.projects.count - 1, 0)

        let allRailCardsRendered = {
            () -> Bool in
            guard stackedCards.count >= expectedRailCount else { return false }
            for index in 0..<expectedRailCount {
                let card = stackedCards.element(boundBy: index)
                if !card.exists { return false }
            }
            return true
        }
        XCTAssertTrue(waitForCondition(timeout: 1) {
            allRailCardsRendered()
        })

        let assertDetailedViewTerminalText = { (context: String, timeout: TimeInterval) in
            XCTAssertTrue(
                waitForFocusedTerminalText(in: app, timeout: timeout),
                "Expected focused terminal viewport to render visible text (\(context)). \(focusedTerminalTextDebugReport(in: app))"
            )
        }

        let railFocusOrder = Array(2...fixture.projects.count) + [1]
        for targetProjectIndex in railFocusOrder {
            XCTAssertTrue(
                focusProjectViaRailCard(in: app, index: targetProjectIndex, timeout: 2.5),
                "Expected stacked rail card for project \(targetProjectIndex) to be tappable."
            )
            assertDetailedViewTerminalText(
                "immediately after focusing project \(targetProjectIndex) via rail card",
                0.25
            )
            assertDetailedViewTerminalText("after focusing project \(targetProjectIndex) via rail card", 0.75)
        }
    }

    func testDetailedViewHydratesFocusedTerminalBeforeRailsWithinBudget() throws {
        let fixture = try makeFixture(projectCount: 5)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        let stackedCards = app.descendants(matching: .any).matching(identifier: "project.stacked.card")
        XCTAssertTrue(waitForCondition(timeout: 20) {
            stackedCards.count >= 4
        })

        let start = Date()
        XCTAssertTrue(waitForCondition(timeout: 18) {
            waitForFocusedTerminalText(in: app, timeout: 0.2)
        }, "Expected focused terminal viewport to render visible text promptly. \(focusedTerminalTextDebugReport(in: app))")
        let focusedReadyElapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(waitForCondition(timeout: 18) {
            stackedCards.count >= 4
        }, "Expected rail cards to remain rendered.")
        let allRailsReadyElapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(focusedReadyElapsed, 20.0)
        XCTAssertLessThan(allRailsReadyElapsed, 26.0)
    }

    func testStackedRailsRenderTerminalHosts() throws {
        let fixture = try makeFixture(projectCount: 4)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        XCTAssertFalse(identifiedElement(in: app, identifier: "vibespace.terminal-only").exists)

        let stackedCards = app.descendants(matching: .any).matching(identifier: "project.stacked.card")
        XCTAssertTrue(waitForCondition(timeout: 20) {
            stackedCards.count >= 3
        })

        for targetProjectIndex in 2...fixture.projects.count {
            XCTAssertTrue(
                focusProjectViaRailCard(in: app, index: targetProjectIndex, timeout: 1),
                "Expected stacked rail card for project \(targetProjectIndex) to be tappable."
            )
            XCTAssertTrue(
                waitForFocusedProjectShell(in: app, index: targetProjectIndex, timeout: 2),
                "Expected project \(targetProjectIndex) to become focused after rail-card switch."
            )
            XCTAssertTrue(
                waitForFocusedTerminalText(in: app, timeout: 1),
                "Expected focused terminal text after switching to project \(targetProjectIndex). \(focusedTerminalTextDebugReport(in: app))"
            )
            XCTAssertTrue(waitForCondition(timeout: 1) {
                stackedCards.count >= 3
            }, "Expected stacked rail cards to remain rendered after switching to project \(targetProjectIndex).")
        }
    }

    func testRepeatedRailProjectSwitchKeepsRailTerminalHostsVisible() throws {
        let fixture = try makeFixture(projectCount: 4)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        let stackedCards = app.descendants(matching: .any).matching(identifier: "project.stacked.card")
        XCTAssertTrue(waitForCondition(timeout: 20) {
            stackedCards.count >= 3
        })

        let switchSequence = [2, 3, 4, 1, 2, 3, 4, 1]
        for (attempt, targetProjectIndex) in switchSequence.enumerated() {
            XCTAssertTrue(
                focusProjectViaRailCard(in: app, index: targetProjectIndex, timeout: 2.5),
                "Expected stacked rail card for project \(targetProjectIndex) to be tappable on attempt \(attempt)."
            )
            XCTAssertTrue(
                waitForFocusedTerminalText(in: app, timeout: 1),
                "Expected focused terminal text after rail switch attempt \(attempt). \(focusedTerminalTextDebugReport(in: app))"
            )
            XCTAssertTrue(waitForCondition(timeout: 1) {
                stackedCards.count >= 3
            }, "Expected stacked rail cards to remain rendered after attempt \(attempt).")
        }
    }

}
