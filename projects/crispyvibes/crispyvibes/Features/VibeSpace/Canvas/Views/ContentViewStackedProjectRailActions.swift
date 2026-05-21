import SwiftUI

extension ContentView {
    var activeVibeSpaceHiddenRailTerminalIDsByProjectPath: [String: Set<UUID>] {
        guard let activeVibeSpaceID = vibespaceShell.activeVibeSpaceID else { return [:] }
        return hiddenRailTerminalIDsByVibeSpace[activeVibeSpaceID] ?? [:]
    }

    var stackedRailObservedVibeSpace: StackedRailObservedVibeSpace {
        StackedRailObservedVibeSpace(
            vibespaceID: vibespaceShell.activeVibeSpaceID,
            projectPaths: vibespaceView.stackedProjects.map { $0.rootURL.standardizedFileURL.path }
        )
    }

    func synchronizeStackedRailStore() {
        stackedRailStore.syncProjects(vibespaceView.stackedProjects)
    }

    var stackedProjectRail: some View {
        VibeSpaceStackedProjectRailView(
            stackedRailStore: stackedRailStore,
            stackedRailOverlayCoordinator: stackedRailOverlayCoordinator,
            vibespaceView: vibespaceView,
            hiddenTerminalIDsByProjectPath: activeVibeSpaceHiddenRailTerminalIDsByProjectPath,
            isHiddenRailSectionExpanded: $isHiddenRailSectionExpanded,
            projectColorTagsByPath: projectColorTagsByPath,
            onAddProjectsRequested: {
                homeCatalogCoordinator.addProjectsToActiveVibeSpaceFromFolderPicker(
                    focusProject: { project, forceTerminalFocus in
                        vibespaceCanvasActionsCoordinator.focusProject(
                            project,
                            forceTerminalFocus: forceTerminalFocus
                        )
                    },
                    openTerminalOnlyVibeSpaceView: {
                        vibespaceCanvasActionsCoordinator.openTerminalOnlyVibeSpaceView()
                    }
                )
            },
            onFocusTerminal: focusRailTerminal,
            onCloseTerminal: closeRailTerminal,
            onHideTerminal: hideRailTerminal,
            onRestartTerminal: restartRailTerminal,
            onRenameTerminal: renameRailTerminal,
            onSpotlightTerminal: spotlightRailTerminal,
            onUnhideTerminal: unhideRailTerminal
        )
    }

    private func focusRailTerminal(_ project: AnyProjectSession, _ tab: TerminalTab) {
        stackedRailOverlayCoordinator.dismiss()
        project.activate()
        project.terminal.selectTab(tab)
        vibespaceCanvasActionsCoordinator.focusProject(project, forceTerminalFocus: true)
    }

    private func closeRailTerminal(_ project: AnyProjectSession, _ tab: TerminalTab) {
        clearRailTerminalPresentationIfNeeded(project: project, tabID: tab.id)
        unhideRailTerminal(project.rootURL.standardizedFileURL.path, tab.id)
        project.terminal.closeTab(tab)
    }

    private func hideRailTerminal(_ projectPath: String, _ tabID: UUID, _ project: AnyProjectSession?) {
        guard let activeVibeSpaceID = vibespaceShell.activeVibeSpaceID else { return }
        if let project {
            clearRailTerminalPresentationIfNeeded(project: project, tabID: tabID)
        }
        mutateHiddenRailTerminals(for: activeVibeSpaceID) { hiddenTerminals in
            var hiddenIDs = hiddenTerminals[projectPath] ?? []
            hiddenIDs.insert(tabID)
            hiddenTerminals[projectPath] = hiddenIDs
        }
    }

    private func unhideRailTerminal(_ projectPath: String, _ tabID: UUID) {
        guard let activeVibeSpaceID = vibespaceShell.activeVibeSpaceID else { return }
        mutateHiddenRailTerminals(for: activeVibeSpaceID) { hiddenTerminals in
            guard var hiddenIDs = hiddenTerminals[projectPath] else { return }
            hiddenIDs.remove(tabID)
            if hiddenIDs.isEmpty {
                hiddenTerminals.removeValue(forKey: projectPath)
            } else {
                hiddenTerminals[projectPath] = hiddenIDs
            }
        }
    }

    private func restartRailTerminal(_ projectPath: String, _ tab: TerminalTab, _ project: AnyProjectSession?) {
        guard let project else { return }
        clearRailTerminalPresentationIfNeeded(project: project, tabID: tab.id)
        let shouldActivate = !(activeVibeSpaceHiddenRailTerminalIDsByProjectPath[projectPath]?.contains(tab.id) ?? false)
        project.terminal.restartTab(tab.id, activateTab: shouldActivate)
    }

    private func renameRailTerminal(_ project: AnyProjectSession, _ tabID: UUID, _ title: String) {
        project.terminal.renameTab(tabID, to: title)
    }

    private func spotlightRailTerminal(_ project: AnyProjectSession, _ tab: TerminalTab) {
        presentTerminalSpotlight(
            terminalViewModel: project.terminalViewModel,
            tabID: tab.id,
            title: tab.title,
            accentColor: vibespaceCanvasActionsCoordinator.colorTag(for: project)?.color,
            owningProjectRootURL: project.rootURL
        )
    }

    private func clearRailTerminalPresentationIfNeeded(project: AnyProjectSession, tabID: UUID) {
        guard let terminalSpotlight = terminalSpotlightCoordinator.spotlight else { return }
        guard case let .persistent(terminalViewModel, spotlightTabID) = terminalSpotlight.source else { return }
        guard terminalViewModel === project.terminalViewModel, spotlightTabID == tabID else { return }
        dismissTerminalSpotlight()
    }

    private func mutateHiddenRailTerminals(
        for vibespaceID: UUID,
        update: (inout [String: Set<UUID>]) -> Void
    ) {
        var hiddenTerminals = hiddenRailTerminalIDsByVibeSpace[vibespaceID] ?? [:]
        update(&hiddenTerminals)
        hiddenRailTerminalIDsByVibeSpace[vibespaceID] = hiddenTerminals
    }
}
