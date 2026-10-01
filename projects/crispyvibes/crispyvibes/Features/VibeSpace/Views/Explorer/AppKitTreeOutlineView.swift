import AppKit

final class AppKitTreeScrollView: NSScrollView {
    private var allowsTreeScrolling = true
    private var usesIntrinsicTreeHeight = true

    func configureScrolling(allowsScrolling: Bool, usesIntrinsicContentHeight: Bool) {
        let sizingChanged = allowsTreeScrolling != allowsScrolling
            || usesIntrinsicTreeHeight != usesIntrinsicContentHeight
        allowsTreeScrolling = allowsScrolling
        usesIntrinsicTreeHeight = usesIntrinsicContentHeight
        hasVerticalScroller = allowsScrolling
        hasHorizontalScroller = false
        autohidesScrollers = allowsScrolling
        borderType = .noBorder
        drawsBackground = false
        verticalScrollElasticity = allowsScrolling ? .automatic : .none
        horizontalScrollElasticity = .none
        if sizingChanged {
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        guard !allowsTreeScrolling,
              usesIntrinsicTreeHeight,
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
    var directoryClickHandler: ((TreeNode) -> Void)?
    var keyDownHandler: ((NSEvent) -> Bool)?

    private var pendingDirectoryClickNode: TreeNode?

    var hasPendingDirectoryClick: Bool {
        pendingDirectoryClickNode != nil
    }

    func deferDirectoryClick(_ node: TreeNode) {
        pendingDirectoryClickNode = node
    }

    func cancelPendingDirectoryClick() {
        pendingDirectoryClickNode = nil
    }

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
            cancelPendingDirectoryClick()
            super.mouseDown(with: event)
            return
        }

        finishInlineEditingIfNeeded()

        let node = row >= 0 ? item(atRow: row) as? TreeNode : nil
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let shouldDeferDirectoryClick = event.type == .leftMouseDown
            && event.clickCount == 1
            && modifiers.isEmpty
            && node?.item.isDirectory == true

        if shouldDeferDirectoryClick, let node {
            deferDirectoryClick(node)
        } else {
            cancelPendingDirectoryClick()
            if let node,
               primaryClickHandler?(node, event) == true {
                return
            }
        }

        super.mouseDown(with: event)

        if shouldDeferDirectoryClick, let node {
            schedulePendingDirectoryClickCommit(for: node)
        }

        if row >= 0 {
            _ = window?.makeFirstResponder(self)
        }
    }

    private func schedulePendingDirectoryClickCommit(for node: TreeNode) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.pendingDirectoryClickNode === node else { return }
            self.cancelPendingDirectoryClick()
            self.directoryClickHandler?(node)
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
