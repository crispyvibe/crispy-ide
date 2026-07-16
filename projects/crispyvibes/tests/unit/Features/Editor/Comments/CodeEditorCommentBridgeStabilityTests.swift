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
}
