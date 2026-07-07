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
}
