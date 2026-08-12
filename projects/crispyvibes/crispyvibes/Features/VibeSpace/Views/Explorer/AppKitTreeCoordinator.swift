import AppKit

// MARK: - Coordinator (data source + delegate)

extension AppKitTreeView {
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: AppKitTreeView
        var outlineView: AppKitOutlineView?
        var rootItems: [FileItem] = []
        var expandedIDs: Set<String> = []
        var loadingIDs: Set<String> = []
        var selectedID: String?
        var renamingID: String?
        var searchQuery: String = ""
        var changedDirectoryIDs: Set<String> = []
        var treeMutationRevision = 0
        var onAction: (FileTreeAction) -> Void = { _ in }
        var onTransferDrop: ([ExplorerItemTransferPlan]) -> Bool = { _ in false }
        var rootURL: URL?
        var projectRootURLs: [URL] = []

        // Node cache for stable identity
        var nodeCache: [String: TreeNode] = [:]
        var loadingNodeCache: [String: LoadingNode] = [:]
        var isSyncingExpansion = false
        var isSyncingSelection = false
        var lastSelectedItemWasFile = false
        var pendingExpansionStates: [String: Bool] = [:]
        var lastAppliedTreeMutationRevision = 0
        var lastAppliedScale = CrispyVibesUIScale.default

        init(_ parent: AppKitTreeView) {
            self.parent = parent
            self.rootItems = parent.rootItems
            self.expandedIDs = parent.expandedIDs
            self.loadingIDs = parent.loadingIDs
            self.selectedID = parent.selectedID
            self.renamingID = parent.renamingID
            self.searchQuery = parent.searchQuery
            self.changedDirectoryIDs = parent.changedDirectoryIDs
            self.treeMutationRevision = parent.treeMutationRevision
            self.onAction = parent.onAction
            self.onTransferDrop = parent.onTransferDrop
            self.rootURL = parent.rootURL
            self.projectRootURLs = parent.projectRootURLs
            self.lastAppliedScale = parent.uiScale
        }

        var isSearchActive: Bool {
            !searchQuery.isEmpty
        }

        func consumePendingTreeMutationRevision() -> Bool {
            guard treeMutationRevision != lastAppliedTreeMutationRevision else { return false }
            lastAppliedTreeMutationRevision = treeMutationRevision
            return true
        }

        // MARK: Node resolution

        func node(for item: FileItem) -> TreeNode {
            if let cached = nodeCache[item.id] {
                cached.item = item
                return cached
            }
            let n = TreeNode(item: item)
            nodeCache[item.id] = n
            return n
        }

        func childNodes(of item: FileItem) -> [TreeNode] {
            guard let children = item.children else { return [] }
            return children.map { node(for: $0) }
        }

        func rootNodes() -> [TreeNode] {
            rootItems.map { node(for: $0) }
        }

        func loadingNode(for parentDirectoryID: String) -> LoadingNode {
            if let cached = loadingNodeCache[parentDirectoryID] {
                return cached
            }
            let node = LoadingNode(parentDirectoryID: parentDirectoryID)
            loadingNodeCache[parentDirectoryID] = node
            return node
        }

        func pruneNodeCache(under item: FileItem) {
            guard let children = item.children else { return }
            for child in children {
                pruneNodeCache(under: child)
                nodeCache.removeValue(forKey: child.id)
                loadingNodeCache.removeValue(forKey: child.id)
            }
        }

        func refreshNodeCache(with items: [FileItem]) {
            var liveIDs: Set<String> = []

            func refresh(_ currentItems: [FileItem]) {
                for item in currentItems {
                    liveIDs.insert(item.id)
                    _ = node(for: item)
                    if let children = item.children {
                        refresh(children)
                    }
                }
            }

            refresh(items)
            nodeCache = nodeCache.filter { liveIDs.contains($0.key) }
            loadingNodeCache = loadingNodeCache.filter { liveIDs.contains($0.key) }
        }

        // MARK: NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil { return rootItems.count }
            guard let node = item as? TreeNode, node.item.isDirectory else { return 0 }
            if loadingIDs.contains(node.item.id) {
                return 1
            }
            return node.item.children?.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil { return rootNodes()[index] }
            guard let node = item as? TreeNode else { return TreeNode(item: rootItems[0]) }
            if loadingIDs.contains(node.item.id), index == 0 {
                return loadingNode(for: node.item.id)
            }
            return childNodes(of: node.item)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? TreeNode else { return false }
            return node.item.isDirectory
        }

        // MARK: Drag source

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard parent.allowsFileTransfers,
                  let node = item as? TreeNode else { return nil }
            return VibeSpaceDragPayload(url: node.item.url).makePasteboardItem()
        }

        // MARK: Drop target

        func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard parent.allowsFileTransfers,
                  let targetURL = dropTargetURL(for: item) else { return [] }
            // F052: a shelf item moves into the project (with shelf + tab retarget).
            if info.draggingPasteboard.availableType(from: [ShelfItemDrag.pasteboardType]) != nil {
                return .move
            }
            return ExplorerItemDropPlanner.dragOperation(
                for: info.draggingPasteboard,
                targetDirectoryURL: targetURL,
                projectRootURLs: projectRootURLs
            )
        }

        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            guard parent.allowsFileTransfers,
                  let targetURL = dropTargetURL(for: item) else { return false }
            // F052: shelf item → move into the target directory; ContentView does
            // the moveItem + shelf/tab retarget off this notification. The path
            // comes from the in-app drag holder (reading custom-type data back
            // from a SwiftUI provider here is unreliable); the pasteboard type is
            // only the marker that this is a shelf drag.
            if info.draggingPasteboard.availableType(from: [ShelfItemDrag.pasteboardType]) != nil {
                let path = MainActor.assumeIsolated { () -> String? in
                    let stashed = ShelfItemDrag.draggingPath
                    ShelfItemDrag.draggingPath = nil
                    return stashed
                } ?? info.draggingPasteboard.data(forType: ShelfItemDrag.pasteboardType)
                    .flatMap { String(data: $0, encoding: .utf8) }
                ShelfItemDrag.logger.info("shelf acceptDrop: path=\(path ?? "nil", privacy: .public) target=\(targetURL.path, privacy: .public)")
                guard let path, !path.isEmpty else { return false }
                NotificationCenter.default.post(
                    name: .shelfFileMoveToProjectRequested,
                    object: nil,
                    userInfo: ["sourcePath": path, "targetDirectory": targetURL]
                )
                return true
            }
            let plans = ExplorerItemDropPlanner.planDrop(
                from: info.draggingPasteboard,
                targetDirectoryURL: targetURL,
                projectRootURLs: projectRootURLs
            )
            guard !plans.isEmpty else { return false }
            return onTransferDrop(plans)
        }

        private func dropTargetURL(for item: Any?) -> URL? {
            if let node = item as? TreeNode {
                return node.item.isDirectory ? node.item.url : node.item.url.deletingLastPathComponent()
            }
            return rootURL
        }

        // MARK: NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            if item is LoadingNode {
                let cellID = NSUserInterfaceItemIdentifier("TreeLoadingCell")
                let cellView: AppKitTreeLoadingCellView

                if let reused = outlineView.makeView(withIdentifier: cellID, owner: nil) as? AppKitTreeLoadingCellView {
                    cellView = reused
                } else {
                    cellView = AppKitTreeLoadingCellView(identifier: cellID)
                }

                cellView.configure(scale: parent.uiScale)
                return cellView
            }

            guard let node = item as? TreeNode else { return nil }

            let cellID = NSUserInterfaceItemIdentifier("TreeCell")
            let cellView: AppKitTreeCellView

            if let reused = outlineView.makeView(withIdentifier: cellID, owner: nil) as? AppKitTreeCellView {
                cellView = reused
            } else {
                cellView = AppKitTreeCellView(identifier: cellID)
            }

            cellView.configure(
                node: node,
                isSelected: selectedID == node.item.id,
                isRenaming: renamingID == node.item.id,
                isExpanded: node.item.isDirectory && isEffectivelyExpanded(node.item.id),
                searchQuery: searchQuery,
                scale: parent.uiScale,
                onAction: onAction,
                onDisclosureToggle: { [weak self] in
                    self?.requestDisclosureToggle(for: node.item)
                },
                renameTextSetter: { [weak self] text in
                    self?.parent.renameText = text
                }
            )

            return cellView
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            max(parent.uiScale.textSize(20), parent.uiScale.chromeSize(22))
        }

    }
}
