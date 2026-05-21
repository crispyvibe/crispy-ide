import Foundation

@MainActor
struct HomeVibeSpaceCatalogUseCase {
    let container: AppContainer

    func loadVibeSpaceState(
        config: VibeSpaceConfigFile,
        projectConfigs: [String: ProjectConfigFile]
    ) async -> VibeSpaceState {
        let existingDirectoryPaths = await VibeSpaceState.existingDirectoryPaths(
            for: config.projectPaths + config.unresolvedProjectPaths
        )
        return container.makeVibeSpaceState(
            config: config,
            projectConfigs: projectConfigs,
            existingDirectoryPaths: existingDirectoryPaths
        )
    }

    func makeVibeSpace(
        named name: String,
        projectURLs: [URL]
    ) -> VibeSpaceState {
        container.makeVibeSpaceState(name: name, projectURLs: projectURLs)
    }

    func applyCreationResult(
        _ result: VibeSpaceCreationResult,
        to vibespace: inout VibeSpaceState
    ) {
        if let selection = result.cliSelection {
            let agentCommand = selection.resolvedStartupCommand
            if !agentCommand.isEmpty {
                vibespace.startupSettings.setProfile(
                    VibeSpaceTerminalStartupProfile(presetID: nil, command: agentCommand),
                    at: 0
                )
            }
        }

        for (path, projectSelection) in result.projectCLIOverrides {
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            let projectCommand = projectSelection.resolvedStartupCommand
            if !projectCommand.isEmpty {
                vibespace.setStartupOverride(
                    VibeSpaceProjectStartupOverride(
                        startupTerminalCount: 1,
                        startupProfiles: [
                            VibeSpaceTerminalStartupProfile(presetID: nil, command: projectCommand)
                        ]
                    ),
                    forProjectPath: normalizedPath
                )
            }
        }
    }
}
