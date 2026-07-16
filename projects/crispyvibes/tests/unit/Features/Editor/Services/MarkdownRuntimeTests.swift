import WebKit
import XCTest

@MainActor
final class MarkdownRuntimeTests: XCTestCase {
    private final class MessageHandler: NSObject, WKScriptMessageHandler {
        let readyExpectation: XCTestExpectation
        var contentExpectation: XCTestExpectation?
        var receivedContent: [String] = []

        init(readyExpectation: XCTestExpectation) {
            self.readyExpectation = readyExpectation
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "editorReady":
                readyExpectation.fulfill()
            case "contentChanged":
                guard let content = message.body as? String else { return }
                receivedContent.append(content)
                contentExpectation?.fulfill()
                contentExpectation = nil
            default:
                break
            }
        }
    }

    func testMarkdownTableRoundTripsAsGFMWithoutHTML() async throws {
        let (webView, handler) = try await loadEditor()
        let contentExpectation = expectation(description: "Markdown content synchronized")
        handler.contentExpectation = contentExpectation

        let markdown = """
        | Name | Value |
        | :--- | ---: |
        | Alpha | a \\| b |
        """
        let script = """
        window.crispyvibesSetMarkdown(\(javascriptString(markdown)), "");
        document.querySelector("tbody td").textContent = "Changed";
        syncToNative();
        """
        _ = try await evaluate(script, in: webView)
        await fulfillment(of: [contentExpectation], timeout: 5)

        let synchronized = try XCTUnwrap(handler.receivedContent.last)
        XCTAssertTrue(synchronized.contains("| Name | Value |"))
        XCTAssertTrue(synchronized.contains("| :--- | ---: |"))
        XCTAssertTrue(synchronized.contains("| Changed | a \\| b |"))
        XCTAssertFalse(synchronized.localizedCaseInsensitiveContains("<table"))
        XCTAssertFalse(synchronized.localizedCaseInsensitiveContains("<td"))
    }

    func testMarkdownRerenderPreservesCaretTextOffset() async throws {
        let (webView, _) = try await loadEditor()
        let original = "Alpha beta gamma"
        let updated = "Alpha beta gamma!"
        let script = """
        window.crispyvibesSetMarkdown(\(javascriptString(original)), "");
        const textNode = document.querySelector("#editor p").firstChild;
        const selection = window.getSelection();
        const range = document.createRange();
        range.setStart(textNode, 8);
        range.collapse(true);
        selection.removeAllRanges();
        selection.addRange(range);
        window.crispyvibesSetMarkdown(\(javascriptString(updated)), "");
        const restored = window.getSelection().getRangeAt(0);
        const prefix = restored.cloneRange();
        prefix.selectNodeContents(document.getElementById("editor"));
        prefix.setEnd(restored.startContainer, restored.startOffset);
        prefix.toString().length;
        """

        let result = try await evaluate(script, in: webView)
        XCTAssertEqual((result as? NSNumber)?.intValue, 8)
    }

    func testMarkdownRerenderPreservesCaretInsideTableCell() async throws {
        let (webView, _) = try await loadEditor()
        let original = """
        | Name | Value |
        | --- | --- |
        | Alpha | beta gamma |
        """
        let updated = original + "\n| Delta | epsilon |"
        let script = """
        window.crispyvibesSetMarkdown(\(javascriptString(original)), "");
        const textNode = document.querySelector("tbody td:nth-child(2)").firstChild;
        const selection = window.getSelection();
        const range = document.createRange();
        range.setStart(textNode, 4);
        range.collapse(true);
        selection.removeAllRanges();
        selection.addRange(range);
        const expectedOffset = markdownTextSelectionSnapshot().start;
        window.crispyvibesSetMarkdown(\(javascriptString(updated)), "");
        const restoredOffset = markdownTextSelectionSnapshot().start;
        [expectedOffset, restoredOffset];
        """

        let result = try await evaluate(script, in: webView) as? [NSNumber]
        let offsets = try XCTUnwrap(result)
        XCTAssertEqual(offsets.count, 2)
        XCTAssertEqual(offsets[1], offsets[0])
    }

    private func loadEditor() async throws -> (WKWebView, MessageHandler) {
        let readyExpectation = expectation(description: "Markdown editor ready")
        let handler = MessageHandler(readyExpectation: readyExpectation)
        let contentController = WKUserContentController()
        contentController.add(handler, name: "editorReady")
        contentController.add(handler, name: "contentChanged")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let editorURL = markdownRuntimeDirectoryURL.appendingPathComponent("editor.html")
        webView.loadFileURL(editorURL, allowingReadAccessTo: markdownRuntimeDirectoryURL)
        await fulfillment(of: [readyExpectation], timeout: 10)
        return (webView, handler)
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func javascriptString(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private var markdownRuntimeDirectoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("crispyvibes/Resources/MarkdownRuntime", isDirectory: true)
    }
}
