import Foundation
import XCTest

class CrispyVibesUIBaseTestCase: XCTestCase {
    var fixtureRoot: URL?
    private var shouldCaptureAllScreenshots = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        shouldCaptureAllScreenshots = ProcessInfo.processInfo.environment["CRISPYVIBES_UI_TEST_CAPTURE_SCREENSHOTS"] == "1"
    }

    override func tearDownWithError() throws {
        let hasFailures = (testRun?.failureCount ?? 0) > 0
        let shouldCaptureCurrentState = shouldCaptureAllScreenshots || hasFailures
        if shouldCaptureCurrentState {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "UI State - \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // Shut the app down before deleting the per-test fixture tree. Leaving the
        // app alive while its vibespace roots disappear makes suite runs flaky,
        // especially with terminals and file watchers still attached to those paths.
        ensureAppUnderTestIsNotRunning()

        if let fixtureRoot {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
    }
}
