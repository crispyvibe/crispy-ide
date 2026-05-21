import AppKit
import WebKit

/// Renders mermaid diagram source into NSImage using a hidden WKWebView.
/// Singleton — one shared webview handles all render requests sequentially.
@MainActor
final class MermaidRenderer {
    static let shared = MermaidRenderer()

    private var webView: WKWebView?
    private var pendingRequests: [(source: String, isDark: Bool, continuation: CheckedContinuation<NSImage?, Never>)] = []
    private var isRendering = false
    private var isReady = false

    private init() {
        setupWebView()
    }

    func render(source: String, isDark: Bool = true) async -> NSImage? {
        await withCheckedContinuation { continuation in
            pendingRequests.append((source: source, isDark: isDark, continuation: continuation))
            processNext()
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        wv.navigationDelegate = NavigationHandler.shared
        wv.setValue(false, forKey: "drawsBackground")
        self.webView = wv

        guard let mermaidURL = Bundle.main.url(forResource: "mermaid.min", withExtension: "js") else { return }
        let mermaidPath = mermaidURL.absoluteString

        let html = """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
        body{margin:0;padding:16px;background:transparent;}
        .mermaid svg{background:transparent !important;}
        </style>
        <script src="\(mermaidPath)"></script>
        </head><body><pre id="container"></pre></body></html>
        """
        wv.loadHTMLString(html, baseURL: mermaidURL.deletingLastPathComponent())
    }

    private func processNext() {
        guard !isRendering, !pendingRequests.isEmpty else { return }
        guard isReady, let webView else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.processNext()
            }
            return
        }
        isRendering = true
        let request = pendingRequests.removeFirst()

        let js = """
        mermaid.initialize({
            startOnLoad:false,
            theme: isDark ? 'dark' : 'default',
            securityLevel:'loose',
            themeVariables: isDark ? {
                background:'transparent',
                primaryColor:'#2d333b',
                primaryTextColor:'#e6edf3',
                primaryBorderColor:'#444c56',
                lineColor:'#768390',
                secondaryColor:'#2d333b',
                tertiaryColor:'#2d333b'
            } : {
                background:'transparent',
                primaryColor:'#f0f4f8',
                primaryTextColor:'#1f2328',
                primaryBorderColor:'#d0d7de',
                lineColor:'#656d76',
                secondaryColor:'#f0f4f8',
                tertiaryColor:'#f0f4f8'
            }
        });
        var el=document.getElementById('container');
        el.innerHTML='';
        el.removeAttribute('data-processed');
        el.textContent=src;
        el.className='mermaid';
        return mermaid.run({nodes:[el]}).then(function(){
            var svg=el.querySelector('svg');
            if(!svg) return JSON.stringify({w:0,h:0});
            var r=svg.getBoundingClientRect();
            return JSON.stringify({w:r.width,h:r.height});
        });
        """

        webView.callAsyncJavaScript(js, arguments: ["src": request.source, "isDark": request.isDark], in: nil, in: .page) { [weak self] result in
            guard let self else {
                request.continuation.resume(returning: nil)
                return
            }
            guard case .success(let value) = result,
                  let jsonStr = value as? String,
                  let data = jsonStr.data(using: .utf8),
                  let size = try? JSONDecoder().decode(DiagramSize.self, from: data),
                  size.w > 0, size.h > 0 else {
                request.continuation.resume(returning: nil)
                self.isRendering = false
                self.processNext()
                return
            }

            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: size.w + 32, height: size.h + 32)
            config.snapshotWidth = NSNumber(value: Int(size.w + 32))

            webView.takeSnapshot(with: config) { image, _ in
                request.continuation.resume(returning: image)
                self.isRendering = false
                self.processNext()
            }
        }
    }

    fileprivate func markReady() {
        isReady = true
        processNext()
    }
}

private struct DiagramSize: Decodable {
    let w: CGFloat
    let h: CGFloat
}

private class NavigationHandler: NSObject, WKNavigationDelegate {
    static let shared = NavigationHandler()
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            MermaidRenderer.shared.markReady()
        }
    }
}
