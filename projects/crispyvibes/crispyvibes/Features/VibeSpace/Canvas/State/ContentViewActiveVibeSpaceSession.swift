import Foundation

@MainActor
struct ActiveVibeSpaceSession {
    let vibespaceID: UUID?
    let vibespaceIndex: Int?
    let vibespace: VibeSpaceState?
    let focusedProject: AnyProjectSession?
    let projects: [AnyProjectSession]
    let stackedProjects: [AnyProjectSession]
    let unresolvedProjectCount: Int
    let sourceControlSelectedFileURL: URL?
}

extension ContentView {
    var hasAnyVibeSpace: Bool {
        vibespaceCatalogStore.hasAnyVibeSpace
    }

    var activeVibeSpaceIndex: Int? {
        vibespaceCatalogStore.activeVibeSpaceIndex(for: activeVibeSpaceID)
    }

    var activeVibeSpaceSession: ActiveVibeSpaceSession {
        let vibespaceIndex = activeVibeSpaceIndex
        let vibespace = vibespaceCatalogStore.vibespaceState(at: vibespaceIndex)
        let focusedProject = vibespace?.focusedProject

        return ActiveVibeSpaceSession(
            vibespaceID: vibespace?.id,
            vibespaceIndex: vibespaceIndex,
            vibespace: vibespace,
            focusedProject: focusedProject,
            projects: vibespace?.projects ?? [],
            stackedProjects: vibespace?.stackedProjects ?? [],
            unresolvedProjectCount: vibespace?.unresolvedProjectPaths.count ?? 0,
            sourceControlSelectedFileURL: contentViewerStore.markdownViewModel.fileURL
                ?? focusedProject?.folderExplorer.selectedFileURL
        )
    }

    func activeVibeSpaceValue<T>(_ transform: (VibeSpaceState, UUID) -> T?) -> T? {
        vibespaceCatalogStore.activeVibeSpaceValue(for: activeVibeSpaceID, transform)
    }

    func mutateActiveVibeSpace(_ update: (inout VibeSpaceState, UUID) -> Void) {
        vibespaceCatalogStore.mutateActiveVibeSpace(for: activeVibeSpaceID, update)
    }

    func vibespaceState(for vibespaceID: UUID) -> VibeSpaceState? {
        vibespaceValue(for: vibespaceID, { $0 })
    }

    func vibespaceValue<T>(for vibespaceID: UUID, _ transform: (VibeSpaceState) -> T?) -> T? {
        vibespaceCatalogStore.vibespaceValue(for: vibespaceID, transform)
    }

    func mutateVibeSpace(id vibespaceID: UUID, _ update: (inout VibeSpaceState) -> Void) {
        vibespaceCatalogStore.mutateVibeSpace(id: vibespaceID, update)
    }

    func allVibeSpaceProjects() -> [(vibespaceID: UUID, project: AnyProjectSession)] {
        vibespaceCatalogStore.allProjects()
    }
}
