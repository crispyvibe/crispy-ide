import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class TerminalFileDropSupportTests: XCTestCase {
    private final class FocusableView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    func testDroppedTextUsesRelativePathInsideCurrentDirectory() {
        let workingDirectory = URL(fileURLWithPath: "/tmp/vibespace", isDirectory: true)
        let droppedURL = workingDirectory.appendingPathComponent("src/example file.swift")

        let text = TerminalFileDropSupport.droppedText(
            for: [droppedURL],
            currentDirectory: workingDirectory
        )

        XCTAssertEqual(text, "'src/example file.swift' ")
    }

    func testDroppedTextUsesAbsolutePathOutsideCurrentDirectory() {
        let workingDirectory = URL(fileURLWithPath: "/tmp/vibespace", isDirectory: true)
        let droppedURL = URL(fileURLWithPath: "/tmp/other/example.swift")

        let text = TerminalFileDropSupport.droppedText(
            for: [droppedURL],
            currentDirectory: workingDirectory
        )

        XCTAssertEqual(text, "/tmp/other/example.swift ")
    }

    func testDroppedTextQuotesAndJoinsMultiplePaths() {
        let workingDirectory = URL(fileURLWithPath: "/tmp/vibespace", isDirectory: true)
        let firstURL = workingDirectory.appendingPathComponent("src/alpha.swift")
        let secondURL = workingDirectory.appendingPathComponent("docs/has space.md")

        let text = TerminalFileDropSupport.droppedText(
            for: [firstURL, secondURL],
            currentDirectory: workingDirectory
        )

        XCTAssertEqual(text, "src/alpha.swift 'docs/has space.md' ")
    }

    func testDroppedTextReturnsNilWhenNoURLsExist() {
        XCTAssertNil(TerminalFileDropSupport.droppedText(for: [], currentDirectory: nil))
    }

    func testShellEscapedRelativePathUsesParentTraversalForInlineInsertion() {
        let workingDirectory = URL(fileURLWithPath: "/tmp/vibespace/app", isDirectory: true)
        let targetURL = URL(fileURLWithPath: "/tmp/vibespace/shared/config.json")

        let text = TerminalFileDropSupport.shellEscapedRelativePath(
            for: targetURL,
            isDirectory: false,
            currentDirectory: workingDirectory
        )

        XCTAssertEqual(text, "../shared/config.json")
    }

    func testRequestFocusMakesDroppedTerminalFirstResponder() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let rootView = FocusableView(frame: window.contentView?.bounds ?? .zero)
        let terminalView = FocusableView(frame: rootView.bounds)

        window.contentView = rootView
        rootView.addSubview(terminalView)

        XCTAssertTrue(window.makeFirstResponder(rootView))
        XCTAssertTrue(window.firstResponder === rootView)

        TerminalFileDropSupport.requestFocus(for: terminalView)

        XCTAssertTrue(window.firstResponder === terminalView)
    }
}
