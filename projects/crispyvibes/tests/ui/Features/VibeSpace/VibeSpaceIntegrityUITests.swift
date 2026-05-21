import Foundation
import XCTest

/// UI tests for REQ-P10-SIGN-001 through SIGN-006
final class VibeSpaceIntegrityUITests: CrispyVibesUIBaseTestCase {

    private func launchAndWaitForPersistence(projectCount: Int) throws -> XCUIApplication {
        let fixture = try makeFixture(projectCount: projectCount)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()
        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    private func findVibeSpaceDirectories() -> [URL] {
        let vibespacesDir = appUnderTestVibeSpacesURL()
        return ((try? FileManager.default.contentsOfDirectory(
            at: vibespacesDir, includingPropertiesForKeys: nil
        )) ?? []).filter { UUID(uuidString: $0.lastPathComponent) != nil }
    }

    // REQ-P10-SIGN-001: vibespace.json has payload + signature
    func testVibeSpaceConfigFileIsSigned() throws {
        _ = try launchAndWaitForPersistence(projectCount: 1)

        let dirs = findVibeSpaceDirectories()
        XCTAssertFalse(dirs.isEmpty, "Need vibespace directories")

        var foundSigned = false
        for dir in dirs {
            let configURL = dir.appendingPathComponent("vibespace.json")
            guard let data = try? Data(contentsOf: configURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if json["payload"] is String && json["signature"] is String {
                foundSigned = true
                // Verify signature is a hex string of expected length (SHA256 = 64 hex chars)
                let sig = json["signature"] as! String
                XCTAssertEqual(sig.count, 64, "HMAC-SHA256 signature should be 64 hex chars")
                break
            }
        }
        XCTAssertTrue(foundSigned, "vibespace.json must have payload and signature fields")
    }

    // REQ-P10-SIGN-001: project config files are signed
    func testProjectConfigFilesAreSigned() throws {
        _ = try launchAndWaitForPersistence(projectCount: 1)

        let dirs = findVibeSpaceDirectories()
        XCTAssertFalse(dirs.isEmpty, "Need vibespace directories")

        var foundSigned = false
        for dir in dirs {
            let projectsDir = dir.appendingPathComponent("projects", isDirectory: true)
            let files = ((try? FileManager.default.contentsOfDirectory(
                at: projectsDir, includingPropertiesForKeys: nil
            )) ?? []).filter { $0.pathExtension == "json" }

            for file in files {
                guard let data = try? Data(contentsOf: file),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                if json["payload"] is String && json["signature"] is String {
                    foundSigned = true
                    break
                }
            }
            if foundSigned { break }
        }
        XCTAssertTrue(foundSigned, "Project config files must have payload and signature fields")
    }

    // REQ-P10-SIGN-006: layout.json is NOT signed
    func testLayoutFileIsNotSigned() throws {
        let app = try launchAndWaitForPersistence(projectCount: 1)

        // Toggle views to trigger layout write
        app.typeKey("t", modifierFlags: .command)
        let boardCanvas = identifiedElement(in: app, identifier: "vibespace.terminal-only")
        XCTAssertTrue(boardCanvas.waitForExistence(timeout: 10))
        app.typeKey("d", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 2)

        let dirs = findVibeSpaceDirectories()
        for dir in dirs {
            let layoutURL = dir.appendingPathComponent("layout.json")
            guard let data = try? Data(contentsOf: layoutURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            XCTAssertNil(json["payload"], "layout.json must not be signed")
            XCTAssertNil(json["signature"], "layout.json must not be signed")
            return
        }
        // Layout file might not exist if no layout changes — acceptable
    }

    // REQ-P10-SIGN-003: No tamper alert on clean vibespace
    func testCleanVibeSpaceLoadsWithoutTamperAlert() throws {
        let app = try launchAndWaitForPersistence(projectCount: 1)

        XCTAssertFalse(app.staticTexts["VibeSpace Configuration Modified"].exists,
            "Clean vibespace should not show tamper alert")
        _ = app // keep reference
    }
}
