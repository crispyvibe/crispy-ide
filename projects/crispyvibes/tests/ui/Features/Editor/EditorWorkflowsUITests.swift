import Foundation
import XCTest

final class EditorWorkflowsUITests: CrispyVibesUIBaseTestCase {
    func testDraggingExplorerFileOntoCodeEditorBodyCreatesSplitAndClearsOverlay() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        XCTAssertTrue(doubleTapExplorerFile(named: "app.swift", in: app))

        let dropSurface = identifiedElement(in: app, identifier: "content-viewer.drop-surface")
        XCTAssertTrue(dropSurface.waitForExistence(timeout: 8))

        let scriptFile = explorerFileCell(named: "script.js", in: app)
        XCTAssertTrue(scriptFile.waitForExistence(timeout: 8))
        let source = scriptFile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = dropSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        source.press(forDuration: 0.6, thenDragTo: target)

        XCTAssertTrue(identifiedElement(in: app, identifier: "content-viewer.state.split").waitForExistence(timeout: 8))
        XCTAssertTrue(waitForCondition(timeout: 4) {
            contentViewerDropOverlay(in: app).count == 0
        })

        XCTAssertFalse(identifiedElement(in: app, identifier: "content-viewer.state.single").exists)
        XCTAssertTrue(identifiedElement(in: app, identifier: "content-viewer.state.split").exists)
        XCTAssertEqual(contentViewerDropOverlay(in: app).count, 0)
    }

    func testSelectingSwiftFileUsesCodeEditorRoute() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))
        XCTAssertTrue(doubleTapExplorerFile(named: "app.swift", in: app))

        XCTAssertTrue(
            identifiedElement(in: app, identifier: "editor.code.swift")
                .waitForExistence(timeout: 10)
        )
    }

    func testSelectingAdditionalLanguageFilesRoutesToCodeEditors() throws {
        let fixture = try makeFixture(projectCount: 1)
        fixtureRoot = fixture.root
        let app = makeApplication(fixture: fixture)
        app.launch()

        XCTAssertTrue(waitForFocusedProjectShell(in: app, index: 1, timeout: 20))

        XCTAssertTrue(doubleTapExplorerFile(named: "script.js", in: app))
        XCTAssertTrue(identifiedElement(in: app, identifier: "editor.code.javascript").waitForExistence(timeout: 10))

        XCTAssertTrue(doubleTapExplorerFile(named: "query.sql", in: app))
        XCTAssertTrue(identifiedElement(in: app, identifier: "editor.code.sql").waitForExistence(timeout: 10))

        XCTAssertTrue(doubleTapExplorerFile(named: "analysis.r", in: app))
        XCTAssertTrue(identifiedElement(in: app, identifier: "editor.code.r").waitForExistence(timeout: 10))
    }

    @discardableResult
    private func tapElementWithRetry(
        _ element: XCUIElement,
        attempts: Int = 3,
        doubleTap: Bool = false
    ) -> Bool {
        for _ in 0..<attempts {
            guard element.waitForExistence(timeout: 1) else { continue }
            if element.isHittable {
                if doubleTap {
                    element.doubleTap()
                } else {
                    element.tap()
                }
                return true
            }
            let center = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            if doubleTap {
                center.doubleTap()
            } else {
                center.tap()
            }
            return true
        }
        return false
    }

    @discardableResult
    private func doubleTapExplorerFile(named fileName: String, in app: XCUIApplication) -> Bool {
        for _ in 0..<3 {
            let fileCell = explorerFileCell(named: fileName, in: app)
            guard fileCell.waitForExistence(timeout: 1) else { continue }
            if fileCell.isHittable {
                fileCell.doubleTap()
            } else {
                fileCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
            }
            return true
        }
        return false
    }

    private func explorerFileCell(named fileName: String, in app: XCUIApplication) -> XCUIElement {
        let fileList = identifiedElement(in: app, identifier: "explorer.file-list")
        if fileList.exists {
            return fileList
                .descendants(matching: .staticText)
                .matching(NSPredicate(format: "label == %@", fileName))
                .firstMatch
        }
        return app.staticTexts[fileName].firstMatch
    }

    private func contentViewerDropOverlay(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "content-viewer.drop-overlay")
    }

    private func openMarkdownDialog(
        commandButton: XCUIElement,
        dialogElement: XCUIElement,
        dialogTitle: XCUIElement
    ) -> Bool {
        for _ in 0..<4 {
            if dialogElement.exists || dialogTitle.exists {
                return true
            }
            guard tapElementWithRetry(commandButton) else { continue }
            let didOpenDialog = waitForCondition(timeout: 1.5) {
                dialogElement.exists || dialogTitle.exists
            }
            if didOpenDialog {
                return true
            }
        }
        return dialogElement.exists || dialogTitle.exists
    }

    private func dismissMarkdownDialog(
        in app: XCUIApplication,
        dialogElement: XCUIElement,
        dialogTitle: XCUIElement,
        cancelByID: XCUIElement,
        cancelByLabel: XCUIElement
    ) -> Bool {
        if cancelByID.exists {
            _ = tapElementWithRetry(cancelByID)
        } else if cancelByLabel.exists {
            _ = tapElementWithRetry(cancelByLabel)
        } else {
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        }
        return waitForCondition(timeout: 4) {
            !dialogElement.exists && !dialogTitle.exists
        }
    }
}
