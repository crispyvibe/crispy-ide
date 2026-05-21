import Foundation

struct VibeSpaceHydrationTarget: Equatable {
    let projectID: UUID
    let includeVibeSpaceDefault: Bool
}

struct VibeSpaceHydrationPreparation: Equatable {
    let editorSessionState: EditorSessionState?
    let targets: [VibeSpaceHydrationTarget]
}

struct VibeSpaceStartupLaunchInstruction: Equatable {
    let terminalIndex: Int
    let command: String
    let tabName: String?
}

struct VibeSpaceStartupLaunchPlan: Equatable {
    let terminalCount: Int
    let launchInstructions: [VibeSpaceStartupLaunchInstruction]
}

@MainActor
struct VibeSpaceHydrationUseCase {
    func prepareHydration(
        for vibespaceID: UUID,
        vibespace: VibeSpaceState,
        layoutPersistence: LayoutPersistenceService
    ) -> VibeSpaceHydrationPreparation {
        layoutPersistence.loadVibeSpaceLayoutIfNeeded(for: vibespaceID)
        return VibeSpaceHydrationPreparation(
            editorSessionState: layoutPersistence.loadEditorSessionState(for: vibespaceID),
            targets: hydrationTargets(for: vibespace)
        )
    }

    func hydrationTargets(for vibespace: VibeSpaceState) -> [VibeSpaceHydrationTarget] {
        guard let focused = vibespace.focusedProject ?? vibespace.projects.first else { return [] }

        var targets = [
            VibeSpaceHydrationTarget(
                projectID: focused.id,
                includeVibeSpaceDefault: true
            )
        ]
        targets.append(
            contentsOf: vibespace.projects
                .filter { $0.id != focused.id }
                .map {
                    VibeSpaceHydrationTarget(
                        projectID: $0.id,
                        includeVibeSpaceDefault: true
                    )
                }
        )
        return targets
    }

    func startupLaunchPlan(
        for projectRootURL: URL,
        in vibespace: VibeSpaceState,
        includeVibeSpaceDefault: Bool
    ) -> VibeSpaceStartupLaunchPlan {
        let projectPath = projectRootURL.standardizedFileURL.path
        if let projectOverride = vibespace.startupOverride(for: projectPath)?.normalized() {
            return VibeSpaceStartupLaunchPlan(
                terminalCount: projectOverride.startupTerminalCount,
                launchInstructions: startupLaunchInstructions(from: projectOverride)
            )
        }

        guard includeVibeSpaceDefault else {
            return VibeSpaceStartupLaunchPlan(
                terminalCount: VibeSpaceStartupSettings.default.startupTerminalCount,
                launchInstructions: []
            )
        }

        let startupSettings = vibespace.startupSettings.normalized()
        return VibeSpaceStartupLaunchPlan(
            terminalCount: startupSettings.startupTerminalCount,
            launchInstructions: startupLaunchInstructions(from: startupSettings)
        )
    }

    private func startupLaunchInstructions(
        from startupOverride: VibeSpaceProjectStartupOverride
    ) -> [VibeSpaceStartupLaunchInstruction] {
        startupOverride.activeProfiles.enumerated().compactMap { index, profile in
            startupLaunchInstruction(from: profile, terminalIndex: index)
        }
    }

    private func startupLaunchInstructions(
        from startupSettings: VibeSpaceStartupSettings
    ) -> [VibeSpaceStartupLaunchInstruction] {
        startupSettings.activeProfiles.enumerated().compactMap { index, profile in
            startupLaunchInstruction(from: profile, terminalIndex: index)
        }
    }

    private func startupLaunchInstruction(
        from startupProfile: VibeSpaceTerminalStartupProfile,
        terminalIndex: Int
    ) -> VibeSpaceStartupLaunchInstruction? {
        if !startupProfile.command.isEmpty {
            return VibeSpaceStartupLaunchInstruction(
                terminalIndex: terminalIndex,
                command: startupProfile.command,
                tabName: nil
            )
        }
        guard let startupPreset = TerminalViewModel.preset(id: startupProfile.presetID) else {
            return nil
        }
        return VibeSpaceStartupLaunchInstruction(
            terminalIndex: terminalIndex,
            command: startupPreset.defaultCommand,
            tabName: startupPreset.shortLabel
        )
    }
}
