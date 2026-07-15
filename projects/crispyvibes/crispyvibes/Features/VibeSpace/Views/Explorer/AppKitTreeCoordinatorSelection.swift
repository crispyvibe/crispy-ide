import AppKit

extension AppKitTreeView.Coordinator {
    func handlePrimaryClick(on node: TreeNode, event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown else { return false }
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        guard renamingID != node.item.id else { return false }

        if event.clickCount == 2 {
            guard !node.item.isDirectory else { return false }
            selectItem(node.item)
            onAction(.openInTab(node.item))
            return true
        }

        guard event.clickCount == 1 else { return false }
        if node.item.isDirectory {
            if isSearchActive {
                selectItem(node.item)
            } else {
                requestExpansionToggle(for: node.item)
            }
            return true
        }

        // Let NSOutlineView handle single-click file selection so native drag
        // recognition can begin from the initial mouse-down.
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard renamingID == nil else { return false }
        guard let node = item as? TreeNode else { return false }
        guard !isSyncingSelection else { return true }
        lastSelectedItemWasFile = !node.item.isDirectory
        onAction(.select(node.item))
        return true
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection else { return }
        guard let outline = outlineView else { return }
        if outline.selectedRow >= 0, renamingID == nil, !lastSelectedItemWasFile {
            outline.window?.makeFirstResponder(outline)
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        guard let characters = event.charactersIgnoringModifiers else { return false }

        if renamingID != nil {
            if characters == "\u{1b}" {
                onAction(.cancelRename)
                return true
            }
            if characters == "\r" || characters == "\u{3}" {
                onAction(.commitRename)
                return true
            }
            return false
        }

        guard let item = currentlySelectedItem() else { return false }

        if characters == "\r" || characters == "\u{3}" {
            onAction(.startRenaming(item))
            return true
        }

        return false
    }

    func syncSelection() {
        guard let outline = outlineView else { return }
        guard renamingID == nil else { return }
        guard let selectedID else {
            lastSelectedItemWasFile = false
            deselectAll(in: outline)
            return
        }
        guard let node = nodeCache[selectedID] else {
            lastSelectedItemWasFile = false
            deselectAll(in: outline)
            return
        }
        lastSelectedItemWasFile = !node.item.isDirectory
        let row = outline.row(forItem: node)
        guard row >= 0 else {
            deselectAll(in: outline)
            return
        }
        if outline.selectedRow != row {
            isSyncingSelection = true
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            isSyncingSelection = false
        }
    }

    func ensureRenameFieldFocused() {
        guard let outline = outlineView,
              let renamingID,
              let node = nodeCache[renamingID] else { return }

        let row = outline.row(forItem: node)
        guard row >= 0,
              let cellView = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? AppKitTreeCellView else {
            return
        }
        _ = cellView.ensureRenameFieldFocused()
    }

    private func currentlySelectedItem() -> FileItem? {
        if let outline = outlineView, outline.selectedRow >= 0,
           let node = outline.item(atRow: outline.selectedRow) as? TreeNode {
            return node.item
        }

        guard let selectedID, let item = nodeCache[selectedID]?.item else { return nil }
        return item
    }

    private func deselectAll(in outline: NSOutlineView) {
        guard outline.selectedRow != -1 else { return }
        isSyncingSelection = true
        outline.deselectAll(nil)
        isSyncingSelection = false
    }

    func selectItem(_ item: FileItem) {
        selectedID = item.id
        lastSelectedItemWasFile = !item.isDirectory

        if let outline = outlineView,
           let node = nodeCache[item.id] {
            let row = outline.row(forItem: node)
            if row >= 0, outline.selectedRow != row {
                isSyncingSelection = true
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                isSyncingSelection = false
            }

            if !item.isDirectory, renamingID == nil {
                outline.window?.makeFirstResponder(outline)
            }
        }

        onAction(.select(item))
    }
}
