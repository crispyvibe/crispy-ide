import Foundation
import XCTest

/// UI tests for REQ-P10-TEST-003: VibeSpace lifecycle — verify per-vibespace directory structure on disk
final class VibeSpaceLifecycleUITests: CrispyVibesUIBaseTestCase {

    private func launchAndWaitForPersistence(projectCount: Int) throws -> XCUIApplication {
        let fixture = try makeFixture(projectCount: projectCount)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()
        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        // Wait for hydration to complete and vibespace persistence writes to flush
        // The terminal session host appearing means hydration finished
        let terminalHost = identifiedElement(in: app, identifier: "terminal.focused.host")
        _ = terminalHost.waitForExistence(timeout: 10)
        // Additional wait for debounced persistence write (200ms) + disk flush
        Thread.sleep(forTimeInterval: 3)
        return app
    }

    private func findVibeSpaceDirectories() -> [URL] {
        let vibespacesDir = appUnderTestVibeSpacesURL()
        return ((try? FileManager.default.contentsOfDirectory(
            at: vibespacesDir, includingPropertiesForKeys: nil
        )) ?? []).filter { UUID(uuidString: $0.lastPathComponent) != nil }
    }

    // REQ-P10-STORE-001: Creating a vibespace creates a per-vibespace directory
    func testCreatingVibeSpaceCreatesPerVibeSpaceDirectory() throws {
        _ = try launchAndWaitForPersistence(projectCount: 1)

        let dirs = findVibeSpaceDirectories()
        XCTAssertGreaterThanOrEqual(dirs.count, 1,
            "vibespaces/ should contain at least one UUID directory, found: \(dirs.map(\.lastPathComponent))")
    }

    // REQ-P10-STORE-005: vibespace.json contains version field
    func testVibeSpaceConfigFileContainsVersion() throws {
        _ = try launchAndWaitForPersistence(projectCount: 1)

        let dirs = findVibeSpaceDirectories()
        XCTAssertFalse(dirs.isEmpty, "Need at least one vibespace directory")

        var foundValidConfig = false
        for dir in dirs {
            let configURL = dir.appendingPathComponent("vibespace.json")
            guard let data = try? Data(contentsOf: configURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = json["payload"] as? String,
                  let payloadData = Data(base64Encoded: payload),
                  let config = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
                continue
            }
            if config["version"] as? Int == 2 {
                foundValidConfig = true
                break
            }
        }
        XCTAssertTrue(foundValidConfig, "At least one vibespace.json should contain version: 2")
    }

    // REQ-P10-STORE-006: Per-project config files exist in projects/ subdirectory
    func testPerProjectConfigFilesExist() throws {
        _ = try launchAndWaitForPersistence(projectCount: 2)

        let dirs = findVibeSpaceDirectories()
        XCTAssertFalse(dirs.isEmpty, "Need at least one vibespace directory")

        var foundProjectFiles = false
        for dir in dirs {
            let projectsDir = dir.appendingPathComponent("projects", isDirectory: true)
            let files = ((try? FileManager.default.contentsOfDirectory(
                at: projectsDir, includingPropertiesForKeys: nil
            )) ?? []).filter { $0.pathExtension == "json" }
            if files.count >= 2 {
                foundProjectFiles = true
                break
            }
        }
        XCTAssertTrue(foundProjectFiles,
            "projects/ should contain at least 2 JSON files for 2 projects")
    }

    // REQ-P10-SVC-006: VibeSpace survives view mode switching
    func testVibeSpaceSurvivesViewModeSwitching() throws {
        let app = try launchAndWaitForPersistence(projectCount: 1)

        app.typeKey("t", modifierFlags: .command)
        let boardCanvas = identifiedElement(in: app, identifier: "vibespace.terminal-only")
        XCTAssertTrue(boardCanvas.waitForExistence(timeout: 10))

        app.typeKey("d", modifierFlags: .command)
        let focusedProject = identifiedElement(in: app, identifier: "project.focused")
        XCTAssertTrue(focusedProject.waitForExistence(timeout: 10),
            "VibeSpace should survive view mode round-trip")
    }
}

final class OnboardingDisclaimerUITests: CrispyVibesUIBaseTestCase {
    func testFirstLaunchShowsDisclaimerAndAcceptContinues() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root

        let app = makeApplication(
            fixture: fixture,
            resetState: true,
            extraLaunchEnvironment: ["CRISPYVIBES_UI_TEST_SHOW_ONBOARDING": "1"]
        )
        app.launch()

        let disclaimer = identifiedElement(in: app, identifier: "onboarding.disclaimer.screen")
        XCTAssertTrue(disclaimer.waitForExistence(timeout: 15))

        let acceptButton = identifiedElement(in: app, identifier: "onboarding.disclaimer.accept")
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 5))
        acceptButton.tap()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
    }

    func testAcceptedDisclaimerPersistsUntilReset() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root

        let firstLaunch = makeApplication(
            fixture: fixture,
            resetState: true,
            extraLaunchEnvironment: ["CRISPYVIBES_UI_TEST_SHOW_ONBOARDING": "1"]
        )
        firstLaunch.launch()

        let acceptButton = identifiedElement(in: firstLaunch, identifier: "onboarding.disclaimer.accept")
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 15))
        acceptButton.tap()
        XCTAssertTrue(waitForFocusedProjectShell(in: firstLaunch, index: 1, timeout: 20))
        firstLaunch.terminate()

        let secondLaunch = makeApplication(
            fixture: fixture,
            resetState: false,
            extraLaunchEnvironment: ["CRISPYVIBES_UI_TEST_SHOW_ONBOARDING": "1"]
        )
        secondLaunch.launch()

        let disclaimer = identifiedElement(in: secondLaunch, identifier: "onboarding.disclaimer.screen")
        XCTAssertFalse(disclaimer.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForFocusedProjectShell(in: secondLaunch, index: 1, timeout: 20))
        secondLaunch.terminate()

        let thirdLaunch = makeApplication(
            fixture: fixture,
            resetState: true,
            extraLaunchEnvironment: ["CRISPYVIBES_UI_TEST_SHOW_ONBOARDING": "1"]
        )
        thirdLaunch.launch()

        let resetDisclaimer = identifiedElement(in: thirdLaunch, identifier: "onboarding.disclaimer.screen")
        XCTAssertTrue(resetDisclaimer.waitForExistence(timeout: 15))
    }
}
