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

    var body: some View {
        VStack(spacing: 0) {
            vibespaceSidebarHeader

            Divider()

            vibespaceSidebarContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .git:
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
        case .sessions:
            VibeSpaceSidebarSessionsPane(
                activeVibeSpaceID: vibespaceShell.activeVibeSpaceID,
                vibespaces: vibespaces,
                onPreviewSession: onPreviewTmuxSession,
                onSendSessionToProject: onSendTmuxSessionToProject,
                onTerminateSession: onTerminateTmuxSession
            )
        case .conversations:
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
}

extension ContentView {
    var vibespaceSidebarPanel: some View {
        VibeSpaceSidebarPanelView(
            shelfStore: shelfStore,
            vibespaceCloneRepositoryCoordinator: vibespaceCloneRepositoryCoordinator,
            vibespaceShell: vibespaceShell,
            vibespaceView: vibespaceView,
            vibespaces: vibespaceCatalogStore.vibespaces,
            vibespaceSourceControlViewModel: vibespaceSourceControlViewModel,
            expandedProjectPaths: expandedVibeSpaceSidebarProjectPaths,
            shellHeaderCornerRadii: shellHeaderCornerRadii,
            projectColorTagsByPath: projectColorTagsByPath,
            onChooseCloneDestination: chooseCloneRepositoryDestinationDirectory,
            onShowGitHubPicker: showCloneRepositoryGitHubMode,
            onShowManualCloneURL: showCloneRepositoryURLMode,
            onRetryProviderCheck: refreshCloneRepositoryProviderOptions,
            onCancelCloneSheet: dismissCloneRepositorySheet,
            onSubmitCloneSheet: cloneRepositoryIntoActiveVibeSpace,
            onPresentCloneRepositorySheet: presentCloneRepositorySheet,
            onRefreshFocusedProjectFiles: refreshFocusedProjectFiles,
            onCreateFileInFocusedProject: createFileInFocusedProject,
            onCreateFolderInFocusedProject: createFolderInFocusedProject,
            onOpenAgentConversation: openACPConversationFromVibeSpace,
            onRefreshSourceControl: { vibespaceSourceControlViewModel.refresh() },
            onOpenSourceControlDiff: { repository, item in
                vibespaceCanvasActionsCoordinator.openSourceControlDiff(
                    repositoryRootURL: repository.repositoryRootURL,
                    item: item
                )
            },
            onSyncSourceControlContext: syncVibeSpaceSourceControlContext,
            onOpenShelfFile: { path in
                openShelfFile(at: path, makeVisible: false)
            },
            onRevealShelfFileInFinder: { path in
                openShelfFileInFinder(at: path)
            },
            onOpenShelfDirectoryInTerminal: { path in
                openShelfDirectoryInTerminal(at: path)
            },
            onRenameShelfFile: { path, newName in
                try renameShelfFile(at: path, to: newName)
            },
            onDeleteShelfFile: { path in
                try deleteShelfFile(at: path)
            },
            onRemoveShelfFile: { path in
                removeShelfFile(at: path)
            },
            onClearShelf: clearShelf,
            onPreviewTmuxSession: previewTmuxSession,
            onSendTmuxSessionToProject: sendTmuxSessionToProject,
            onTerminateTmuxSession: terminateTmuxSession,
            agentConversationStore: appContainer.agentConversationStore,
            externalAgentSessionService: appContainer.externalAgentSessionService,
            dockedAgentPreviewCoordinator: appContainer.dockedAgentPreviewCoordinator,
            onProjectExpansionToggled: toggleVibeSpaceSidebarProjectExpansion,
            onFocusedProjectAppeared: revealFocusedVibeSpaceSidebarProject,
            onProjectAction: handleVibeSpaceSidebarAction,
            onProjectTransferDrop: { project, plans in
                handleVibeSpaceSidebarTransferDrop(plans, for: project)
            },
            onOpenConversationThread: { thread in
                if vibespaceView.selectedCanvasMode == .terminalOnly {
                    // Board mode: show floating preview
                    let project = vibespaceView.focusedProject ?? vibespaceView.activeVibeSpaceProjects.first
                    dockedAgentPreviewCoordinator.showPreview(
                        threadId: thread.id,
                        title: thread.title,
                        agentId: thread.agentId,
                        projectIdentifier: project?.projectIdentifier,
                        vibespaceID: vibespaceShell.activeVibeSpaceID
                    )
                } else {
                    // Detailed mode: open as tab
                    _ = contentViewerStore.openACPPaneForThread(
                        agentId: thread.agentId,
                        projectPath: thread.projectPath,
                        threadId: thread.id,
                        projects: vibespaceView.activeVibeSpaceProjects,
                        vibespaceID: vibespaceShell.activeVibeSpaceID
                    )
                }
            },
            onDeleteConversationThread: { threadId in
                // Close tabs and tear down store
                if let store = contentViewerStore.sessionRegistry.store(forThread: threadId) {
                    contentViewerStore.removeACPStore(id: store.id)
                    NotificationCenter.default.post(
                        name: .acpStoreRemoved, object: nil,
                        userInfo: ["storeID": store.id]
                    )
                }
                // Dismiss dock preview if showing this thread
                if dockedAgentPreviewCoordinator.previewThreadId == threadId {
                    dockedAgentPreviewCoordinator.dismissPreview()
                }
                // Delete from DB
                await appContainer.agentConversationStore.deleteThread(id: threadId)
            },
            onPreviewExternalSession: { transcript in
                externalAgentSessionPreview = transcript
            }
        )
    }

    private func refreshFocusedProjectFiles() {
        withPrimarySidebarProject { project in
            project.folderExplorer.refreshTree(trigger: .manual)
        }
    }

    private func createFileInFocusedProject() {
        withPrimarySidebarProject { project in
            project.folderExplorer.createNewFileAtSelection()
        }
    }

    private func createFolderInFocusedProject() {
        withPrimarySidebarProject { project in
            project.folderExplorer.createNewFolderAtSelection()
        }
    }

    private func openACPConversationFromVibeSpace() {
        if let activeVibeSpaceID = vibespaceShell.activeVibeSpaceID {
            layoutPersistence.setCanvasMode(.detailed, for: activeVibeSpaceID)
        }
        _ = contentViewerStore.openACPPane(
            focusedProject: appContainer.acpVibeSpaceSessionService.focusedProject,
            preferredAgentID: appContainer.acpVibeSpaceSessionService.preferredAgentID,
            vibespaceID: vibespaceShell.activeVibeSpaceID
        )
    }

    func synchronizeVibeSpaceSidebarExpansion() {
        let projectPaths = Set(vibespaceView.activeVibeSpaceProjects.map { $0.rootURL.standardizedFileURL.path })
        setExpandedVibeSpaceSidebarProjectPaths(
            expandedVibeSpaceSidebarProjectPaths.intersection(projectPaths)
        )

        guard !projectPaths.isEmpty else {
            setExpandedVibeSpaceSidebarProjectPaths([])
            return
        }

        guard vibespaceView.selectedCanvasMode != .terminalOnly else { return }

        guard let focusedPath = vibespaceView.focusedProject?.rootURL.standardizedFileURL.path else { return }
        if !expandedVibeSpaceSidebarProjectPaths.contains(focusedPath) {
            var nextExpandedPaths = expandedVibeSpaceSidebarProjectPaths
            nextExpandedPaths.insert(focusedPath)
            setExpandedVibeSpaceSidebarProjectPaths(nextExpandedPaths)
        }
    }

    private func toggleVibeSpaceSidebarProjectExpansion(_ project: AnyProjectSession) {
        let path = project.rootURL.standardizedFileURL.path
        var nextExpandedPaths = expandedVibeSpaceSidebarProjectPaths
        if nextExpandedPaths.contains(path) {
            nextExpandedPaths.remove(path)
        } else {
            project.activate()
            project.ensureExplorerLoaded()
            project.folderExplorer.activeSidebarTab = vibespaceShell.sidebarTab
            nextExpandedPaths.insert(path)
        }
        setExpandedVibeSpaceSidebarProjectPaths(nextExpandedPaths)
    }

    private func revealFocusedVibeSpaceSidebarProject(_ project: AnyProjectSession) {
        let projectPath = project.rootURL.standardizedFileURL.path
        DispatchQueue.main.async {
            var nextExpandedPaths = expandedVibeSpaceSidebarProjectPaths
            nextExpandedPaths.insert(projectPath)
            setExpandedVibeSpaceSidebarProjectPaths(nextExpandedPaths)
        }
    }

    func syncVibeSpaceSourceControlContext() {
        vibespaceSourceControlViewModel.updateVibeSpace(
            projects: vibespaceView.activeVibeSpaceProjects,
            focusedProject: vibespaceView.focusedProject,
            selectedFileURL: vibespaceView.sourceControlSelectedFileURL,
            sourceControlSettings: vibespaceView.activeVibeSpace?.sourceControlSettings ?? .default
        )
    }

    private func prepareProjectForSidebarInteraction(_ project: AnyProjectSession, revealEditor: Bool = false) {
        project.ensureExplorerLoaded()
        project.folderExplorer.activeSidebarTab = vibespaceShell.sidebarTab

        if revealEditor, let activeVibeSpaceID = vibespaceShell.activeVibeSpaceID {
            layoutPersistence.setCanvasMode(.detailed, for: activeVibeSpaceID)
        }
    }

    private func selectVibeSpaceSidebarItem(_ item: FileItem, in project: AnyProjectSession) {
        project.ensureExplorerLoaded()
        project.folderExplorer.activeSidebarTab = vibespaceShell.sidebarTab
        project.folderExplorer.select(item)
    }

    private func openVibeSpaceSidebarItemInTab(_ item: FileItem, in project: AnyProjectSession) {
        let shouldRevealEditor = !item.isDirectory && vibespaceView.selectedCanvasMode != .terminalOnly
        prepareProjectForSidebarInteraction(project, revealEditor: shouldRevealEditor)
        project.folderExplorer.openInTab(item)
    }

    private func handleVibeSpaceSidebarAction(_ project: AnyProjectSession, _ action: FileTreeAction) {
        let vm = project.folderExplorer
        switch action {
        case .toggleExpansion(let item):
            prepareProjectForSidebarInteraction(project)
            vm.toggleExpansion(for: item)
        case .select(let item): selectVibeSpaceSidebarItem(item, in: project)
        case .openInTab(let item): openVibeSpaceSidebarItemInTab(item, in: project)
        case .openInFinder(let url): appContainer.vibespaceInteraction.revealInFinder(url)
        case .createNewFile(let item): vm.createNewFile(in: item)
        case .createNewFolder(let item): vm.createNewFolder(in: item)
        case .startRenaming(let item): vm.startRenaming(item: item)
        case .commitRename: vm.commitRename()
        case .cancelRename: vm.cancelRename()
        case .openInTerminal(let url):
            prepareProjectForSidebarInteraction(project)
            project.terminal.openOrSelectTab(for: url)
        case .openInSplitHorizontal(let item): vm.openInSplitHorizontal(item)
        case .openInSplitVertical(let item): vm.openInSplitVertical(item)
        case .requestDelete(let item): vm.deleteItem(item)
        }
    }

    private func handleVibeSpaceSidebarTransferDrop(
        _ plans: [ExplorerItemTransferPlan],
        for project: AnyProjectSession
    ) -> Bool {
        guard !plans.isEmpty else { return false }
        project.folderExplorer.transferItems(using: plans)
        return true
    }

    private var defaultExpandedVibeSpaceSidebarProjectPaths: Set<String> {
        guard vibespaceView.selectedCanvasMode != .terminalOnly,
              let focusedPath = vibespaceView.focusedProject?.rootURL.standardizedFileURL.path else {
            return []
        }
        return [focusedPath]
    }

    private func withPrimarySidebarProject(_ action: (AnyProjectSession) -> Void) {
        guard let project = vibespaceView.focusedProject ?? vibespaceView.activeVibeSpaceProjects.first else { return }
        project.ensureExplorerLoaded()
        action(project)
    }

    private func setExpandedVibeSpaceSidebarProjectPaths(_ paths: Set<String>) {
        if expandedVibeSpaceSidebarProjectPaths != paths {
            expandedVibeSpaceSidebarProjectPaths = paths
        }
    }
}
