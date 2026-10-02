import SwiftUI
import AppKit

/// A request to insert text at the code editor's current selection. Identity is
/// a fresh UUID per request so inserting the same snippet twice still fires.
struct EditorInsertionRequest: Equatable {
    let id: UUID
    let text: String
    init(_ text: String) {
        self.id = UUID()
        self.text = text
    }
}

/// Generic code editor with syntax highlighting support
struct CodeEditorView: NSViewRepresentable {
    let fileURL: URL
    let language: LanguageDefinition
    var codeEditorAccessibilityIdentifier: String?
    var embeddedDropBridge: ContentViewerEmbeddedDropBridge? = nil
    var pendingSourceSelection: MarkdownViewModel.SourceSelection? = nil
    var onPendingSourceSelectionConsumed: (() -> Void)? = nil
    /// Insert-at-cursor hook (e.g. the LaTeX math palette). When a new request
    /// arrives it is inserted at the current selection, then consumed.
    var insertionRequest: EditorInsertionRequest? = nil
    var onInsertionConsumed: (() -> Void)? = nil
    var isBufferLoading: Bool = false
    @Binding var content: String
    let onContentChange: (String) -> Void
    @AppStorage(AppPreferences.codeFontFamilyKey)
    private var codeFontFamily = AppPreferences.defaultCodeFontFamily
    @AppStorage(AppPreferences.codeFontSizeKey)
    private var codeFontSize = AppPreferences.defaultCodeFontSize
    @AppStorage(AppPreferences.editorLineNumberModeKey)
    private var lineNumberModeRaw = AppPreferences.defaultEditorLineNumberMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appThemePalette) private var appThemePalette
    /// F049: optional bridge from the editor's NSTextView to the SwiftUI
    /// comments overlay + panel. When provided, the bridge is wired in
    /// `updateNSView` so the overlay can draw geometry-accurate decorations.
    @Environment(\.codeEditorCommentBridge) private var commentBridge: CodeEditorCommentBridge?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ContentViewerDropAwareTextView.scrollableTextView()
        scrollView.setAccessibilityIdentifier(codeEditorAccessibilityIdentifier ?? "editor.code")
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        if let textView = scrollView.documentView as? ContentViewerDropAwareTextView {
            textView.embeddedDropBridge = embeddedDropBridge
            configureTextView(textView)
            textView.delegate = context.coordinator
            textView.string = content
            context.coordinator.lastFileURL = fileURL.standardizedFileURL

            let theme = resolvedTheme(for: colorScheme)
            applyConfiguredFont(to: textView)
            applyTheme(theme, to: textView)
            updateLineNumberRuler(in: scrollView, theme: theme)
            language.applySyntaxHighlighting(
                to: textView,
                theme: theme,
                baseFont: resolvedEditorFont
            )
            enforceVisibleForeground(in: textView, theme: theme)
            applyPendingSourceSelectionIfNeeded(in: textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? ContentViewerDropAwareTextView else { return }
        let theme = resolvedTheme(for: colorScheme)
        updateLineNumberRuler(in: nsView, theme: theme)
        guard !isBufferLoading else {
            textView.isEditable = false
            return
        }
        textView.isEditable = true
        context.coordinator.parent = self
        textView.embeddedDropBridge = embeddedDropBridge
        let activeFileURL = fileURL.standardizedFileURL
        let isDocumentSwitch = context.coordinator.lastFileURL != activeFileURL
        context.coordinator.lastFileURL = activeFileURL

        applyConfiguredFont(to: textView)
        applyTheme(theme, to: textView)

        // Only update if content changed externally
        if textView.string != content {
            let wasFirstResponder = textView.window?.firstResponder === textView
            let selectedRange = textView.selectedRange()
            let scrollOrigin = isDocumentSwitch ? nil : currentScrollOrigin(in: textView)
            textView.string = content

            // Defer highlighting so text appears immediately
            let lang = language
            let font = resolvedEditorFont
            DispatchQueue.main.async {
                guard textView.window != nil else { return }
                lang.applySyntaxHighlighting(to: textView, theme: theme, baseFont: font)
                self.enforceVisibleForeground(in: textView, theme: theme)
            }

            if isDocumentSwitch {
                resetSelectionAndScroll(toStartIn: textView)
            } else {
                // Restore selection if valid
                let textLength = (textView.string as NSString).length
                if selectedRange.location <= textLength {
                    let safeRange = NSRange(
                        location: min(selectedRange.location, textLength),
                        length: min(selectedRange.length, max(0, textLength - selectedRange.location))
                    )
                    textView.setSelectedRange(safeRange)
                }
                if pendingSourceSelection == nil {
                    restoreScrollOrigin(scrollOrigin, in: textView)
                }
            }
            if wasFirstResponder {
                textView.window?.makeFirstResponder(textView)
            }
        }

        // Update theme if color scheme changed
        context.coordinator.updateThemeIfNeeded(textView: textView, colorScheme: colorScheme)
        applyPendingSourceSelectionIfNeeded(in: textView)
        applyInsertionRequestIfNeeded(in: textView, coordinator: context.coordinator)

        // F049: register the textView with the comment bridge so the SwiftUI
        // overlay can compute pixel-accurate rects for gutter + highlights.
        if let commentBridge {
            commentBridge.observe(scrollView: nsView, textView: textView)
        }
        if let dropAware = textView as? ContentViewerDropAwareTextView {
            dropAware.commentFilePath = fileURL.standardizedFileURL.path
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, colorScheme: colorScheme)
    }

    private func configureTextView(_ textView: NSTextView) {
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        applyConfiguredFont(to: textView)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.layoutManager?.backgroundLayoutEnabled = true
        textView.textContainer?.lineFragmentPadding = 4
        textView.textContainerInset = NSSize(width: 6, height: 10)
    }

    private func resetSelectionAndScroll(toStartIn textView: NSTextView) {
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        if let scrollView = textView.enclosingScrollView {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func currentScrollOrigin(in textView: NSTextView) -> CGPoint? {
        textView.enclosingScrollView?.contentView.bounds.origin
    }

    private func restoreScrollOrigin(_ origin: CGPoint?, in textView: NSTextView) {
        guard let origin else { return }

        DispatchQueue.main.async {
            guard let scrollView = textView.enclosingScrollView,
                  let documentView = scrollView.documentView,
                  textView.window != nil else { return }

            if let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }

            let documentBounds = documentView.bounds
            let visibleBounds = scrollView.contentView.bounds
            let target = CGPoint(
                x: min(max(origin.x, 0), max(0, documentBounds.width - visibleBounds.width)),
                y: min(max(origin.y, 0), max(0, documentBounds.height - visibleBounds.height))
            )
            scrollView.contentView.scroll(to: target)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    /// Insert the pending snippet at the current selection (math palette).
    /// Identity-guarded so the same request isn't applied twice.
    private func applyInsertionRequestIfNeeded(in textView: NSTextView, coordinator: Coordinator) {
        guard let insertionRequest, coordinator.lastInsertionID != insertionRequest.id else { return }
        coordinator.lastInsertionID = insertionRequest.id
        if textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
        textView.insertText(insertionRequest.text, replacementRange: textView.selectedRange())
        onInsertionConsumed?()
    }

    private func applyPendingSourceSelectionIfNeeded(in textView: NSTextView) {
        guard let pendingSourceSelection else { return }
        let targetRange = sourceSelectionRange(
            for: pendingSourceSelection,
            in: textView.string
        )
        textView.setSelectedRange(targetRange)
        textView.scrollRangeToVisible(targetRange)
        onPendingSourceSelectionConsumed?()
    }

    private func resolvedTheme(for colorScheme: ColorScheme) -> SyntaxTheme {
        SyntaxTheme.fromPalette(appThemePalette, colorScheme: colorScheme)
    }

    private var lineNumberMode: EditorLineNumberMode {
        EditorLineNumberMode(rawValue: lineNumberModeRaw) ?? .source
    }

    private func updateLineNumberRuler(
        in scrollView: NSScrollView,
        theme: SyntaxTheme
    ) {
        guard let ruler = scrollView.verticalRulerView as? CodeEditorLineNumberRulerView else {
            return
        }
        ruler.update(
            isVisible: lineNumberMode.showsSourceEditors,
            editorFont: resolvedEditorFont,
            backgroundColor: theme.background,
            numberColor: theme.text.withAlphaComponent(0.52),
            activeNumberColor: NSColor(appThemePalette.accentColor),
            dividerColor: NSColor(appThemePalette.borderColorValue)
        )
    }

    private var resolvedEditorFont: NSFont {
        AppPreferences.codeFont(familyRawValue: codeFontFamily, size: CGFloat(codeFontSize))
    }

    private func applyConfiguredFont(to textView: NSTextView) {
        let targetFont = resolvedEditorFont
        if textView.font?.fontName != targetFont.fontName ||
            abs((textView.font?.pointSize ?? 0) - targetFont.pointSize) > 0.1 {
            textView.font = targetFont
        }
    }

    private func applyTheme(_ theme: SyntaxTheme, to textView: NSTextView) {
        textView.drawsBackground = true
        textView.backgroundColor = theme.background
        // Set typing attributes instead of textColor to avoid wiping syntax highlighting
        textView.insertionPointColor = theme.text
        var attrs = textView.typingAttributes
        attrs[.foregroundColor] = theme.text
        textView.typingAttributes = attrs
        let selectedBackground = appThemePalette.terminalSelectionBackground.nsColor
        textView.selectedTextAttributes = [
            .backgroundColor: selectedBackground,
            .foregroundColor: theme.text
        ]
    }

    private func enforceVisibleForeground(in textView: NSTextView, theme: SyntaxTheme) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let background = theme.background.usingColorSpace(.sRGB) ?? theme.background
        var fallbackRanges: [NSRange] = []
        fallbackRanges.reserveCapacity(8)

        storage.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            guard range.length > 0 else { return }
            let color = (value as? NSColor)?.usingColorSpace(.sRGB) ?? theme.text
            if color.alphaComponent < 0.15 || contrastRatio(between: color, and: background) < 1.25 {
                fallbackRanges.append(range)
            }
        }

        guard !fallbackRanges.isEmpty else { return }
        storage.beginEditing()
        for range in fallbackRanges {
            storage.addAttribute(.foregroundColor, value: theme.text, range: range)
        }
        storage.endEditing()
    }

    private func contrastRatio(between lhs: NSColor, and rhs: NSColor) -> CGFloat {
        let l1 = relativeLuminance(of: lhs)
        let l2 = relativeLuminance(of: rhs)
        let high = max(l1, l2)
        let low = min(l1, l2)
        return (high + 0.05) / (low + 0.05)
    }

    private func relativeLuminance(of color: NSColor) -> CGFloat {
        let c = color.usingColorSpace(.sRGB) ?? color
        func channel(_ value: CGFloat) -> CGFloat {
            if value <= 0.03928 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }

        let r = channel(c.redComponent)
        let g = channel(c.greenComponent)
        let b = channel(c.blueComponent)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        var lastColorScheme: ColorScheme
        var lastFileURL: URL?
        var lastInsertionID: UUID?
        private var lastThemeBackground: NSColor?
        private var highlightWorkItem: DispatchWorkItem?

        init(parent: CodeEditorView, colorScheme: ColorScheme) {
            self.parent = parent
            self.lastColorScheme = colorScheme
            self.lastFileURL = parent.fileURL.standardizedFileURL
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.onContentChange(textView.string)

            highlightWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, textView.window != nil else { return }
                let theme = parent.resolvedTheme(for: lastColorScheme)
                parent.language.applySyntaxHighlighting(
                    to: textView,
                    theme: theme,
                    baseFont: parent.resolvedEditorFont
                )
                parent.enforceVisibleForeground(in: textView, theme: theme)
            }
            highlightWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }

        func updateThemeIfNeeded(textView: NSTextView, colorScheme: ColorScheme) {
            let theme = parent.resolvedTheme(for: colorScheme)
            let themeChanged = lastColorScheme != colorScheme || lastThemeBackground != theme.background
            guard themeChanged else { return }
            lastColorScheme = colorScheme
            lastThemeBackground = theme.background
            parent.applyTheme(theme, to: textView)
            parent.language.applySyntaxHighlighting(
                to: textView,
                theme: theme,
                baseFont: parent.resolvedEditorFont
            )
            parent.enforceVisibleForeground(in: textView, theme: theme)
        }
    }
}

func sourceSelectionRange(
    for selection: MarkdownViewModel.SourceSelection,
    in text: String
) -> NSRange {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard !lines.isEmpty else { return NSRange(location: 0, length: 0) }

    let clampedLineIndex = min(max(selection.line - 1, 0), lines.count - 1)
    var location = 0
    for index in 0..<clampedLineIndex {
        location += (lines[index] as NSString).length + 1
    }

    let lineText = lines[clampedLineIndex] as NSString
    let targetColumn = max((selection.column ?? 1) - 1, 0)
    let clampedColumn = min(targetColumn, lineText.length)
    return NSRange(location: location + clampedColumn, length: 0)
}

final class CodeEditorLineNumberRulerView: NSRulerView {
    static let commentLaneWidth: CGFloat = 22
    static let minimumNumberDigits = 3

    private weak var textView: NSTextView?
    private var lineStarts: [Int] = [0]
    private var numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private var backgroundColor = NSColor.clear
    private var numberColor = NSColor.secondaryLabelColor
    private var activeNumberColor = NSColor.labelColor
    private var dividerColor = NSColor.separatorColor
    private var textStorageObservation: NSObjectProtocol?
    private var selectionObservation: NSObjectProtocol?
    private var scrollObservation: NSObjectProtocol?

    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        refreshLineStarts()
        observe(textView: textView, scrollView: scrollView)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let textStorageObservation {
            NotificationCenter.default.removeObserver(textStorageObservation)
        }
        if let selectionObservation {
            NotificationCenter.default.removeObserver(selectionObservation)
        }
        if let scrollObservation {
            NotificationCenter.default.removeObserver(scrollObservation)
        }
    }

    func update(
        isVisible: Bool,
        editorFont: NSFont,
        backgroundColor: NSColor,
        numberColor: NSColor,
        activeNumberColor: NSColor,
        dividerColor: NSColor
    ) {
        numberFont = NSFont.monospacedDigitSystemFont(
            ofSize: max(8, editorFont.pointSize * 0.82),
            weight: .regular
        )
        self.backgroundColor = backgroundColor
        self.numberColor = numberColor
        self.activeNumberColor = activeNumberColor
        self.dividerColor = dividerColor
        refreshLineStarts()

        guard let scrollView else { return }
        scrollView.hasVerticalRuler = isVisible
        scrollView.rulersVisible = isVisible
        let thickness = Self.requiredThickness(
            lineCount: lineStarts.count,
            font: numberFont
        )
        if abs(ruleThickness - thickness) > 0.5 {
            ruleThickness = thickness
            scrollView.tile()
        }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        dividerColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let origin = textView.textContainerOrigin
        let visibleTextRect = textView.visibleRect
        let visibleContainerRect = visibleTextRect.offsetBy(dx: -origin.x, dy: -origin.y)
        layoutManager.ensureLayout(forBoundingRect: visibleContainerRect, in: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleContainerRect,
            in: textContainer
        )
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        let selectedLineIndex = lineIndex(containing: textView.selectedRange().location)
        var index = max(0, lowerBound(for: characterRange.location) - 1)
        let visibleUpperBound = NSMaxRange(characterRange)

        while index < lineStarts.count {
            let characterLocation = lineStarts[index]
            if characterLocation > visibleUpperBound && index > 0 { break }
            guard let lineRect = lineFragmentRect(
                at: characterLocation,
                textView: textView,
                layoutManager: layoutManager
            ) else {
                index += 1
                continue
            }
            let point = convert(
                NSPoint(x: 0, y: origin.y + lineRect.minY),
                from: textView
            )
            let lineHeight = max(lineRect.height, numberFont.ascender - numberFont.descender)
            let label = "\(index + 1)" as NSString
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .right
            let attributes: [NSAttributedString.Key: Any] = [
                .font: numberFont,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: index == selectedLineIndex
                    ? activeNumberColor
                    : numberColor
            ]
            let size = label.size(withAttributes: attributes)
            let labelRect = NSRect(
                x: Self.commentLaneWidth + 4,
                y: point.y + max(0, (lineHeight - size.height) / 2),
                width: max(0, ruleThickness - Self.commentLaneWidth - 10),
                height: size.height
            )
            label.draw(in: labelRect, withAttributes: attributes)
            index += 1
        }
    }

    static func logicalLineStarts(in text: String) -> [Int] {
        let value = text as NSString
        var starts = [0]
        guard value.length > 0 else { return starts }
        for index in 0..<value.length where value.character(at: index) == 0x0A {
            starts.append(index + 1)
        }
        return starts
    }

    static func requiredThickness(lineCount: Int, font: NSFont) -> CGFloat {
        let digitCount = max(minimumNumberDigits, String(max(1, lineCount)).count)
        let sample = String(repeating: "8", count: digitCount) as NSString
        let width = sample.size(withAttributes: [.font: font]).width
        return ceil(commentLaneWidth + width + 14)
    }

    private func observe(textView: NSTextView, scrollView: NSScrollView) {
        if let storage = textView.textStorage {
            textStorageObservation = NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification,
                object: storage,
                queue: .main
            ) { [weak self, weak storage] _ in
                guard let self else { return }
                if storage?.editedMask.contains(.editedCharacters) == true {
                    self.refreshLineStarts()
                }
                self.needsDisplay = true
            }
        }
        selectionObservation = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObservation = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    private func refreshLineStarts() {
        lineStarts = Self.logicalLineStarts(in: textView?.string ?? "")
    }

    private func lowerBound(for characterLocation: Int) -> Int {
        var lower = 0
        var upper = lineStarts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lineStarts[middle] < characterLocation {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func lineIndex(containing characterLocation: Int) -> Int {
        max(0, min(lineStarts.count - 1, lowerBound(for: characterLocation + 1) - 1))
    }

    private func lineFragmentRect(
        at characterLocation: Int,
        textView: NSTextView,
        layoutManager: NSLayoutManager
    ) -> NSRect? {
        let length = (textView.string as NSString).length
        if length == 0 {
            return NSRect(
                x: 0,
                y: 0,
                width: 0,
                height: numberFont.ascender - numberFont.descender + numberFont.leading
            )
        }
        if characterLocation == length {
            guard length > 0 else { return nil }
            let previousGlyph = layoutManager.glyphIndexForCharacter(at: length - 1)
            let previousRect = layoutManager.lineFragmentRect(
                forGlyphAt: previousGlyph,
                effectiveRange: nil
            )
            return NSRect(
                x: previousRect.minX,
                y: previousRect.maxY,
                width: previousRect.width,
                height: previousRect.height
            )
        }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterLocation)
        return layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    }
}

final class ContentViewerDropAwareTextView: NSTextView {
    private static let contextualEditingSelectors: Set<Selector> = [
        #selector(NSText.cut(_:)),
        #selector(NSText.copy(_:)),
        #selector(NSText.paste(_:)),
        #selector(NSText.selectAll(_:))
    ]

    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        retargetContextualEditingItems(in: menu)
        addCommentMenuItemIfNeeded(in: menu)
        return menu
    }

    /// F049-R03 / R06: add an "Add Comment to Selection" item to the
    /// editor's context menu. Posts `commentsRequestAddForSelection` so the
    /// active pane's `CommentsPanelView` opens its composer pre-seeded with
    /// the current selection.
    private func addCommentMenuItemIfNeeded(in menu: NSMenu) {
        // Avoid duplicating if already injected on this menu instance.
        if menu.items.contains(where: { $0.identifier == .commentsAdd }) { return }

        menu.addItem(NSMenuItem.separator())
        let item = NSMenuItem(
            title: "Add Comment to Selection",
            action: #selector(addCommentForSelection(_:)),
            keyEquivalent: ""
        )
        item.identifier = .commentsAdd
        item.target = self
        menu.addItem(item)
    }

    @objc private func addCommentForSelection(_ sender: Any?) {
        let nsString = self.string as NSString
        let selected = self.selectedRange()
        let range: NSRange
        if selected.length == 0 {
            // Use whole line at caret as fallback
            let safeLoc = max(0, min(selected.location, nsString.length))
            range = nsString.lineRange(for: NSRange(location: safeLoc, length: 0))
        } else {
            range = selected
        }
        let safeLen = max(0, min(range.length, nsString.length - range.location))
        let safeRange = NSRange(location: range.location, length: safeLen)
        let anchorText = nsString.substring(with: safeRange)
        let (startLine, startCol) = lineColumnPair(at: safeRange.location, in: nsString)
        let endLoc = safeRange.location + safeRange.length
        let (endLine, endCol) = lineColumnPair(at: endLoc, in: nsString)
        let leadingStart = max(0, safeRange.location - CodeEditorCommentBridge.maxContextBytes)
        let leading = nsString.substring(with: NSRange(location: leadingStart, length: safeRange.location - leadingStart))
        let trailingLen = min(CodeEditorCommentBridge.maxContextBytes, max(0, nsString.length - endLoc))
        let trailing = trailingLen > 0
            ? nsString.substring(with: NSRange(location: endLoc, length: trailingLen))
            : ""

        // Build a CommentAnchor and delegate payload construction so the
        // notification schema lives in exactly one place.
        let anchor = CommentAnchor(
            startLine: startLine,
            startColumn: startCol,
            endLine: endLine,
            endColumn: endCol,
            anchorHash: CommentAnchor.hash(anchorText),
            anchorText: anchorText,
            leadingContext: leading,
            trailingContext: trailing
        )
        NotificationCenter.default.post(
            name: .commentsRequestAddForSelection,
            object: nil,
            userInfo: anchor.notificationPayload(filePath: commentFilePath)
        )
    }

    private func lineColumnPair(at offset: Int, in string: NSString) -> (Int, Int) {
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

    override class func scrollableTextView() -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        let textView = ContentViewerDropAwareTextView(frame: .zero)
        let contentSize = scrollView.contentSize

        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        let lineNumberRuler = CodeEditorLineNumberRulerView(
            scrollView: scrollView,
            textView: textView
        )
        scrollView.verticalRulerView = lineNumberRuler
        scrollView.hasVerticalRuler = false
        scrollView.rulersVisible = false

        return scrollView
    }

    var embeddedDropBridge: ContentViewerEmbeddedDropBridge? {
        didSet { updateRegisteredDraggedTypes() }
    }

    /// F049: file path of the open document, set by `CodeEditorView` so the
    /// "Add Comment to Selection" menu item can include it in its
    /// notification payload.
    var commentFilePath: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        updateRegisteredDraggedTypes()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        updateRegisteredDraggedTypes()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        updateRegisteredDraggedTypes()
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

    private func retargetContextualEditingItems(in menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                retargetContextualEditingItems(in: submenu)
            }

            guard let action = item.action,
                  Self.contextualEditingSelectors.contains(action) else {
                continue
            }
            item.target = self
        }
    }
}


extension NSUserInterfaceItemIdentifier {
    /// F049: identifier for the "Add Comment to Selection" context-menu item.
    static let commentsAdd = NSUserInterfaceItemIdentifier("comments.add-to-selection")
}
