import AppKit
import JavaScriptCore
import SwiftUI

/// Renders markdown as rich text using NSAttributedString HTML rendering.
/// Handles block elements (paragraphs, lists, headings) that SwiftUI's
/// AttributedString(markdown:) collapses into inline text.
struct MarkdownHTMLView: NSViewRepresentable {
    @Environment(\.crispyvibesUIScale) private var uiScale
    let markdown: String
    var font: Font = AppTypographyTokens.body
    var foregroundColor: Color? = nil
    let onLinkTargetActivated: ((URL) -> Void)?
    let onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?

    func makeNSView(context: Context) -> MarkdownHTMLTextView {
        let textView = MarkdownHTMLTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ textView: MarkdownHTMLTextView, context: Context) {
        let resolved = NSFont.systemFont(ofSize: uiScale.textSize(13))
        let colorKey = cssColor(foregroundColor)
        // Fingerprint the inputs that would change the rendered output. If nothing has
        // changed since the last render, skip the expensive XPC-backed HTML parse. This
        // is critical because SwiftUI can invoke updateNSView on every ancestor state
        // change even when our own inputs are unchanged.
        let fingerprint = "\(resolved.pointSize)|\(colorKey)|\(markdown)"
        if textView.lastRenderedFingerprint == fingerprint { return }
        textView.lastRenderedFingerprint = fingerprint

        let html = MarkdownToHTML.convert(markdown)
        let css = """
        <style>
        body {
            font-family: -apple-system, SF Pro Text, Helvetica Neue, sans-serif;
            font-size: \(resolved.pointSize)px;
            color: \(colorKey);
            line-height: 1.5;
            margin: 0; padding: 0;
        }
        p { margin: 0 0 0.5em 0; }
        ul, ol { margin: 0 0 0.5em 0; padding-left: 1.4em; }
        li { margin: 0 0 0.2em 0; }
        h1, h2, h3, h4 { margin: 0.6em 0 0.3em 0; }
        h1 { font-size: 1.3em; } h2 { font-size: 1.15em; } h3 { font-size: 1.05em; }
        code { font-family: SF Mono, Menlo, monospace; font-size: 0.9em;
               background: rgba(128,128,128,0.15); padding: 1px 4px; border-radius: 3px; }
        pre { margin: 0.5em 0; }
        pre code { background: none; padding: 0; }
        a { color: #E8912D; }
        blockquote { border-left: 3px solid rgba(128,128,128,0.3); margin: 0.5em 0; padding-left: 0.8em;
                     color: rgba(128,128,128,0.8); }
        table { border-collapse: collapse; margin: 0.5em 0; width: 100%; }
        th, td { border: 1px solid rgba(128,128,128,0.3); padding: 4px 8px; text-align: left; }
        th { font-weight: 600; background: rgba(128,128,128,0.1); }
        </style>
        """
        let fullHTML = "<html><head><meta charset=\"utf-8\">\(css)</head><body>\(html)</body></html>"

        if let data = fullHTML.data(using: .utf8),
           let attributed = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue
               ],
               documentAttributes: nil
           ) {
            let linked = NSMutableAttributedString(attributedString: attributed)
            ACPTextLinking.applyDetectedLinks(to: linked)
            ACPTextLinking.styleLinks(in: linked)
            textView.linkTextAttributes = ACPTextLinking.linkTextAttributes
            textView.textStorage?.setAttributedString(linked)
        } else {
            textView.string = markdown
        }

        // Force layout and update intrinsic height
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.invalidateIntrinsicContentSize()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLinkTargetActivated: onLinkTargetActivated,
            onFileSystemTargetActivated: onFileSystemTargetActivated
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let onLinkTargetActivated: ((URL) -> Void)?
        let onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?

        init(onLinkTargetActivated: ((URL) -> Void)?, onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?) {
            self.onLinkTargetActivated = onLinkTargetActivated
            self.onFileSystemTargetActivated = onFileSystemTargetActivated
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return false }
            _ = ACPTextLinking.handle(
                url: url,
                onLinkTargetActivated: onLinkTargetActivated,
                onFileSystemTargetActivated: onFileSystemTargetActivated
            )
            return true
        }
    }

    private func resolveNSFont(_ font: Font) -> NSFont {
        switch font {
        case .body: return .systemFont(ofSize: NSFont.systemFontSize)
        case .callout: return .systemFont(ofSize: NSFont.systemFontSize - 1)
        case .caption: return .systemFont(ofSize: NSFont.smallSystemFontSize)
        case .caption2: return .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        default: return .systemFont(ofSize: NSFont.systemFontSize)
        }
    }

    private func cssColor(_ color: Color?) -> String {
        let color = color.map(NSColor.init) ?? NSColor.labelColor
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#ffffff" }
        return String(format: "rgba(%.0f,%.0f,%.0f,%.2f)",
                      rgb.redComponent * 255, rgb.greenComponent * 255,
                      rgb.blueComponent * 255, rgb.alphaComponent)
    }
}

/// NSTextView subclass that reports correct intrinsic content size for SwiftUI layout.
final class MarkdownHTMLTextView: NSTextView {
    private var mouseDownLocationInWindow: NSPoint?
    /// Fingerprint of the last successful render (markdown + font size + color). Used
    /// by `MarkdownHTMLView.updateNSView` to skip the expensive HTML parse when the
    /// inputs haven't changed between updates.
    var lastRenderedFingerprint: String?

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(rect.height + textContainerInset.height * 2))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocationInWindow = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let isClick = mouseDownLocationInWindow.map { hypot($0.x - event.locationInWindow.x, $0.y - event.locationInWindow.y) <= 3 } ?? false
        mouseDownLocationInWindow = nil
        if isClick,
           selectedRange().length == 0,
           let link = linkTarget(at: event),
           delegate?.textView?(self, clickedOnLink: link.value, at: link.characterIndex) == true {
            return
        }
        super.mouseUp(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let layoutManager, let textContainer, let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            layoutManager.ensureLayout(for: textContainer)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                self.addCursorRect(self.textContainerRect(from: rect), cursor: .pointingHand)
            }
        }
    }

    private func linkTarget(at event: NSEvent) -> (value: Any, characterIndex: Int)? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let containerPoint = textContainerPoint(from: event.locationInWindow)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        guard glyphRect.insetBy(dx: -2, dy: -2).contains(containerPoint) else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        var effectiveRange = NSRange(location: 0, length: 0)
        guard let value = textStorage.attribute(.link, at: characterIndex, effectiveRange: &effectiveRange),
              NSLocationInRange(characterIndex, effectiveRange) else { return nil }
        return (value, characterIndex)
    }

    private func textContainerPoint(from windowPoint: NSPoint) -> NSPoint {
        let localPoint = convert(windowPoint, from: nil)
        return NSPoint(
            x: localPoint.x - textContainerOrigin.x,
            y: localPoint.y - textContainerOrigin.y
        )
    }

    private func textContainerRect(from rect: NSRect) -> NSRect {
        NSRect(
            x: rect.origin.x + textContainerOrigin.x,
            y: rect.origin.y + textContainerOrigin.y,
            width: rect.width,
            height: rect.height
        )
    }
}

/// Markdown → HTML converter backed by marked.js (bundled in MarkdownRuntime).
/// Supports full GFM including tables, fenced code blocks, task lists, etc.
enum MarkdownToHTML {
    private static let context: JSContext? = {
        guard let ctx = JSContext() else { return nil }
        guard let url = Bundle.main.url(forResource: "marked.umd", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        ctx.evaluateScript(source)
        ctx.evaluateScript("marked.use({ gfm: true, breaks: true });")
        ctx.evaluateScript("function __crispyvibes_parse(md) { return marked.parse(md); }")
        return ctx
    }()

    static func convert(_ markdown: String) -> String {
        guard let context,
              let parseFn = context.objectForKeyedSubscript("__crispyvibes_parse"),
              let result = parseFn.call(withArguments: [markdown]),
              let html = result.toString(),
              html != "undefined" else {
            return escapeHTML(markdown)
        }
        return html
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
