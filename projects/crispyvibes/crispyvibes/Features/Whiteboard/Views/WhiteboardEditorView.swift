import AppKit
import Foundation
import OSLog
import SwiftUI
import WebKit

// MARK: - WhiteboardEditorView

/// F052: the whiteboard editing surface. Hosts the offline Excalidraw canvas in
/// a `WKWebView` and binds the scene JSON to the document buffer: Swift pushes
/// the file contents into the canvas, the canvas posts debounced scene JSON back
/// on every edit, and that flows through `content` → `userDidEdit` → autosave —
/// exactly like `MarkupRenderedEditor` does for markdown/HTML.
struct WhiteboardEditorView: NSViewRepresentable {
    let fileURL: URL?
    var isBufferLoading: Bool = false
    @Binding var content: String
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "whiteboardReady")
        contentController.add(context.coordinator, name: "whiteboardChanged")
        contentController.add(context.coordinator, name: "whiteboardLog")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let handler = ExcalidrawSchemeHandler.make()
        if let handler {
            configuration.setURLSchemeHandler(handler, forURLScheme: ExcalidrawSchemeHandler.scheme)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityLabel(AppStrings.Whiteboard.canvasAccessibilityLabel)
        // Web inspector only in debug builds — never expose it in release.
        #if DEBUG
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        #endif
        context.coordinator.attach(webView: webView)

        if handler == nil {
            // The vendored runtime is missing (build misconfiguration). Show an
            // explanation instead of a silent blank pane (M7).
            webView.loadHTMLString(Self.runtimeUnavailableHTML, baseURL: nil)
        } else if let url = URL(string: "\(ExcalidrawSchemeHandler.scheme)://\(ExcalidrawSchemeHandler.host)/index.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncSceneIfNeeded()
        context.coordinator.syncThemeIfNeeded()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "whiteboardReady")
        controller.removeScriptMessageHandler(forName: "whiteboardChanged")
        controller.removeScriptMessageHandler(forName: "whiteboardLog")
    }

    private static let runtimeUnavailableHTML = """
    <html><body style="margin:0;font:13px -apple-system;display:flex;align-items:center;justify-content:center;height:100%;color:#888;background:transparent">
    <p>The whiteboard runtime is unavailable. Rebuild the app to restore it.</p>
    </body></html>
    """

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: WhiteboardEditorView
        private(set) weak var webView: WKWebView?
        private var isReady = false
        private var lastInjectedScene = ""
        private var lastInjectedTheme = ""
        private let logger = Logger(subsystem: "com.crispyvibe.app", category: "whiteboard.editor")

        init(parent: WhiteboardEditorView) { self.parent = parent }

        func attach(webView: WKWebView) { self.webView = webView }

        /// Push the buffer's scene JSON into the canvas. Skipped while the
        /// buffer is still loading so we never blank a scene mid-open, and
        /// echo-guarded so re-emitting our own content doesn't loop.
        func syncSceneIfNeeded(force: Bool = false) {
            guard isReady, let webView, !parent.isBufferLoading else { return }
            guard force || parent.content != lastInjectedScene else { return }
            lastInjectedScene = parent.content
            let script = "window.crispyvibesSetScene(\(Self.jsString(parent.content)));"
            webView.evaluateJavaScript(script)
        }

        func syncThemeIfNeeded(force: Bool = false) {
            guard isReady, let webView else { return }
            let theme = parent.colorScheme == .dark ? "dark" : "light"
            guard force || theme != lastInjectedTheme else { return }
            lastInjectedTheme = theme
            webView.evaluateJavaScript("window.crispyvibesSetTheme(\(Self.jsString(theme)));")
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "whiteboardReady":
                isReady = true
                syncThemeIfNeeded(force: true)
                syncSceneIfNeeded(force: true)
            case "whiteboardChanged":
                guard let json = message.body as? String, json != parent.content else { return }
                lastInjectedScene = json
                parent.content = json
            case "whiteboardLog":
                logger.debug("excalidraw: \(String(describing: message.body), privacy: .public)")
            default:
                break
            }
        }

        // MARK: WKNavigationDelegate — confine navigation to the local scheme.

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if target.scheme == ExcalidrawSchemeHandler.scheme {
                decisionHandler(.allow)
                return
            }
            // `about:`/`blob:` are needed by Excalidraw (workers, image export).
            // `data:` is deliberately NOT allowed: a `data:text/html` navigation
            // would create a null origin that doesn't inherit the page CSP.
            if ["about", "blob"].contains(target.scheme) {
                decisionHandler(.allow)
                return
            }
            // Anything else (an external link) opens in the system browser.
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(target)
            }
            decisionHandler(.cancel)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            isReady = false
            lastInjectedScene = ""
            lastInjectedTheme = ""
            if let url = URL(string: "\(ExcalidrawSchemeHandler.scheme)://\(ExcalidrawSchemeHandler.host)/index.html") {
                webView.load(URLRequest(url: url))
            }
        }

        /// Encode a Swift string as a safe JS string literal (handles quotes,
        /// newlines, unicode) — same approach as `MarkupRenderedEditor`.
        private static func jsString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let encoded = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return encoded
        }
    }
}
