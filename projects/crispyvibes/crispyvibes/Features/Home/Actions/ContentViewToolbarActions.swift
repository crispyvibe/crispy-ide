import AppKit
import SwiftUI

extension ContentView {
    func syncWindowTitleWithVibeSpace() {
        let resolvedTitle: String
        if let vibespaceName = activeVibeSpaceSession.vibespace?.name.trimmingCharacters(in: .whitespacesAndNewlines),
                  !vibespaceName.isEmpty {
            resolvedTitle = vibespaceName
        } else {
            resolvedTitle = AppStrings.Brand.crispyvibes
        }

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
}
