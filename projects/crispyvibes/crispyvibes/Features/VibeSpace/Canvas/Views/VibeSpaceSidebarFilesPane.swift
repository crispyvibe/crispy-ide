import SwiftUI

struct VibeSpaceSidebarFilesPane: View {
    @Environment(\.appThemePalette) private var activeThemePalette
    @ObservedObject var shelfStore: ShelfStore

    let projects: [AnyProjectSession]
    let focusedProject: AnyProjectSession?
    let expandedProjectPaths: Set<String>
    let selectedCanvasMode: VibeSpaceCanvasMode
    let projectColorTagsByPath: [String: ProjectColorTag]
    let onOpenShelfFile: (String) -> Void
    let onRevealShelfFileInFinder: (String) -> Void
    let onOpenShelfDirectoryInTerminal: (String) -> Void
    let onRenameShelfFile: (String, String) throws -> Void
    let onDeleteShelfFile: (String) throws -> Void
    let onRemoveShelfFile: (String) -> Void
    let onClearShelf: () -> Void
    let onProjectExpansionToggled: (AnyProjectSession) -> Void
    let onFocusedProjectAppeared: (AnyProjectSession) -> Void
    let onProjectAction: (AnyProjectSession, FileTreeAction) -> Void
    let onProjectTransferDrop: (AnyProjectSession, [ExplorerItemTransferPlan]) -> Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if !shelfStore.filePaths.isEmpty {
                    ShelfSidebarSectionView(
                        shelfStore: shelfStore,
                        onOpenFile: onOpenShelfFile,
                        onRevealInFinder: onRevealShelfFileInFinder,
                        onOpenDirectoryInTerminal: onOpenShelfDirectoryInTerminal,
                        onRenameFile: onRenameShelfFile,
                        onDeleteFile: onDeleteShelfFile,
                        onRemoveFile: onRemoveShelfFile,
                        onClear: onClearShelf
                    )
                }

                if projects.isEmpty {
                    ContentUnavailableView(
                        AppStrings.VibeSpace.noProjects,
                        systemImage: "folder",
                        description: Text(AppStrings.Explorer.openVibeSpaceToBrowse)
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ForEach(projects) { project in
                        projectSection(for: project)
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .background(activeThemePalette.canvasBackgroundColor)
        .accessibilityIdentifier("vibespace.sidebar.files")
    }

    private func projectSection(for project: AnyProjectSession) -> some View {
        VibeSpaceProjectFilesSectionView(
            project: project,
            isExpanded: expandedProjectPaths.contains(project.rootURL.standardizedFileURL.path),
            isFocused: focusedProject?.id == project.id,
            accentColor: projectColorTagsByPath[project.rootURL.standardizedFileURL.path]?.color ?? activeThemePalette.accentColor,
            selectedVibeSpaceCanvasMode: selectedCanvasMode,
            projectRootURLs: projects.map(\.rootURL),
            onFocusAndToggleExpansion: {
                onProjectExpansionToggled(project)
            },
            onAppearWhenFocused: {
                onFocusedProjectAppeared(project)
            },
            onAction: { action in
                onProjectAction(project, action)
            },
            onTransferDrop: { plans in
                onProjectTransferDrop(project, plans)
            }
        )
    }
}
