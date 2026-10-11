import Foundation
import XCTest

final class ChromeAndSettingsUITests: CrispyVibesUIBaseTestCase {
    func testAppTerminationMatchingRejectsEveryMainProfileAndAllowsLocalOnly() {
        XCTAssertFalse(
            UITestAppTarget.main.shouldTerminate(
                bundleIdentifier: "com.crispyvibe.app",
                executablePath: UITestAppTarget.installedProductionExecutablePath
            )
        )
        XCTAssertFalse(
            UITestAppTarget.main.shouldTerminate(
                bundleIdentifier: "com.crispyvibe.app",
                executablePath: "/tmp/DerivedData/Build/Products/Debug/Crispy.app/Contents/MacOS/Crispy"
            )
        )
        XCTAssertTrue(
            UITestAppTarget.local.shouldTerminate(
                bundleIdentifier: "com.crispyvibe.app.local",
                executablePath: "/tmp/DerivedData/Build/Products/DebugLocal/CrispyLocal.app/Contents/MacOS/CrispyLocal"
            )
        )
    }

    func testSidebarDividerReleaseOutsideWindowKeepsAppResponsive() throws {
        guard UITestAppTarget.current == .local else {
            throw XCTSkip("NativeSplitView regression runs only against CrispyLocal.app.")
        }
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        XCTAssertTrue(openDetailedVibeSpaceView(in: app, timeout: 12))

        let split = identifiedElement(in: app, identifier: "app.sidebar.split")
        let sidebar = identifiedElement(in: app, identifier: "vibespace.sidebar.files")
        XCTAssertTrue(split.waitForExistence(timeout: 8))
        XCTAssertTrue(sidebar.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(split.frame.width, 0)

        let configuredIterations = Int(
            ProcessInfo.processInfo.environment["CRISPYVIBES_SPLIT_DRAG_STRESS_ITERATIONS"] ?? "1"
        ) ?? 1
        let iterations = min(max(configuredIterations, 1), 20)
        for _ in 0..<iterations {
            let dividerOffset = min(
                max((sidebar.frame.maxX - split.frame.minX) / split.frame.width, 0.05),
                0.95
            )
            let divider = split.coordinate(
                withNormalizedOffset: CGVector(dx: dividerOffset, dy: 0.5)
            )
            let outsideWindow = app.coordinate(
                withNormalizedOffset: CGVector(dx: 1.1, dy: 0.5)
            )
            divider.press(forDuration: 0.1, thenDragTo: outsideWindow)
        }

        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(
            identifiedElement(in: app, identifier: "vibespace.terminal-only")
                .waitForExistence(timeout: 8),
            "The app should accept navigation immediately after an interrupted divider drag."
        )

        app.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(
            identifiedElement(in: app, identifier: "vibespace.sidebar.files")
                .waitForExistence(timeout: 8),
            "The detailed canvas should remain responsive after returning from Terminal Board."
        )
    }
}
