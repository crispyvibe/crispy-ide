import AppKit

extension AppKitTreeView.Coordinator {
    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isSyncingExpansion else { return }
        guard let node = notification.userInfo?["NSObject"] as? TreeNode else { return }
        if pendingExpansionStates[node.item.id] == true { return }
        if setLocalExpansionState(for: node.item.id, isExpanded: true) {
            pendingExpansionStates[node.item.id] = true
            onAction(.toggleExpansion(node.item))
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isSyncingExpansion else { return }
        guard let node = notification.userInfo?["NSObject"] as? TreeNode else { return }
        pruneNodeCache(under: node.item)
        if pendingExpansionStates[node.item.id] == false { return }
        if setLocalExpansionState(for: node.item.id, isExpanded: false) {
            pendingExpansionStates[node.item.id] = false
            onAction(.toggleExpansion(node.item))
        }
    }

    func requestExpansionToggle(for item: FileItem) {
        selectItem(item)
        toggleExpansion(for: item)
    }

    func requestDisclosureToggle(for item: FileItem) {
        toggleExpansion(for: item)
    }

    private func toggleExpansion(for item: FileItem) {
        guard !isSearchActive else { return }

        let shouldExpand = !isEffectivelyExpanded(item.id)
        guard setLocalExpansionState(for: item.id, isExpanded: shouldExpand) else { return }
        pendingExpansionStates[item.id] = shouldExpand
        syncExpansionState()
        onAction(.toggleExpansion(item))
    }

    @discardableResult
    func setLocalExpansionState(for itemID: String, isExpanded: Bool) -> Bool {
        if isExpanded {
            let result = expandedIDs.insert(itemID)
            return result.inserted
        }

        return expandedIDs.remove(itemID) != nil
    }

    func isEffectivelyExpanded(_ itemID: String) -> Bool {
        if isSearchActive {
            return true
        }

        if let pendingState = pendingExpansionStates[itemID] {
            return pendingState
        }

        return expandedIDs.contains(itemID)
    }

    func desiredExpandedDirectoryIDs() -> [String] {
        var directoryIDs: [String] = []

        func appendDirectories(from items: [FileItem], ancestorsExpanded: Bool) {
            for item in items where item.isDirectory {
                let shouldExpand = isSearchActive || (ancestorsExpanded && isEffectivelyExpanded(item.id))
                if shouldExpand {
                    directoryIDs.append(item.id)
                }

                let shouldTraverseChildren = isSearchActive || shouldExpand
                if shouldTraverseChildren, let children = item.children {
                    appendDirectories(from: children, ancestorsExpanded: shouldTraverseChildren)
                }
            }
        }

        appendDirectories(from: rootItems, ancestorsExpanded: true)
        return directoryIDs
    }

    func reconcilePendingExpansionStates(using parentExpandedIDs: Set<String>? = nil) {
        let sourceExpandedIDs = parentExpandedIDs ?? expandedIDs
        var mergedExpandedIDs = sourceExpandedIDs

        pendingExpansionStates = pendingExpansionStates.filter { itemID, expectedState in
            guard sourceExpandedIDs.contains(itemID) != expectedState else {
                return false
            }

            if expectedState {
                mergedExpandedIDs.insert(itemID)
            } else {
                mergedExpandedIDs.remove(itemID)
            }
            return true
        }

        expandedIDs = mergedExpandedIDs
    }

    func reloadChangedDirectoryNodes() {
        guard let outline = outlineView else { return }
        for id in changedDirectoryIDs.sorted() {
            guard let node = nodeCache[id] else { continue }
            if id == rootURL?.standardizedFileURL.path || outline.isItemExpanded(node) {
                outline.reloadItem(node, reloadChildren: true)
            }
        }
    }

    func syncExpansionState() {
        guard let outline = outlineView else { return }
        isSyncingExpansion = true
        defer { isSyncingExpansion = false }
        var changedExpansionState = false

        for row in (0..<outline.numberOfRows).reversed() {
            guard let node = outline.item(atRow: row) as? TreeNode else { continue }
            if node.item.isDirectory && outline.isItemExpanded(node) && !isEffectivelyExpanded(node.item.id) {
                outline.collapseItem(node, collapseChildren: true)
                changedExpansionState = true
            }
        }

        for id in desiredExpandedDirectoryIDs() {
            guard let node = nodeCache[id] else { continue }
            if !outline.isItemExpanded(node) {
                outline.expandItem(node, expandChildren: false)
                changedExpansionState = true
            }
        }

        if changedExpansionState {
            outline.noteNumberOfRowsChanged()
            outline.layoutSubtreeIfNeeded()
        }
    }
}
