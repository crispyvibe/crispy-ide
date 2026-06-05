import Foundation
import OSLog
import WebKit

/// F052: serves the vendored offline Excalidraw runtime to the whiteboard
/// `WKWebView` over a private `app-excalidraw://local/` scheme. Everything the
/// canvas loads (the UMD bundle, React, fonts, locale chunks) is read from
/// `ExcalidrawRuntime/` inside the app bundle — the handler refuses any path
/// that escapes that directory and never touches the network, so the editor is
/// provably offline. This avoids `file://`, under which Excalidraw's `fetch`ed
/// locale/asset chunks are blocked by WebKit.
///
/// Thread-safety: WebKit invokes the `WKURLSchemeHandler` methods on the main
/// thread, and the only stored state (`rootURL`) is an immutable `let`, so no
/// additional synchronization is required. It is not annotated `@MainActor`
/// because `WKURLSchemeHandler` requirements are not main-actor isolated.
final class ExcalidrawSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "app-excalidraw"
    static let host = "local"

    /// Symlink-resolved runtime root; every served file must remain inside it.
    private let rootURL: URL
    private let logger = Logger(subsystem: "com.crispyvibe.app", category: "whiteboard.scheme")

    private init(rootURL: URL) {
        self.rootURL = rootURL
        super.init()
    }

    /// Returns nil if the runtime folder isn't present in the bundle (build misconfig).
    static func make() -> ExcalidrawSchemeHandler? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let runtime = resourceURL.appendingPathComponent("ExcalidrawRuntime", isDirectory: true)
        guard FileManager.default.fileExists(atPath: runtime.path) else { return nil }
        // Resolve symlinks so the containment check below can't be defeated by a
        // symlink inside the runtime folder pointing elsewhere.
        return ExcalidrawSchemeHandler(rootURL: runtime.resolvingSymlinksInPath())
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(Self.failure("missing url"))
            return
        }

        // Map `app-excalidraw://local/<path>` → `<runtime>/<path>`; default to index.html.
        var relativePath = url.path
        if relativePath.hasPrefix("/") { relativePath.removeFirst() }
        if relativePath.isEmpty { relativePath = "index.html" }

        // Resolve symlinks before the containment comparison so a symlinked file
        // can't escape the runtime root.
        let resolved = rootURL.appendingPathComponent(relativePath).resolvingSymlinksInPath()
        let rootPath = rootURL.path

        guard resolved.path == rootPath || resolved.path.hasPrefix(rootPath + "/") else {
            logger.error("blocked path traversal: \(relativePath, privacy: .public)")
            urlSchemeTask.didFailWithError(Self.failure("forbidden"))
            return
        }

        guard let data = try? Data(contentsOf: resolved) else {
            urlSchemeTask.didFailWithError(Self.failure("not found"))
            return
        }

        // Safe to force-unwrap: `url` is a valid URL and the header fields are
        // well-formed string literals, so `HTTPURLResponse.init` never fails here.
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: resolved.pathExtension),
                "Content-Length": String(data.count),
                "X-Content-Type-Options": "nosniff",
                "Cache-Control": "no-store"
            ]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func failure(_ reason: String) -> NSError {
        NSError(domain: "ExcalidrawSchemeHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: reason])
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }
}
