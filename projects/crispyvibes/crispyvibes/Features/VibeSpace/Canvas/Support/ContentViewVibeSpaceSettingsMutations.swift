import AppKit
import SwiftUI

extension ContentView {
    func projectColorTag(
        for vibespaceID: UUID,
        projectPath: String
    ) -> ProjectColorTag? {
        vibespaceValue(for: vibespaceID) { vibespace in
            vibespace.colorTag(for: projectPath)
        }
    }

    func startupSettings(for vibespaceID: UUID) -> VibeSpaceStartupSettings {
        vibespaceValue(for: vibespaceID) { vibespace in
            vibespace.startupSettings.normalized()
        } ?? .default
    }

    func startupOverride(
        for vibespaceID: UUID,
        projectPath: String
    ) -> VibeSpaceProjectStartupOverride? {
        vibespaceValue(for: vibespaceID) { vibespace in
            vibespace.startupOverride(for: projectPath)?.normalized()
        }
    }

    func vibespaceDefaultTerminalShell(for vibespaceID: UUID) -> TerminalShellPreference? {
        vibespaceValue(for: vibespaceID) { vibespace in
            vibespace.defaultTerminalShell
        }
    }

    func vibespaceSourceControlSettings(for vibespaceID: UUID) -> VibeSpaceSourceControlSettings {
        vibespaceValue(for: vibespaceID) { vibespace in
            vibespace.sourceControlSettings
        } ?? .default
    }

    func projectTerminalShellOverride(
        for vibespaceID: UUID,
        projectPath: String
    ) -> TerminalShellPreference? {
        vibespaceValue(for: vibespaceID) { vibespace in
            vibespace.terminalShellOverride(for: projectPath)
        }
    }

    func projectACPAgentOverrideID(
        for vibespaceID: UUID,
        projectPath: String
    ) -> String? {
        vibespaceValue(for: vibespaceID) { vibespace in
            vibespace.acpAgentOverrideID(for: projectPath)
        }
    }

    func updateStartupSettings(
        for vibespaceID: UUID,
        mutate: (inout VibeSpaceStartupSettings) -> Void
    ) {
        guard let currentSettings = vibespaceValue(for: vibespaceID, { $0.startupSettings }) else { return }
        var updated = currentSettings
        mutate(&updated)
        updated = updated.normalized()
        guard updated != currentSettings else { return }
        mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.startupSettings = updated
        }
        clearStartupExecutionFlags(for: vibespaceID)
        persistVibeSpaceCatalog()
        if vibespaceShell.activeVibeSpaceID == vibespaceID {
            scheduleVibeSpaceTerminalHydration(for: vibespaceID)
        }
    }

    func updateStartupOverride(
        for vibespaceID: UUID,
        projectPath: String,
        startupOverride: VibeSpaceProjectStartupOverride?
    ) {
        let normalizedOverride = startupOverride?.normalized()
        if vibespaceValue(for: vibespaceID, { $0.startupOverride(for: projectPath)?.normalized() }) == normalizedOverride {
            return
        }
        mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.setStartupOverride(normalizedOverride, forProjectPath: projectPath)
        }
        let normalizedProjectPath = VibeSpaceState.normalizedPath(from: projectPath)
        clearStartupExecutionFlag(forProjectPath: normalizedProjectPath, in: vibespaceID)
        persistVibeSpaceCatalog()
        if vibespaceShell.activeVibeSpaceID == vibespaceID {
            scheduleVibeSpaceTerminalHydration(for: vibespaceID)
        }
    }

    func updateVibeSpaceDefaultTerminalShell(
        for vibespaceID: UUID,
        defaultTerminalShell: TerminalShellPreference?
    ) {
        if vibespaceValue(for: vibespaceID, { $0.defaultTerminalShell }) == defaultTerminalShell {
            return
        }
        mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.defaultTerminalShell = defaultTerminalShell
        }
        persistVibeSpaceCatalog()
        refreshTerminalShellResolutionContexts(for: vibespaceID)
    }

    func updateProjectTerminalShellOverride(
        for vibespaceID: UUID,
        projectPath: String,
        shellPreference: TerminalShellPreference?
    ) {
        if vibespaceValue(for: vibespaceID, { $0.terminalShellOverride(for: projectPath) }) == shellPreference {
            return
        }
        mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.setTerminalShellOverride(shellPreference, forProjectPath: projectPath)
        }
        persistVibeSpaceCatalog()
        refreshTerminalShellResolutionContexts(for: vibespaceID)
    }

    func updateProjectACPAgentOverrideID(
        for vibespaceID: UUID,
        projectPath: String,
        agentID: String?
    ) {
        if vibespaceValue(for: vibespaceID, { $0.acpAgentOverrideID(for: projectPath) }) == agentID {
            return
        }
        mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.setACPAgentOverrideID(agentID, forProjectPath: projectPath)
        }
        persistVibeSpaceCatalog()
    }

    func updateVibeSpaceSourceControlSettings(
        for vibespaceID: UUID,
        sourceControlSettings: VibeSpaceSourceControlSettings
    ) {
        let normalizedSettings = sourceControlSettings.normalized()
        guard vibespaceValue(for: vibespaceID, { $0.sourceControlSettings }) != normalizedSettings else { return }

        mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.sourceControlSettings = normalizedSettings
        }
        persistVibeSpaceCatalog()

        if vibespaceShell.activeVibeSpaceID == vibespaceID {
            vibespaceSourceControlViewModel.updateVibeSpace(
                projects: vibespaceView.activeVibeSpaceProjects,
                focusedProject: vibespaceView.focusedProject,
                selectedFileURL: vibespaceView.sourceControlSelectedFileURL,
                sourceControlSettings: normalizedSettings
            )
        }
    }

    func projectShortcut(
        for vibespaceID: UUID,
        projectPath: String
    ) -> Int? {
        vibespaceValue(for: vibespaceID) { vibespace in
            vibespace.shortcutIndex(for: projectPath)
        }
    }

    func updateProjectShortcut(
        for vibespaceID: UUID,
        projectPath: String,
        shortcut: Int?
    ) {
        if vibespaceValue(for: vibespaceID, { $0.shortcutIndex(for: projectPath) }) == shortcut {
            return
        }
        mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.setShortcut(shortcut, forProjectPath: projectPath)
        }
        persistVibeSpaceCatalog()
    }

    func updateVibeSpaceShortcuts(
        for vibespaceID: UUID,
        shortcuts: [TerminalShortcutDefinition]
    ) {
        if vibespaceValue(for: vibespaceID, { $0.vibespaceShortcuts }) == shortcuts {
            return
        }
        mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.vibespaceShortcuts = shortcuts
        }
        appContainer.vibespaceManagement.setVibeSpaceShortcuts(shortcuts, vibespaceID: vibespaceID)
        persistVibeSpaceCatalog()
    }

    func updateProjectScopedShortcuts(
        for vibespaceID: UUID,
        projectPath: String,
        shortcuts: [TerminalShortcutDefinition]
    ) {
        if vibespaceValue(for: vibespaceID, { $0.projectScopedShortcuts(forProjectPath: projectPath) }) == shortcuts {
            return
        }
        mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.setProjectScopedShortcuts(shortcuts, forProjectPath: projectPath)
        }
        appContainer.vibespaceManagement.setProjectShortcuts(shortcuts, vibespaceID: vibespaceID, projectPath: projectPath)
        persistVibeSpaceCatalog()
    }

    func updateProjectColorTag(
        for vibespaceID: UUID,
        projectPath: String,
        colorTag: ProjectColorTag?
    ) {
        if vibespaceValue(for: vibespaceID, { $0.colorTag(for: projectPath) }) == colorTag {
            return
        }
        mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.setColorTag(colorTag, forProjectPath: projectPath)
        }
        persistVibeSpaceCatalog()
    }

    func addProjectsToVibeSpaceFromSettings(_ vibespaceID: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Project Folder(s)"

        guard panel.runModal() == .OK else { return }

        var focused: AnyProjectSession?
        mutateVibeSpace(id: vibespaceID) { vibespace in
            focused = vibespace.addProjects(from: panel.urls)
        }
        persistVibeSpaceCatalog()
        if vibespaceShell.activeVibeSpaceID == vibespaceID {
            if let focused {
                vibespaceCanvasActionsCoordinator.focusProject(focused)
            }
            scheduleVibeSpaceTerminalHydration(for: vibespaceID)
        }
    }

    @MainActor
    func addRemoteProjectToVibeSpace(_ vibespaceID: UUID) {
        let connectionManager = appContainer.sshConnectionManager
        let pickerVM = SSHConnectionPickerViewModel(connectionManager: connectionManager)
        let profileStore = SSHProfileStore()
        let catalogStore = vibespaceCatalogStore
        let container = appContainer
        let canvasCoordinator = vibespaceCanvasActionsCoordinator
        let shell = vibespaceShell
        let catalogCoordinator = homeCatalogCoordinator
        let overlayController = sshPickerOverlayController

        let presentation = SSHPickerPresentation(
            viewModel: pickerVM,
            profileStore: profileStore,
            onFolderSelected: { connection, remotePath in
                let identifier = "\(connection.profile.sshURI)\(remotePath)"
                let session = container.makeProjectSessionFromIdentifier(identifier, vibespaceID: vibespaceID)
                catalogStore.mutateVibeSpace(id: vibespaceID) { vibespace in
                    vibespace.projects.append(session)
                    vibespace.storedProjectPaths.append(session.projectIdentifier)
                    if vibespace.focusedProjectID == nil { vibespace.focusedProjectID = session.id }
                }
                catalogCoordinator.persistVibeSpaceCatalog()
                if shell.activeVibeSpaceID == vibespaceID {
                    canvasCoordinator.focusProject(session)
                }
                overlayController.dismiss()
            },
            onCancel: { overlayController.dismiss() }
        )

        overlayController.present(presentation)
    }

    func removeProjectFromVibeSpaceSettings(
        _ projectID: UUID,
        vibespaceID: UUID
    ) {
        let removedProjectPath = vibespaceValue(for: vibespaceID) { vibespace in
            vibespace.projects.first(where: { $0.id == projectID })?.rootURL.path
        }
        mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.removeProject(id: projectID)
        }
        if let removedProjectPath {
            clearStartupExecutionFlag(forProjectPath: removedProjectPath, in: vibespaceID)
        }
        persistVibeSpaceCatalog()
    }

    func moveVibeSpaceProjects(
        _ sourceOffsets: IndexSet,
        to destinationOffset: Int,
        vibespaceID: UUID
    ) {
        mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.moveProjects(fromOffsets: sourceOffsets, toOffset: destinationOffset)
        }
        persistVibeSpaceCatalog()
    }

    func reindexVibeSpaceProjects(_ vibespaceID: UUID) {
        Task { @MainActor in
            guard let paths = vibespaceValue(for: vibespaceID, { $0.availabilityReconciliationPaths() }) else { return }
            let existingDirectoryPaths = await VibeSpaceState.existingDirectoryPaths(for: paths)
            mutateVibeSpace(id: vibespaceID) { vibespace in
                vibespace.reconcileProjectAvailability(using: existingDirectoryPaths)
            }
            clearStartupExecutionFlags(for: vibespaceID)
            persistVibeSpaceCatalog()
            if vibespaceShell.activeVibeSpaceID == vibespaceID {
                scheduleVibeSpaceTerminalHydration(for: vibespaceID)
            }
        }
    }
}
