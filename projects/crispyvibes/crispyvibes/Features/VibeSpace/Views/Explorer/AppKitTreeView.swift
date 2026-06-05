import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - NSViewRepresentable

struct AppKitTreeView: NSViewRepresentable {
    @Environment(\.crispyvibesUIScale) var uiScale

    let rootItems: [FileItem]
    let expandedIDs: Set<String>
    let loadingIDs: Set<String>
    let selectedID: String?
    let renamingID: String?
    let searchQuery: String
    let changedDirectoryIDs: Set<String>
    let treeMutationRevision: Int
    let allowsScrolling: Bool
    var rootURL: URL? = nil
    var projectRootURLs: [URL] = []
    @Binding var renameText: String
    let onAction: (FileTreeAction) -> Void
    let onTransferDrop: ([ExplorerItemTransferPlan]) -> Bool

    init(
        rootItems: [FileItem],
        expandedIDs: Set<String>,
        loadingIDs: Set<String>,
        selectedID: String?,
        renamingID: String?,
        searchQuery: String,
        changedDirectoryIDs: Set<String> = [],
        treeMutationRevision: Int = 0,
        allowsScrolling: Bool,
        rootURL: URL? = nil,
        projectRootURLs: [URL] = [],
        renameText: Binding<String>,
        onAction: @escaping (FileTreeAction) -> Void,
        onTransferDrop: @escaping ([ExplorerItemTransferPlan]) -> Bool
    ) {
        self.rootItems = rootItems
        self.expandedIDs = expandedIDs
        self.loadingIDs = loadingIDs
        self.selectedID = selectedID
        self.renamingID = renamingID
        self.searchQuery = searchQuery
        self.changedDirectoryIDs = changedDirectoryIDs
        self.treeMutationRevision = treeMutationRevision
        self.allowsScrolling = allowsScrolling
        self.rootURL = rootURL
        self.projectRootURLs = projectRootURLs
        _renameText = renameText
        self.onAction = onAction
        self.onTransferDrop = onTransferDrop
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = AppKitTreeScrollView()
        scrollView.configureScrolling(allowsScrolling: allowsScrolling)

        let outline = AppKitOutlineView()
        outline.headerView = nil
        applyScale(to: outline)
        outline.autoresizesOutlineColumn = true
        outline.usesAlternatingRowBackgroundColors = false
        outline.selectionHighlightStyle = .none
        outline.style = .plain
        outline.intercellSpacing = NSSize(width: 0, height: 0)
        outline.backgroundColor = .clear
        outline.floatsGroupRows = false
        outline.registerForDraggedTypes([
            VibeSpaceDragPayload.pasteboardType,
            ShelfItemDrag.pasteboardType,
            .fileURL,
            .string
        ])
        outline.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        outline.setDraggingSourceOperationMask([.copy], forLocal: false)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree"))
        column.isEditable = false
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator

        context.coordinator.outlineView = outline
        let coordinator = context.coordinator
        outline.contextMenuProvider = { [weak coordinator] item in
            coordinator?.buildContextMenu(for: item)
        }
        outline.rootContextMenuProvider = { [weak coordinator] in
            coordinator?.buildRootContextMenu()
        }
        outline.primaryClickHandler = { [weak coordinator] node, event in
            coordinator?.handlePrimaryClick(on: node, event: event) ?? false
        }
        outline.keyDownHandler = { [weak coordinator] event in
            coordinator?.handleKeyDown(event) ?? false
        }
        scrollView.documentView = outline

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let outline = coordinator.outlineView!
        let scaleChanged = coordinator.lastAppliedScale != uiScale
        if scaleChanged {
            coordinator.lastAppliedScale = uiScale
        }
        applyScale(to: outline)
        (scrollView as? AppKitTreeScrollView)?.configureScrolling(allowsScrolling: allowsScrolling)
        let previousRowCount = outline.numberOfRows

        let oldRoots = coordinator.rootItems
        coordinator.rootItems = rootItems
        coordinator.loadingIDs = loadingIDs
        coordinator.selectedID = selectedID
        coordinator.renamingID = renamingID
        coordinator.searchQuery = searchQuery
        coordinator.changedDirectoryIDs = changedDirectoryIDs
        coordinator.treeMutationRevision = treeMutationRevision
        coordinator.onAction = onAction
        coordinator.onTransferDrop = onTransferDrop
        coordinator.rootURL = rootURL
        coordinator.projectRootURLs = projectRootURLs
        coordinator.refreshNodeCache(with: rootItems)
        coordinator.reconcilePendingExpansionStates(using: expandedIDs)

        // Determine if tree structure changed
        let rootsChanged = !rootItemsMatch(oldRoots, rootItems)

        if rootsChanged {
            applyRootDiff(outline: outline, coordinator: coordinator, oldRoots: oldRoots, newRoots: rootItems)
            coordinator.syncExpansionState()
        } else {
            // Skip subtree reloads once the rename field editor is active so AppKit
            // does not recreate the cell view mid-edit.
            if renamingID == nil,
               coordinator.consumePendingTreeMutationRevision() {
                coordinator.reloadChangedDirectoryNodes()
                coordinator.syncExpansionState()
            }
        }

        // Sync selection
        coordinator.syncSelection()

        // Update visible rows (selection highlight, rename state, etc.)
        // Must run on the first cycle after renamingID is set (to trigger beginRenameMode
        // via cellView.update), but skip once the field editor is active.
        if !rootsChanged {
            let fieldEditorActive = scrollView.window?.firstResponder is NSTextView
            if !fieldEditorActive {
                let visibleRange = outline.rows(in: outline.visibleRect)
                for row in visibleRange.location..<(visibleRange.location + visibleRange.length) {
                    guard row >= 0, row < outline.numberOfRows else { continue }
                    if let cellView = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? AppKitTreeCellView {
                        if let node = outline.item(atRow: row) as? TreeNode {
                            cellView.update(
                                node: node,
                                isSelected: selectedID == node.item.id,
                                isRenaming: renamingID == node.item.id,
                                isExpanded: node.item.isDirectory && coordinator.isEffectivelyExpanded(node.item.id),
                                searchQuery: searchQuery,
                                scale: uiScale
                            )
                        }
                    }
                }
            }
        }

        if scaleChanged {
            outline.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<outline.numberOfRows))
            outline.reloadData(forRowIndexes: IndexSet(integersIn: 0..<outline.numberOfRows), columnIndexes: IndexSet(integer: 0))
            scrollView.invalidateIntrinsicContentSize()
        }

        if renamingID != nil {
            coordinator.ensureRenameFieldFocused()
        }

        if Self.shouldInvalidateIntrinsicContentSize(
            allowsScrolling: allowsScrolling,
            previousRowCount: previousRowCount,
            currentRowCount: outline.numberOfRows,
            renamingID: renamingID
        ) {
            scrollView.invalidateIntrinsicContentSize()
        }
    }

    private func applyScale(to outline: NSOutlineView) {
        outline.rowHeight = max(uiScale.textSize(20), uiScale.chromeSize(22))
        outline.indentationPerLevel = uiScale.spacing(14)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func rootItemsMatch(_ a: [FileItem], _ b: [FileItem]) -> Bool {
        guard a.count == b.count else { return false }
        for (lhs, rhs) in zip(a, b) {
            if lhs.url != rhs.url || lhs.isDirectory != rhs.isDirectory { return false }
            if lhs.isGitIgnored != rhs.isGitIgnored || lhs.isHidden != rhs.isHidden { return false }
        }
        return true
    }

    private func applyRootDiff(
        outline: NSOutlineView,
        coordinator: Coordinator,
        oldRoots: [FileItem],
        newRoots: [FileItem]
    ) {
        let oldIDs = oldRoots.map(\.id)
        let newIDs = newRoots.map(\.id)

        // Fast path: if order and set are identical, just reload existing nodes in place
        if oldIDs == newIDs {
            for node in coordinator.rootNodes() {
                outline.reloadItem(node, reloadChildren: true)
            }
            return
        }

        let oldSet = Set(oldIDs)
        let newSet = Set(newIDs)
        let removed = oldSet.subtracting(newSet)
        let added = newSet.subtracting(oldSet)

        // Pure reorder — no adds/removes, fall back to full reload
        if removed.isEmpty, added.isEmpty {
            outline.reloadData()
            return
        }

        // Remove deleted items (reverse order to keep indices stable)
        if !removed.isEmpty {
            let indicesToRemove = IndexSet(oldIDs.enumerated().compactMap { removed.contains($1) ? $0 : nil })
            outline.removeItems(at: indicesToRemove, inParent: nil, withAnimation: .slideUp)
        }

        // Insert new items
        if !added.isEmpty {
            let indicesToInsert = IndexSet(newIDs.enumerated().compactMap { added.contains($1) ? $0 : nil })
            outline.insertItems(at: indicesToInsert, inParent: nil, withAnimation: .slideDown)
        }

        // Reload surviving items to pick up any property changes
        for item in newRoots where !added.contains(item.id) {
            if let node = coordinator.nodeCache[item.id] {
                outline.reloadItem(node, reloadChildren: true)
            }
        }
    }

    static func shouldInvalidateIntrinsicContentSize(
        allowsScrolling: Bool,
        previousRowCount: Int,
        currentRowCount: Int,
        renamingID: String?
    ) -> Bool {
        guard !allowsScrolling else { return false }
        guard renamingID == nil else { return false }
        return previousRowCount != currentRowCount
    }
}
