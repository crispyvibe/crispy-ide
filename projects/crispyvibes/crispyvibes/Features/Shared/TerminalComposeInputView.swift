import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Compose Layout Tokens

enum ComposeLayoutTokens {
    // Compact bar (default state)
    static let compactBarHeight: CGFloat = 34
    static let compactBarCornerRadius: CGFloat = 17
    static let compactBarHorizontalPadding: CGFloat = 12
    static let compactBarIconSize: CGFloat = 14
    static let compactSendButtonSize: CGFloat = 24

    // Expanded overlay
    static let editorMinHeight: CGFloat = 28
    static let editorDefaultHeight: CGFloat = 28
    static let editorMaxHeight: CGFloat = 300
    static let editorCornerRadius: CGFloat = 12
    static let editorPadding: CGFloat = 8
    static let editorBorderOpacity: Double = 0.4
    static var editorFont: Font { AppTypographyTokens.scaledSystem(12, design: .monospaced) }

    static let resizeHandleHeight: CGFloat = 3
    static let resizeHandleVerticalPadding: CGFloat = 2
    static let resizeHandleOpacity: Double = 0.25

    static let actionButtonSize: CGFloat = 26
    static let actionIconSize: CGFloat = 13
    static let actionDisabledOpacity: Double = 0.3
    static let actionSecondaryOpacity: Double = 0.7

    static let contentHorizontalPadding: CGFloat = 10
    static let contentVerticalPadding: CGFloat = 8
    static let buttonSpacing: CGFloat = 4
    static let editorButtonSpacing: CGFloat = 6
    static let backgroundOpacity: Double = 0.3
    static let actionButtonCornerRadius: CGFloat = 7
    static let actionButtonBackgroundOpacity: Double = 0.08
    static let actionButtonPrimaryBackgroundOpacity: Double = 0.16
    static let actionButtonBorderOpacity: Double = 0.18

    static var shortcutFont: Font { AppTypographyTokens.scaledSystem(9, weight: .medium) }
    static let shortcutOpacity: Double = 0.5
}

// MARK: - Reusable Compose Input

struct TerminalComposeInputView: View {
    @Environment(\.appThemePalette) private var palette
    @Binding var text: String
    @Binding var pendingSelectionLocation: Int?
    @State private var editorHeight: CGFloat
    @State private var contentHeight: CGFloat = 28
    let isRephrasing: Bool
    let showBroadcast: Bool
    let requestFocus: Bool
    let canSendOverride: Bool?
    let showsResizeHandle: Bool
    let showsBackground: Bool
    let verticalPadding: CGFloat
    let onSend: () -> Void
    let onBroadcast: (() -> Void)?
    let onRephrase: () -> Void
    let onCycleTargetUp: (() -> Void)?
    let onCycleTargetDown: (() -> Void)?
    let inlineOverlayActive: Bool
    let onInlineMoveUp: (() -> Void)?
    let onInlineMoveDown: (() -> Void)?
    let onInlineMoveRight: (() -> Void)?
    let onInlineConfirm: (() -> Void)?
    let onInlineDismiss: (() -> Void)?
    let onPasteImage: ((NSImage) -> Void)?
    let onHistoryBack: (() -> Void)?
    let onHistoryForward: (() -> Void)?

    init(
        text: Binding<String>,
        pendingSelectionLocation: Binding<Int?> = .constant(nil),
        initialHeight: CGFloat = ComposeLayoutTokens.editorDefaultHeight,
        isRephrasing: Bool = false,
        showBroadcast: Bool = false,
        requestFocus: Bool = false,
        canSendOverride: Bool? = nil,
        showsResizeHandle: Bool = true,
        showsBackground: Bool = true,
        verticalPadding: CGFloat = ComposeLayoutTokens.contentVerticalPadding,
        onSend: @escaping () -> Void,
        onBroadcast: (() -> Void)? = nil,
        onRephrase: @escaping () -> Void,
        onCycleTargetUp: (() -> Void)? = nil,
        onCycleTargetDown: (() -> Void)? = nil,
        inlineOverlayActive: Bool = false,
        onInlineMoveUp: (() -> Void)? = nil,
        onInlineMoveDown: (() -> Void)? = nil,
        onInlineMoveRight: (() -> Void)? = nil,
        onInlineConfirm: (() -> Void)? = nil,
        onInlineDismiss: (() -> Void)? = nil,
        onPasteImage: ((NSImage) -> Void)? = nil,
        onHistoryBack: (() -> Void)? = nil,
        onHistoryForward: (() -> Void)? = nil
    ) {
        _text = text
        _pendingSelectionLocation = pendingSelectionLocation
        _editorHeight = State(initialValue: initialHeight)
        self.isRephrasing = isRephrasing
        self.showBroadcast = showBroadcast
        self.requestFocus = requestFocus
        self.canSendOverride = canSendOverride
        self.showsResizeHandle = showsResizeHandle
        self.showsBackground = showsBackground
        self.verticalPadding = verticalPadding
        self.onSend = onSend
        self.onBroadcast = onBroadcast
        self.onRephrase = onRephrase
        self.onCycleTargetUp = onCycleTargetUp
        self.onCycleTargetDown = onCycleTargetDown
        self.inlineOverlayActive = inlineOverlayActive
        self.onInlineMoveUp = onInlineMoveUp
        self.onInlineMoveDown = onInlineMoveDown
        self.onInlineMoveRight = onInlineMoveRight
        self.onInlineConfirm = onInlineConfirm
        self.onInlineDismiss = onInlineDismiss
        self.onPasteImage = onPasteImage
        self.onHistoryBack = onHistoryBack
        self.onHistoryForward = onHistoryForward
    }

    private var canSend: Bool {
        canSendOverride ?? !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            composeEditor

            // Inline action buttons — show only when there's text
            if canSend {
                if isRephrasing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    VStack(spacing: 1) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.accentColor.opacity(0.7))
                            .frame(width: 24, height: 24)
                        Text("⌘R")
                            .font(ComposeLayoutTokens.shortcutFont)
                            .foregroundStyle(palette.secondaryTextColor.opacity(ComposeLayoutTokens.shortcutOpacity))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onRephrase() }
                }

                if showBroadcast, let onBroadcast {
                    VStack(spacing: 1) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.accentColor.opacity(0.7))
                            .frame(width: 24, height: 24)
                        Text("⌘B")
                            .font(ComposeLayoutTokens.shortcutFont)
                            .foregroundStyle(palette.secondaryTextColor.opacity(ComposeLayoutTokens.shortcutOpacity))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onBroadcast() }
                }
            }

            // Send button — always visible
            VStack(spacing: 1) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(canSend ? .white : palette.secondaryTextColor.opacity(0.4))
                    .frame(width: ComposeLayoutTokens.compactSendButtonSize, height: ComposeLayoutTokens.compactSendButtonSize)
                    .background(
                        Circle()
                            .fill(canSend ? palette.accentColor : palette.primaryTextColor.opacity(0.06))
                    )
                if canSend {
                    Text("⌘↩")
                        .font(ComposeLayoutTokens.shortcutFont)
                        .foregroundStyle(palette.secondaryTextColor.opacity(ComposeLayoutTokens.shortcutOpacity))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if canSend { onSend() } }
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .scrollAssistGlassBackground(in: RoundedRectangle(cornerRadius: ComposeLayoutTokens.editorCornerRadius))
        .shadow(color: canSend ? palette.accentColor.opacity(0.3) : .clear, radius: 6, y: 0)
        .animation(.easeOut(duration: 0.2), value: canSend)
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty {
                contentHeight = 28
            }
        }
    }

    // MARK: - Compact Bar

    private var composeResizeHandle: some View {
        Rectangle()
            .fill(palette.borderColorValue.opacity(ComposeLayoutTokens.resizeHandleOpacity))
            .frame(height: ComposeLayoutTokens.resizeHandleHeight)
            .frame(maxWidth: .infinity)
            .padding(.vertical, ComposeLayoutTokens.resizeHandleVerticalPadding)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        editorHeight = max(
                            ComposeLayoutTokens.editorMinHeight,
                            min(ComposeLayoutTokens.editorMaxHeight, editorHeight - value.translation.height)
                        )
                    }
            )
            .onHover { hovering in
                #if os(macOS)
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                #endif
            }
    }

    private var composeEditor: some View {
        ComposeTextEditorRepresentable(
            text: $text,
            contentHeight: $contentHeight,
            pendingSelectionLocation: $pendingSelectionLocation,
            requestFocus: requestFocus,
            palette: palette,
            canSend: canSend,
            showBroadcast: showBroadcast,
            isRephrasing: isRephrasing,
            onSend: onSend,
            onBroadcast: onBroadcast,
            onRephrase: onRephrase,
            onCycleTargetUp: onCycleTargetUp,
            onCycleTargetDown: onCycleTargetDown,
            inlineOverlayActive: inlineOverlayActive,
            onInlineMoveUp: onInlineMoveUp,
            onInlineMoveDown: onInlineMoveDown,
            onInlineMoveRight: onInlineMoveRight,
            onInlineConfirm: onInlineConfirm,
            onInlineDismiss: onInlineDismiss,
            onPasteImage: onPasteImage,
            onHistoryBack: onHistoryBack,
            onHistoryForward: onHistoryForward
        )
            .frame(maxWidth: .infinity)
            .frame(height: min(contentHeight, ComposeLayoutTokens.editorMaxHeight))
    }

    private var composeActions: some View {
        VStack(spacing: ComposeLayoutTokens.buttonSpacing) {
            composeActionButton(
                icon: "paperplane.fill",
                shortcut: "⌘↩",
                keyboardShortcut: .return,
                enabled: canSend,
                primary: true
            ) { onSend() }

            if showBroadcast, let onBroadcast {
                composeActionButton(
                    icon: "antenna.radiowaves.left.and.right",
                    shortcut: "⌘B",
                    keyboardShortcut: "b",
                    enabled: canSend,
                    primary: false
                ) { onBroadcast() }
            }

            if isRephrasing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: ComposeLayoutTokens.actionButtonSize, height: ComposeLayoutTokens.actionButtonSize)
            } else {
                composeActionButton(
                    icon: "wand.and.stars",
                    shortcut: "⌘R",
                    keyboardShortcut: "r",
                    enabled: canSend,
                    primary: false
                ) { onRephrase() }
            }
        }
    }

    private func composeActionButton(
        icon: String,
        shortcut: String,
        keyboardShortcut: KeyEquivalent?,
        keyboardShortcutModifiers: EventModifiers = [.command],
        enabled: Bool,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 1) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(AppTypographyTokens.scaledIcon(ComposeLayoutTokens.actionIconSize, weight: primary ? .regular : .semibold))
                    .foregroundStyle(
                        enabled
                            ? palette.accentColor.opacity(primary ? 1 : ComposeLayoutTokens.actionSecondaryOpacity)
                            : palette.secondaryTextColor.opacity(ComposeLayoutTokens.actionDisabledOpacity)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: ComposeLayoutTokens.actionButtonCornerRadius, style: .continuous)
                            .fill(
                                enabled
                                    ? (primary
                                        ? palette.accentColor.opacity(ComposeLayoutTokens.actionButtonPrimaryBackgroundOpacity)
                                        : palette.primaryTextColor.opacity(ComposeLayoutTokens.actionButtonBackgroundOpacity))
                                    : palette.primaryTextColor.opacity(0.03)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ComposeLayoutTokens.actionButtonCornerRadius, style: .continuous)
                            .stroke(
                                enabled
                                    ? (primary
                                        ? palette.accentColor.opacity(0.32)
                                        : palette.borderColorValue.opacity(ComposeLayoutTokens.actionButtonBorderOpacity))
                                    : palette.borderColorValue.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .optionalKeyboardShortcut(keyboardShortcut, modifiers: keyboardShortcutModifiers)
            .frame(width: ComposeLayoutTokens.actionButtonSize, height: ComposeLayoutTokens.actionButtonSize)

            Text(shortcut)
                .font(ComposeLayoutTokens.shortcutFont)
                .foregroundStyle(palette.secondaryTextColor.opacity(ComposeLayoutTokens.shortcutOpacity))
        }
    }
}

private struct OptionalKeyboardShortcutModifier: ViewModifier {
    let key: KeyEquivalent?
    let modifiers: EventModifiers

    @ViewBuilder
    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: modifiers)
        } else {
            content
        }
    }
}

private extension View {
    func optionalKeyboardShortcut(_ key: KeyEquivalent?, modifiers: EventModifiers) -> some View {
        modifier(OptionalKeyboardShortcutModifier(key: key, modifiers: modifiers))
    }
}

#if os(macOS)
private struct ComposeTextEditorRepresentable: NSViewRepresentable {
    @Environment(\.crispyvibesUIScale) private var uiScale

    @Binding var text: String
    @Binding var contentHeight: CGFloat
    @Binding var pendingSelectionLocation: Int?

    let requestFocus: Bool
    let palette: AppThemePalette
    let canSend: Bool
    let showBroadcast: Bool
    let isRephrasing: Bool
    let onSend: () -> Void
    let onBroadcast: (() -> Void)?
    let onRephrase: () -> Void
    let onCycleTargetUp: (() -> Void)?
    let onCycleTargetDown: (() -> Void)?
    let inlineOverlayActive: Bool
    let onInlineMoveUp: (() -> Void)?
    let onInlineMoveDown: (() -> Void)?
    let onInlineMoveRight: (() -> Void)?
    let onInlineConfirm: (() -> Void)?
    let onInlineDismiss: (() -> Void)?
    let onPasteImage: ((NSImage) -> Void)?
    let onHistoryBack: (() -> Void)?
    let onHistoryForward: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        let textView = ComposeTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
        configureOnce(textView: textView)
        configureDynamic(textView: textView, coordinator: context.coordinator)
        textView.string = text
        DispatchQueue.main.async {
            context.coordinator.updateContentHeight(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposeTextView else { return }
        configureDynamic(textView: textView, coordinator: context.coordinator)

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            let length = (textView.string as NSString).length
            let safeRange = NSRange(
                location: min(selectedRange.location, length),
                length: min(selectedRange.length, max(0, length - min(selectedRange.location, length)))
            )
            textView.setSelectedRange(safeRange)
            context.coordinator.updateContentHeight(textView)
        }

        if let pendingSelectionLocation {
            let location = min(pendingSelectionLocation, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            DispatchQueue.main.async {
                self.pendingSelectionLocation = nil
            }
        }

        if requestFocus, context.coordinator.lastFocusRequest != requestFocus {
            DispatchQueue.main.async {
                guard let window = textView.window else { return }
                if window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
            }
        }
        context.coordinator.lastFocusRequest = requestFocus
    }

    private func configureOnce(textView: ComposeTextView) {
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.drawsBackground = false
    }

    private func configureDynamic(textView: ComposeTextView, coordinator: Coordinator) {
        coordinator.textView = textView
        textView.delegate = coordinator
        textView.backgroundColor = .clear
        textView.textColor = palette.terminalForeground.nsColor
        textView.insertionPointColor = palette.terminalForeground.nsColor
        let targetFont = NSFont.monospacedSystemFont(ofSize: uiScale.textSize(12), weight: .regular)
        if textView.font?.fontName != targetFont.fontName ||
            abs((textView.font?.pointSize ?? 0) - targetFont.pointSize) > 0.1 {
            textView.font = targetFont
        }
        textView.selectedTextAttributes = [
            .backgroundColor: palette.terminalSelectionBackground.nsColor,
            .foregroundColor: palette.terminalForeground.nsColor
        ]
        textView.canSend = canSend
        textView.showBroadcast = showBroadcast
        textView.isRephrasing = isRephrasing
        textView.onSend = onSend
        textView.onBroadcast = onBroadcast
        textView.onRephrase = onRephrase
        textView.onCycleTargetUp = onCycleTargetUp
        textView.onCycleTargetDown = onCycleTargetDown
        textView.inlineOverlayActive = inlineOverlayActive
        textView.onInlineMoveUp = onInlineMoveUp
        textView.onInlineMoveDown = onInlineMoveDown
        textView.onInlineMoveRight = onInlineMoveRight
        textView.onInlineConfirm = onInlineConfirm
        textView.onInlineDismiss = onInlineDismiss
        textView.onPasteImage = onPasteImage
        textView.onHistoryBack = onHistoryBack
        textView.onHistoryForward = onHistoryForward
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var contentHeight: CGFloat
        weak var textView: NSTextView?
        var lastFocusRequest = false

        init(text: Binding<String>, contentHeight: Binding<CGFloat>) {
            _text = text
            _contentHeight = contentHeight
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            if textView.string.isEmpty {
                DispatchQueue.main.async { self.contentHeight = 28 }
            } else {
                updateContentHeight(textView)
            }
        }

        func updateContentHeight(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = max(28, usedRect.height + textView.textContainerInset.height * 2)
            if abs(newHeight - contentHeight) > 1 {
                DispatchQueue.main.async {
                    self.contentHeight = newHeight
                }
            }
        }
    }
}

private final class ComposeTextView: NSTextView {
    private static let contextualEditingSelectors: Set<Selector> = [
        #selector(NSText.cut(_:)),
        #selector(NSText.copy(_:)),
        #selector(NSText.paste(_:)),
        #selector(NSText.selectAll(_:))
    ]

    var canSend = false
    var showBroadcast = false
    var isRephrasing = false
    var placeholderString = "Compose message… (⌘↩ to send)"
    var placeholderColor: NSColor = .secondaryLabelColor
    var onSend: (() -> Void)?
    var onBroadcast: (() -> Void)?
    var onRephrase: (() -> Void)?
    var onCycleTargetUp: (() -> Void)?
    var onCycleTargetDown: (() -> Void)?
    var inlineOverlayActive = false
    var onInlineMoveUp: (() -> Void)?
    var onInlineMoveDown: (() -> Void)?
    var onInlineMoveRight: (() -> Void)?
    var onInlineConfirm: (() -> Void)?
    var onInlineDismiss: (() -> Void)?
    var onPasteImage: ((NSImage) -> Void)?
    var onHistoryBack: (() -> Void)?
    var onHistoryForward: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let font = self.font {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: placeholderColor
            ]
            let inset = textContainerInset
            let rect = NSRect(x: inset.width + (textContainer?.lineFragmentPadding ?? 0),
                              y: inset.height, width: bounds.width, height: bounds.height)
            placeholderString.draw(in: rect, withAttributes: attrs)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true // redraw to show/hide placeholder
    }

    private var isCaretOnFirstVisualLine: Bool {
        guard let layoutManager, let textContainer else { return true }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: selectedRange().location)
        let caretLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let firstLineRect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        return caretLineRect.origin.y == firstLineRect.origin.y
    }

    private var isCaretOnLastVisualLine: Bool {
        guard let layoutManager, let textContainer else { return true }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: selectedRange().location)
        let caretLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let lastGlyphIndex = max(0, layoutManager.numberOfGlyphs - 1)
        let lastLineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
        return caretLineRect.origin.y == lastLineRect.origin.y
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        guard let menu = super.menu(for: event) else { return nil }
        retargetContextualEditingItems(in: menu)
        return menu
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        reclaimFocusAfterFileDropIfNeeded(from: sender.draggingPasteboard)
        return super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        reclaimFocusAfterFileDropIfNeeded(from: sender.draggingPasteboard)
        return super.performDragOperation(sender)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(NSText.paste(_:)) {
            let pb = NSPasteboard.general
            // Always enable paste if there's anything useful on the pasteboard
            if pb.availableType(from: [.string, .tiff, .png, .fileURL]) != nil {
                return true
            }
        }
        return super.validateMenuItem(menuItem)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        // Intercept image pastes when the caller renders image attachments separately.
        if let onPasteImage {
            // Check for image data on pasteboard
            if let imageType = pb.availableType(from: [.tiff, .png]),
               let data = pb.data(forType: imageType),
               let image = NSImage(data: data) {
                onPasteImage(image)
                return
            }
            // Check for file URLs pointing to images
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
                let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "tiff", "bmp"]
                for url in urls where imageExtensions.contains(url.pathExtension.lowercased()) {
                    if let image = NSImage(contentsOf: url) {
                        onPasteImage(image)
                        return
                    }
                }
            }
        }
        // For terminal/spotlight compose: paste file URLs as paths
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let paths = urls.map(\.path).joined(separator: " ")
            insertText(paths, replacementRange: selectedRange())
            return
        }
        if let imagePath = saveClipboardImageIfNeeded(from: pb) {
            insertText(imagePath, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    private func saveClipboardImageIfNeeded(from pasteboard: NSPasteboard) -> String? {
        let types = pasteboard.types ?? []
        let hasText = types.contains(.string) || types.contains(.html) || types.contains(.rtf) || types.contains(.rtfd)
        guard !hasText else { return nil }

        guard let image = NSImage(pasteboard: pasteboard),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "crispyvibes-terminal-paste",
            isDirectory: true
        )
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "clipboard-\(timestamp)-\(UUID().uuidString.prefix(8)).png"
        let fileURL = directory.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pngData.write(to: fileURL, options: .atomic)
            return ShellEscaping.singleQuote(fileURL.path)
        } catch {
            return nil
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if handleSendShortcut(modifiers: modifiers, keyCode: event.keyCode) {
            return true
        }

        if modifiers == [.command], characters == "b", showBroadcast, canSend {
            onBroadcast?()
            return true
        }

        if modifiers == [.command], characters == "r", canSend, !isRephrasing {
            onRephrase?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if handleSendShortcut(modifiers: modifiers, keyCode: event.keyCode) {
            return
        }

        if inlineOverlayActive, modifiers.isEmpty {
            switch event.keyCode {
            case 36, 76:
                onInlineConfirm?()
                return
            case 48:
                onInlineConfirm?()
                return
            case 53:
                onInlineDismiss?()
                return
            case 125:
                onInlineMoveDown?()
                return
            case 126:
                onInlineMoveUp?()
                return
            case 124:
                onInlineMoveRight?()
                return
            default:
                break
            }
        }

        if modifiers == [.option], event.keyCode == 126 {
            onCycleTargetUp?()
            return
        }

        if modifiers == [.option], event.keyCode == 125 {
            onCycleTargetDown?()
            return
        }

        // History navigation: plain Up/Down, no overlay, zero-width caret
        if modifiers.isEmpty, selectedRange().length == 0, !inlineOverlayActive {
            if event.keyCode == 126, isCaretOnFirstVisualLine, onHistoryBack != nil {
                onHistoryBack?()
                return
            }
            if event.keyCode == 125, isCaretOnLastVisualLine, onHistoryForward != nil {
                onHistoryForward?()
                return
            }
        }

        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        if inlineOverlayActive {
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                onInlineMoveDown?()
                return
            case #selector(NSResponder.moveUp(_:)):
                onInlineMoveUp?()
                return
            case #selector(NSResponder.moveRight(_:)):
                onInlineMoveRight?()
                return
            case #selector(NSResponder.insertTab(_:)):
                onInlineConfirm?()
                return
            case #selector(NSResponder.insertNewline(_:)):
                onInlineConfirm?()
                return
            case #selector(NSResponder.cancelOperation(_:)):
                onInlineDismiss?()
                return
            default:
                break
            }
        }

        // History navigation: plain moveUp/moveDown when no overlay, zero-width caret,
        // and caret is on first/last visual line.
        if !inlineOverlayActive, selectedRange().length == 0 {
            if selector == #selector(NSResponder.moveUp(_:)),
               isCaretOnFirstVisualLine,
               let onHistoryBack {
                onHistoryBack()
                return
            }
            if selector == #selector(NSResponder.moveDown(_:)),
               isCaretOnLastVisualLine,
               let onHistoryForward {
                onHistoryForward()
                return
            }
        }

        super.doCommand(by: selector)
    }

    private func handleSendShortcut(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        guard modifiers == [.command], keyCode == 36 || keyCode == 76 else {
            return false
        }
        guard canSend else { return true }
        onSend?()
        return true
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

    private func reclaimFocusAfterFileDropIfNeeded(from pasteboard: NSPasteboard) {
        guard !TerminalFileDropSupport.fileURLs(from: pasteboard).isEmpty else { return }
        TerminalFileDropSupport.requestFocus(for: self)
    }
}
#endif
