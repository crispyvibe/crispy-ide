import AppKit

final class AppKitTreeScrollView: NSScrollView {
    private var allowsTreeScrolling = true

    func configureScrolling(allowsScrolling: Bool) {
        let scrollingChanged = allowsTreeScrolling != allowsScrolling
        allowsTreeScrolling = allowsScrolling
        hasVerticalScroller = allowsScrolling
        hasHorizontalScroller = false
        autohidesScrollers = allowsScrolling
        borderType = .noBorder
        drawsBackground = false
        verticalScrollElasticity = allowsScrolling ? .automatic : .none
        horizontalScrollElasticity = .none
        if scrollingChanged {
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        guard !allowsTreeScrolling,
              let outlineView = documentView as? NSOutlineView else {
            return super.intrinsicContentSize
        }

        guard outlineView.numberOfRows > 0 else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 0)
        }

        let lastRowRect = outlineView.rect(ofRow: outlineView.numberOfRows - 1)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(lastRowRect.maxY))
    }
}

final class AppKitOutlineView: NSOutlineView {
    var contextMenuProvider: ((FileItem) -> NSMenu?)?
    var rootContextMenuProvider: (() -> NSMenu?)?
    var primaryClickHandler: ((TreeNode, NSEvent) -> Bool)?
    var keyDownHandler: ((NSEvent) -> Bool)?

    private func finishInlineEditingIfNeeded() {
        window?.endEditing(for: nil)
    }

    override var acceptsFirstResponder: Bool { true }

    private func activeRenameCellView() -> AppKitTreeCellView? {
        let visibleRange = rows(in: visibleRect)
        guard visibleRange.length > 0 else { return nil }

        for row in visibleRange.location..<(visibleRange.location + visibleRange.length) {
            guard row >= 0, row < numberOfRows else { continue }
            guard let cellView = view(atColumn: 0, row: row, makeIfNecessary: false) as? AppKitTreeCellView,
                  cellView.isRenameInteractionActive else {
                continue
            }
            return cellView
        }

        return nil
    }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        .zero
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        finishInlineEditingIfNeeded()
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0, let node = item(atRow: row) as? TreeNode else {
            return rootContextMenuProvider?() ?? super.menu(for: event)
        }
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return contextMenuProvider?(node.item)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)

        if let firstResponder = window?.firstResponder as? NSTextView,
           let cellView = firstResponder.superview?.superview as? AppKitTreeCellView,
           cellView.isInRenameMode {
            super.mouseDown(with: event)
            return
        }

        finishInlineEditingIfNeeded()

        if row >= 0,
           let node = item(atRow: row) as? TreeNode,
           primaryClickHandler?(node, event) == true {
            return
        }

        super.mouseDown(with: event)

        if row >= 0 {
            _ = window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if let renameCellView = activeRenameCellView() {
            _ = renameCellView.ensureRenameFieldFocused()
        }

        if let editor = window?.firstResponder as? NSTextView,
           editor.superview is NSTextField {
            if let chars = event.charactersIgnoringModifiers,
               (chars == "\u{1b}" || chars == "\r" || chars == "\u{3}") {
                if keyDownHandler?(event) == true { return }
            }
            editor.keyDown(with: event)
            return
        }
        if keyDownHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}
