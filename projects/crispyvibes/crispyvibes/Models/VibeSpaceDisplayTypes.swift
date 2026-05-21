import Foundation
import CoreGraphics

enum ProjectRailPosition: String, CaseIterable, Identifiable {
    case left
    case right
    case top
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }

    var symbolName: String {
        switch self {
        case .left: return "sidebar.left"
        case .right: return "sidebar.right"
        case .top: return "rectangle.tophalf.inset.filled"
        case .bottom: return "rectangle.bottomhalf.inset.filled"
        }
    }

    var isHorizontalRail: Bool {
        self == .top || self == .bottom
    }

    var expandsTowardLeadingInCanvas: Bool {
        self == .right
    }

    var expandsUpward: Bool {
        isHorizontalRail
    }
}

enum VibeSpaceCanvasMode: String, CaseIterable, Identifiable {
    case detailed
    case terminalOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .detailed:
            return "Detailed"
        case .terminalOnly:
            return "Terminal Board"
        }
    }

    var symbolName: String {
        switch self {
        case .detailed:
            return "square.split.2x1"
        case .terminalOnly:
            return "square.grid.2x2"
        }
    }
}

enum AppSideMenuDockPosition: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }

    var symbolName: String {
        switch self {
        case .left:
            return "sidebar.left"
        case .right:
            return "sidebar.right"
        }
    }
}

enum VibeSpaceTerminalOnlyLayoutOrientation: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vertical:
            return "Vertical"
        case .horizontal:
            return "Horizontal"
        }
    }

    var symbolName: String {
        switch self {
        case .vertical:
            return "square.split.2x1"
        case .horizontal:
            return "square.split.1x2"
        }
    }
}

struct TerminalTraversalProjectSnapshot: Equatable {
    let projectID: UUID
    let tabIDs: [UUID]
    let activeTabID: UUID?

    init(projectID: UUID, tabIDs: [UUID], activeTabID: UUID? = nil) {
        self.projectID = projectID
        self.tabIDs = tabIDs
        self.activeTabID = activeTabID
    }
}

struct TerminalTraversalTarget: Equatable {
    let projectID: UUID
    let tabID: UUID
}

enum TerminalTraversal {
    static func adjacentTarget(
        in projects: [TerminalTraversalProjectSnapshot],
        focusedProjectID: UUID?,
        offset: Int
    ) -> TerminalTraversalTarget? {
        guard offset != 0 else { return nil }

        let orderedTargets = projects.flatMap { project in
            project.tabIDs.map { tabID in
                TerminalTraversalTarget(projectID: project.projectID, tabID: tabID)
            }
        }
        guard !orderedTargets.isEmpty else { return nil }

        let focusedProject = focusedProjectID.flatMap { projectID in
            projects.first(where: { $0.projectID == projectID })
        } ?? projects.first

        let currentTarget = focusedProject.flatMap { project in
            if let activeTabID = project.activeTabID,
               project.tabIDs.contains(activeTabID) {
                return TerminalTraversalTarget(projectID: project.projectID, tabID: activeTabID)
            }
            if let fallbackTabID = project.tabIDs.first {
                return TerminalTraversalTarget(projectID: project.projectID, tabID: fallbackTabID)
            }
            return nil
        }

        let currentIndex = currentTarget.flatMap { target in
            orderedTargets.firstIndex(of: target)
        } ?? 0
        let targetIndex = wrappedIndexAfterShifting(
            currentIndex,
            by: offset,
            upperBoundExclusive: orderedTargets.count
        )
        return orderedTargets[targetIndex]
    }

    private static func wrappedIndexAfterShifting(
        _ index: Int,
        by shift: Int,
        upperBoundExclusive count: Int
    ) -> Int {
        guard count > 0 else { return 0 }
        let normalized = (index + shift) % count
        return normalized >= 0 ? normalized : normalized + count
    }
}

func clamped(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
    Swift.max(lower, Swift.min(value, upper))
}
