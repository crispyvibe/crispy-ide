import Foundation
import SwiftUI

struct PlainTextEditor: NSViewRepresentable {
    let fileURL: URL
    var embeddedDropBridge: ContentViewerEmbeddedDropBridge? = nil
    var pendingSourceSelection: MarkdownViewModel.SourceSelection? = nil
    var onPendingSourceSelectionConsumed: (() -> Void)? = nil
    var isBufferLoading: Bool = false
    @Binding var content: String
    let onContentChange: (String) -> Void
    @AppStorage(AppPreferences.codeFontFamilyKey)
    private var codeFontFamily = AppPreferences.defaultCodeFontFamily
    @AppStorage(AppPreferences.codeFontSizeKey)
    private var codeFontSize = AppPreferences.defaultCodeFontSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appThemePalette) private var appThemePalette
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ContentViewerDropAwareTextView.scrollableTextView()
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
            textView.delegate = context.coordinator
            textView.string = content
            context.coordinator.lastFileURL = fileURL.standardizedFileURL
            applyTheme(to: textView, colorScheme: colorScheme)
            applyPendingSourceSelectionIfNeeded(in: textView)
        }

        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? ContentViewerDropAwareTextView else { return }
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
        applyTheme(to: textView, colorScheme: colorScheme)
        if textView.string != content {
            let wasFirstResponder = textView.window?.firstResponder === textView
            let selectedRange = textView.selectedRange()
            let scrollOrigin = isDocumentSwitch ? nil : currentScrollOrigin(in: textView)
            textView.string = content
            if isDocumentSwitch {
                resetSelectionAndScroll(toStartIn: textView)
            } else {
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
        applyPendingSourceSelectionIfNeeded(in: textView)

    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func applyTheme(to textView: NSTextView, colorScheme: ColorScheme) {
        let theme = SyntaxTheme.fromPalette(appThemePalette, colorScheme: colorScheme)
        textView.drawsBackground = true
        textView.backgroundColor = theme.background
        textView.textColor = theme.text
        textView.insertionPointColor = theme.text
        let selectedBackground = appThemePalette.terminalSelectionBackground.nsColor
        textView.selectedTextAttributes = [
            .backgroundColor: selectedBackground,
            .foregroundColor: theme.text
        ]
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
    
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        var lastFileURL: URL?

        init(parent: PlainTextEditor) {
            self.parent = parent
            self.lastFileURL = parent.fileURL.standardizedFileURL
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.onContentChange(textView.string)
        }
    }
}
