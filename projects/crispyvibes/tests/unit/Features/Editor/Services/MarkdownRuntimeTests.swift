import WebKit
import XCTest

@MainActor
final class MarkdownRuntimeTests: XCTestCase {
    private final class MessageHandler: NSObject, WKScriptMessageHandler {
        let readyExpectation: XCTestExpectation
        var contentExpectation: XCTestExpectation?
        var linkExpectation: XCTestExpectation?
        var receivedContent: [String] = []
        var receivedLinkActions: [[String: Any]] = []
        var eventOrder: [String] = []

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
                eventOrder.append("contentChanged")
                contentExpectation?.fulfill()
                contentExpectation = nil
            case "markdownLinkAction":
                guard let action = message.body as? [String: Any] else { return }
                receivedLinkActions.append(action)
                eventOrder.append("markdownLinkAction")
                linkExpectation?.fulfill()
                linkExpectation = nil
            default:
                break
            }
        }
    }

    func testCurrencyDollarAmountsRemainLiteralProse() async throws {
        let (webView, handler) = try await loadEditor()
        let markdown = #"**Objective 3: Modernize AA's EDP** \[$8M ARR by 2028, 2027 in year $2M\]"#
        let script = """
        window.crispyvibesSetMarkdown(\(javascriptString(markdown)), "");
        """
        _ = try await evaluate(script, in: webView)

        let renderedText = try await evaluate(
            "document.getElementById('editor').textContent.trim()",
            in: webView
        ) as? String
        let mathCount = try await evaluate(
            "document.querySelectorAll('#editor .katex').length",
            in: webView
        ) as? NSNumber
        let currencyCount = try await evaluate(
            "document.querySelectorAll('#editor .crispyvibes-literal-currency').length",
            in: webView
        ) as? NSNumber
        let currenciesAreEditable = try await evaluate(
            "Array.from(document.querySelectorAll('#editor .crispyvibes-literal-currency'))"
                + ".every((element) => element.isContentEditable)",
            in: webView
        ) as? NSNumber
        let roundTrip = try await evaluate(
            "turndownService.turndown(document.getElementById('editor'))",
            in: webView
        ) as? String

        XCTAssertEqual(
            renderedText,
            "Objective 3: Modernize AA's EDP [$8M ARR by 2028, 2027 in year $2M]"
        )
        XCTAssertEqual(mathCount?.intValue, 0)
        XCTAssertEqual(currencyCount?.intValue, 2)
        XCTAssertEqual(currenciesAreEditable?.boolValue, true)
        XCTAssertTrue(roundTrip?.contains("$8M ARR by 2028, 2027 in year $2M") == true)

        let contentExpectation = expectation(description: "Edited currency synchronized")
        handler.contentExpectation = contentExpectation
        _ = try await evaluate(
            "document.querySelector('#editor .crispyvibes-literal-currency').textContent = '$9M';"
                + " syncToNative();",
            in: webView
        )
        await fulfillment(of: [contentExpectation], timeout: 5)

        let synchronized = try XCTUnwrap(handler.receivedContent.last)
        XCTAssertTrue(synchronized.contains("$9M ARR by 2028, 2027 in year $2M"))
    }

    func testSymbolicSingleDollarInlineMathStillRenders() async throws {
        let (webView, _) = try await loadEditor()
        let markdown = "Energy is $E = mc^2$."
        let script = """
        window.crispyvibesSetMarkdown(\(javascriptString(markdown)), "");
        document.querySelectorAll('#editor .katex').length;
        """

        let mathCount = try await evaluate(script, in: webView) as? NSNumber
        XCTAssertEqual(mathCount?.intValue, 1)
    }

    func testExplicitNumericInlineMathRendersAndSurvivesRoundTrip() async throws {
        let (webView, _) = try await loadEditor()
        let markdown = #"Numeric math: \\(2 + 3 = 5\\)."#
        let script = """
        window.crispyvibesSetMarkdown(\(javascriptString(markdown)), "");
        const firstMathCount = document.querySelectorAll('#editor .katex').length;
        const roundTrip = turndownService.turndown(document.getElementById('editor'));
        window.crispyvibesSetMarkdown('', '');
        window.crispyvibesSetMarkdown(roundTrip, '');
        [
          firstMathCount,
          roundTrip,
          document.querySelectorAll('#editor .katex').length,
          document.querySelectorAll('#editor .crispyvibes-literal-currency').length
        ];
        """

        let result = try await evaluate(script, in: webView) as? [Any]
        let values = try XCTUnwrap(result)
        XCTAssertEqual((values[0] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(values[1] as? String, markdown)
        XCTAssertEqual((values[2] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((values[3] as? NSNumber)?.intValue, 0)
    }

    func testCommaDecimalCurrencyAmountsRemainLiteralProse() async throws {
        let (webView, _) = try await loadEditor()
        let markdown = "Totals may not add due to rounding; $16,654.65 ≠ $16,655.00."
        let script = """
        window.crispyvibesSetMarkdown(\(javascriptString(markdown)), "");
        [
          document.getElementById('editor').textContent.trim(),
          document.querySelectorAll('#editor .katex').length,
          document.querySelectorAll('#editor .crispyvibes-literal-currency').length,
          turndownService.turndown(document.getElementById('editor'))
        ];
        """

        let result = try await evaluate(script, in: webView) as? [Any]
        let values = try XCTUnwrap(result)
        XCTAssertEqual(values[0] as? String, markdown)
        XCTAssertEqual((values[1] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((values[2] as? NSNumber)?.intValue, 2)
        XCTAssertEqual(values[3] as? String, markdown)
    }

    func testNumericDisplayMathStillRenders() async throws {
        let (webView, _) = try await loadEditor()
        let markdown = "$$2 + 3 = 5$$"
        let script = """
        window.crispyvibesSetMarkdown(\(javascriptString(markdown)), "");
        [
          document.querySelectorAll('#editor .katex-display').length,
          document.querySelectorAll('#editor .crispyvibes-literal-currency').length
        ];
        """

        let result = try await evaluate(script, in: webView) as? [NSNumber]
        let counts = try XCTUnwrap(result)
        XCTAssertEqual(counts[0].intValue, 1)
        XCTAssertEqual(counts[1].intValue, 0)
    }

    func testMarkdownHeadingsReceiveStableDuplicateSafeAnchors() async throws {
        let (webView, _) = try await loadEditor()
        let markdown = """
        # Revenue & Growth
        ## Revenue & Growth
        ## Résumé / 2026
        """
        let script = """
        window.crispyvibesSetMarkdown(\(javascriptString(markdown)), "");
        Array.from(document.querySelectorAll('#editor h1, #editor h2')).map((heading) => heading.id);
        """

        let ids = try await evaluate(script, in: webView) as? [String]
        XCTAssertEqual(ids, ["revenue-growth", "revenue-growth-2", "résumé-2026"])
    }

    func testInternalMarkdownLinkNavigatesWithoutNativeAction() async throws {
        let (webView, handler) = try await loadEditor()
        let markdown = "[Jump](#target-section)\n\n## Target Section"
        let script = """
        window.crispyvibesSetMarkdown(\(javascriptString(markdown)), "");
        const link = document.querySelector('#editor a');
        link.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
        [
          document.getElementById('target-section').classList.contains('crispyvibes-link-target-flash'),
          document.getElementById('crispyvibes-link-popover') === null,
          markdownNavigationHistory.length
        ];
        """

        let result = try await evaluate(script, in: webView) as? [Any]
        let values = try XCTUnwrap(result)
        XCTAssertEqual(values[0] as? Bool, true)
        XCTAssertEqual(values[1] as? Bool, true)
        XCTAssertEqual((values[2] as? NSNumber)?.intValue, 1)
        XCTAssertTrue(handler.receivedLinkActions.isEmpty)
    }

    func testWebLinkAskPreferenceShowsPopoverAndPostsSelectedAction() async throws {
        let (webView, handler) = try await loadEditor()
        let markdown = "[Report](https://example.com/report?q=1)"
        let showScript = """
        window.crispyvibesSetWebLinkPreference('ask');
        window.crispyvibesSetMarkdown(\(javascriptString(markdown)), "");
        document.querySelector('#editor a').dispatchEvent(
          new MouseEvent('click', { bubbles: true, cancelable: true })
        );
        [
          document.getElementById('crispyvibes-link-popover') !== null,
          Array.from(document.querySelectorAll('#crispyvibes-link-popover button'))
            .map((button) => button.textContent)
        ];
        """

        let shown = try await evaluate(showScript, in: webView) as? [Any]
        let values = try XCTUnwrap(shown)
        XCTAssertEqual(values[0] as? Bool, true)
        let labels = values[1] as? [String]
        XCTAssertTrue(labels?.contains("Open in Crispy") == true)
        XCTAssertTrue(labels?.contains("Default Browser") == true)
        XCTAssertTrue(labels?.contains("Edit") == true)
        XCTAssertTrue(labels?.contains("Copy") == true)
        XCTAssertTrue(labels?.contains("Remove") == true)

        let linkExpectation = expectation(description: "Crispy link action posted")
        handler.linkExpectation = linkExpectation
        _ = try await evaluate(
            "document.querySelector('[data-link-action=\"openInCrispy\"]').click()",
            in: webView
        )
        await fulfillment(of: [linkExpectation], timeout: 5)

        let action = try XCTUnwrap(handler.receivedLinkActions.last)
        XCTAssertEqual(action["action"] as? String, "openInCrispy")
        XCTAssertEqual(action["targetKind"] as? String, "web")
        XCTAssertEqual(action["resolvedURL"] as? String, "https://example.com/report?q=1")
    }

    func testSavedWebPreferenceRoutesWithoutPopover() async throws {
        let (webView, handler) = try await loadEditor()
        let linkExpectation = expectation(description: "Default browser action posted")
        handler.linkExpectation = linkExpectation
        let markdown = "[Report](https://example.com/report)"
        let script = """
        window.crispyvibesSetWebLinkPreference('defaultBrowser');
        window.crispyvibesSetMarkdown(\(javascriptString(markdown)), "");
        document.querySelector('#editor a').dispatchEvent(
          new MouseEvent('click', { bubbles: true, cancelable: true })
        );
        document.getElementById('crispyvibes-link-popover') === null;
        """

        let hasNoPopover = try await evaluate(script, in: webView) as? Bool
        await fulfillment(of: [linkExpectation], timeout: 5)
        XCTAssertEqual(hasNoPopover, true)
        let action = try XCTUnwrap(handler.receivedLinkActions.last)
        XCTAssertEqual(action["action"] as? String, "openInDefaultBrowser")
        XCTAssertEqual(action["targetKind"] as? String, "web")
    }

    func testRelativeDocumentLinkResolvesAndPreservesFragment() async throws {
        let (webView, handler) = try await loadEditor()
        let linkExpectation = expectation(description: "Relative document action posted")
        handler.linkExpectation = linkExpectation
        let markdown = "[Setup](../guide.md#installation)"
        let baseURL = "file:///tmp/crispy-markdown-links/docs/"
        let script = """
        window.crispyvibesSetMarkdown(
          \(javascriptString(markdown)),
          \(javascriptString(baseURL))
        );
        const link = document.querySelector('#editor a');
        link.textContent = 'Setup Updated';
        link.dispatchEvent(new InputEvent('input', { bubbles: true }));
        link.dispatchEvent(
          new MouseEvent('click', { bubbles: true, cancelable: true })
        );
        """

        _ = try await evaluate(script, in: webView)
        await fulfillment(of: [linkExpectation], timeout: 5)
        XCTAssertEqual(
            Array(handler.eventOrder.prefix(2)),
            ["contentChanged", "markdownLinkAction"]
        )
        XCTAssertTrue(handler.receivedContent.last?.contains("[Setup Updated]") == true)
        let action = try XCTUnwrap(handler.receivedLinkActions.last)
        XCTAssertEqual(action["action"] as? String, "openInCrispy")
        XCTAssertEqual(action["targetKind"] as? String, "localFile")
        XCTAssertEqual(
            action["resolvedURL"] as? String,
            "file:///tmp/crispy-markdown-links/guide.md#installation"
        )
        XCTAssertEqual(action["fragment"] as? String, "installation")
    }

    func testUnsafeMarkdownLinkIsBlockedWithoutNativeAction() async throws {
        let (webView, handler) = try await loadEditor()
        let markdown = "[Danger](javascript:alert(1))"
        let script = """
        window.crispyvibesSetMarkdown(\(javascriptString(markdown)), "");
        const link = document.querySelector('#editor a');
        link.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
        [
          document.querySelector('.crispyvibes-toast')?.textContent || '',
          document.getElementById('crispyvibes-link-popover') === null
        ];
        """

        let result = try await evaluate(script, in: webView) as? [Any]
        let values = try XCTUnwrap(result)
        XCTAssertTrue((values[0] as? String)?.contains("not supported") == true)
        XCTAssertEqual(values[1] as? Bool, true)
        XCTAssertTrue(handler.receivedLinkActions.isEmpty)
    }

    func testContextMenuCanEditAndRemoveExistingMarkdownLink() async throws {
        let (webView, _) = try await loadEditor()
        let markdown = "[Guide](https://example.com/old)"
        let script = """
        window.crispyvibesSetMarkdown(\(javascriptString(markdown)), "");
        let link = document.querySelector('#editor a');
        link.dispatchEvent(new MouseEvent('contextmenu', {
          bubbles: true,
          cancelable: true,
          clientX: 20,
          clientY: 20
        }));
        document.querySelector('[data-link-action="edit"]').click();
        const input = document.getElementById('markdown-link-url-input');
        const prefilled = input.value;
        input.value = '#updated-section';
        document.querySelector('[data-accessibility-id="editor.markdown.link.apply"]').click();
        const edited = turndownService.turndown(document.getElementById('editor')).trim();

        link = document.querySelector('#editor a');
        link.dispatchEvent(new MouseEvent('contextmenu', {
          bubbles: true,
          cancelable: true,
          clientX: 20,
          clientY: 20
        }));
        document.querySelector('[data-link-action="remove"]').click();
        const removed = turndownService.turndown(document.getElementById('editor')).trim();
        [prefilled, edited, removed];
        """

        let result = try await evaluate(script, in: webView) as? [String]
        XCTAssertEqual(
            result,
            ["https://example.com/old", "[Guide](#updated-section)", "Guide"]
        )
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
        contentController.add(handler, name: "markdownLinkAction")

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
