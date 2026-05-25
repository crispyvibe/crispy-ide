import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class FileAndTerminalTabModelTests: XCTestCase {
    func testFileItemDisplayAndMarkdownDetection() {
        let markdown = FileItem(url: URL(fileURLWithPath: "/tmp/readme.MD"), isDirectory: false, children: nil)
        XCTAssertEqual(markdown.displayName, "readme.MD")
        XCTAssertTrue(markdown.isMarkdown)

        let markdownAlt = FileItem(url: URL(fileURLWithPath: "/tmp/guide.markdown"), isDirectory: false, children: nil)
        XCTAssertTrue(markdownAlt.isMarkdown)

        let folder = FileItem(url: URL(fileURLWithPath: "/tmp/folder"), isDirectory: true, children: nil)
        XCTAssertEqual(folder.displayName, "folder")
        XCTAssertFalse(folder.isMarkdown)
    }

    func testTerminalTabTitlePriority() {
        let workingDirectory = URL(fileURLWithPath: "/tmp/sample")

        let withCustom = TerminalTab(
            workingDirectory: workingDirectory,
            customName: "My Tab",
            sessionTitle: "Session"
        )
        XCTAssertEqual(withCustom.title, "My Tab")

        let withSessionTitle = TerminalTab(
            workingDirectory: workingDirectory,
            customName: "",
            sessionTitle: "Session"
        )
        XCTAssertEqual(withSessionTitle.title, "sample")

        let withDirectoryFallback = TerminalTab(
            workingDirectory: workingDirectory,
            customName: nil,
            sessionTitle: nil
        )
        XCTAssertEqual(withDirectoryFallback.title, "sample")
    }

    func testTerminalTabStatusText() {
        let running = TerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/a"), exitCode: nil)
        XCTAssertEqual(running.statusText, "Running")

        let exited = TerminalTab(workingDirectory: URL(fileURLWithPath: "/tmp/a"), exitCode: 127)
        XCTAssertEqual(exited.statusText, "Exited (127)")
    }

}
