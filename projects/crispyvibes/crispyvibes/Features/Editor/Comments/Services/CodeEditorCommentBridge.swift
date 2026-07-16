import AppKit
import Combine
import WebKit

/// F049: bridge between `CodeEditorView` (which owns the NSTextView) and the
/// SwiftUI comments UI. Holds a weak reference to the active text view so the
/// overlay can compute pixel-accurate rects, and exposes scroll + selection
/// affordances.
///
/// In rich-mode markdown/HTML, the bridge also tracks the active WKWebView
/// so scroll/decoration calls dispatch to JavaScript instead of NSTextView.
@MainActor
final class CodeEditorCommentBridge: ObservableObject, CommentSurfaceBridge {

    private enum ActiveSurface {
        case text
        case rich
    }

    /// Context bytes captured before/after the anchored range. Keep in sync
    /// with the Rust persistence helper's `MAX_CONTEXT_BYTES = 64`.
    static let maxContextBytes = 64

    weak var textView: NSTextView?
    weak var enclosingScroll: NSScrollView?
    weak var richModeWebView: WKWebView?

    /// Bumps whenever scroll offset / size changes so the SwiftUI overlay
    /// re-renders.
    @Published private(set) var geometryTick: Int = 0

    private var scrollObservation: NSObjectProtocol?
    private var boundsObservation: NSObjectProtocol?
    private var activeSurface: ActiveSurface = .text
    private var lastRichDecorationScript: String?

    // MARK: - CommentSurfaceBridge

    func captureSelectionAnchor() async -> CommentAnchor? {
        currentSelectionAnchor()
    }

    func scrollAndSelect(anchor: CommentAnchor) async {
        scrollAndSelectSync(anchor: anchor)
    }

    func syncDecorations(threads: [CommentThread], selectedThreadID: String?) {
        // Code editor (NSTextView) decorations are drawn by SwiftUI overlay
        // observing `geometryTick` + `commentStore.threads(...)`. The bridge
        // only needs to forward to the rich-mode webview when present.
        syncRichModeDecorations(threads: threads, selectedThreadID: selectedThreadID)
    }

    /// Compute the bounding rects of a 1-based (line, col) → (line, col)
    /// range in the textView's coordinate space. Returns an empty array if
    /// the textView is unavailable or the range is out of bounds.
    func rects(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) -> [CGRect] {
        guard let tv = textView,
              let lm = tv.layoutManager,
              let tc = tv.textContainer
        else { return [] }
        let nsString = tv.string as NSString
        guard let nsRange = nsRange(
            from: nsString,
            startLine: startLine,
            startColumn: startColumn,
            endLine: endLine,
            endColumn: endColumn
        ) else { return [] }
        let glyphRange = lm.glyphRange(forCharacterRange: nsRange, actualCharacterRange: nil)
        var rects: [CGRect] = []
        lm.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: tc
        ) { rect, _ in
            // textContainer rect → textView coords (add origin)
            let origin = tv.textContainerOrigin
            rects.append(rect.offsetBy(dx: origin.x, dy: origin.y))
        }
        return rects
    }

    /// Convert (line, col)-pair → NSRange in the current text. Returns nil
    /// if out-of-bounds.
    func nsRange(
        from string: NSString,
        startLine: Int,
        startColumn: Int,
        endLine: Int,
        endColumn: Int
    ) -> NSRange? {
        var lineNumber = 1
        var lineStart = 0
        var startOffset: Int? = nil
        var endOffset: Int? = nil
        var i = 0
        while i < string.length {
            if lineNumber == startLine && startOffset == nil {
                let col = max(1, min(startColumn, lineLength(string: string, lineStart: lineStart)) )
                startOffset = lineStart + (col - 1)
            }
            if lineNumber == endLine && endOffset == nil {
                let lineLen = lineLength(string: string, lineStart: lineStart)
                let col = max(1, min(endColumn, lineLen + 1))
                endOffset = lineStart + (col - 1)
                break
            }
            // advance to next line
            let c = string.character(at: i)
            i += 1
            if c == 0x0A { // newline
                lineNumber += 1
                lineStart = i
            }
        }
        // Handle requests at or beyond last line
        if startOffset == nil, lineNumber == startLine {
            let col = max(1, startColumn)
            startOffset = min(string.length, lineStart + (col - 1))
        }
        if endOffset == nil, lineNumber == endLine {
            let col = max(1, endColumn)
            endOffset = min(string.length, lineStart + (col - 1))
        }
        guard let s = startOffset, let e = endOffset, e >= s, s <= string.length else { return nil }
        return NSRange(location: s, length: min(e - s, string.length - s))
    }

    private func lineLength(string: NSString, lineStart: Int) -> Int {
        var i = lineStart
        while i < string.length && string.character(at: i) != 0x0A { i += 1 }
        return i - lineStart
    }

    /// Scroll the editor to bring the start of the given anchor into view
    /// and place the caret at its start. Sync entry point used by call
    /// sites that already run on the main actor.
    func scrollAndSelectSync(anchor: CommentAnchor) {
        switch activeSurface {
        case .rich:
            if scrollRichMode(anchor: anchor) { return }
            _ = scrollTextMode(anchor: anchor)
        case .text:
            if scrollTextMode(anchor: anchor) { return }
            _ = scrollRichMode(anchor: anchor)
        }
    }

    private func scrollTextMode(anchor: CommentAnchor) -> Bool {
        if let tv = textView {
            let nsString = tv.string as NSString
            guard let range = nsRange(
                from: nsString,
                startLine: anchor.startLine,
                startColumn: anchor.startColumn,
                endLine: anchor.endLine,
                endColumn: anchor.endColumn
            ) else { return false }
            tv.setSelectedRange(range)
            tv.scrollRangeToVisible(range)
            if tv.window?.firstResponder !== tv {
                tv.window?.makeFirstResponder(tv)
            }
            return true
        }
        return false
    }

    private func scrollRichMode(anchor: CommentAnchor) -> Bool {
        if let wv = richModeWebView {
            // Rich mode: dispatch to JS scrollToAnchor — sends the full
            // anchor so HTML mode can use `domSelector` and markdown can
            // use `startLine`.
            var anchorPayload: [String: Any] = [
                "startLine": anchor.startLine,
                "endLine": anchor.endLine,
            ]
            if let selector = anchor.domSelector {
                anchorPayload["domSelector"] = selector
            }
            let json = (try? JSONSerialization.data(withJSONObject: anchorPayload))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let js = "if(window.crispyvibesComments){window.crispyvibesComments.scrollToAnchor(\(json));}"
            wv.evaluateJavaScript(js, completionHandler: nil)
            return true
        }
        return false
    }

    /// Scroll to the thread with the given id within the file at `filePath`,
    /// looking up the anchor on the supplied store. Sync overload used by
    /// SwiftUI views that don't want to await. The protocol-level
    /// `scrollToThread(id:in:surfaceTarget:)` async variant is preferred
    /// for new code that crosses bridge implementations.
    func scrollToThread(id: String, in store: VibeSpaceCommentStore, filePath: String) {
        guard let thread = store.threads(forFile: filePath).first(where: { $0.id == id }) else { return }
        scrollAndSelectSync(anchor: thread.root.anchor)
    }

    /// Push the current per-file thread list into the rich-mode webview so
    /// JS can apply decorations. No-op when textView is the active editor.
    /// Each thread payload includes both `startLine` (markdown adapter
    /// path) and `selector` (HTML iframe adapter path) — the JS dispatch
    /// picks the right one based on the active `editorMode`.
    func syncRichModeDecorations(threads: [CommentThread], selectedThreadID: String?) {
        guard let wv = richModeWebView else { return }
        let payload = threads.map { thread -> [String: Any] in
            var entry: [String: Any] = [
                "id": thread.id,
                "startLine": thread.root.anchor.startLine,
                "endLine": thread.root.anchor.endLine,
                "status": thread.status.rawValue,
            ]
            if let selector = thread.root.anchor.domSelector {
                entry["selector"] = selector
            }
            return entry
        }
        let json = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let selected = selectedThreadID.map { "\"\($0)\"" } ?? "null"
        let js = "if(window.crispyvibesComments){window.crispyvibesComments.setComments(\(json), \(selected));}"
        guard js != lastRichDecorationScript else { return }
        lastRichDecorationScript = js
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Convenience: pull the thread list off the supplied store and sync.
    /// Used by the rich-mode editor coordinator so the JSON building lives
    /// here, not in the view layer.
    func syncRichModeDecorations(from store: VibeSpaceCommentStore, filePath: String, selectedThreadID: String?) {
        let threads = store.threads(forFile: filePath)
        syncRichModeDecorations(threads: threads, selectedThreadID: selectedThreadID)
    }

    /// Register the rich-mode WKWebView with the bridge.
    func observeRichMode(webView: WKWebView) {
        let registrationChanged = richModeWebView !== webView
        let surfaceChanged: Bool
        switch activeSurface {
        case .text: surfaceChanged = true
        case .rich: surfaceChanged = false
        }
        guard registrationChanged || surfaceChanged else { return }
        self.richModeWebView = webView
        activeSurface = .rich
        if registrationChanged {
            lastRichDecorationScript = nil
        }
        // Bump tick so any observers know the editor surface has switched.
        geometryTick &+= 1
    }

    func invalidateRichModeDecorations() {
        lastRichDecorationScript = nil
    }

    /// Convert the textView's current selection into a `CommentAnchor`-ready
    /// triple (range + line/col + content). Returns nil if no selection or
    /// cursor-only.
    func currentSelectionAnchor() -> CommentAnchor? {
        guard let tv = textView else { return nil }
        let selected = tv.selectedRange()
        let nsString = tv.string as NSString
        if selected.length == 0 {
            // Use whole line at the caret as fallback
            let caret = max(0, min(selected.location, nsString.length))
            let lineRange = nsString.lineRange(for: NSRange(location: caret, length: 0))
            return anchor(from: nsString, range: lineRange)
        }
        return anchor(from: nsString, range: selected)
    }

    /// Build a `CommentAnchor` from an NSRange in the current text.
    private func anchor(from nsString: NSString, range: NSRange) -> CommentAnchor? {
        guard range.location <= nsString.length else { return nil }
        let safeLen = min(range.length, nsString.length - range.location)
        let safeRange = NSRange(location: range.location, length: safeLen)
        let (startLine, startCol) = lineColumn(at: safeRange.location, in: nsString)
        let endLoc = safeRange.location + safeRange.length
        let (endLine, endCol) = lineColumn(at: endLoc, in: nsString)
        let anchorText = nsString.substring(with: safeRange)
        let leading = leadingContext(for: safeRange, in: nsString)
        let trailing = trailingContext(for: safeRange, in: nsString)
        return CommentAnchor(
            startLine: startLine,
            startColumn: startCol,
            endLine: endLine,
            endColumn: endCol,
            anchorHash: CommentAnchor.hash(anchorText),
            anchorText: anchorText,
            leadingContext: leading,
            trailingContext: trailing
        )
    }

    private func lineColumn(at offset: Int, in string: NSString) -> (line: Int, column: Int) {
        var line = 1
        var lineStart = 0
        var i = 0
        let target = max(0, min(offset, string.length))
        while i < target {
            if string.character(at: i) == 0x0A {
                line += 1
                lineStart = i + 1
            }
            i += 1
        }
        return (line, target - lineStart + 1)
    }

    private func leadingContext(for range: NSRange, in string: NSString) -> String {
        let start = max(0, range.location - Self.maxContextBytes)
        let len = range.location - start
        guard len > 0 else { return "" }
        return string.substring(with: NSRange(location: start, length: len))
    }

    private func trailingContext(for range: NSRange, in string: NSString) -> String {
        let endLoc = range.location + range.length
        let remaining = string.length - endLoc
        guard remaining > 0 else { return "" }
        let len = min(Self.maxContextBytes, remaining)
        return string.substring(with: NSRange(location: endLoc, length: len))
    }

    /// Subscribe to scroll-view bounds changes so the overlay knows when to
    /// re-render highlight rects.
    func observe(scrollView: NSScrollView, textView: NSTextView) {
        // If a different scroll view is being registered, tear down the old
        // observers so we don't leak notifications from a deallocated view
        // (and so the overlay can re-bind to the new geometry).
        let registrationChanged = enclosingScroll !== scrollView || self.textView !== textView
        let surfaceChanged: Bool
        switch activeSurface {
        case .text: surfaceChanged = false
        case .rich: surfaceChanged = true
        }
        if registrationChanged {
            if let token = scrollObservation { NotificationCenter.default.removeObserver(token) }
            if let token = boundsObservation { NotificationCenter.default.removeObserver(token) }
            scrollObservation = nil
            boundsObservation = nil
        }

        self.textView = textView
        self.enclosingScroll = scrollView
        activeSurface = .text

        if scrollObservation == nil {
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObservation = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.geometryTick &+= 1 }
            }
        }
        if boundsObservation == nil {
            textView.postsFrameChangedNotifications = true
            boundsObservation = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: textView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.geometryTick &+= 1 }
            }
        }
        if registrationChanged || surfaceChanged {
            geometryTick &+= 1
        }
    }

    deinit {
        if let scrollObservation { NotificationCenter.default.removeObserver(scrollObservation) }
        if let boundsObservation { NotificationCenter.default.removeObserver(boundsObservation) }
    }
}
