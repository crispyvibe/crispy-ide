import SwiftUI

extension ContentView {
    @MainActor
    struct VibeSpaceSettingsContext {
        let vibespaceName: String
        let selectedCategory: Binding<VibeSpaceSettingsCategory>
        let projects: [VibeSpaceSettingsProjectItem]
        let availableTerminalPresets: [TerminalPresetDefinition]
        let availableACPAgents: [ACPDiscoveredAgent]
        let startupSettings: Binding<VibeSpaceStartupSettings>
        let vibespaceDefaultTerminalShell: Binding<TerminalShellPreference?>
        let sourceControlSettings: Binding<VibeSpaceSourceControlSettings>
        let startupOverrideForPath: (String) -> VibeSpaceProjectStartupOverride?
        let setStartupOverride: (String, VibeSpaceProjectStartupOverride?) -> Void
        let projectACPAgentOverrideIDForPath: (String) -> String?
        let setProjectACPAgentOverrideID: (String, String?) -> Void
        let setProjectShortcut: (String, Int?) -> Void
        let projectColorTagForPath: (String) -> ProjectColorTag?
        let setProjectColorTag: (String, ProjectColorTag?) -> Void
        let projectTerminalShellOverrideForPath: (String) -> TerminalShellPreference?
        let setProjectTerminalShellOverride: (String, TerminalShellPreference?) -> Void
        let onAddProjects: () -> Void
        let onAddRemoteProject: () -> Void
        let onRemoveProject: (UUID) -> Void
        let onMoveProjects: (IndexSet, Int) -> Void
        let onRenameVibeSpace: (String) -> Void
        let onReindexProjects: () -> Void
        let onClose: () -> Void
        let vibespaceShortcuts: [TerminalShortcutDefinition]
        let setVibeSpaceShortcuts: ([TerminalShortcutDefinition]) -> Void
        let projectShortcutsForPath: (String) -> [TerminalShortcutDefinition]
        let setProjectShortcutsForPath: (String, [TerminalShortcutDefinition]) -> Void
    }

    func vibespaceSettingsContext(for vibespaceID: UUID) -> VibeSpaceSettingsContext? {
        guard let vibespace = vibespaceState(for: vibespaceID) else { return nil }

        return VibeSpaceSettingsContext(
            vibespaceName: vibespace.name,
            selectedCategory: vibespaceShell.vibespaceSettingsCategoryBinding,
            projects: vibespace.projects.map { project in
                VibeSpaceSettingsProjectItem(
                    id: project.id,
                    title: project.title,
                    path: project.rootURL.path,
                    shortcutIndex: vibespace.shortcutIndex(for: project),
                    colorTag: vibespace.colorTag(for: project)
                )
            },
            availableTerminalPresets: TerminalViewModel.availableBuiltInPresets(
                using: appContainer.terminalViewModelDependencies
            ),
            availableACPAgents: ACPAgentRegistry.discoverInstalledAgents(),
            startupSettings: Binding(
                get: { startupSettings(for: vibespaceID) },
                set: { newValue in
                    updateStartupSettings(for: vibespaceID) { settings in
                        settings = newValue
                    }
                }
            ),
            vibespaceDefaultTerminalShell: Binding(
                get: { vibespaceDefaultTerminalShell(for: vibespaceID) },
                set: { newValue in
                    updateVibeSpaceDefaultTerminalShell(
                        for: vibespaceID,
                        defaultTerminalShell: newValue
                    )
                }
            ),
            sourceControlSettings: Binding(
                get: { vibespaceSourceControlSettings(for: vibespaceID) },
                set: { newValue in
                    updateVibeSpaceSourceControlSettings(
                        for: vibespaceID,
                        sourceControlSettings: newValue
                    )
                }
            ),
            startupOverrideForPath: { projectPath in
                startupOverride(for: vibespaceID, projectPath: projectPath)
            },
            setStartupOverride: { projectPath, startupOverride in
                updateStartupOverride(
                    for: vibespaceID,
                    projectPath: projectPath,
                    startupOverride: startupOverride
                )
            },
            projectACPAgentOverrideIDForPath: { projectPath in
                projectACPAgentOverrideID(for: vibespaceID, projectPath: projectPath)
            },
            setProjectACPAgentOverrideID: { projectPath, agentID in
                updateProjectACPAgentOverrideID(
                    for: vibespaceID,
                    projectPath: projectPath,
                    agentID: agentID
                )
            },
            setProjectShortcut: { projectPath, shortcut in
                updateProjectShortcut(
                    for: vibespaceID,
                    projectPath: projectPath,
                    shortcut: shortcut
                )
            },
            projectColorTagForPath: { projectPath in
                projectColorTag(for: vibespaceID, projectPath: projectPath)
            },
            setProjectColorTag: { projectPath, colorTag in
                updateProjectColorTag(
                    for: vibespaceID,
                    projectPath: projectPath,
                    colorTag: colorTag
                )
            },
            projectTerminalShellOverrideForPath: { projectPath in
                projectTerminalShellOverride(for: vibespaceID, projectPath: projectPath)
            },
            setProjectTerminalShellOverride: { projectPath, shellPreference in
                updateProjectTerminalShellOverride(
                    for: vibespaceID,
                    projectPath: projectPath,
                    shellPreference: shellPreference
                )
            },
            onAddProjects: {
                addProjectsToVibeSpaceFromSettings(vibespaceID)
            },
            onAddRemoteProject: {
                addRemoteProjectToVibeSpace(vibespaceID)
            },
            onRemoveProject: { projectID in
                removeProjectFromVibeSpaceSettings(projectID, vibespaceID: vibespaceID)
            },
            onMoveProjects: { sourceOffsets, destinationOffset in
                moveVibeSpaceProjects(
                    sourceOffsets,
                    to: destinationOffset,
                    vibespaceID: vibespaceID
                )
            },
            onRenameVibeSpace: { updatedName in
                homeCatalogCoordinator.renameVibeSpace(
                    vibespaceID,
                    to: updatedName,
                    onActiveVibeSpaceRenamed: syncWindowTitleWithVibeSpace
                )
            },
            onReindexProjects: {
                reindexVibeSpaceProjects(vibespaceID)
            },
            onClose: {
                vibespaceShell.dismissSurface()
            },
            vibespaceShortcuts: appContainer.vibespaceManagement.vibespaceShortcuts(vibespaceID: vibespaceID),
            setVibeSpaceShortcuts: { shortcuts in
                updateVibeSpaceShortcuts(for: vibespaceID, shortcuts: shortcuts)
            },
            projectShortcutsForPath: { projectPath in
                appContainer.vibespaceManagement.projectShortcuts(vibespaceID: vibespaceID, projectPath: projectPath)
            },
            setProjectShortcutsForPath: { projectPath, shortcuts in
                updateProjectScopedShortcuts(
                    for: vibespaceID,
                    projectPath: projectPath,
                    shortcuts: shortcuts
                )
            }
        )
    }
}
