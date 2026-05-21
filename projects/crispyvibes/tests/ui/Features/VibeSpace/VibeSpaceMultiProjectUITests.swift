import Foundation
import XCTest

/// UI tests for REQ-P10-TEST-004 and STORE-002/003
final class VibeSpaceMultiProjectUITests: CrispyVibesUIBaseTestCase {

    private func launchAndWaitForPersistence(projectCount: Int) throws -> XCUIApplication {
        let fixture = try makeFixture(projectCount: projectCount)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()
        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    // REQ-P10-TEST-004: No CLI preset labels on board
    func testMultiProjectVibeSpaceWithNoCLIShowsNoPresetTerminals() throws {
        let app = try launchAndWaitForPersistence(projectCount: 3)

        app.typeKey("t", modifierFlags: .command)
        let boardCanvas = identifiedElement(in: app, identifier: "vibespace.terminal-only")
        XCTAssertTrue(boardCanvas.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)

        for name in ["Kiro", "Claude", "Codex", "Gemini"] {
            XCTAssertFalse(app.staticTexts[name].exists,
                "No CLI preset '\(name)' should appear without CLI selection")
        }
    }

    // REQ-P10-TEST-004: All 3 projects accessible
    func testAllThreeProjectsAccessibleViaShortcuts() throws {
        let app = try launchAndWaitForPersistence(projectCount: 3)

        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(waitForCondition(timeout: 8) {
            projectSpecificFile(in: app, index: 2).exists
        }, "Project 2 should be accessible via ⌘2")

        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(waitForCondition(timeout: 8) {
            projectSpecificFile(in: app, index: 3).exists
        }, "Project 3 should be accessible via ⌘3")
    }

    // REQ-P10-STORE-002: app-state.json has only recentVibeSpaceIDs
    func testAppStateFileContainsOnlyRecentIDs() throws {
        _ = try launchAndWaitForPersistence(projectCount: 1)

        let appStateURL = appUnderTestSupportURL().appendingPathComponent("app-state.json")
        guard let data = try? Data(contentsOf: appStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("app-state.json should exist and be valid JSON")
            return
        }

        XCTAssertNotNil(json["recentVibeSpaceIDs"] as? [String],
            "app-state.json must have recentVibeSpaceIDs")

        let forbiddenKeys = ["startupSettings", "projectColorTags", "projectPaths",
                             "projectStartupOverrides", "activeVibeSpaceID", "catalog"]
        for key in forbiddenKeys {
            XCTAssertNil(json[key], "app-state.json must not contain '\(key)'")
        }
    }

    // REQ-P10-STORE-003: Only allowed keys in app-state.json
    func testNoVibeSpaceConfigInGlobalAppState() throws {
        _ = try launchAndWaitForPersistence(projectCount: 2)

        let appStateURL = appUnderTestSupportURL().appendingPathComponent("app-state.json")
        guard let data = try? Data(contentsOf: appStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("app-state.json should exist")
            return
        }

        let allowedKeys: Set<String> = ["recentVibeSpaceIDs", "hasAcceptedDisclaimer", "sidebarWidth"]
        let extraKeys = Set(json.keys).subtracting(allowedKeys)
        XCTAssertTrue(extraKeys.isEmpty,
            "app-state.json has unexpected keys: \(extraKeys)")
    }
}
