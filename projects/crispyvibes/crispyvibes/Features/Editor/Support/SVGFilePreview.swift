import SwiftUI
import WebKit

struct SVGFilePreview: NSViewRepresentable {
    let fileURL: URL

    final class Coordinator: NSObject {
        var lastLoadedPath: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = CrispyVibesNoContextMenuWebView(frame: .zero, configuration: configuration)
        webView.setAccessibilityIdentifier("editor.preview.image.svg")
        loadSVGIfNeeded(into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        loadSVGIfNeeded(into: nsView, coordinator: context.coordinator)
    }

    private func loadSVGIfNeeded(into webView: WKWebView, coordinator: Coordinator) {
        guard coordinator.lastLoadedPath != fileURL.path else { return }
        coordinator.lastLoadedPath = fileURL.path
        webView.loadFileURL(
            fileURL,
            allowingReadAccessTo: fileURL.deletingLastPathComponent()
        )
    }
}
