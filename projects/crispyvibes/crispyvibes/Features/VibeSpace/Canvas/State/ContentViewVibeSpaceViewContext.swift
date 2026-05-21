import SwiftUI

@MainActor
struct VibeSpaceViewContext {
    let activeVibeSpace: VibeSpaceState?
    let focusedProject: AnyProjectSession?
    let activeVibeSpaceProjects: [AnyProjectSession]
    let stackedProjects: [AnyProjectSession]
    let unresolvedProjectCount: Int
    let sourceControlSelectedFileURL: URL?
    let selectedCanvasMode: VibeSpaceCanvasMode
    let selectedRailPosition: ProjectRailPosition

    private let layoutPersistence: LayoutPersistenceService
    private let vibespaceID: UUID?

    init(
        activeVibeSpace: VibeSpaceState?,
        focusedProject: AnyProjectSession?,
        activeVibeSpaceProjects: [AnyProjectSession],
        stackedProjects: [AnyProjectSession],
        unresolvedProjectCount: Int,
        sourceControlSelectedFileURL: URL?,
        selectedCanvasMode: VibeSpaceCanvasMode,
        selectedRailPosition: ProjectRailPosition,
        layoutPersistence: LayoutPersistenceService,
        vibespaceID: UUID?
    ) {
        self.activeVibeSpace = activeVibeSpace
        self.focusedProject = focusedProject
        self.activeVibeSpaceProjects = activeVibeSpaceProjects
        self.stackedProjects = stackedProjects
        self.unresolvedProjectCount = unresolvedProjectCount
        self.sourceControlSelectedFileURL = sourceControlSelectedFileURL
        self.selectedCanvasMode = selectedCanvasMode
        self.selectedRailPosition = selectedRailPosition
        self.layoutPersistence = layoutPersistence
        self.vibespaceID = vibespaceID
    }

    var clampedRailWidth: CGFloat {
        switch selectedRailPosition {
        case .left:
            return layoutPersistence.railSize(for: .left, vibespaceID: vibespaceID)
        case .right:
            return layoutPersistence.railSize(for: .right, vibespaceID: vibespaceID)
        case .top, .bottom:
            return 300
        }
    }

    var clampedRailHeight: CGFloat {
        switch selectedRailPosition {
        case .top:
            return layoutPersistence.railSize(for: .top, vibespaceID: vibespaceID)
        case .bottom:
            return layoutPersistence.railSize(for: .bottom, vibespaceID: vibespaceID)
        case .left, .right:
            return 250
        }
    }

    func railSizeBinding(for position: ProjectRailPosition) -> Binding<CGFloat> {
        Binding(
            get: {
                switch position {
                case .left, .right:
                    return clampedRailWidth
                case .top, .bottom:
                    return clampedRailHeight
                }
            },
            set: { newValue in
                layoutPersistence.setRailSize(newValue, for: position, vibespaceID: vibespaceID)
            }
        )
    }

    func detailedTerminalPaneHeightBinding() -> Binding<CGFloat> {
        Binding(
            get: {
                layoutPersistence.detailedTerminalPaneHeight(for: vibespaceID)
            },
            set: { newValue in
                layoutPersistence.setDetailedTerminalPaneHeight(newValue, for: vibespaceID)
            }
        )
    }

    var isDetailedTerminalPaneCollapsed: Bool {
        layoutPersistence.isDetailedTerminalPaneCollapsed(for: vibespaceID)
    }

    func detailedTerminalPaneCollapsedBinding() -> Binding<Bool> {
        Binding(
            get: {
                layoutPersistence.isDetailedTerminalPaneCollapsed(for: vibespaceID)
            },
            set: { newValue in
                layoutPersistence.setDetailedTerminalPaneCollapsed(newValue, for: vibespaceID)
            }
        )
    }

    func setCanvasMode(_ mode: VibeSpaceCanvasMode) {
        layoutPersistence.setCanvasMode(mode, for: vibespaceID)
    }
}

extension ContentView {
    var vibespaceView: VibeSpaceViewContext {
        let session = activeVibeSpaceSession
        return VibeSpaceViewContext(
            activeVibeSpace: session.vibespace,
            focusedProject: session.focusedProject,
            activeVibeSpaceProjects: session.projects,
            stackedProjects: session.stackedProjects,
            unresolvedProjectCount: session.unresolvedProjectCount,
            sourceControlSelectedFileURL: session.sourceControlSelectedFileURL,
            selectedCanvasMode: selectedVibeSpaceCanvasMode,
            selectedRailPosition: selectedProjectRailPosition,
            layoutPersistence: layoutPersistence,
            vibespaceID: session.vibespaceID
        )
    }
}
