import Combine
import Darwin
import Foundation
import OSLog
import SwiftUI
import WebKit

// MARK: - JupyterServerService

/// F049-R08: owns the lifecycle of locally-spawned Jupyter servers. One server
/// is started lazily per root directory and hosts every notebook beneath it.
/// Modeled on the `ACPTransport` managed-process pattern: Swift owns the
/// process and chrome; the embedded Notebook 7 UI owns the kernel protocol.
///
/// F049-R09: each server binds `127.0.0.1` only, requires a per-server token,
/// and that token is never written to logs.
@MainActor
final class JupyterServerService {
    /// A running server scoped to a root directory.
    struct Server {
        let baseURL: URL
        let token: String
        let rootDirectory: URL
    }

    enum StartError: LocalizedError {
        case jupyterNotFound
        case noFreePort
        case readinessTimedOut
        case terminated(String)

        var errorDescription: String? {
            switch self {
            case .jupyterNotFound:
                return "Jupyter is not installed in the resolved environment."
            case .noFreePort:
                return "Could not reserve a local port for the Jupyter server."
            case .readinessTimedOut:
                return "The Jupyter server did not become ready in time."
            case .terminated(let reason):
                return "The Jupyter server exited unexpectedly. \(reason)"
            }
        }
    }

    private let logger = Logger(subsystem: "com.crispyvibe.app", category: "notebook.jupyter")
    private var servers: [String: Server] = [:]
    private var processes: [String: Process] = [:]
    private var startTasks: [String: Task<Server, Error>] = [:]
    /// One persistent web-view arbiter per notebook path, so the live notebook
    /// (DOM + kernel session + executed outputs) is shared and re-parented
    /// across surfaces (inline pane, split, spotlight) instead of reloaded.
    private var arbiters: [String: NotebookWebViewArbiter] = [:]

    /// Returns the shared web-view arbiter for a notebook, creating (and loading
    /// the web view) once per notebook path.
    func webViewArbiter(forNotebook fileURL: URL, url: URL) -> NotebookWebViewArbiter {
        let key = fileURL.standardizedFileURL.path
        if let existing = arbiters[key] { return existing }
        let arbiter = NotebookWebViewArbiter(url: url, notebookPath: key)
        arbiters[key] = arbiter
        return arbiter
    }

    /// F049-R07: whether a `jupyter` executable is resolvable on the user's PATH.
    /// Used to surface actionable messaging without spawning a process.
    func isJupyterAvailable() -> Bool {
        resolvedJupyterPath() != nil
    }

    /// Resolves the WKWebView URL for a notebook, lazily starting (and reusing)
    /// the server rooted at the notebook's directory.
    func notebookURL(for fileURL: URL) async throws -> URL {
        let root = fileURL.deletingLastPathComponent().standardizedFileURL
        let server = try await ensureServer(rootDirectory: root)
        let relativePath = fileURL.standardizedFileURL.lastPathComponent
        let encodedPath = relativePath
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath
        let encodedToken = server.token
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? server.token
        guard let url = URL(string: "notebooks/\(encodedPath)?token=\(encodedToken)", relativeTo: server.baseURL) else {
            throw StartError.terminated("Invalid notebook URL.")
        }
        return url.absoluteURL
    }

    /// F049-R08: terminate every server and kernel. Called from the app
    /// termination path so no process is leaked on quit.
    func shutdownAll() {
        startTasks.values.forEach { $0.cancel() }
        startTasks.removeAll()
        arbiters.values.forEach { $0.shutdown() }
        arbiters.removeAll()
        for process in processes.values where process.isRunning {
            process.terminate()
        }
        processes.removeAll()
        servers.removeAll()
    }

    // MARK: - Lifecycle

    private func ensureServer(rootDirectory: URL) async throws -> Server {
        let key = rootDirectory.path
        if let existing = servers[key], processes[key]?.isRunning == true {
            return existing
        }
        if let inFlight = startTasks[key] {
            return try await inFlight.value
        }

        let task = Task<Server, Error> { [weak self] in
            guard let self else { throw StartError.terminated("Service released.") }
            return try await self.startServer(rootDirectory: rootDirectory)
        }
        startTasks[key] = task
        defer { startTasks[key] = nil }

        do {
            let server = try await task.value
            servers[key] = server
            return server
        } catch {
            processes[key]?.terminate()
            processes[key] = nil
            throw error
        }
    }

    private func startServer(rootDirectory: URL) async throws -> Server {
        guard let jupyterPath = resolvedJupyterPath() else { throw StartError.jupyterNotFound }
        guard let port = Self.reserveFreePort() else { throw StartError.noFreePort }
        let token = Self.makeToken()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            jupyterPath, "notebook",
            "--no-browser",
            "--ip=127.0.0.1",
            "--port=\(port)",
            "--ServerApp.token=\(token)",
            "--ServerApp.password=",
            "--ServerApp.open_browser=False",
            "--ServerApp.root_dir=\(rootDirectory.path)",
        ]
        process.environment = CommandPathResolver.environmentWithResolvedPath()

        // Drain pipes so a full buffer never blocks the server process.
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        outPipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        errPipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }

        do {
            try process.run()
        } catch {
            throw StartError.terminated(error.localizedDescription)
        }
        processes[rootDirectory.path] = process
        // F049-R09: deliberately log without the URL/token.
        logger.info("Jupyter server starting on 127.0.0.1:\(port, privacy: .public)")

        let baseURL = URL(string: "http://127.0.0.1:\(port)/")!
        try await waitUntilReady(baseURL: baseURL, token: token, process: process)
        return Server(baseURL: baseURL, token: token, rootDirectory: rootDirectory)
    }

    private func waitUntilReady(baseURL: URL, token: String, process: Process) async throws {
        let statusURL = URL(string: "api/status?token=\(token)", relativeTo: baseURL)!
        for _ in 0..<60 {
            if !process.isRunning { throw StartError.terminated("Process exited during startup.") }
            if Task.isCancelled { throw CancellationError() }
            var request = URLRequest(url: statusURL)
            request.timeoutInterval = 2
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        throw StartError.readinessTimedOut
    }

    // MARK: - Helpers

    private func resolvedJupyterPath() -> String? {
        let fileManager = FileManager.default
        for directory in CommandPathResolver.searchPaths() {
            for name in ["jupyter", "jupyter-notebook"] {
                let candidate = (directory as NSString).appendingPathComponent(name)
                if fileManager.isExecutableFile(atPath: candidate) {
                    return name == "jupyter" ? "jupyter" : candidate
                }
            }
        }
        return nil
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Reserves an ephemeral loopback port by binding to `:0`, then releasing it
    /// for the spawned server to claim.
    private static func reserveFreePort() -> Int? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Foundation.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        var resolved = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &resolved) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0 else { return nil }
        return Int(UInt16(bigEndian: resolved.sin_port))
    }
}

// MARK: - Environment

private struct JupyterServerServiceEnvironmentKey: EnvironmentKey {
    static let defaultValue: JupyterServerService? = nil
}

extension EnvironmentValues {
    /// App-wide Jupyter server service, injected at the root. Optional so
    /// previews/tests without the service degrade gracefully.
    var jupyterServerService: JupyterServerService? {
        get { self[JupyterServerServiceEnvironmentKey.self] }
        set { self[JupyterServerServiceEnvironmentKey.self] = newValue }
    }
}

// MARK: - NotebookEditorView

/// F049-R01/R10: the dedicated notebook surface. Hosts the embedded Notebook 7
/// UI served by the local Jupyter server inside a `WKWebView`.
struct NotebookEditorView: View {
    let fileURL: URL
    @Environment(\.jupyterServerService) private var service
    /// F049: comment env provided by the surrounding content-viewer/editor.
    @Environment(\.vibespaceCommentStoreEnvironment) private var commentStore
    @Environment(\.commentsPanelEnvironment) private var commentsPanel
    @Environment(\.commentsFilePathEnvironment) private var commentsFilePath

    private enum Phase: Equatable {
        case starting
        case ready(NotebookWebViewArbiter)
        case unavailable
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.starting, .starting), (.unavailable, .unavailable): return true
            case let (.ready(a), .ready(b)): return a === b
            case let (.failed(a), .failed(b)): return a == b
            default: return false
            }
        }
    }

    @State private var phase: Phase = .starting

    var body: some View {
        Group {
            switch phase {
            case .starting:
                ProgressView(String(localized: "notebook.starting.title"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("editor.notebook.starting")
            case .ready(let arbiter):
                NotebookWebViewHost(arbiter: arbiter)
                    .accessibilityIdentifier("editor.notebook.web")
                    .onAppear { wireComments(arbiter) }
                    .onReceive(commentChanges) { _ in pushDecorations(arbiter) }
                    .onChange(of: commentsPanel?.selectedThreadID) { _, id in
                        guard let id, let store = commentStore,
                              let thread = store.threads(forFile: commentPath).first(where: { $0.id == id })
                        else { return }
                        arbiter.commentBridge.scrollAndSelect(anchor: thread.root.anchor)
                        pushDecorations(arbiter)
                    }
            case .unavailable:
                ContentUnavailableView {
                    Label(String(localized: "notebook.unavailable.title"), systemImage: "book.closed")
                } description: {
                    Text(String(localized: "notebook.unavailable.description"))
                }
                .accessibilityIdentifier("editor.notebook.unavailable")
            case .failed(let message):
                ContentUnavailableView {
                    Label(String(localized: "notebook.failed.title"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
                .accessibilityIdentifier("editor.notebook.failed")
            }
        }
        .task(id: fileURL) { await start() }
    }

    private func start() async {
        phase = .starting
        guard let service else {
            phase = .failed(String(localized: "notebook.failed.noService"))
            return
        }
        guard service.isJupyterAvailable() else {
            phase = .unavailable
            return
        }
        do {
            let url = try await service.notebookURL(for: fileURL)
            phase = .ready(service.webViewArbiter(forNotebook: fileURL, url: url))
        } catch is CancellationError {
            // View went away or file changed; leave state untouched.
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Comments (F049)

    /// The comment key: the notebook's file path (stable across sessions),
    /// not the localhost URL whose port changes each launch.
    private var commentPath: String {
        commentsFilePath ?? fileURL.standardizedFileURL.path
    }

    private var commentChanges: AnyPublisher<Void, Never> {
        commentStore?.changes.eraseToAnyPublisher() ?? Empty(completeImmediately: false).eraseToAnyPublisher()
    }

    /// Connect the in-notebook bridge to the central store + side panel.
    /// Idempotent — safe to call on every appear.
    private func wireComments(_ arbiter: NotebookWebViewArbiter) {
        let path = commentPath
        arbiter.commentBridge.onRequestAddWithBody = { [weak commentStore] anchor, body in
            guard let store = commentStore else { return }
            Task { @MainActor in
                _ = await store.add(filePath: path, anchor: anchor, body: body, surfaceKind: .file)
            }
        }
        arbiter.commentBridge.onGutterClick = { [weak commentsPanel] threadID in
            commentsPanel?.revealForReply(threadID: threadID)
        }
        arbiter.onPageLoaded = { [weak commentStore, weak commentsPanel, weak arbiter] in
            guard let arbiter, let store = commentStore else { return }
            arbiter.commentBridge.syncDecorations(
                threads: store.threads(forFile: path),
                selectedThreadID: commentsPanel?.selectedThreadID
            )
        }
        Task { @MainActor [weak commentStore] in
            guard let store = commentStore, let vsID = store.currentVibeSpaceID() else { return }
            await store.refreshFile(vibespaceID: vsID, filePath: path)
            pushDecorations(arbiter)
        }
    }

    private func pushDecorations(_ arbiter: NotebookWebViewArbiter) {
        guard let store = commentStore else { return }
        arbiter.commentBridge.syncDecorations(
            threads: store.threads(forFile: commentPath),
            selectedThreadID: commentsPanel?.selectedThreadID
        )
    }
}

/// Owns one persistent `WKWebView` for a notebook and arbitrates which mounted
/// surface (inline pane, split, spotlight) currently displays it. The live DOM
/// — including executed cell outputs and the kernel session — survives moving
/// between surfaces because the same web view is re-parented, never reloaded.
@MainActor
final class NotebookWebViewArbiter {
    let webView: WKWebView
    /// F049: in-notebook comment bridge (cell-id anchoring). Lives with the
    /// persistent web view so decorations survive surface moves + reloads.
    let commentBridge = NotebookCommentBridge()
    /// Called after each finished load (initial + reload) so the view can
    /// re-push comment decorations once the bundle is (re)injected.
    var onPageLoaded: (() -> Void)?
    private let navigationDelegate: NotebookNavigationDelegate
    private let notebookPath: String
    private let hosts = NSHashTable<NotebookHostContainerView>.weakObjects()
    private var nextSeq = 0
    private var fileChangeObserver: (any NSObjectProtocol)?
    private var reloadTask: Task<Void, Never>?

    init(url: URL, notebookPath: String) {
        self.notebookPath = notebookPath
        navigationDelegate = NotebookNavigationDelegate(allowedHost: url.host, allowedPort: url.port)
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = navigationDelegate
        commentBridge.attach(webView: webView)
        navigationDelegate.onDidFinish = { [weak self] in
            guard let self else { return }
            self.commentBridge.pageDidLoad()
            self.onPageLoaded?()
        }
        webView.load(URLRequest(url: url))
        // F049-R06: external on-disk edits (e.g. by an agent) won't surface in
        // the cached, in-memory Notebook 7 view, so reload when the watcher
        // reports this file changed. Debounced to coalesce burst events.
        fileChangeObserver = NotificationCenter.default.addObserver(
            forName: .fileSystemContentsDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let paths = note.userInfo?["changedPaths"] as? Set<String> else { return }
            MainActor.assumeIsolated { self?.handleExternalChange(paths) }
        }
    }

    private func handleExternalChange(_ changedPaths: Set<String>) {
        guard changedPaths.contains(notebookPath) else { return }
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            self.webView.reload()
        }
    }

    func register(_ host: NotebookHostContainerView) {
        hosts.add(host)
    }

    /// A host became visible; it wins ownership (most-recent-claim) and the web
    /// view re-parents to it.
    func claim(_ host: NotebookHostContainerView) {
        nextSeq += 1
        host.claimSeq = nextSeq
        host.isLive = true
        recompute()
    }

    /// A host disappeared (closed/hidden); ownership falls back to the
    /// next most-recently-claimed live host.
    func resign(_ host: NotebookHostContainerView) {
        host.isLive = false
        recompute()
    }

    func recompute() {
        let owner = hosts.allObjects
            .filter { $0.isLive }
            .max { $0.claimSeq < $1.claimSeq }
        guard let owner else {
            if webView.superview != nil { webView.removeFromSuperview() }
            return
        }
        if webView.superview !== owner {
            webView.removeFromSuperview()
            webView.frame = owner.bounds
            webView.autoresizingMask = [.width, .height]
            owner.addSubview(webView)
        }
    }

    func shutdown() {
        reloadTask?.cancel()
        commentBridge.detach()
        if let fileChangeObserver {
            NotificationCenter.default.removeObserver(fileChangeObserver)
            self.fileChangeObserver = nil
        }
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.removeFromSuperview()
    }
}

/// `NSViewRepresentable` that hands its container to the shared arbiter. Many of
/// these may exist for one notebook (one per surface); they all point at the
/// same arbiter and thus the same web view.
private struct NotebookWebViewHost: NSViewRepresentable {
    let arbiter: NotebookWebViewArbiter

    func makeNSView(context: Context) -> NotebookHostContainerView {
        let container = NotebookHostContainerView()
        container.arbiter = arbiter
        arbiter.register(container)
        return container
    }

    func updateNSView(_ container: NotebookHostContainerView, context: Context) {
        container.arbiter = arbiter
        arbiter.register(container)
    }
}

/// Container whose window/visibility transitions drive arbitration.
@MainActor
final class NotebookHostContainerView: NSView {
    weak var arbiter: NotebookWebViewArbiter?
    var claimSeq = 0
    var isLive = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { arbiter?.claim(self) } else { arbiter?.resign(self) }
    }

    override func layout() {
        super.layout()
        arbiter?.recompute()
    }

    deinit {
        MainActor.assumeIsolated {
            arbiter?.resign(self)
        }
    }
}

/// Confines top-level navigation to the local server origin (F049-R09);
/// external links open in the system browser.
final class NotebookNavigationDelegate: NSObject, WKNavigationDelegate {
    private let allowedHost: String?
    private let allowedPort: Int?
    /// Fired on every finished navigation (initial load + reloads).
    var onDidFinish: (() -> Void)?

    init(allowedHost: String?, allowedPort: Int?) {
        self.allowedHost = allowedHost
        self.allowedPort = allowedPort
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onDidFinish?()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let target = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if target.scheme == "http" && target.host == allowedHost && target.port == allowedPort {
            decisionHandler(.allow)
            return
        }
        if ["about", "blob", "data"].contains(target.scheme) {
            decisionHandler(.allow)
            return
        }
        if navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(target)
        }
        decisionHandler(.cancel)
    }
}

// MARK: - NotebookCommentBridge

/// F049: comment surface bridge for the in-notebook `WKWebView`. Anchors
/// comments to the **nbformat cell id** (carried in `CommentAnchor.domSelector`)
/// with the cell's source fingerprint (`domFingerprint`) as a reorder/edit
/// fallback — see the marker design. Injects a cell-aware JS adapter that
/// captures selections, renders per-cell gutter markers, and scrolls to a cell.
@MainActor
final class NotebookCommentBridge: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    var onRequestAddWithBody: ((CommentAnchor, String) -> Void)?
    var onGutterClick: ((String) -> Void)?

    func attach(webView: WKWebView) {
        guard self.webView !== webView else { return }
        detach()
        self.webView = webView
        let controller = webView.configuration.userContentController
        controller.add(self, name: "nbCommentsRequestAdd")
        controller.add(self, name: "nbCommentsGutterClick")
    }

    func detach() {
        guard let webView else { return }
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "nbCommentsRequestAdd")
        controller.removeScriptMessageHandler(forName: "nbCommentsGutterClick")
        self.webView = nil
    }

    /// Re-inject the adapter after each finished load (idempotent in-page).
    func pageDidLoad() {
        webView?.evaluateJavaScript(Self.bundleSource, completionHandler: nil)
    }

    func syncDecorations(threads: [CommentThread], selectedThreadID: String?) {
        guard let webView else { return }
        let payload = threads.map { thread -> [String: Any] in
            [
                "id": thread.id,
                "cellId": thread.root.anchor.domSelector ?? "",
                "fingerprint": thread.root.anchor.domFingerprint ?? "",
                "status": thread.status.rawValue,
            ]
        }
        let json = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let selected = selectedThreadID.map { "\"\($0)\"" } ?? "null"
        webView.evaluateJavaScript(
            "window.crispyvibesNotebookComments&&window.crispyvibesNotebookComments.setComments(\(json),\(selected));",
            completionHandler: nil
        )
    }

    func scrollAndSelect(anchor: CommentAnchor) {
        guard let webView, let cellId = anchor.domSelector else { return }
        let escaped = cellId
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        webView.evaluateJavaScript(
            "window.crispyvibesNotebookComments&&window.crispyvibesNotebookComments.scrollTo(\"\(escaped)\");",
            completionHandler: nil
        )
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let name = message.name
        let body = message.body
        Task { @MainActor [weak self] in self?.handle(name: name, body: body) }
    }

    private func handle(name: String, body: Any) {
        switch name {
        case "nbCommentsRequestAdd":
            guard let info = body as? [String: Any] else { return }
            let anchor = CommentAnchor.fromNotificationPayload(info)
            guard let text = info["body"] as? String, !text.isEmpty else { return }
            onRequestAddWithBody?(anchor, text)
        case "nbCommentsGutterClick":
            guard let info = body as? [String: Any], let id = info["threadID"] as? String else { return }
            onGutterClick?(id)
        default:
            break
        }
    }

    /// Cell-id-anchored adapter. Idempotent. Disconnects its MutationObserver
    /// while it mutates the DOM so re-decoration never loops.
    static let bundleSource = #"""
    (function () {
      if (window.__cvNbComments) return;
      var pending = [], selectedId = null, lastAnchor = null, applyScheduled = false, composerAnchor = null;

      function cells() { return Array.prototype.slice.call(document.querySelectorAll('.jp-Notebook .jp-Cell, .jp-Cell')); }
      function cellIdOf(el, idx) { return (el.dataset && el.dataset.id) || el.getAttribute('data-id') || ('idx:' + idx); }
      function cellText(el) { var e = el.querySelector('.cm-content, .jp-InputArea-editor'); return ((e ? e.textContent : el.textContent) || '').slice(0, 4096); }
      function djb2(s) { var h = 5381; for (var i = 0; i < s.length; i++) h = ((h << 5) + h) + s.charCodeAt(i); return (h >>> 0).toString(16); }
      function force(el, st) { for (var k in st) el.style.setProperty(k, st[k], 'important'); }

      function enclosingCell(node) {
        var el = node && node.nodeType === 1 ? node : (node && node.parentElement);
        while (el && el !== document.body) { if (el.classList && el.classList.contains('jp-Cell')) return el; el = el.parentElement; }
        return null;
      }
      function findCell(t) {
        var cs = cells(), i;
        for (i = 0; i < cs.length; i++) { if (cellIdOf(cs[i], i) === t.cellId) return cs[i]; }
        if (t.fingerprint) { for (i = 0; i < cs.length; i++) { if (djb2(cellText(cs[i])) === t.fingerprint) return cs[i]; } }
        return null;
      }

      function applyDecorations() {
        var old = document.querySelectorAll('.cv-nb-gutter');
        for (var k = 0; k < old.length; k++) old[k].remove();
        var marked = document.querySelectorAll('[data-cv-nb]');
        for (var m = 0; m < marked.length; m++) { marked[m].removeAttribute('data-cv-nb'); marked[m].style.removeProperty('outline'); }
        pending.forEach(function (t) {
          var el = findCell(t); if (!el) return;
          el.setAttribute('data-cv-nb', t.id);
          if (getComputedStyle(el).position === 'static') el.style.position = 'relative';
          force(el, { 'outline': (t.id === selectedId ? '2px solid rgba(42,144,255,0.9)' : '1px solid rgba(42,144,255,0.5)'), 'outline-offset': '-1px' });
          var b = document.createElement('button');
          b.className = 'cv-nb-gutter'; b.textContent = '💬'; b.dataset.t = t.id;
          force(b, { all: 'initial', position: 'absolute', top: '4px', right: '4px', width: '20px', height: '20px', padding: '0', border: '0', 'border-radius': '4px', background: 'rgba(42,144,255,0.92)', cursor: 'pointer', 'z-index': '40', font: '12px system-ui', 'line-height': '20px', 'text-align': 'center' });
          b.addEventListener('mousedown', function (e) { e.preventDefault(); e.stopPropagation(); });
          b.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); post('nbCommentsGutterClick', { threadID: this.dataset.t }); });
          el.appendChild(b);
        });
      }

      var nbRoot = document.querySelector('.jp-Notebook') || document.body;
      var observer = new MutationObserver(scheduleApply);
      function scheduleApply() { if (applyScheduled) return; applyScheduled = true; requestAnimationFrame(function () { applyScheduled = false; doApply(); }); }
      function doApply() { try { observer.disconnect(); } catch (_) {} applyDecorations(); try { observer.observe(nbRoot, { childList: true, subtree: true }); } catch (_) {} }
      try { observer.observe(nbRoot, { childList: true, subtree: true }); } catch (_) {}

      function post(name, payload) { try { window.webkit.messageHandlers[name].postMessage(payload); } catch (_) {} }

      function captureAnchor() {
        var sel = window.getSelection(); if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return null;
        var cell = enclosingCell(sel.anchorNode); if (!cell) return null;
        var idx = cells().indexOf(cell);
        var cellNum = idx >= 0 ? idx + 1 : 1;
        var text = sel.toString().slice(0, 4096);
        return { domSelector: cellIdOf(cell, idx), domFingerprint: djb2(cellText(cell)), anchorText: text, domTextOffset: 0, domTextLength: text.length, startLine: cellNum, startColumn: 1, endLine: cellNum, endColumn: 1 };
      }

      var addBtn = null;
      function ensureAdd() {
        if (addBtn) return addBtn;
        addBtn = document.createElement('button'); addBtn.textContent = '💬 Comment';
        force(addBtn, { all: 'initial', position: 'fixed', 'z-index': '2147483647', display: 'none', padding: '4px 9px', font: '12px system-ui', background: 'rgba(40,40,40,0.92)', color: 'white', border: '0.5px solid rgba(255,255,255,0.18)', 'border-radius': '6px', cursor: 'pointer' });
        addBtn.addEventListener('mousedown', function (e) { e.preventDefault(); });
        addBtn.addEventListener('click', function () { if (lastAnchor) showComposer(); });
        document.body.appendChild(addBtn); return addBtn;
      }
      function reposition() {
        if (comp && comp.style.getPropertyValue('display') === 'block') return;
        var b = ensureAdd(); var sel = window.getSelection();
        if (!sel || sel.rangeCount === 0 || sel.isCollapsed) { b.style.display = 'none'; lastAnchor = null; return; }
        var a = captureAnchor(); if (!a) { b.style.display = 'none'; lastAnchor = null; return; }
        lastAnchor = a; var r = sel.getRangeAt(0).getBoundingClientRect();
        if (r.width === 0 && r.height === 0) { b.style.display = 'none'; return; }
        force(b, { top: Math.max(8, r.top - 30) + 'px', left: Math.min(window.innerWidth - 130, Math.max(8, r.left)) + 'px', display: 'block' });
      }

      var comp = null;
      function ensureComposer() {
        if (comp) return comp;
        comp = document.createElement('div');
        force(comp, { all: 'initial', position: 'fixed', 'z-index': '2147483647', display: 'none', width: '280px', padding: '8px', background: 'rgba(30,30,30,0.96)', border: '0.5px solid rgba(255,255,255,0.18)', 'border-radius': '8px', 'font-family': 'system-ui' });
        var ta = document.createElement('textarea');
        force(ta, { all: 'initial', width: '100%', 'min-height': '44px', padding: '6px', background: 'rgba(255,255,255,0.08)', border: '0.5px solid rgba(255,255,255,0.15)', 'border-radius': '6px', color: 'white', font: '13px system-ui', display: 'block', 'box-sizing': 'border-box' });
        ta.placeholder = 'Write a comment...'; comp.appendChild(ta); comp._ta = ta;
        var row = document.createElement('div'); force(row, { all: 'initial', display: 'flex', 'justify-content': 'flex-end', gap: '6px', 'margin-top': '6px' });
        var cancel = document.createElement('button'); cancel.textContent = 'Cancel'; force(cancel, { all: 'initial', padding: '3px 10px', background: 'rgba(255,255,255,0.1)', color: 'white', 'border-radius': '4px', cursor: 'pointer' });
        var submit = document.createElement('button'); submit.textContent = 'Comment'; force(submit, { all: 'initial', padding: '3px 10px', background: 'rgba(80,120,255,0.9)', color: 'white', 'border-radius': '4px', cursor: 'pointer', 'font-weight': '600' });
        row.appendChild(cancel); row.appendChild(submit); comp.appendChild(row);
        cancel.addEventListener('click', function (e) { e.preventDefault(); hideComposer(); });
        submit.addEventListener('click', function (e) {
          e.preventDefault(); var body = ta.value.trim(); if (!body || !composerAnchor) return;
          var p = {}; for (var key in composerAnchor) p[key] = composerAnchor[key]; p.body = body;
          post('nbCommentsRequestAdd', p); hideComposer();
        });
        comp.addEventListener('mousedown', function (e) { e.preventDefault(); });
        document.body.appendChild(comp); return comp;
      }
      function showComposer() { var c = ensureComposer(); composerAnchor = lastAnchor; ensureAdd().style.display = 'none'; c._ta.value = ''; force(c, { top: addBtn.style.top, left: addBtn.style.left, display: 'block' }); setTimeout(function () { c._ta.focus(); }, 50); }
      function hideComposer() { if (comp) comp.style.setProperty('display', 'none', 'important'); composerAnchor = null; }

      document.addEventListener('selectionchange', function () { setTimeout(reposition, 0); });

      window.crispyvibesNotebookComments = {
        setComments: function (threads, sel) { pending = threads || []; selectedId = sel; doApply(); },
        scrollTo: function (cellId) { var el = findCell({ cellId: cellId }); if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' }); }
      };
      window.__cvNbComments = true;
    })();
    """#
}
