import AppKit
import SwiftUI

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
                // Surface (docked preview in board mode vs detail tab) is decided
                // centrally by ContentSurfacePolicy via present(_:).
                vibespaceCanvasActionsCoordinator.present(.conversationThread(thread))
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
            },
            isUnified: appShellStore.vibespaceSidebarUnified,
            onOpenWorktree: { path in
                _ = vibespaceCanvasActionsCoordinator.addProjectsViaCLI(urls: [URL(fileURLWithPath: path)])
            },
            onDeleteWorktree: { path in
                deleteWorktree(path: path)
            },
            onNewChat: { project in
                newChat(for: project)
            },
            onNewWorktree: { repoRoot in
                newWorktree(repoRoot: repoRoot)
            },
            worktreeService: appContainer.worktreeService,
            viewModel: unifiedSidebarViewModel
        )
    }

    /// Open a new agent (ACP) conversation scoped to a specific worktree.
    /// Surface (board tile vs detail tab) is decided centrally by
    /// `VibeSpaceCanvasActionsCoordinator.present(_:)` based on the active view.
    private func newChat(for project: AnyProjectSession) {
        vibespaceCanvasActionsCoordinator.present(
            .agentChat(
                project: project,
                preferredAgentID: appContainer.acpVibeSpaceSessionService.preferredAgentID
            )
        )
    }

    /// F055: prompt for a branch, create a sibling worktree on it, and open it.
    private func newWorktree(repoRoot: String) {
        let prompt = NSAlert()
        prompt.messageText = AppStrings.Worktree.newTitle
        prompt.informativeText = AppStrings.Worktree.newMessage
        prompt.addButton(withTitle: AppStrings.Worktree.newCreateButton)
        prompt.addButton(withTitle: AppStrings.Worktree.cancel)
        let field = NSTextField(string: "")
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        field.placeholderString = AppStrings.Worktree.newBranchPlaceholder
        prompt.accessoryView = field
        field.selectText(nil)
        guard prompt.runModal() == .alertFirstButtonReturn else { return }
        let branch = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return }

        let repoURL = URL(fileURLWithPath: repoRoot)
        let safeName = "\(repoURL.lastPathComponent)-\(branch.replacingOccurrences(of: "/", with: "-"))"
        let worktreePath = repoURL.deletingLastPathComponent().appendingPathComponent(safeName).path

        Task { @MainActor in
            let result = await unifiedSidebarViewModel.addWorktree(repoRoot: repoRoot, worktreePath: worktreePath, branch: branch)
            if let path = result.path {
                _ = vibespaceCanvasActionsCoordinator.addProjectsViaCLI(urls: [URL(fileURLWithPath: path)])
                NotificationCenter.default.post(name: .vibespaceWorktreesDidChange, object: nil)
            } else {
                let fail = NSAlert()
                fail.alertStyle = .warning
                fail.messageText = AppStrings.Worktree.createFailedTitle
                fail.informativeText = result.error ?? "git worktree add failed."
                fail.runModal()
            }
        }
    }

    /// F055: delete a git worktree from disk (confirmed). Removes its project
    /// first if it's added, runs `git worktree remove`, offers a force fallback
    /// for dirty/locked worktrees, then re-discovers worktrees.
    private func deleteWorktree(path: String) {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = AppStrings.Worktree.deleteConfirmTitle(name)
        confirm.informativeText = AppStrings.Worktree.deleteConfirmMessage
        confirm.addButton(withTitle: AppStrings.Worktree.deleteButton)
        confirm.addButton(withTitle: AppStrings.Worktree.cancel)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let normalized = VibeSpaceState.normalizedPath(from: path)
        if let project = activeVibeSpaceSession.projects.first(where: { $0.projectIdentifier == normalized }) {
            vibespaceCanvasActionsCoordinator.removeProject(id: project.id)
        }

        Task { @MainActor in
            if let error = await unifiedSidebarViewModel.removeWorktree(path: path, force: false) {
                let force = NSAlert()
                force.alertStyle = .critical
                force.messageText = AppStrings.Worktree.forceDeleteTitle
                force.informativeText = AppStrings.Worktree.forceDeleteMessage(error)
                force.addButton(withTitle: AppStrings.Worktree.forceDeleteButton)
                force.addButton(withTitle: AppStrings.Worktree.cancel)
                if force.runModal() == .alertFirstButtonReturn {
                    _ = await unifiedSidebarViewModel.removeWorktree(path: path, force: true)
                }
            }
            NotificationCenter.default.post(name: .vibespaceWorktreesDidChange, object: nil)
        }
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
        vibespaceCanvasActionsCoordinator.present(
            .agentChat(
                project: appContainer.acpVibeSpaceSessionService.focusedProject,
                preferredAgentID: appContainer.acpVibeSpaceSessionService.preferredAgentID
            )
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
        // File surfacing: reveal the editor only when the policy routes files
        // to a detail tab (i.e. not board mode, where a file shows as a docked
        // preview). Same rulebook the file-open use case consults.
        let shouldRevealEditor = !item.isDirectory
            && ContentSurfacePolicy.surface(for: .file, mode: vibespaceView.selectedCanvasMode) == .detailTab
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

