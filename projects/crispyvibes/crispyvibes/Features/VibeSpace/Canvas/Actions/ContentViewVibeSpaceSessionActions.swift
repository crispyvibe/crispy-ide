import SwiftUI

extension ContentView {
    func previewTmuxSession(_ session: VibeSpaceSidebarTmuxSession) {
        switch session.source {
        case .local:
            let project = session.launchContextProjectID.flatMap { projectID in
                vibespaceView.activeVibeSpaceProjects.first(where: { $0.id == projectID })
            }
            let accentColor = project.flatMap { vibespaceCanvasActionsCoordinator.colorTag(for: $0)?.color }
            let shellResolutionProvider: @Sendable () -> TerminalShellResolution

            if let project {
                let shellResolutionProviderStore = project.terminal.shellResolutionProviderStore
                shellResolutionProvider = { shellResolutionProviderStore.resolve() }
            } else {
                shellResolutionProvider = {
                    TerminalShellResolver.resolve(context: TerminalShellResolutionContext())
                }
            }

            presentTemporaryTerminalSpotlight(
                title: session.sessionName,
                accentColor: accentColor,
                directoryURL: session.workingDirectoryURL,
                shellResolutionProvider: shellResolutionProvider,
                sessionConfigurator: { terminalSession in
                    terminalSession.tmuxSessionName = session.sessionName
                },
                owningProjectRootURL: project?.rootURL
            )

        case .remote:
            guard let projectID = session.launchContextProjectID,
                  let project = vibespaceView.activeVibeSpaceProjects.first(where: { $0.id == projectID }),
                  let connection = project.sshConnection else { return }

            let accentColor = vibespaceCanvasActionsCoordinator.colorTag(for: project)?.color
            let shellResolutionProviderStore = project.terminal.shellResolutionProviderStore
            let profile = connection.profile
            let hasTmux = connection.hasTmux
            let workingDirectory = session.workingDirectory

            presentTemporaryTerminalSpotlight(
                title: session.sessionName,
                accentColor: accentColor,
                directoryURL: session.workingDirectoryURL,
                shellResolutionProvider: { shellResolutionProviderStore.resolve() },
                sessionConfigurator: { terminalSession in
                    terminalSession.tmuxSessionName = session.sessionName
                    terminalSession.processLaunchOverride = { _ in
                        RemoteProjectSession.makeSSHLaunchInvocation(
                            profile: profile,
                            workingDirectory: workingDirectory,
                            hasTmux: hasTmux,
                            tmuxSessionName: session.sessionName
                        )
                    }
                },
                owningProjectRootURL: project.rootURL
            )
        }
    }

    func sendTmuxSessionToProject(_ session: VibeSpaceSidebarTmuxSession, projectID: UUID) {
        guard let project = vibespaceView.activeVibeSpaceProjects.first(where: { $0.id == projectID }) else {
            return
        }

        if let existingTab = project.terminal.tabs.first(where: { tab in
            project.terminal.session(for: tab.id)?.tmuxSessionName == session.sessionName
        }) {
            project.terminal.selectTab(existingTab)
        } else {
            project.terminal.createTab(
                directoryURL: session.workingDirectoryURL,
                customName: session.sessionName,
                origin: .adHoc,
                tmuxSessionName: session.sessionName,
                startImmediately: true
            )
        }

        vibespaceCanvasActionsCoordinator.focusProject(project, forceTerminalFocus: true)
        requestTerminalFocusWithStabilization(for: project.terminal)
        dismissTerminalSpotlight()
    }

    func terminateTmuxSession(_ session: VibeSpaceSidebarTmuxSession) async {
        if case let .transient(spotlightSession) = terminalSpotlightCoordinator.spotlight?.source,
           spotlightSession.tmuxSessionName == session.sessionName {
            dismissTerminalSpotlight()
        }

        switch session.source {
        case .local:
            let sessionName = session.sessionName
            await Task.detached(priority: .utility) {
                TmuxService.killSession(sessionName)
            }.value

        case .remote:
            guard let projectID = session.launchContextProjectID,
                  let project = vibespaceView.activeVibeSpaceProjects.first(where: { $0.id == projectID }),
                  let connection = project.sshConnection else { return }

            let sessionName = session.sessionName
            let executor = RemoteCommandExecutor(connection: connection)
            _ = try? await executor.execute(
                tool: "tmux",
                arguments: ["kill-session", "-t", sessionName],
                stdinData: nil,
                timeout: 10
            )
        }
    }
}
