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
    let allowsFileTransfers: Bool
    let allowsScrolling: Bool
    let usesIntrinsicContentHeight: Bool
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
        allowsFileTransfers: Bool = true,
        allowsScrolling: Bool,
        usesIntrinsicContentHeight: Bool = true,
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
        self.allowsFileTransfers = allowsFileTransfers
        self.allowsScrolling = allowsScrolling
        self.usesIntrinsicContentHeight = usesIntrinsicContentHeight
        self.rootURL = rootURL
        self.projectRootURLs = projectRootURLs
        _renameText = renameText
        self.onAction = onAction
        self.onTransferDrop = onTransferDrop
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = AppKitTreeScrollView()
        scrollView.configureScrolling(
            allowsScrolling: allowsScrolling,
            usesIntrinsicContentHeight: usesIntrinsicContentHeight
        )

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
        (scrollView as? AppKitTreeScrollView)?.configureScrolling(
            allowsScrolling: allowsScrolling,
            usesIntrinsicContentHeight: usesIntrinsicContentHeight
        )
        let previousRowCount = outline.numberOfRows

        let oldRoots = coordinator.rootItems
        let searchChanged = coordinator.searchQuery != searchQuery
        let treeMutationChanged = coordinator.treeMutationRevision != treeMutationRevision
        let rootsChanged = !rootItemsMatch(oldRoots, rootItems)
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
        if rootsChanged || treeMutationChanged || searchChanged {
            coordinator.refreshNodeCache(with: rootItems)
        }
        coordinator.reconcilePendingExpansionStates(using: expandedIDs)

        if rootsChanged {
            applyRootDiff(outline: outline, coordinator: coordinator, oldRoots: oldRoots, newRoots: rootItems)
            if coordinator.consumePendingTreeMutationRevision() {
                coordinator.reloadChangedDirectoryNodes()
            }
            coordinator.syncExpansionState()
        } else if searchChanged {
            outline.reloadData()
            coordinator.syncExpansionState()
        } else {
            let renameTargetAlreadyVisible: Bool
            if let renamingID, let node = coordinator.nodeCache[renamingID] {
                renameTargetAlreadyVisible = outline.row(forItem: node) >= 0
            } else {
                renameTargetAlreadyVisible = false
            }
            if !renameTargetAlreadyVisible,
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
            if usesIntrinsicContentHeight {
                scrollView.invalidateIntrinsicContentSize()
            }
        }

        if renamingID != nil {
            coordinator.ensureRenameFieldFocused()
        }

        if usesIntrinsicContentHeight,
           Self.shouldInvalidateIntrinsicContentSize(
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
        let oldItemsByID = Dictionary(uniqueKeysWithValues: oldRoots.map { ($0.id, $0) })

        // Metadata-only root changes do not require rebuilding expanded subtrees.
        if oldIDs == newIDs {
            for item in newRoots where oldItemsByID[item.id] != item {
                if let node = coordinator.nodeCache[item.id] {
                    outline.reloadItem(node, reloadChildren: false)
                }
            }
            return
        }

        let oldSet = Set(oldIDs)
        let newSet = Set(newIDs)
        let removed = oldSet.subtracting(newSet)
        let added = newSet.subtracting(oldSet)
        let oldSurvivorOrder = oldIDs.filter(newSet.contains)
        let newSurvivorOrder = newIDs.filter(oldSet.contains)

        // Incremental indexes are only valid when surviving rows keep order.
        if oldSurvivorOrder != newSurvivorOrder {
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

        // Reload surviving rows to pick up metadata without recreating children.
        for item in newRoots where !added.contains(item.id) && oldItemsByID[item.id] != item {
            if let node = coordinator.nodeCache[item.id] {
                outline.reloadItem(node, reloadChildren: false)
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
