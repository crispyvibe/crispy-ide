import Foundation
import XCTest
@testable import CrispyVibes

// Regression tests for ACP chat markdown rendering. SwiftUI Text ignores
// AttributedString presentationIntent, so parseMarkdown must re-materialize
// block structure (paragraph breaks, headings, lists) and detect links against
// the FINAL rendered text, not the raw markdown.

final class ACPSelectableTextMarkdownTests: XCTestCase {

    private func rendered(_ markdown: String) -> String {
        String(ACPSelectableText.parseMarkdown(markdown).characters)
    }

    /// Paragraphs separated by blank lines must not render glued together.
    func test_paragraphBreaksSurviveRendering() {
        let out = rendered("First paragraph.\n\nSecond paragraph.")
        XCTAssertTrue(out.contains("First paragraph.\n\nSecond paragraph."),
                      "paragraph breaks must be rebuilt, got: \(out)")
    }

    /// Single newlines from agents are treated as paragraph breaks, not glue.
    func test_singleNewlineDoesNotGlueSentences() {
        let out = rendered("what \"the app\" refers to.\nThe \"app\" appears to be the web directory.")
        XCTAssertFalse(out.contains("refers to.The"), "sentences must not fuse across newlines, got: \(out)")
    }

    /// `##` headings must break onto their own line and not swallow neighbors.
    func test_headingsSeparateFromBodyText() {
        let out = rendered("keep it under ~15 lines:\n## What changed\nStuff.\n## What's verified\nMore stuff.")
        XCTAssertFalse(out.contains("lines:What changed"), "heading must not glue to the previous line, got: \(out)")
        XCTAssertFalse(out.contains("What changedWhat's verified"), "headings must not fuse together, got: \(out)")
        XCTAssertTrue(out.contains("What changed"), "heading text must survive")
    }

    /// List items get visible bullets and line breaks.
    func test_listItemsGetBulletsAndBreaks() {
        let out = rendered("Changes:\n- first item\n- second item")
        XCTAssertTrue(out.contains("• first item"), "unordered items must render a bullet, got: \(out)")
        XCTAssertFalse(out.contains("first itemsecond") || out.contains("first item second item"),
                       "list items must not fuse, got: \(out)")
    }

    /// Ordered lists keep their ordinals.
    func test_orderedListKeepsOrdinals() {
        let out = rendered("Steps:\n1. reproduce\n2. patch")
        XCTAssertTrue(out.contains("1. reproduce"), "ordered items must keep ordinals, got: \(out)")
        XCTAssertTrue(out.contains("2. patch"), "ordered items must keep ordinals, got: \(out)")
    }

    /// Links must land on the URL in the FINAL text, not at raw-markdown offsets
    /// (stripped `**` syntax used to shift every later link range left).
    func test_linkRangesAlignAfterMarkdownStripping() {
        let attributed = ACPSelectableText.parseMarkdown(
            "Some **bold emphasis** and `inline code` first, then see https://example.com/docs for more."
        )
        var linkedText = ""
        for run in attributed.runs where run.link != nil {
            linkedText += String(attributed.characters[run.range])
        }
        XCTAssertTrue(linkedText.contains("https://example.com/docs"),
                      "the link attribute must cover the URL itself, got linked text: '\(linkedText)'")
    }

    /// Plain text with no markdown passes through unharmed.
    func test_plainTextPassesThrough() {
        let out = rendered("Just a plain sentence.")
        XCTAssertEqual(out, "Just a plain sentence.")
    }

    // MARK: - F060 path links

    /// Absolute file paths (with optional :line:col) always become links.
    func test_absolutePathsBecomeLinks() {
        let attributed = ACPSelectableText.parseMarkdown("Edited /tmp/some/File.swift:42 today.")
        var links: [URL] = []
        for run in attributed.runs where run.link != nil { links.append(run.link!) }
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.scheme, "crispyvibes-file")
        XCTAssertTrue(links.first?.absoluteString.contains("line=42") ?? false)
    }

    /// Relative paths link ONLY when they resolve to a real file under the
    /// base directory — existence is the false-positive filter (F060).
    func test_relativePathsLinkOnlyWhenTheyExist() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-link-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("src"), withIntermediateDirectories: true)
        let real = dir.appendingPathComponent("src/Parser.swift")
        try "x".write(to: real, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let text = "Changed src/Parser.swift:7 but ghost/Missing.swift stays, and/or nothing."
        let attributed = ACPSelectableText.parseMarkdown(text, baseDirectory: dir)
        var linked: [String] = []
        for run in attributed.runs where run.link != nil {
            linked.append(String(attributed.characters[run.range]))
        }
        XCTAssertEqual(linked, ["src/Parser.swift:7"],
                       "existing relative path links; missing path and prose like and/or must not")
    }

    /// Without a base directory, relative paths never link (no resolution root).
    func test_relativePathsIgnoredWithoutBaseDirectory() {
        let attributed = ACPSelectableText.parseMarkdown("See src/Parser.swift here.")
        for run in attributed.runs {
            XCTAssertNil(run.link)
        }
    }
}
