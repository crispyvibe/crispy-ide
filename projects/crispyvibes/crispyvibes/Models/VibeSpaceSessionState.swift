import Foundation

// MARK: - VibeSpace Session State

/// Captures the full runtime state of a vibespace for persistence.
/// Separate from vibespace settings and vibe space preset configuration.
/// Presets define the baseline; session state captures the runtime delta.
struct VibeSpaceSessionState: Codable, Equatable {
    var projectStates: [ProjectTerminalSessionState]
    var vibeCastTargetTabID: UUID?
    var editorState: EditorSessionState?

    static let empty = VibeSpaceSessionState(projectStates: [])
}

struct ProjectTerminalSessionState: Codable, Equatable {
    var projectPath: String
    var terminalEntries: [TerminalSessionEntry]
    var activeTerminalDirectory: String?
}

// MARK: - Terminal Session Restorer

/// Pure logic for computing restore actions from persisted session state
/// and current preset configuration. No side effects.
enum TerminalSessionRestorer {

    struct RestoreAction: Equatable {
        var directory: URL
        var customName: String?
        var origin: TerminalOrigin
        var shouldExecuteCommand: Bool
        var command: String?
    }

    /// Computes restore actions from persisted entries and current preset config.
    ///
    /// - Parameters:
    ///   - entries: Persisted terminal session entries from last session.
    ///   - presetProfiles: Current startup profiles from vibespace/project config.
    ///   - projectRoot: The project root URL (fallback directory).
    /// - Returns: Ordered list of restore actions.
    static func restoreActions(
        entries: [TerminalSessionEntry],
        presetProfiles: [IndexedProfile],
        projectRoot: URL
    ) -> [RestoreAction] {
        guard !entries.isEmpty else {
            return fallbackActions(presetProfiles: presetProfiles, projectRoot: projectRoot)
        }

        var actions: [RestoreAction] = []
        var restoredPresetIndices = Set<Int>()

        for entry in entries {
            let dir = URL(fileURLWithPath: entry.workingDirectoryPath).standardizedFileURL
            switch entry.origin {
            case let .preset(profileIndex, command):
                restoredPresetIndices.insert(profileIndex)
                // Re-execute preset command on restore
                actions.append(RestoreAction(
                    directory: dir,
                    customName: entry.customName,
                    origin: entry.origin,
                    shouldExecuteCommand: true,
                    command: command
                ))
            case .adHoc:
                // Restore name only, no command execution
                actions.append(RestoreAction(
                    directory: dir,
                    customName: entry.customName,
                    origin: .adHoc,
                    shouldExecuteCommand: false,
                    command: nil
                ))
            case .acp:
                continue
            case .agentCLI:
                continue
            }
        }

        // TERM-004a: Recreate missing preset terminals that were removed during last session
        for profile in presetProfiles where !restoredPresetIndices.contains(profile.index) {
            guard !profile.command.isEmpty else { continue }
            actions.append(RestoreAction(
                directory: projectRoot,
                customName: profile.tabName,
                origin: .preset(profileIndex: profile.index, command: profile.command),
                shouldExecuteCommand: true,
                command: profile.command
            ))
        }

        return actions
    }

    /// Fallback when no session entries exist (first launch or cleared state).
    private static func fallbackActions(
        presetProfiles: [IndexedProfile],
        projectRoot: URL
    ) -> [RestoreAction] {
        if presetProfiles.isEmpty {
            return [RestoreAction(
                directory: projectRoot,
                customName: nil,
                origin: .adHoc,
                shouldExecuteCommand: false,
                command: nil
            )]
        }
        return presetProfiles.map { profile in
            RestoreAction(
                directory: projectRoot,
                customName: profile.tabName,
                origin: profile.command.isEmpty
                    ? .adHoc
                    : .preset(profileIndex: profile.index, command: profile.command),
                shouldExecuteCommand: !profile.command.isEmpty,
                command: profile.command.isEmpty ? nil : profile.command
            )
        }
    }

    struct IndexedProfile: Equatable {
        var index: Int
        var command: String
        var tabName: String?
    }
}

@MainActor
enum ProjectTerminalSessionPersistence {
    static func restore(
        into terminalViewModel: TerminalViewModel,
        vibespaceManagement: VibeSpaceManagementService?,
        vibespaceID: UUID?,
        projectIdentifier: String,
        defaultDirectory: URL,
        pathMapper: (String) -> String = { $0 }
    ) {
        guard let vibespaceManagement,
              let vibespaceID,
              let session = vibespaceManagement.loadProjectSession(forProject: projectIdentifier, in: vibespaceID) else {
            terminalViewModel.restoreTabsFromEntries(
                [],
                activeDirectory: nil,
                activeIdentity: nil,
                defaultDirectory: defaultDirectory
            )
            return
        }

        let restoredState = ProjectSessionPersistedState(
            terminalEntries: session.entries.map { entry in
                TerminalSessionEntry(
                    id: entry.id,
                    workingDirectoryPath: pathMapper(entry.workingDirectoryPath),
                    customName: entry.customName,
                    origin: entry.origin,
                    tmuxSessionName: entry.tmuxSessionName
                )
            },
            activeTerminalDirectory: session.activeDirectory.map(pathMapper),
            activeTerminalIdentity: session.activeIdentity
        )

        terminalViewModel.restoreTabsFromEntries(
            restoredState.terminalEntries,
            activeDirectory: restoredState.activeTerminalDirectory.map { URL(fileURLWithPath: $0) },
            activeIdentity: restoredState.activeTerminalIdentity,
            defaultDirectory: defaultDirectory
        )
    }

    static func persist(
        from terminalViewModel: TerminalViewModel,
        vibespaceManagement: VibeSpaceManagementService?,
        vibespaceID: UUID?,
        projectIdentifier: String
    ) {
        guard let vibespaceManagement, let vibespaceID else { return }
        let state = snapshot(from: terminalViewModel)
        vibespaceManagement.saveProjectSession(
            entries: state.terminalEntries,
            activeDirectory: state.activeTerminalDirectory,
            activeIdentity: state.activeTerminalIdentity,
            forProject: projectIdentifier,
            in: vibespaceID
        )
    }

    static func snapshot(from terminalViewModel: TerminalViewModel) -> ProjectSessionPersistedState {
        let persistedTabs = terminalViewModel.tabs.filter { tab in
            if case .acp = tab.origin {
                return false
            }
            return true
        }
        let entries = persistedTabs.map { tab in
            TerminalSessionEntry(
                id: tab.id,
                workingDirectoryPath: tab.workingDirectory.standardizedFileURL.path,
                customName: tab.customName,
                origin: tab.origin,
                tmuxSessionName: terminalViewModel.session(for: tab.id)?.tmuxSessionName
            )
        }
        let activePersistedTab = terminalViewModel.activeTab.flatMap { tab -> TerminalTab? in
            if case .acp = tab.origin {
                return nil
            }
            return tab
        }
        let activeTerminalDirectory = activePersistedTab?.workingDirectory.standardizedFileURL.path
        let activeTerminalIdentity = activePersistedTab.flatMap { tab in
            TerminalViewModel.persistenceIdentity(tabID: tab.id)
        }
        return ProjectSessionPersistedState(
            terminalEntries: entries,
            activeTerminalDirectory: activeTerminalDirectory,
            activeTerminalIdentity: activeTerminalIdentity
        )
    }
}
