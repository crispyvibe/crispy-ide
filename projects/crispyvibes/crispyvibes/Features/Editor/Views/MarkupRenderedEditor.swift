import Combine
import Foundation
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct MarkupRenderedEditor: NSViewRepresentable {
    enum Mode {
        case markdown
        case html
    }

    let mode: Mode
    let baseDirectoryURL: URL?
    let commandRequest: EditorCommandRequest?
    var isBufferLoading: Bool = false
    var embeddedDropBridge: ContentViewerEmbeddedDropBridge? = nil
    @Binding var content: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appThemePalette) private var appThemePalette
    /// F049: rich-mode bridge — when non-nil, comments are surfaced in the
    /// rendered markdown/HTML via JS-injected decorations and a floating
    /// "Add Comment" button.
    @Environment(\.codeEditorCommentBridge) private var commentBridge: CodeEditorCommentBridge?
    @Environment(\.vibespaceCommentStoreEnvironment) private var commentStoreEnv: VibeSpaceCommentStore?
    @Environment(\.commentsPanelEnvironment) private var commentsPanelEnv: CommentsPanelStore?
    @Environment(\.commentsFilePathEnvironment) private var commentsFilePath: String?

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private(set) weak var webView: WKWebView?
        var parent: MarkupRenderedEditor
        var isEditorReady = false
        var lastInjectedContent = ""
        var lastInjectedThemeTokens = ""
        var lastMode: Mode?
        var lastHandledCommandID: UUID?
        var lastImageCandidateRequestID = 0
        /// F049: Combine subscription that re-syncs decorations whenever
        /// the store reports changes. Replaces the prior NotificationCenter
        /// observer.
        var commentStoreSubscription: AnyCancellable?

        init(parent: MarkupRenderedEditor) {
            self.parent = parent
        }

        func attach(webView: WKWebView) {
            self.webView = webView
            // F049: subscribe to the store's `changes` Combine subject so
            // we re-sync decorations whenever any write completes. Scoped
            // to the parent's bound store so we don't fan out across
            // unrelated editor instances.
            if commentStoreSubscription == nil, let store = parent.commentStoreEnv {
                commentStoreSubscription = store.changes
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in
                        self?.syncCommentDecorationsIfNeeded()
                    }
            }
        }

        func readAccessURL() -> URL {
            // HTML mode needs both:
            // 1) bundled editor assets (editor.html + scripts/css) and
            // 2) file-adjacent local assets for relative links.
            // A root read scope keeps both available.
            if parent.mode == .html {
                return URL(fileURLWithPath: "/")
            }
            
            // Markdown mode needs access to both bundle resources (for editor assets)
            // and the markdown file's directory (for relative images)
            if parent.mode == .markdown {
                // Grant access to root to allow both bundle and user files
                return URL(fileURLWithPath: "/")
            }
            
            if let resourceURL = Bundle.main.resourceURL {
                return resourceURL
            }
            return URL(fileURLWithPath: "/")
        }

        func syncContentToEditor(force: Bool = false) {
            guard isEditorReady, let webView else { return }
            guard !parent.isBufferLoading else { return }
            let modeChanged = lastMode != parent.mode
            guard modeChanged || force || parent.content != lastInjectedContent else { return }

            let serializedContent = Self.serializeForJavaScript(parent.content)
            let script: String
            if parent.mode == .markdown {
                let baseURLString = parent.baseDirectoryURL?.absoluteString ?? ""
                let serializedBaseURL = Self.serializeForJavaScript(baseURLString)
                script = "window.crispyvibesSetMarkdown(\(serializedContent), \(serializedBaseURL));"
            } else {
                let baseURLString = parent.baseDirectoryURL?.absoluteString ?? ""
                let serializedBaseURL = Self.serializeForJavaScript(baseURLString)
                script = "window.crispyvibesSetHTML(\(serializedContent), \(serializedBaseURL));"
            }
            webView.evaluateJavaScript(script)
            lastInjectedContent = parent.content
            lastMode = parent.mode
        }

        func syncThemeTokensToEditor(force: Bool = false) {
            guard isEditorReady, let webView else { return }
            let serializedTokens = Self.serializeDictionaryForJavaScript(parent.themeTokensForWebEditor)
            guard force || serializedTokens != lastInjectedThemeTokens else { return }

            let script = "window.crispyvibesSetThemeTokens(\(serializedTokens));"
            webView.evaluateJavaScript(script)
            lastInjectedThemeTokens = serializedTokens
        }

        func applyFormattingCommandIfNeeded() {
            guard isEditorReady, let webView, let request = parent.commandRequest else { return }
            guard request.id != lastHandledCommandID else { return }

            let serializedCommand = Self.serializeForJavaScript(request.command.rawValue)
            let script = "window.crispyvibesApplyFormattingCommand(\(serializedCommand));"
            webView.evaluateJavaScript(script)
            lastHandledCommandID = request.id
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "editorReady":
                isEditorReady = true
                syncThemeTokensToEditor(force: true)
                syncContentToEditor(force: true)
                applyFormattingCommandIfNeeded()
                // F049: register the webview with the bridge as soon as the
                // editor reports ready, so scrollToLine etc. work.
                if let bridge = parent.commentBridge, let webView {
                    bridge.observeRichMode(webView: webView)
                }
                syncCommentDecorationsIfNeeded()

            case "contentChanged":
                guard let content = message.body as? String else { return }
                guard content != parent.content else { return }
                parent.content = content
                lastInjectedContent = content
                // After content edits, decorations need a refresh.
                syncCommentDecorationsIfNeeded()

            case "requestImageCandidates":
                handleImageCandidateRequest(message.body)

            case "commentsRichSelectionChanged":
                // Selection moved; we don't store it on the Swift side
                // (the JS button handles its own state) but a future
                // enhancement could mirror it back to the panel.
                break

            case "commentsRichRequestAdd":
                // F049-v2: build the anchor via the shared decoder so all
                // DOM-selector fields (`domSelector`, `domTextOffset`,
                // `domTextLength`, `domFingerprint`) captured by the iframe
                // adapter survive the round-trip into persistence.
                guard let info = message.body as? [String: Any] else { return }
                let anchor = CommentAnchor.fromNotificationPayload(info)
                NotificationCenter.default.post(
                    name: .commentsRequestAddForSelection,
                    object: nil,
                    userInfo: anchor.notificationPayload(filePath: parent.commentsFilePath)
                )

            case "commentsRichGutterClick":
                // F049: gutter-button click in rich-mode markdown — open
                // the panel + select thread + auto-open reply composer
                // (matches the SwiftUI `revealForReply` flow).
                guard let info = message.body as? [String: Any],
                      let threadID = info["threadID"] as? String else { return }
                parent.commentsPanelEnv?.revealForReply(threadID: threadID)

            default:
                break
            }
        }

        /// Push the current per-file thread list into the WKWebView. Called
        /// on editor ready, after content edits, and when the comment
        /// store's Combine `changes` subject fires. Delegates the JSON +
        /// JavaScript serialization to `CodeEditorCommentBridge` so the
        /// view layer does not own bridge protocol details.
        func syncCommentDecorationsIfNeeded() {
            guard isEditorReady,
                  let bridge = parent.commentBridge,
                  let store = parent.commentStoreEnv,
                  let path = parent.commentsFilePath
            else { return }
            bridge.syncRichModeDecorations(
                from: store,
                filePath: path,
                selectedThreadID: parent.commentsPanelEnv?.selectedThreadID
            )
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // Recover transparently when WKWebView's WebContent process is recycled.
            isEditorReady = false
            lastInjectedContent = ""
            lastInjectedThemeTokens = ""
            lastMode = nil
            MarkupRenderedEditor.loadLocalEditor(into: webView, readAccessURL: readAccessURL())
        }

        private func handleImageCandidateRequest(_ body: Any) {
            let requestID = Self.requestIDFromScriptMessageBody(body)
            guard parent.mode == .markdown else {
                sendImageCandidatesResponse(requestID: requestID, candidates: [])
                return
            }

            lastImageCandidateRequestID += 1
            let localRequestID = lastImageCandidateRequestID
            let baseDirectory = parent.baseDirectoryURL

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let candidates = MarkdownImageCandidateScanner.scan(baseDirectoryURL: baseDirectory)
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard localRequestID == self.lastImageCandidateRequestID else { return }
                    self.sendImageCandidatesResponse(requestID: requestID, candidates: candidates)
                }
            }
        }

        private func sendImageCandidatesResponse(requestID: String, candidates: [MarkdownImageCandidate]) {
            guard let webView else { return }
            let payload: [String: Any] = [
                "requestID": requestID,
                "candidates": candidates.map(\.scriptPayload)
            ]
            let serializedPayload = Self.serializeJSONObjectForJavaScript(payload)
            let script = "window.crispyvibesReceiveImageCandidates(\(serializedPayload));"
            webView.evaluateJavaScript(script)
        }

        private static func requestIDFromScriptMessageBody(_ body: Any) -> String {
            if let dictionary = body as? [String: Any],
               let requestID = dictionary["requestID"] as? String,
               !requestID.isEmpty {
                return requestID
            }
            return UUID().uuidString
        }

        private static func serializeForJavaScript(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let encoded = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return encoded
        }

        private static func serializeDictionaryForJavaScript(_ value: [String: String]) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                  let encoded = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return encoded
        }

        private static func serializeJSONObjectForJavaScript(_ value: Any) -> String {
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                  let encoded = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return encoded
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "editorReady")
        contentController.add(context.coordinator, name: "contentChanged")
        contentController.add(context.coordinator, name: "requestImageCandidates")
        contentController.add(context.coordinator, name: "commentsRichSelectionChanged")
        contentController.add(context.coordinator, name: "commentsRichRequestAdd")
        contentController.add(context.coordinator, name: "commentsRichGutterClick")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = CrispyVibesNoContextMenuWebView(frame: .zero, configuration: configuration)
        webView.embeddedDropBridge = embeddedDropBridge
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.attach(webView: webView)
        Self.loadLocalEditor(into: webView, readAccessURL: context.coordinator.readAccessURL())
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        (nsView as? CrispyVibesNoContextMenuWebView)?.embeddedDropBridge = embeddedDropBridge
        context.coordinator.syncThemeTokensToEditor()
        context.coordinator.syncContentToEditor()
        context.coordinator.applyFormattingCommandIfNeeded()
        // F049: ensure the bridge has the live webView reference and that
        // decorations reflect the latest threads + selection state.
        if let bridge = commentBridge {
            bridge.observeRichMode(webView: nsView)
        }
        // F049-v2: re-attempt subscription creation if the store arrived
        // after makeNSView (common — environment propagates after initial
        // render). Without this, the Combine subscription is never created
        // and store mutations never trigger decoration refresh.
        if context.coordinator.commentStoreSubscription == nil, let store = commentStoreEnv {
            context.coordinator.commentStoreSubscription = store.changes
                .receive(on: RunLoop.main)
                .sink { [weak coordinator = context.coordinator] _ in
                    coordinator?.syncCommentDecorationsIfNeeded()
                }
        }
        context.coordinator.syncCommentDecorationsIfNeeded()
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.stopLoading()
        nsView.navigationDelegate = nil
        let contentController = nsView.configuration.userContentController
        contentController.removeScriptMessageHandler(forName: "editorReady")
        contentController.removeScriptMessageHandler(forName: "contentChanged")
        contentController.removeScriptMessageHandler(forName: "requestImageCandidates")
        contentController.removeScriptMessageHandler(forName: "commentsRichSelectionChanged")
        contentController.removeScriptMessageHandler(forName: "commentsRichRequestAdd")
        contentController.removeScriptMessageHandler(forName: "commentsRichGutterClick")
    }

    private static func loadLocalEditor(into webView: WKWebView, readAccessURL: URL) {
        guard let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html") else {
            webView.loadHTMLString("<html><body><p>Markdown renderer assets not found.</p></body></html>", baseURL: nil)
            return
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: readAccessURL)
    }

    private var themeTokensForWebEditor: [String: String] {
        MarkupEditorThemeTokenBuilder(
            palette: appThemePalette,
            colorScheme: colorScheme
        )
        .build()
    }
}

final class CrispyVibesNoContextMenuWebView: WKWebView {
    var embeddedDropBridge: ContentViewerEmbeddedDropBridge? {
        didSet { updateRegisteredDraggedTypes() }
    }

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        updateRegisteredDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let embeddedDropBridge,
              ContentViewerTabDragSupport.canReadDropItem(from: sender.draggingPasteboard) else {
            return []
        }
        embeddedDropBridge.updateTargeting(swiftUILocation(from: sender), bounds.size)
        return .move
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let embeddedDropBridge,
              ContentViewerTabDragSupport.canReadDropItem(from: sender.draggingPasteboard) else {
            return []
        }
        embeddedDropBridge.updateTargeting(swiftUILocation(from: sender), bounds.size)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        embeddedDropBridge?.clearTargeting()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let embeddedDropBridge else { return false }
        let canReadItem = ContentViewerTabDragSupport.canReadDropItem(from: sender.draggingPasteboard)
        if !canReadItem {
            embeddedDropBridge.clearTargeting()
        }
        return canReadItem
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let embeddedDropBridge else { return false }
        defer { embeddedDropBridge.clearTargeting() }
        guard let item = ContentViewerTabDragSupport.readDropItem(from: sender.draggingPasteboard) else {
            return false
        }
        return embeddedDropBridge.performDrop(item, swiftUILocation(from: sender), bounds.size)
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        embeddedDropBridge?.clearTargeting()
    }

    private func updateRegisteredDraggedTypes() {
        guard embeddedDropBridge != nil else {
            unregisterDraggedTypes()
            return
        }
        registerForDraggedTypes([
            NSPasteboard.PasteboardType(ContentViewerTabDragSupport.contentViewerTabType.identifier),
            .fileURL
        ])
    }

    private func swiftUILocation(from sender: any NSDraggingInfo) -> CGPoint {
        let local = convert(sender.draggingLocation, from: nil)
        return CGPoint(x: local.x, y: bounds.height - local.y)
    }
}
