import AppKit
@testable import CrispyVibes
import WebKit
import XCTest

@MainActor
final class CodeEditorCommentBridgeStabilityTests: XCTestCase {
    func testRepeatedRichSurfaceRegistrationDoesNotRepublishGeometry() {
        let bridge = CodeEditorCommentBridge()
        let webView = WKWebView(frame: .zero)

        bridge.observeRichMode(webView: webView)
        let firstTick = bridge.geometryTick
        bridge.observeRichMode(webView: webView)

        XCTAssertEqual(firstTick, 1)
        XCTAssertEqual(bridge.geometryTick, firstTick)
    }

    func testRepeatedTextSurfaceRegistrationDoesNotRepublishGeometry() {
        let bridge = CodeEditorCommentBridge()
        let scrollView = NSScrollView(frame: .zero)
        let textView = NSTextView(frame: .zero)

        bridge.observe(scrollView: scrollView, textView: textView)
        let firstTick = bridge.geometryTick
        bridge.observe(scrollView: scrollView, textView: textView)

        XCTAssertEqual(firstTick, 1)
        XCTAssertEqual(bridge.geometryTick, firstTick)
    }

    func testNativeTextFactoryInstallsHiddenLineNumberRuler() throws {
        let scrollView = ContentViewerDropAwareTextView.scrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let ruler = try XCTUnwrap(scrollView.verticalRulerView as? CodeEditorLineNumberRulerView)

        XCTAssertFalse(scrollView.hasVerticalRuler)
        XCTAssertFalse(scrollView.rulersVisible)
        XCTAssertEqual(CodeEditorLineNumberRulerView.logicalLineStarts(in: ""), [0])
        XCTAssertEqual(CodeEditorLineNumberRulerView.logicalLineStarts(in: "a\nb\n"), [0, 2, 4])

        let small = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let large = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .regular)
        XCTAssertGreaterThan(
            CodeEditorLineNumberRulerView.requiredThickness(lineCount: 1_000, font: small),
            CodeEditorLineNumberRulerView.requiredThickness(lineCount: 999, font: small)
        )
        XCTAssertGreaterThan(
            CodeEditorLineNumberRulerView.requiredThickness(lineCount: 999, font: large),
            CodeEditorLineNumberRulerView.requiredThickness(lineCount: 999, font: small)
        )

        textView.string = "one\ntwo"
        ruler.update(
            isVisible: true,
            editorFont: large,
            backgroundColor: .black,
            numberColor: .secondaryLabelColor,
            activeNumberColor: .systemBlue,
            dividerColor: .separatorColor
        )
        XCTAssertTrue(scrollView.hasVerticalRuler)
        XCTAssertTrue(scrollView.rulersVisible)

        ruler.update(
            isVisible: false,
            editorFont: small,
            backgroundColor: .white,
            numberColor: .secondaryLabelColor,
            activeNumberColor: .systemBlue,
            dividerColor: .separatorColor
        )
        XCTAssertFalse(scrollView.hasVerticalRuler)
        XCTAssertFalse(scrollView.rulersVisible)
    }

    func testCommentGutterUsesReservedRulerLaneWhenVisible() throws {
        let bridge = CodeEditorCommentBridge()
        let scrollView = ContentViewerDropAwareTextView.scrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let ruler = try XCTUnwrap(scrollView.verticalRulerView as? CodeEditorLineNumberRulerView)
        bridge.observe(scrollView: scrollView, textView: textView)

        XCTAssertEqual(bridge.commentGutterCenterX, 8)
        ruler.update(
            isVisible: true,
            editorFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
            backgroundColor: .black,
            numberColor: .secondaryLabelColor,
            activeNumberColor: .systemBlue,
            dividerColor: .separatorColor
        )
        XCTAssertEqual(
            bridge.commentGutterCenterX,
            CodeEditorLineNumberRulerView.commentLaneWidth / 2
        )
    }

    func testViewportRectsApplyClipFrameAndScrollOffsetExactlyOnce() throws {
        let bridge = CodeEditorCommentBridge()
        let scrollView = ContentViewerDropAwareTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 600)
        textView.string = "alpha beta\ngamma delta\nthird line"
        bridge.observe(scrollView: scrollView, textView: textView)
        scrollView.tile()
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }

        let direct = try XCTUnwrap(
            bridge.rects(startLine: 2, startColumn: 1, endLine: 2, endColumn: 6).first
        )
        let viewport = try XCTUnwrap(
            bridge.viewportRects(startLine: 2, startColumn: 1, endLine: 2, endColumn: 6).first
        )
        XCTAssertEqual(viewport.minX - direct.minX, scrollView.contentView.frame.minX, accuracy: 0.01)
        XCTAssertEqual(viewport.minY - direct.minY, scrollView.contentView.frame.minY, accuracy: 0.01)

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 10))
        let scrolled = try XCTUnwrap(
            bridge.viewportRects(startLine: 2, startColumn: 1, endLine: 2, endColumn: 6).first
        )
        XCTAssertEqual(scrolled.minY, viewport.minY - 10, accuracy: 0.01)
    }
}
