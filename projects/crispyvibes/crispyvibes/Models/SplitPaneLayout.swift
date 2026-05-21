import Foundation

// MARK: - Split Orientation

enum SplitOrientation: String, Codable, Equatable {
    case horizontal
    case vertical

    var toggled: SplitOrientation {
        self == .horizontal ? .vertical : .horizontal
    }
}

// MARK: - Layout Node (structural only — no content)

indirect enum SplitPaneNode: Equatable {
    case leaf(id: UUID)
    case split(id: UUID, orientation: SplitOrientation, first: SplitPaneNode, second: SplitPaneNode, ratio: Double)

    static let maxPanes = 4

    var id: UUID {
        switch self {
        case .leaf(let id): return id
        case .split(let id, _, _, _, _): return id
        }
    }

    var leafCount: Int {
        switch self {
        case .leaf: return 1
        case .split(_, _, let first, let second, _):
            return first.leafCount + second.leafCount
        }
    }

    var allLeafIDs: [UUID] {
        switch self {
        case .leaf(let id): return [id]
        case .split(_, _, let first, let second, _):
            return first.allLeafIDs + second.allLeafIDs
        }
    }

    func containsLeaf(_ targetID: UUID) -> Bool {
        switch self {
        case .leaf(let id): return id == targetID
        case .split(_, _, let first, let second, _):
            return first.containsLeaf(targetID) || second.containsLeaf(targetID)
        }
    }

    static func singleLeaf() -> SplitPaneNode {
        .leaf(id: UUID())
    }
}
