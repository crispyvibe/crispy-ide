import AppKit
import SwiftUI

extension ContentView {
    func syncWindowTitleWithVibeSpace() {
        let canvasModeLabel: String
        switch selectedVibeSpaceCanvasMode {
        case .detailed:
            canvasModeLabel = "Detailed View"
        case .terminalOnly:
            canvasModeLabel = "Board View"
        }

        var components: [String] = []
        if let vibespaceName = activeVibeSpaceSession.vibespace?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !vibespaceName.isEmpty {
            components.append(vibespaceName)
        }
        if activeVibeSpaceID != nil {
            components.append(canvasModeLabel)
            if let focusedTitle = activeVibeSpaceSession.focusedProject?.title.trimmingCharacters(in: .whitespacesAndNewlines),
               !focusedTitle.isEmpty {
                components.append(focusedTitle)
            }
        }

        let resolvedTitle = components.isEmpty
            ? AppStrings.Brand.crispyvibes
            : components.joined(separator: " / ")

        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first,
           window.title != resolvedTitle {
            window.title = resolvedTitle
        }
    }

    func showHomeCanvas() {
        homeShell.showHome()
    }

    func showVibeSpaceSettingsFromAppMenu() {
        guard homeShell.hasActiveVibeSpace else { return }
        homeShell.presentVibeSpaceSettingsForActiveVibeSpace()
        persistVibeSpaceCatalog()
    }

    func showAppSettingsFromAppMenu(category: AppSettingsCategory) {
        homeShell.presentAppSettings(category)
    }

    func showHelpFromAppMenu() {
        homeShell.dismissSurface()
        walkthroughController.presentFromToolbar()
    }

    func showProjectSidebar(_ tab: FolderExplorerViewModel.SidebarTab) {
        guard homeShell.hasActiveVibeSpace else { return }

        if showsVibeSpaceSidebar && homeShell.vibespaceSidebarTab == tab {
            homeShell.hideVibeSpaceSidebar()
            return
        }

        homeShell.showVibeSpaceSidebar(tab)

        let targetProject = activeVibeSpaceSession.focusedProject ?? activeVibeSpaceSession.projects.first
        guard let targetProject else { return }

        if activeVibeSpaceSession.focusedProject?.id != targetProject.id {
            vibespaceCanvasActionsCoordinator.focusProject(targetProject)
        }

        if tab != .sessions && tab != .conversations {
            targetProject.folderExplorer.activeSidebarTab = tab
        }
        if tab == .git {
            targetProject.folderExplorer.refreshGitStatus()
        }
        synchronizeVibeSpaceSidebarExpansion()
    }

    func openACPConversationFromToolbar() {
        if selectedVibeSpaceCanvasMode == .terminalOnly {
            NotificationCenter.default.post(name: .addACPTileToBoard, object: nil)
        } else {
            if let activeVibeSpaceID = vibespaceShell.activeVibeSpaceID {
                layoutPersistence.setCanvasMode(.detailed, for: activeVibeSpaceID)
            }
            _ = contentViewerStore.openACPPane(
                focusedProject: appContainer.acpVibeSpaceSessionService.focusedProject,
                preferredAgentID: appContainer.acpVibeSpaceSessionService.preferredAgentID,
                vibespaceID: vibespaceShell.activeVibeSpaceID
            )
        }
    }

    /// Handles the title-bar New Terminal popover submission. The popover
    /// can request three flavors:
    ///
    /// - **Project / custom path row in board mode** → adds a board tile on
    ///   the primary surface so the terminal persists across sessions.
    /// - **Project / custom path row in detailed mode** → opens a temporary
    ///   spotlight terminal so the editor layout stays intact.
    /// - **Temporary Terminal row (`preferTemporary == true`)** → always
    ///   opens a temporary spotlight terminal, regardless of canvas mode.
    func createTerminalFromToolbar(notification: Notification) {
        guard
            let directoryURL = notification.userInfo?[AppCommandUserInfoKey.currentDirectoryURL] as? URL
        else { return }
        let projectPath = notification.userInfo?[AppCommandUserInfoKey.projectPath] as? String
        let preferTemporary = (notification.userInfo?[AppCommandUserInfoKey.preferTemporary] as? Bool) ?? false

        let useSpotlight = preferTemporary || selectedVibeSpaceCanvasMode != .terminalOnly

        if !useSpotlight {
            _ = boardStore.addTile(
                projectPath: projectPath,
                directoryURL: directoryURL.standardizedFileURL,
                preferStandalone: projectPath == nil,
                surfaceID: VibeSpaceTerminalBoardState.primarySurfaceID
            )
            return
        }

        let owningProject = projectPath.flatMap { path in
            vibespaceView.activeVibeSpaceProjects.first(where: {
                $0.rootURL.standardizedFileURL.path == path
            })
        }
        let title = owningProject?.title ?? directoryURL.lastPathComponent
        let accentColor = owningProject.flatMap { vibespaceCanvasActionsCoordinator.colorTag(for: $0)?.color }
        let shellResolutionProvider: @Sendable () -> TerminalShellResolution
        if let owningProject {
            let store = owningProject.terminal.shellResolutionProviderStore
            shellResolutionProvider = { store.resolve() }
        } else {
            shellResolutionProvider = {
                TerminalShellResolver.resolve(context: TerminalShellResolutionContext())
            }
        }
        presentTemporaryTerminalSpotlight(
            title: title,
            accentColor: accentColor,
            directoryURL: directoryURL.standardizedFileURL,
            shellResolutionProvider: shellResolutionProvider,
            owningProjectRootURL: owningProject?.rootURL
        )
    }
}
