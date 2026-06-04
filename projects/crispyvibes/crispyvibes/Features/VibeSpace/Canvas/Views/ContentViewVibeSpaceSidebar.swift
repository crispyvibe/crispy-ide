import AppKit
import SwiftUI

struct VibeSpaceSidebarPanelView: View {
    @Environment(\.appThemePalette) private var activeThemePalette
    @AppStorage(AppPreferences.codeFontSizeKey) private var codeFontSize = AppPreferences.defaultCodeFontSize
    @ObservedObject var shelfStore: ShelfStore
    @ObservedObject var vibespaceCloneRepositoryCoordinator: VibeSpaceCloneRepositoryCoordinator

    let vibespaceShell: VibeSpaceShellContext
    let vibespaceView: VibeSpaceViewContext
    let vibespaces: [VibeSpaceState]
    let vibespaceSourceControlViewModel: VibeSpaceSourceControlViewModel
    let expandedProjectPaths: Set<String>
    let shellHeaderCornerRadii: RectangleCornerRadii
    let projectColorTagsByPath: [String: ProjectColorTag]
    let onChooseCloneDestination: () -> Void
    let onShowGitHubPicker: () -> Void
    let onShowManualCloneURL: () -> Void
    let onRetryProviderCheck: () -> Void
    let onCancelCloneSheet: () -> Void
    let onSubmitCloneSheet: () -> Void
    let onPresentCloneRepositorySheet: () -> Void
    let onRefreshFocusedProjectFiles: () -> Void
    let onCreateFileInFocusedProject: () -> Void
    let onCreateFolderInFocusedProject: () -> Void
    let onOpenAgentConversation: () -> Void
    let onRefreshSourceControl: () -> Void
    let onOpenSourceControlDiff: (VibeSpaceSourceControlRepositoryViewModel, VibeSpaceSourceControlStatusItem) -> Void
    let onSyncSourceControlContext: () -> Void
    let onOpenShelfFile: (String) -> Void
    let onRevealShelfFileInFinder: (String) -> Void
    let onOpenShelfDirectoryInTerminal: (String) -> Void
    let onRenameShelfFile: (String, String) throws -> Void
    let onDeleteShelfFile: (String) throws -> Void
    let onRemoveShelfFile: (String) -> Void
    let onClearShelf: () -> Void
    let onPreviewTmuxSession: (VibeSpaceSidebarTmuxSession) -> Void
    let onSendTmuxSessionToProject: (VibeSpaceSidebarTmuxSession, UUID) -> Void
    let onTerminateTmuxSession: (VibeSpaceSidebarTmuxSession) async -> Void
    let agentConversationStore: AgentConversationStore
    let externalAgentSessionService: ExternalAgentSessionService
    let dockedAgentPreviewCoordinator: DockedAgentPreviewCoordinator
    let onProjectExpansionToggled: (AnyProjectSession) -> Void
    let onFocusedProjectAppeared: (AnyProjectSession) -> Void
    let onProjectAction: (AnyProjectSession, FileTreeAction) -> Void
    let onProjectTransferDrop: (AnyProjectSession, [ExplorerItemTransferPlan]) -> Bool
    let onOpenConversationThread: (ConversationThreadSummary) -> Void
    let onDeleteConversationThread: (String) async -> Void
    let onPreviewExternalSession: (ExternalAgentTranscript) -> Void
    /// F053: when true, render the stacked collapsible unified layout instead
    /// of the classic tab-swapped content. Default false (classic).
    var isUnified: Bool = false
    /// F053: flips between classic and unified layouts (header toggle button).
    let onToggleUnified: () -> Void
    /// F052: open a not-added git worktree as a project (by absolute path).
    let onOpenWorktree: (String) -> Void
    /// F052: delete a git worktree from disk (by absolute path), confirmed.
    let onDeleteWorktree: (String) -> Void
    /// Start a new agent chat for a specific worktree/project.
    let onNewChat: (AnyProjectSession) -> Void
    /// F052: create a new worktree for the repo whose main root is passed.
    let onNewWorktree: (String) -> Void
    /// F052: git worktree discovery/mutations (injected, not called as a free function).
    let worktreeService: any WorktreeServicing

    @ObservedObject var viewModel: UnifiedSidebarViewModel

    // Forwarders so the panel body reads VM-owned state without the View
    // touching services directly (layering: ViewModels mediate state/logic).
    private var unifiedThreadsByProject: [String: [ConversationThreadSummary]] { viewModel.threadsByProject }
    private var worktreeInfoByProject: [String: ProjectWorktreeInfo] { viewModel.worktreeInfoByProject }
    private var worktreesByCommonDir: [String: [WorktreeEntry]] { viewModel.worktreesByCommonDir }

    var body: some View {
        VStack(spacing: 0) {
            if isUnified {
                unifiedSidebarHeader

                Divider()

                unifiedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                vibespaceSidebarHeader

                Divider()

                vibespaceSidebarContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(activeThemePalette.canvasBackgroundColor)
        .crispyvibesContainerBorder(opacity: 0.6)
        .sheet(isPresented: vibespaceShell.cloneRepositorySheetBinding) {
            VibeSpaceCloneRepositorySheet(
                state: Binding(
                    get: { vibespaceCloneRepositoryCoordinator.state },
                    set: { vibespaceCloneRepositoryCoordinator.state = $0 }
                ),
                onChooseDestination: onChooseCloneDestination,
                onShowGitHubPicker: onShowGitHubPicker,
                onShowManualURL: onShowManualCloneURL,
                onRetryProviderCheck: onRetryProviderCheck,
                onCancel: onCancelCloneSheet,
                onSubmit: onSubmitCloneSheet
            )
        }
    }

    private var chromeScale: CGFloat {
        AppPreferences.chromeScale(forCodeFontSize: codeFontSize)
    }

    private var vibespaceSidebarHeader: some View {
        CrispyVibesHeaderChrome(
            style: .panel,
            background: activeThemePalette.canvasSecondaryBackgroundColor.opacity(0.94),
            cornerRadii: shellHeaderCornerRadii
        ) {
            if vibespaceShell.sidebarTab == .files {
                Text(AppStrings.Sidebar.filesTab)
                    .font(CrispyVibesHeaderStyle.panel.titleFont(scale: chromeScale))
                    .foregroundStyle(activeThemePalette.primaryTextColor)
            } else if vibespaceShell.sidebarTab == .git {
                Text(AppStrings.SourceControl.title)
                    .font(CrispyVibesHeaderStyle.panel.titleFont(scale: chromeScale))
                    .foregroundStyle(activeThemePalette.primaryTextColor)
            } else if vibespaceShell.sidebarTab == .sessions {
                Text(AppStrings.Sidebar.sessionsTab)
                    .font(CrispyVibesHeaderStyle.panel.titleFont(scale: chromeScale))
                    .foregroundStyle(activeThemePalette.primaryTextColor)
            } else {
                Text(AppStrings.Sidebar.conversationsTab)
                    .font(CrispyVibesHeaderStyle.panel.titleFont(scale: chromeScale))
                    .foregroundStyle(activeThemePalette.primaryTextColor)
            }

            Spacer(minLength: 8)

            if vibespaceShell.sidebarTab == .files {
                vibespaceSidebarFilesActions
            } else if vibespaceShell.sidebarTab == .git {
                vibespaceSidebarGitActions
            }

            unifiedModeToggleButton
        }
    }

    private var unifiedSidebarHeader: some View {
        CrispyVibesHeaderChrome(
            style: .panel,
            background: activeThemePalette.canvasSecondaryBackgroundColor.opacity(0.94),
            cornerRadii: shellHeaderCornerRadii
        ) {
            Text(vibespaceView.activeVibeSpace?.name ?? AppStrings.Sidebar.filesTab)
                .font(CrispyVibesHeaderStyle.panel.titleFont(scale: chromeScale))
                .foregroundStyle(activeThemePalette.primaryTextColor)
                .lineLimit(1)

            Spacer(minLength: 8)

            unifiedModeToggleButton
        }
    }

    private var unifiedModeToggleButton: some View {
        vibespaceSidebarIconButton(
            symbolName: isUnified ? "sidebar.left" : "rectangle.3.group",
            helpText: isUnified ? "Classic Sidebar" : "Unified Sidebar",
            accessibilityIdentifier: "vibespace.sidebar.unified-toggle"
        ) {
            onToggleUnified()
        }
    }

    /// F053 (increment 1): per-project unified layout. Each project is a node
    /// that expands to its own Files / Source Control / Conversations
    /// sub-sections, consolidating what the classic view splits across tabs.
    /// Per-worktree grouping (Repository tier) is the next increment.
    @ViewBuilder
    private var unifiedContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if vibespaceView.activeVibeSpaceProjects.isEmpty {
                    ContentUnavailableView(
                        AppStrings.VibeSpace.noProjects,
                        systemImage: "folder",
                        description: Text(AppStrings.Explorer.openVibeSpaceToBrowse)
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ForEach(unifiedProjectGroups) { group in
                        if group.addedProjects.count == 1 && group.otherWorktrees.isEmpty {
                            VibeSpaceWorktreeNodeView(
                                project: group.addedProjects[0],
                                branch: worktreeInfoByProject[group.addedProjects[0].projectIdentifier]?.branch,
                                isFocused: vibespaceView.focusedProject?.id == group.addedProjects[0].id,
                                accentColor: projectColorTagsByPath[group.addedProjects[0].rootURL.standardizedFileURL.path]?.color
                                    ?? activeThemePalette.accentColor,
                                projectRootURLs: vibespaceView.activeVibeSpaceProjects.map(\.rootURL),
                                sourceControl: vibespaceSourceControlViewModel,
                                threads: unifiedThreadsByProject[group.addedProjects[0].projectIdentifier] ?? [],
                                onProjectAction: { onProjectAction(group.addedProjects[0], $0) },
                                onProjectTransferDrop: { onProjectTransferDrop(group.addedProjects[0], $0) },
                                onOpenDiff: onOpenSourceControlDiff,
                                onOpenThread: onOpenConversationThread,
                                onNewChat: { onNewChat(group.addedProjects[0]) }
                            )
                        } else {
                            VibeSpaceRepositoryNodeView(
                                title: group.title,
                                worktrees: group.addedProjects,
                                otherWorktrees: group.otherWorktrees,
                                branchByPath: worktreeInfoByProject.mapValues(\.branch),
                                primaryPath: group.primaryPath,
                                focusedProjectID: vibespaceView.focusedProject?.id,
                                accentColor: projectColorTagsByPath[group.addedProjects[0].rootURL.standardizedFileURL.path]?.color
                                    ?? activeThemePalette.accentColor,
                                projectRootURLs: vibespaceView.activeVibeSpaceProjects.map(\.rootURL),
                                sourceControl: vibespaceSourceControlViewModel,
                                threadsByProject: unifiedThreadsByProject,
                                onProjectAction: { onProjectAction($0, $1) },
                                onProjectTransferDrop: { onProjectTransferDrop($0, $1) },
                                onOpenDiff: onOpenSourceControlDiff,
                                onOpenThread: onOpenConversationThread,
                                onOpenWorktree: onOpenWorktree,
                                onDeleteWorktree: onDeleteWorktree,
                                onNewChat: onNewChat,
                                onNewWorktree: {
                                    onNewWorktree(group.primaryPath ?? group.addedProjects[0].projectIdentifier)
                                }
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .background(activeThemePalette.canvasBackgroundColor)
        .task(id: unifiedReloadKey) {
            await reloadUnified()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vibespaceWorktreesDidChange)) { _ in
            Task { await reloadUnified() }
        }
        .accessibilityIdentifier("vibespace.sidebar.unified")
    }

    /// Triggers the view model's reload (conversation threads + git worktree
    /// discovery) and syncs the source-control context. Re-run on
    /// vibespace/project-set change and after worktree mutations.
    private func reloadUnified() async {
        viewModel.configure(worktreeService: worktreeService, conversationStore: agentConversationStore)
        onSyncSourceControlContext()
        await viewModel.reload(
            projectPaths: vibespaceView.activeVibeSpaceProjects.map(\.projectIdentifier),
            vibespaceID: vibespaceShell.activeVibeSpaceID
        )
    }

    /// Re-runs thread/worktree discovery when the vibespace OR its project set
    /// changes (e.g. after "Open as Project" adds a worktree, so it re-clubs
    /// into its repository instead of appearing as a standalone node).
    private var unifiedReloadKey: String {
        let vibespace = vibespaceShell.activeVibeSpaceID?.uuidString ?? ""
        let paths = vibespaceView.activeVibeSpaceProjects.map(\.projectIdentifier).joined(separator: "|")
        return "\(vibespace)#\(paths)"
    }

    /// F052/F053: groups vibespace projects by shared git repository (worktrees
    /// of the same repo are clubbed) and attaches the repo's not-added
    /// worktrees. Order follows the project list.
    private var unifiedProjectGroups: [UnifiedProjectGroup] {
        var members: [[AnyProjectSession]] = []
        var indexByCommonDir: [String: Int] = [:]
        for project in vibespaceView.activeVibeSpaceProjects {
            if let commonDir = worktreeInfoByProject[project.projectIdentifier]?.commonDir,
               let groupIndex = indexByCommonDir[commonDir] {
                members[groupIndex].append(project)
            } else {
                members.append([project])
                if let commonDir = worktreeInfoByProject[project.projectIdentifier]?.commonDir {
                    indexByCommonDir[commonDir] = members.count - 1
                }
            }
        }
        return members.map { group in
            let commonDir = worktreeInfoByProject[group[0].projectIdentifier]?.commonDir
            let addedPaths = Set(group.map(\.projectIdentifier))
            let other = (commonDir.flatMap { worktreesByCommonDir[$0] } ?? [])
                .filter { !addedPaths.contains($0.path) }
            let isRepoGroup = group.count > 1 || !other.isEmpty
            let primaryPath = commonDir.map {
                URL(fileURLWithPath: $0).standardizedFileURL.deletingLastPathComponent().path
            }
            let title: String
            if isRepoGroup, let commonDir {
                let name = URL(fileURLWithPath: commonDir).deletingLastPathComponent().lastPathComponent
                title = name.isEmpty ? group[0].title : name
            } else {
                title = group[0].title
            }
            return UnifiedProjectGroup(
                id: group[0].id,
                addedProjects: group,
                title: title,
                otherWorktrees: other,
                primaryPath: primaryPath
            )
        }
    }

    @ViewBuilder
    private var vibespaceSidebarFilesActions: some View {
        vibespaceSidebarIconButton(
            symbolName: "plus.rectangle.on.folder",
            helpText: "Add File or Folder to Shelf",
            accessibilityIdentifier: "vibespace.sidebar.files.add-to-shelf"
        ) {
            openFileOrFolderToShelf()
        }
    }

    private func openFileOrFolderToShelf() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.prompt = "Add to Shelf"
        panel.message = "Select files or folders to add to the shelf"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        _ = shelfStore.addFiles(panel.urls)
    }

    @ViewBuilder
    private var vibespaceSidebarGitActions: some View {
        if !vibespaceView.activeVibeSpaceProjects.isEmpty {
            HStack(spacing: 6) {
                vibespaceSidebarIconButton(
                    symbolName: "square.and.arrow.down",
                    helpText: AppStrings.SourceControl.cloneRepository,
                    accessibilityIdentifier: "vibespace.sidebar.git.clone"
                ) {
                    onPresentCloneRepositorySheet()
                }

                vibespaceSidebarIconButton(
                    symbolName: "arrow.clockwise",
                    helpText: AppStrings.SourceControl.refreshRepository,
                    accessibilityIdentifier: "vibespace.sidebar.git.refresh"
                ) {
                    onRefreshSourceControl()
                }
            }
        }
    }

    private static func saveFileDialog(content: String, defaultName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func vibespaceSidebarIconButton(
        symbolName: String,
        helpText: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        CrispyVibesIconButton(
            systemName: symbolName,
            variant: .panel,
            color: activeThemePalette.secondaryTextColor,
            accessibilityLabel: helpText,
            action: action
        )
        .help(helpText)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var vibespaceSidebarContent: some View {
        switch vibespaceShell.sidebarTab {
        case .files:
            filesPane
        case .git:
            gitPane
        case .sessions:
            sessionsPane
        case .conversations:
            conversationsPane
        }
    }

    @ViewBuilder
    var filesPane: some View {
        VibeSpaceSidebarFilesPane(
            shelfStore: shelfStore,
            projects: vibespaceView.activeVibeSpaceProjects,
            focusedProject: vibespaceView.focusedProject,
            expandedProjectPaths: expandedProjectPaths,
            selectedCanvasMode: vibespaceView.selectedCanvasMode,
            projectColorTagsByPath: projectColorTagsByPath,
            parkedProjectPaths: vibespaceView.activeVibeSpace?.parkedProjectPaths ?? [],
            onOpenShelfFile: onOpenShelfFile,
            onRevealShelfFileInFinder: onRevealShelfFileInFinder,
            onOpenShelfDirectoryInTerminal: onOpenShelfDirectoryInTerminal,
            onRenameShelfFile: onRenameShelfFile,
            onDeleteShelfFile: onDeleteShelfFile,
            onRemoveShelfFile: onRemoveShelfFile,
            onClearShelf: onClearShelf,
            onProjectExpansionToggled: onProjectExpansionToggled,
            onFocusedProjectAppeared: onFocusedProjectAppeared,
            onProjectAction: onProjectAction,
            onProjectTransferDrop: onProjectTransferDrop
        )
    }

    @ViewBuilder
    var gitPane: some View {
        VibeSpaceSidebarGitPane(
            projects: vibespaceView.activeVibeSpaceProjects,
            focusedProjectID: vibespaceView.focusedProject?.id,
            activeVibeSpaceID: vibespaceShell.activeVibeSpaceID,
            sourceControlSelectedFileURL: vibespaceView.sourceControlSelectedFileURL,
            sourceControlSettings: vibespaceView.activeVibeSpace?.sourceControlSettings ?? .default,
            viewModel: vibespaceSourceControlViewModel,
            onCloneRequested: onPresentCloneRepositorySheet,
            onOpenDiff: onOpenSourceControlDiff,
            onSyncSourceControlContext: onSyncSourceControlContext
        )
    }

    @ViewBuilder
    var sessionsPane: some View {
        VibeSpaceSidebarSessionsPane(
            activeVibeSpaceID: vibespaceShell.activeVibeSpaceID,
            vibespaces: vibespaces,
            onPreviewSession: onPreviewTmuxSession,
            onSendSessionToProject: onSendTmuxSessionToProject,
            onTerminateSession: onTerminateTmuxSession
        )
    }

    @ViewBuilder
    var conversationsPane: some View {
        VibeSpaceSidebarConversationsPane(
            store: agentConversationStore,
            externalSessionService: externalAgentSessionService,
            vibespaceID: vibespaceShell.activeVibeSpaceID,
            vibespaceName: vibespaceView.activeVibeSpace?.name,
            projectColorTagsByPath: projectColorTagsByPath,
            onOpenThread: { thread in
                onOpenConversationThread(thread)
            },
            onDeleteThread: { threadId in
                await onDeleteConversationThread(threadId)
            },
            onExportMarkdown: { threadId in
                guard let markdown = await agentConversationStore.exportMarkdown(threadId: threadId) else { return }
                await MainActor.run { Self.saveFileDialog(content: markdown, defaultName: "conversation.md") }
            },
            onExportJSON: { threadId in
                guard let json = await agentConversationStore.exportJSON(threadId: threadId) else { return }
                await MainActor.run { Self.saveFileDialog(content: json, defaultName: "conversation.json") }
            },
            onPreviewExternalSession: onPreviewExternalSession
        )
    }
}
