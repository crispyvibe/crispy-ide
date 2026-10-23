import SwiftUI

struct VibeSpaceSidebarFilesPane: View {
    @Environment(\.appThemePalette) private var activeThemePalette
    @ObservedObject var shelfStore: ShelfStore

    let projects: [AnyProjectSession]
    let focusedProject: AnyProjectSession?
    let expandedProjectPaths: Set<String>
    let selectedCanvasMode: VibeSpaceCanvasMode
    let projectColorTagsByPath: [String: ProjectColorTag]
    /// F021-R12: paths of parked projects, surfaced in the Files tab as a
    /// distinct section. Empty when no projects are parked.
    var parkedProjectPaths: [String] = []
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
            // F024-S01: project sections can contain variable-height AppKit trees.
            // A LazyVStack can enter a self-invalidating item-phase loop on macOS 26,
            // permanently blocking the main thread. The project count is small, so
            // eager layout is both safe and more stable here.
            VStack(alignment: .leading, spacing: 8) {
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

                // F021-R12: Parked Projects section. Rendered below active
                // projects when at least one project is parked.
                if !parkedProjectPaths.isEmpty {
                    parkedProjectsSection
                }
            }
            .padding(.vertical, 10)
        }
        .background(activeThemePalette.canvasBackgroundColor)
        .accessibilityIdentifier("vibespace.sidebar.files")
    }

    @ViewBuilder
    private var parkedProjectsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.VibeSpace.parkedProjectsHeader)
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(activeThemePalette.secondaryTextColor)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            ForEach(parkedProjectPaths, id: \.self) { path in
                parkedProjectRow(for: path)
            }
        }
        .accessibilityIdentifier("vibespace.sidebar.files.parked")
    }

    private func parkedProjectRow(for path: String) -> some View {
        let presentation = ParkedProjectPresentation(identifier: path)
        return HStack(spacing: 8) {
            Image(systemName: presentation.isRemote ? "server.rack" : "shippingbox")
                .foregroundStyle(activeThemePalette.secondaryTextColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.displayName)
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(activeThemePalette.primaryTextColor)
                    .lineLimit(1)
                if let detail = presentation.remoteDetail {
                    Text(detail)
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(activeThemePalette.secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if presentation.isRemote {
                Text(AppStrings.VibeSpace.remoteProjectBadge)
                    .font(AppTypographyTokens.caption2Semibold)
                    .foregroundStyle(activeThemePalette.secondaryTextColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(activeThemePalette.selectionBackgroundColor.opacity(0.24), in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            // F021-R13: activate (unpark) the project from its right-click menu.
            Button(AppStrings.VibeSpace.activateProjectAction) {
                NotificationCenter.default.post(
                    name: .activateProjectRequested,
                    object: nil,
                    userInfo: [AppCommandUserInfoKey.projectPath: path]
                )
            }
            // F021-R19: remove the parked project without activating it.
            Button(AppStrings.VibeSpace.removeProjectAction, role: .destructive) {
                NotificationCenter.default.post(
                    name: .removeParkedProjectRequested,
                    object: nil,
                    userInfo: [AppCommandUserInfoKey.projectPath: path]
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier(
            "vibespace.sidebar.files.parked.row.\(AppDiagnostics.pathToken(path))"
        )
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

struct ParkedProjectPresentation {
    let displayName: String
    let isRemote: Bool
    let remoteDetail: String?
    let accessibilityLabel: String

    init(identifier: String) {
        guard let location = SSHConnectionProfile.parseIdentifierLocation(identifier) else {
            let name = URL(fileURLWithPath: identifier).lastPathComponent
            self.displayName = name.isEmpty ? identifier : name
            self.isRemote = false
            self.remoteDetail = nil
            self.accessibilityLabel = self.displayName
            return
        }

        let name = (location.remotePath as NSString).lastPathComponent
        let hostDisplay = location.port == 22
            ? location.host
            : AppStrings.VibeSpace.remoteHostPort(host: location.host, port: location.port)
        self.displayName = name.isEmpty ? location.remotePath : name
        self.isRemote = true
        self.remoteDetail = AppStrings.VibeSpace.remoteProjectDetail(
            host: hostDisplay,
            path: Self.abbreviatedPath(location.remotePath)
        )
        self.accessibilityLabel = AppStrings.VibeSpace.parkedRemoteProjectAccessibility(
            name: self.displayName,
            host: hostDisplay
        )
    }

    private static func abbreviatedPath(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return "/" }
        return AppStrings.VibeSpace.remotePathBasename(name)
    }
}
