import Foundation

enum SplitLayoutEngine {

    static func addSplit(
        to root: SplitPaneNode,
        at paneID: UUID,
        orientation: SplitOrientation
    ) -> SplitPaneNode? {
        guard root.leafCount < SplitPaneNode.maxPanes else { return nil }
        return insertSplit(in: root, at: paneID, orientation: orientation)
    }

    static func removePane(from root: SplitPaneNode, paneID: UUID) -> SplitPaneNode? {
        guard case .split = root else { return nil }
        return collapsePane(in: root, paneID: paneID)
    }

    static func toggleOrientation(of root: SplitPaneNode, containing paneID: UUID) -> SplitPaneNode? {
        toggleParentOrientation(in: root, for: paneID)
    }

    static func updateRatio(in root: SplitPaneNode, splitID: UUID, ratio: Double) -> SplitPaneNode? {
        setRatio(in: root, splitID: splitID, ratio: max(0.1, min(0.9, ratio)))
    }

    // MARK: - Private

    private static func insertSplit(in node: SplitPaneNode, at paneID: UUID, orientation: SplitOrientation) -> SplitPaneNode? {
        switch node {
        case .leaf(let id):
            guard id == paneID else { return nil }
            return .split(
                id: UUID(),
                orientation: orientation,
                first: .leaf(id: id),
                second: .leaf(id: UUID()),
                ratio: 0.5
            )
        case .split(let id, let o, let first, let second, let ratio):
            if let updated = insertSplit(in: first, at: paneID, orientation: orientation) {
                return .split(id: id, orientation: o, first: updated, second: second, ratio: ratio)
            }
            if let updated = insertSplit(in: second, at: paneID, orientation: orientation) {
                return .split(id: id, orientation: o, first: first, second: updated, ratio: ratio)
            }
            return nil
        }
    }

    private static func collapsePane(in node: SplitPaneNode, paneID: UUID) -> SplitPaneNode? {
        guard case .split(_, _, let first, let second, _) = node else { return nil }
        if case .leaf(let id) = first, id == paneID { return second }
        if case .leaf(let id) = second, id == paneID { return first }
        if let updated = collapsePane(in: first, paneID: paneID) {
            return .split(id: node.id, orientation: splitOrientation(node), first: updated, second: second, ratio: splitRatio(node))
        }
        if let updated = collapsePane(in: second, paneID: paneID) {
            return .split(id: node.id, orientation: splitOrientation(node), first: first, second: updated, ratio: splitRatio(node))
        }
        return nil
    }

    private static func toggleParentOrientation(in node: SplitPaneNode, for paneID: UUID) -> SplitPaneNode? {
        guard case .split(let id, let o, let first, let second, let ratio) = node else { return nil }
        if isLeafOrDirectChild(first, id: paneID) || isLeafOrDirectChild(second, id: paneID) {
            return .split(id: id, orientation: o.toggled, first: first, second: second, ratio: ratio)
        }
        if let updated = toggleParentOrientation(in: first, for: paneID) {
            return .split(id: id, orientation: o, first: updated, second: second, ratio: ratio)
        }
        if let updated = toggleParentOrientation(in: second, for: paneID) {
            return .split(id: id, orientation: o, first: first, second: updated, ratio: ratio)
        }
        return nil
    }

    private static func setRatio(in node: SplitPaneNode, splitID: UUID, ratio: Double) -> SplitPaneNode? {
        guard case .split(let id, let o, let first, let second, let r) = node else { return nil }
        if id == splitID {
            return .split(id: id, orientation: o, first: first, second: second, ratio: ratio)
        }
        if let updated = setRatio(in: first, splitID: splitID, ratio: ratio) {
            return .split(id: id, orientation: o, first: updated, second: second, ratio: r)
        }
        if let updated = setRatio(in: second, splitID: splitID, ratio: ratio) {
            return .split(id: id, orientation: o, first: first, second: updated, ratio: r)
        }
        return nil
    }

    private static func isLeafOrDirectChild(_ node: SplitPaneNode, id: UUID) -> Bool {
        if case .leaf(let leafID) = node { return leafID == id }
        return false
    }

    private static func splitOrientation(_ node: SplitPaneNode) -> SplitOrientation {
        if case .split(_, let o, _, _, _) = node { return o }
        return .horizontal
    }

    private static func splitRatio(_ node: SplitPaneNode) -> Double {
        if case .split(_, _, _, _, let r) = node { return r }
        return 0.5
    }
}
