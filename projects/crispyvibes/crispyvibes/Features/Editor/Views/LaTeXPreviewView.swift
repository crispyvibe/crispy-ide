import AppKit
import Foundation
import OSLog
import SwiftUI
import WebKit

// MARK: - LaTeXPreviewView

/// Offline LaTeX WYSIWYG editor. Hosts the vendored KaTeX runtime
/// (`Resources/LaTeXRuntime`) in a `WKWebView` loaded over `file://` and pushes
/// the document source in for rendering into a contenteditable surface. Prose,
/// headings and lists are edited in place; math is rendered by KaTeX and edited
/// through a popup. Edits round-trip back to LaTeX (`onEdit`), preserving the
/// preamble and any unmodeled environment verbatim — so editing never destroys
/// source we can't represent. Mirrors the markdown rich editor's pattern.
struct LaTeXPreviewView: NSViewRepresentable {
    let content: String
    var isBufferLoading: Bool = false
    /// Carries the full updated document source back to the buffer whenever the
    /// rendered surface is edited (typing, formatting, or in-place math edits).
    var onEdit: ((String) -> Void)? = nil
    /// Toolbar formatting command (bold/italic/headings/lists/code) applied to
    /// the current selection. Identity-guarded so it fires once per request.
    var commandRequest: EditorCommandRequest? = nil
    /// Snippet to insert at the caret (math palette). Identity-guarded.
    var insertionRequest: EditorInsertionRequest? = nil
    var onInsertionConsumed: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "latexReady")
        contentController.add(context.coordinator, name: "latexChanged")
        contentController.add(context.coordinator, name: "latexLog")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityLabel(AppStrings.LaTeX.previewAccessibilityLabel)
        #if DEBUG
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        #endif
        context.coordinator.attach(webView: webView)

        if let indexURL = Self.runtimeIndexURL {
            // Grant read access to the whole runtime directory so KaTeX's CSS,
            // JS, and the `fonts/` subtree all load over file://.
            webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(Self.runtimeUnavailableHTML, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncContentIfNeeded()
        context.coordinator.syncThemeIfNeeded()
        context.coordinator.applyCommandIfNeeded()
        context.coordinator.applyInsertionIfNeeded()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "latexReady")
        controller.removeScriptMessageHandler(forName: "latexChanged")
        controller.removeScriptMessageHandler(forName: "latexLog")
    }

    /// Bundled `LaTeXRuntime/index.html` (folder reference). `nil` if the
    /// vendored runtime is missing from the build.
    static var runtimeIndexURL: URL? {
        Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "LaTeXRuntime")
    }

    private static var runtimeUnavailableHTML: String {
        """
        <html><body style="margin:0;font:13px -apple-system;display:flex;align-items:center;justify-content:center;height:100%;color:#888;background:transparent">
        <p>\(AppStrings.LaTeX.runtimeUnavailable)</p>
        </body></html>
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: LaTeXPreviewView
        private(set) weak var webView: WKWebView?
        private var isReady = false
        private var lastInjectedContent: String?
        private var lastInjectedTheme = ""
        private var lastHandledCommandID: UUID?
        private var lastInsertionID: UUID?
        private let logger = Logger(subsystem: "com.crispyvibe.app", category: "latex.preview")

        init(parent: LaTeXPreviewView) { self.parent = parent }

        func attach(webView: WKWebView) { self.webView = webView }

        func syncContentIfNeeded(force: Bool = false) {
            guard isReady, let webView, !parent.isBufferLoading else { return }
            guard force || parent.content != lastInjectedContent else { return }
            lastInjectedContent = parent.content
            webView.evaluateJavaScript("window.crispyvibesSetLatex(\(Self.jsString(parent.content)));")
        }

        func syncThemeIfNeeded(force: Bool = false) {
            guard isReady, let webView else { return }
            let theme = parent.colorScheme == .dark ? "dark" : "light"
            guard force || theme != lastInjectedTheme else { return }
            lastInjectedTheme = theme
            webView.evaluateJavaScript("window.crispyvibesSetTheme(\(Self.jsString(theme)));")
        }

        /// Apply a toolbar formatting command to the current selection once.
        func applyCommandIfNeeded() {
            guard isReady, let webView, let request = parent.commandRequest else { return }
            guard request.id != lastHandledCommandID else { return }
            lastHandledCommandID = request.id
            webView.evaluateJavaScript("window.crispyvibesApplyCommand(\(Self.jsString(request.command.rawValue)));")
        }

        /// Insert a snippet at the caret once (math palette).
        func applyInsertionIfNeeded() {
            guard isReady, let webView, let request = parent.insertionRequest else { return }
            guard request.id != lastInsertionID else { return }
            lastInsertionID = request.id
            webView.evaluateJavaScript("window.crispyvibesInsertMath(\(Self.jsString(request.text)));")
            parent.onInsertionConsumed?()
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "latexReady":
                isReady = true
                syncThemeIfNeeded(force: true)
                syncContentIfNeeded(force: true)
                applyCommandIfNeeded()
                applyInsertionIfNeeded()
            case "latexChanged":
                guard let source = message.body as? String, source != parent.content else { return }
                // Mark this as the last-injected content so the buffer update we
                // trigger doesn't bounce back as a re-injection that would rebuild
                // the DOM and reset the caret while the user is typing.
                lastInjectedContent = source
                parent.onEdit?(source)
            case "latexLog":
                logger.debug("katex: \(String(describing: message.body), privacy: .public)")
            default:
                break
            }
        }

        // MARK: WKNavigationDelegate — confine to the local file runtime.

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // The bundled runtime loads over file://; allow only that and the
            // initial about:blank. External links open in the system browser.
            if target.isFileURL || target.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(target)
            }
            decisionHandler(.cancel)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            isReady = false
            lastInjectedContent = nil
            lastInjectedTheme = ""
            if let indexURL = LaTeXPreviewView.runtimeIndexURL {
                webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
            }
        }

        private static func jsString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let encoded = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return encoded
        }
    }
}
