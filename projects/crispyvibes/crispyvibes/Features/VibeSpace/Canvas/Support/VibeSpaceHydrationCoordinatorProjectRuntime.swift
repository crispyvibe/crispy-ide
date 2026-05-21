import Foundation

@MainActor
extension VibeSpaceHydrationCoordinator {
    func prepareProjectRuntime(
        _ project: AnyProjectSession,
        vibespaceID: UUID,
        includeVibeSpaceDefault: Bool,
        transitionID: String?,
        startIfCreated: Bool
    ) {
        project.activate()
        wireProjectFileOpenHandler(project)
        applyTerminalShellResolutionContext(to: project, vibespaceID: vibespaceID)
        if project.metadata.hostLabel == nil {
            project.terminal.ensureActiveTerminal(
                defaultDirectory: project.rootURL,
                transitionID: transitionID,
                startIfCreated: startIfCreated
            )
            applyStartupConfigurationIfNeeded(
                for: project,
                vibespaceID: vibespaceID,
                includeVibeSpaceDefault: includeVibeSpaceDefault
            )
        }
        syncTerminalDiagnosticsVibeSpaceID(for: project, vibespaceID: vibespaceID)
    }

    func wireProjectFileOpenHandler(_ project: AnyProjectSession) {
        vibespaceCanvasFileOpenUseCase.wireProjectFileOpenHandler(
            project,
            contentViewerStore: contentViewerStore,
            splitViewStore: splitViewStore,
            appShellStore: appShellStore,
            vibespaceCatalogStore: vibespaceCatalogStore,
            dockPreviewBridge: dockPreviewBridge,
            canvasModeProvider: canvasModeProvider
        )
    }

    func primeRemoteProjectsForRestore(in vibespace: VibeSpaceState) {
        for project in vibespace.projects where project.metadata.hostLabel != nil {
            project.activate()
            wireProjectFileOpenHandler(project)
        }
    }

    func syncTerminalDiagnosticsVibeSpaceID(
        for project: AnyProjectSession,
        vibespaceID: UUID
    ) {
        for tab in project.terminal.tabs {
            if let session = project.terminal.session(for: tab.id) {
                project.terminalViewModel.terminalServices.diagnosticsSnapshot.update(sessionID: session.id) {
                    $0.vibespaceID = vibespaceID
                }
            }
        }
    }

    func applyStartupConfigurationIfNeeded(
        for project: AnyProjectSession,
        vibespaceID: UUID,
        includeVibeSpaceDefault: Bool
    ) {
        guard let vibespace = vibespaceState(for: vibespaceID) else { return }
        let projectPath = project.rootURL.standardizedFileURL.path

        if hasExecutedStartup(forProjectPath: projectPath, in: vibespaceID) {
            return
        }

        let hasProjectOverride = vibespace.startupOverride(for: projectPath) != nil
        if !includeVibeSpaceDefault, !hasProjectOverride {
            return
        }

        let tabs = project.terminal.tabs
        let hasRestoredOrigins = tabs.contains(where: {
            if case .preset = $0.origin { return true }
            return false
        })

        if hasRestoredOrigins {
            let currentPlan = vibespaceHydrationUseCase.startupLaunchPlan(
                for: project.rootURL,
                in: vibespace,
                includeVibeSpaceDefault: includeVibeSpaceDefault
            )
            for tab in tabs {
                if case let .preset(profileIndex, _) = tab.origin,
                   let tabIndex = tabs.firstIndex(where: { $0.id == tab.id }),
                   let instruction = currentPlan.launchInstructions.first(where: { $0.terminalIndex == profileIndex }) {
                    project.terminal.runStartupCommandOnTab(
                        instruction.command,
                        customName: instruction.tabName,
                        tabIndex: tabIndex,
                        origin: .preset(profileIndex: profileIndex, command: instruction.command),
                        defaultDirectory: project.rootURL,
                        activateTab: false
                    )
                }
            }
        } else {
            let startupPlan = vibespaceHydrationUseCase.startupLaunchPlan(
                for: project.rootURL,
                in: vibespace,
                includeVibeSpaceDefault: includeVibeSpaceDefault
            )
            project.terminal.ensureTerminalCount(
                startupPlan.terminalCount,
                defaultDirectory: project.rootURL
            )
            for launchInstruction in startupPlan.launchInstructions {
                project.terminal.runStartupCommandOnTab(
                    launchInstruction.command,
                    customName: launchInstruction.tabName,
                    tabIndex: launchInstruction.terminalIndex,
                    origin: .preset(
                        profileIndex: launchInstruction.terminalIndex,
                        command: launchInstruction.command
                    ),
                    defaultDirectory: project.rootURL,
                    activateTab: false
                )
            }
        }

        markStartupExecuted(forProjectPath: projectPath, in: vibespaceID)
    }

    func hasExecutedStartup(forProjectPath projectPath: String, in vibespaceID: UUID) -> Bool {
        startupExecutedProjectPathsByVibeSpace[vibespaceID]?.contains(projectPath) ?? false
    }
}
