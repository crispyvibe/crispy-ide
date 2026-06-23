import AppKit
import Foundation
import PDFKit

// MARK: - CompiledPreviewContainerView

/// Hosts the visible `PDFView`, a status/error overlay, and the transient
/// inline line-editor. Forwards page clicks (page index + PDF-space point +
/// window-space point) to the coordinator.
@MainActor
final class CompiledPreviewContainerView: NSView {
    let pdfView = ClickablePDFView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let statusScroll = NSScrollView()
    private let statusText = NSTextView()
    private var editPanel: NSView?
    private var editTextView: NSTextView?
    private var editCommit: ((String) -> Void)?
    private var errorBanner: NSView?
    private var hintShown = false
    private var highlightAnnotations: [(PDFPage, PDFAnnotation)] = []

    var onPageClick: ((Int, CGPoint, CGPoint) -> Void)? {
        get { pdfView.onPageClick }
        set { pdfView.onPageClick = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.autoresizingMask = [.width, .height]
        pdfView.frame = bounds
        addSubview(pdfView)

        statusLabel.font = NSFont.preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])

        statusText.isEditable = false
        statusText.isSelectable = true
        statusText.drawsBackground = false
        statusText.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusText.textColor = .secondaryLabelColor
        statusScroll.documentView = statusText
        statusScroll.hasVerticalScroller = true
        statusScroll.drawsBackground = false
        statusScroll.autoresizingMask = [.width, .height]
        statusScroll.frame = bounds
        statusScroll.isHidden = true
        addSubview(statusScroll)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func display(document: PDFDocument) {
        // Preserve the page AND the scroll point across recompiles (not just the
        // page) so a re-render doesn't jump the reader.
        clearHighlight()
        let prevIndex = pdfView.currentPage.flatMap { pdfView.document?.index(for: $0) }
        let prevPoint = pdfView.currentDestination?.point
        pdfView.document = document
        if let prevIndex, prevIndex < document.pageCount, let page = document.page(at: prevIndex) {
            if let prevPoint {
                pdfView.go(to: PDFDestination(page: page, at: prevPoint))
            } else {
                pdfView.go(to: page)
            }
        }
        pdfView.isHidden = false
        statusScroll.isHidden = true
        statusLabel.isHidden = true
        hideErrorBanner()
        showFirstRunHintIfNeeded()
    }

    func showStatus(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        statusLabel.isHidden = false
        statusScroll.isHidden = true
        if pdfView.document == nil { pdfView.isHidden = true }
    }

    func showCompileError(log: String) {
        // Non-destructive: if we already have a rendered page, keep it and show
        // a dismissible banner. Only take over the whole view when there is no
        // previous PDF to fall back to.
        if pdfView.document != nil {
            showErrorBanner()
            return
        }
        statusLabel.isHidden = true
        statusText.string = "\(AppStrings.LaTeX.compileFailedTitle)\n\n\(log)"
        statusScroll.isHidden = false
        statusScroll.frame = bounds
        pdfView.isHidden = true
    }

    // MARK: Error banner (non-destructive)

    private func showErrorBanner() {
        hideErrorBanner()
        let bar = NSView(frame: NSRect(x: 0, y: bounds.height - 30, width: bounds.width, height: 30))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.92).cgColor
        bar.autoresizingMask = [.width, .minYMargin]
        let label = NSTextField(labelWithString: "Compilation failed \u{2014} showing the last successful render")
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.frame = NSRect(x: 12, y: 6, width: bar.bounds.width - 90, height: 18)
        label.autoresizingMask = [.width]
        bar.addSubview(label)
        let close = NSButton(title: "Dismiss", target: self, action: #selector(dismissErrorBanner))
        close.bezelStyle = .inline
        close.controlSize = .small
        close.frame = NSRect(x: bar.bounds.width - 76, y: 4, width: 64, height: 22)
        close.autoresizingMask = [.minXMargin]
        bar.addSubview(close)
        addSubview(bar)
        errorBanner = bar
    }

    @objc private func dismissErrorBanner() { hideErrorBanner() }

    private func hideErrorBanner() {
        errorBanner?.removeFromSuperview()
        errorBanner = nil
    }

    // MARK: Mapped-region highlight

    /// Draw a translucent overlay over the page region a SyncTeX forward map
    /// resolved to, so the user sees exactly which area their edit affects.
    /// `syncBoxes` are in SyncTeX coordinates (top-left origin, points); they're
    /// converted to PDFKit page coordinates (bottom-left origin) here, where the
    /// true page height is known. Annotations track zoom/scroll automatically.
    func showHighlight(syncBoxes: [LaTeXNativeCompiler.SyncBox]) {
        clearHighlight()
        guard let doc = pdfView.document, !syncBoxes.isEmpty else { return }
        var unions: [Int: CGRect] = [:]
        for box in syncBoxes {
            let pageIndex = box.page - 1
            guard pageIndex >= 0, pageIndex < doc.pageCount, let page = doc.page(at: pageIndex) else { continue }
            let pageHeight = page.bounds(for: .mediaBox).height
            let rect = CGRect(
                x: box.h - 2,
                y: pageHeight - box.v - box.height - 2,
                width: max(box.width, 8) + 4,
                height: box.height + 4
            )
            unions[pageIndex] = unions[pageIndex]?.union(rect) ?? rect
        }
        for (pageIndex, rect) in unions {
            guard let page = doc.page(at: pageIndex) else { continue }
            let annotation = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
            annotation.color = .clear
            annotation.interiorColor = NSColor.controlAccentColor.withAlphaComponent(0.16)
            let border = PDFBorder()
            border.lineWidth = 0
            annotation.border = border
            page.addAnnotation(annotation)
            highlightAnnotations.append((page, annotation))
        }
    }

    func clearHighlight() {
        for (page, annotation) in highlightAnnotations { page.removeAnnotation(annotation) }
        highlightAnnotations.removeAll()
    }

    // MARK: Comment affordance (select text -> "Comment")

    private var commentButton: NSButton?
    private var commentButtonAction: (() -> Void)?

    /// Float a "Comment" button just above the current text selection — the
    /// same select-then-comment gesture used elsewhere in the app. `pdfViewRect`
    /// is in the PDFView's coordinate space; convert to the container's space
    /// (PDFView is flipped, the container is not) before placing the button.
    func showCommentButton(near pdfViewRect: CGRect, onClick: @escaping () -> Void) {
        commentButtonAction = onClick
        let viewRect = convert(pdfViewRect, from: pdfView)
        let button: NSButton
        if let existing = commentButton {
            button = existing
        } else {
            button = NSButton(title: "Comment", target: self, action: #selector(commentButtonTapped))
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.bezelColor = .controlAccentColor
            button.contentTintColor = .white
            button.attributedTitle = NSAttributedString(
                string: "Comment",
                attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)]
            )
            button.wantsLayer = true
            button.shadow = NSShadow()
            addSubview(button)
            commentButton = button
        }
        let width: CGFloat = 110, height: CGFloat = 28
        var x = viewRect.midX - width / 2
        x = min(max(8, x), max(8, bounds.width - width - 8))
        var y = viewRect.maxY + 6
        if y + height > bounds.height - 8 { y = max(8, viewRect.minY - height - 6) }
        button.frame = NSRect(x: x, y: y, width: width, height: height)
        button.isHidden = false
    }

    func hideCommentButton() { commentButton?.isHidden = true }

    @objc private func commentButtonTapped() { commentButtonAction?() }

    // MARK: First-run hint

    private func showFirstRunHintIfNeeded() {
        guard !hintShown else { return }
        hintShown = true
        let hint = NSTextField(labelWithString: "Double-click any text to edit \u{00B7} \u{2318}\u{21A9} to save")
        hint.textColor = .white
        hint.backgroundColor = NSColor.black.withAlphaComponent(0.72)
        hint.drawsBackground = true
        hint.isBezeled = false
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.alignment = .center
        hint.wantsLayer = true
        hint.layer?.cornerRadius = 8
        let width: CGFloat = 340, height: CGFloat = 28
        hint.frame = NSRect(x: (bounds.width - width) / 2, y: 16, width: width, height: height)
        hint.autoresizingMask = [.minXMargin, .maxXMargin]
        addSubview(hint)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak hint] in hint?.removeFromSuperview() }
    }

    // MARK: Block editor

    /// Show a multi-line editor near the clicked point, prefilled with the
    /// source block. Commits on the Save button or Cmd-Return; cancels on Esc
    /// or the Cancel button.
    func beginBlockEdit(atWindowPoint windowPoint: CGPoint, text: String, rangeLabel: String, onCommit: @escaping (String) -> Void) {
        dismissEditor(commit: false)
        let local = convert(windowPoint, from: nil)

        let panelWidth = min(max(360, bounds.width - 48), 680)
        let headerHeight: CGFloat = 22
        let buttonBarHeight: CGFloat = 34
        let lineCount = max(text.components(separatedBy: "\n").count, 1)
        let textHeight = min(max(CGFloat(lineCount) * 17 + 14, 56), max(120, bounds.height * 0.5))
        let panelHeight = headerHeight + textHeight + buttonBarHeight

        var originX = local.x - 12
        originX = min(max(8, originX), max(8, bounds.width - panelWidth - 8))
        var originY = local.y - panelHeight - 10
        if originY < 8 { originY = min(local.y + 10, bounds.height - panelHeight - 8) }
        originY = max(8, originY)

        let panel = NSView(frame: NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight))
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        panel.layer?.borderWidth = 1
        panel.layer?.cornerRadius = 8
        panel.shadow = NSShadow()

        // Header: which source lines this edits (ties to the page region).
        let header = NSTextField(labelWithString: rangeLabel)
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.frame = NSRect(x: 10, y: panelHeight - headerHeight, width: panelWidth - 20, height: headerHeight - 2)
        header.autoresizingMask = [.width, .minYMargin]
        panel.addSubview(header)

        let scroll = NSScrollView(frame: NSRect(x: 1, y: buttonBarHeight, width: panelWidth - 2, height: panelHeight - headerHeight - buttonBarHeight))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        let textView = BlockEditTextView(frame: scroll.bounds)
        textView.string = text
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.onCommit = { [weak self] in self?.dismissEditor(commit: true) }
        textView.onCancel = { [weak self] in self?.dismissEditor(commit: false) }
        scroll.documentView = textView
        panel.addSubview(scroll)

        // Footer: keyboard hint (left) + Cancel/Save (right).
        let hint = NSTextField(labelWithString: "\u{2318}\u{21A9} Save \u{00B7} Esc Cancel")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 10, y: 9, width: 180, height: 16)
        panel.addSubview(hint)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(blockEditCancel))
        cancel.bezelStyle = .rounded
        cancel.controlSize = .small
        cancel.frame = NSRect(x: panelWidth - 150, y: 4, width: 68, height: 24)
        cancel.autoresizingMask = [.minXMargin]
        panel.addSubview(cancel)

        let save = NSButton(title: "Save", target: self, action: #selector(blockEditSave))
        save.bezelStyle = .rounded
        save.controlSize = .small
        save.bezelColor = .controlAccentColor
        save.frame = NSRect(x: panelWidth - 78, y: 4, width: 70, height: 24)
        save.autoresizingMask = [.minXMargin]
        panel.addSubview(save)

        addSubview(panel)
        window?.makeFirstResponder(textView)
        editPanel = panel
        editTextView = textView
        editCommit = onCommit
    }

    @objc private func blockEditSave() { dismissEditor(commit: true) }
    @objc private func blockEditCancel() { dismissEditor(commit: false) }

    private func dismissEditor(commit: Bool) {
        guard let panel = editPanel else { return }
        let value = editTextView?.string ?? ""
        let handler = editCommit
        editPanel = nil
        editTextView = nil
        editCommit = nil
        panel.removeFromSuperview()
        clearHighlight()
        if commit { handler?(value) }
    }
}

// MARK: - BlockEditTextView

/// Multi-line editor that commits on Cmd-Return and cancels on Esc.
@MainActor
final class BlockEditTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Cmd-Return commits.
        if event.keyCode == 36, event.modifierFlags.contains(.command) {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

// MARK: - ClickablePDFView

/// A `PDFView` that reports clicks as a 1-based page index, a point in PDF
/// coordinates from the page top-left (SyncTeX's convention), and the original
/// window-space point (for placing the inline editor).
@MainActor
final class ClickablePDFView: PDFView {
    var onPageClick: ((Int, CGPoint, CGPoint) -> Void)?
    var onProbableSelection: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event) // runs the selection drag loop synchronously
        guard event.clickCount == 2 else {
            // Single click / drag finished — the text selection may have changed.
            onProbableSelection?()
            return
        }
        let windowPoint = event.locationInWindow
        let viewPoint = convert(windowPoint, from: nil)
        guard let document, let page = page(for: viewPoint, nearest: true) else { return }
        let pageIndex = document.index(for: page)
        let pagePoint = convert(viewPoint, to: page)
        let mediaBounds = page.bounds(for: .mediaBox)
        let topLeft = CGPoint(x: pagePoint.x, y: mediaBounds.height - pagePoint.y)
        onPageClick?(pageIndex + 1, topLeft, windowPoint)
    }
}
