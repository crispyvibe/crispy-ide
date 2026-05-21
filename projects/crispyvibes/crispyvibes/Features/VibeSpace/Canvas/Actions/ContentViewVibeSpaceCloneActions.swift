import AppKit
import Foundation

extension ContentView {
    func presentCloneRepositorySheet() {
        vibespaceShell.presentCloneRepositorySheet()
        refreshCloneRepositoryProviderOptions()
    }

    func dismissCloneRepositorySheet() {
        vibespaceShell.dismissCloneRepositorySheet()
        vibespaceCloneRepositoryCoordinator.reset()
    }

    func chooseCloneRepositoryDestinationDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Destination"

        let currentDestinationPath = vibespaceCloneRepositoryCoordinator.state.destinationParentPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentDestinationPath.isEmpty {
            let currentDestinationURL = URL(fileURLWithPath: currentDestinationPath).standardizedFileURL
            if VibeSpaceState.isExistingDirectory(path: currentDestinationURL.path) {
                panel.directoryURL = currentDestinationURL
            }
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        vibespaceCloneRepositoryCoordinator.state.destinationParentPath = selectedURL.standardizedFileURL.path
    }

    func refreshCloneRepositoryProviderOptions() {
        vibespaceCloneRepositoryCoordinator.state.beginCheckingProviders(
            destinationParentPath: vibespaceCloneRepositoryCoordinator.state.destinationParentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? defaultCloneRepositoryParentDirectory().path
                : vibespaceCloneRepositoryCoordinator.state.destinationParentPath
        )
        loadCloneRepositoryProviderOptions()
    }

    func loadCloneRepositoryProviderOptions() {
        let requestID = vibespaceCloneRepositoryCoordinator.state.loadRequestID
        let worker = appContainer.makePaneWorker(pane: .explorer)

        Task { @MainActor in
            do {
                let payloadText = try await worker.execute(.gitHubCloneOptions, arguments: [:], timeout: 20)
                let payload = try decodeGitHubCloneOptionsPayload(from: payloadText)
                guard vibespaceShell.isCloneRepositorySheetPresented,
                      vibespaceCloneRepositoryCoordinator.state.loadRequestID == requestID else { return }
                vibespaceCloneRepositoryCoordinator.state.applyGitHubCloneOptions(payload)
            } catch {
                guard vibespaceShell.isCloneRepositorySheetPresented,
                      vibespaceCloneRepositoryCoordinator.state.loadRequestID == requestID else { return }
                vibespaceCloneRepositoryCoordinator.state.isLoadingProviderOptions = false
                vibespaceCloneRepositoryCoordinator.state.sourceMode = .manualURL
                vibespaceCloneRepositoryCoordinator.state.helperMessage = "Paste a repository URL to continue."
                vibespaceCloneRepositoryCoordinator.state.errorMessage = "Unable to load GitHub repositories: \(error.localizedDescription)"
            }
        }
    }

    func showCloneRepositoryURLMode() {
        vibespaceCloneRepositoryCoordinator.state.showManualURL()
    }

    func showCloneRepositoryGitHubMode() {
        vibespaceCloneRepositoryCoordinator.state.showGitHubPicker()
    }

    func cloneRepositoryIntoActiveVibeSpace() {
        guard let vibespaceID = activeVibeSpaceSession.vibespaceID else { return }

        let repositoryURL = vibespaceCloneRepositoryCoordinator.state.effectiveRepositoryURL
        guard !repositoryURL.isEmpty else {
            vibespaceCloneRepositoryCoordinator.state.errorMessage = "Select a repository to clone."
            return
        }

        let destinationParentPath = vibespaceCloneRepositoryCoordinator.state.destinationParentPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destinationParentPath.isEmpty else {
            vibespaceCloneRepositoryCoordinator.state.errorMessage = "Choose a destination folder."
            return
        }

        vibespaceCloneRepositoryCoordinator.state.beginSubmitting()
        let explicitDirectoryName = vibespaceCloneRepositoryCoordinator.state.trimmedDirectoryName
        let worker = appContainer.makePaneWorker(pane: .explorer)

        Task { @MainActor in
            do {
                let clonedPath = try await worker.execute(
                    .gitCloneRepository,
                    arguments: [
                        "repositoryURL": repositoryURL,
                        "destinationParentPath": destinationParentPath,
                        "directoryName": explicitDirectoryName
                    ],
                    timeout: 120
                )

                guard let clonedPath, !clonedPath.isEmpty else {
                    throw PaneWorkerError.invalidResponse
                }

                let clonedURL = URL(fileURLWithPath: clonedPath).standardizedFileURL
                var focusedProject: AnyProjectSession?
                mutateActiveVibeSpace { vibespace, _ in
                    focusedProject = vibespace.addProjects(from: [clonedURL])
                }
                if let focusedProject {
                    vibespaceCanvasActionsCoordinator.focusProject(focusedProject)
                }
                persistVibeSpaceCatalog()
                scheduleVibeSpaceTerminalHydration(for: vibespaceID)
                vibespaceSourceControlViewModel.updateVibeSpace(
                    projects: activeVibeSpaceSession.projects,
                    focusedProject: focusedProject,
                    selectedFileURL: activeVibeSpaceSession.sourceControlSelectedFileURL,
                    sourceControlSettings: activeVibeSpaceSession.vibespace?.sourceControlSettings ?? .default
                )
                dismissCloneRepositorySheet()
            } catch {
                vibespaceCloneRepositoryCoordinator.state.finishSubmitting(
                    errorMessage: "Clone failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func defaultCloneRepositoryParentDirectory() -> URL {
        if let focusedProject = activeVibeSpaceSession.focusedProject {
            return focusedProject.rootURL.deletingLastPathComponent().standardizedFileURL
        }
        if let firstProject = activeVibeSpaceSession.projects.first {
            return firstProject.rootURL.deletingLastPathComponent().standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    private func decodeGitHubCloneOptionsPayload(from payload: String?) throws -> WorkerGitHubCloneOptionsPayload {
        guard let payload,
              let data = payload.data(using: .utf8) else {
            return WorkerGitHubCloneOptionsPayload(
                cliAvailable: false,
                authenticated: false,
                repositories: [],
                message: "Paste a repository URL to continue."
            )
        }
        return try JSONDecoder().decode(WorkerGitHubCloneOptionsPayload.self, from: data)
    }
}
