import Foundation

enum VibeSpaceCloneRepositorySourceMode {
    case checkingProviders
    case githubPicker
    case manualURL
}

struct VibeSpaceCloneRepositorySheetState {
    var sourceMode: VibeSpaceCloneRepositorySourceMode = .checkingProviders
    var githubCLIAvailable = false
    var githubAuthenticated = false
    var githubRepositories: [WorkerGitHubRepositoryNode] = []
    var selectedGitHubRepositoryID: WorkerGitHubRepositoryNode.ID?
    var repositorySearchQuery = ""
    var repositoryURL = ""
    var destinationParentPath = ""
    var directoryName = ""
    var isSubmitting = false
    var isLoadingProviderOptions = false
    var isShowingAdvancedOptions = false
    var helperMessage: String?
    var errorMessage: String?
    var loadRequestID = UUID()

    var trimmedRepositoryURL: String {
        repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDirectoryName: String {
        directoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var filteredGitHubRepositories: [WorkerGitHubRepositoryNode] {
        let query = repositorySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return githubRepositories }

        return githubRepositories.filter { repository in
            repository.nameWithOwner.localizedCaseInsensitiveContains(query) ||
            (repository.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var selectedGitHubRepository: WorkerGitHubRepositoryNode? {
        githubRepositories.first { $0.id == selectedGitHubRepositoryID }
    }

    var effectiveRepositoryURL: String {
        switch sourceMode {
        case .githubPicker:
            return selectedGitHubRepository?.cloneURL ?? ""
        case .checkingProviders, .manualURL:
            return trimmedRepositoryURL
        }
    }

    var canSubmit: Bool {
        !effectiveRepositoryURL.isEmpty &&
        !destinationParentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSubmitting &&
        !isLoadingProviderOptions
    }

    mutating func beginCheckingProviders(destinationParentPath: String) {
        sourceMode = .checkingProviders
        githubCLIAvailable = false
        githubAuthenticated = false
        githubRepositories = []
        selectedGitHubRepositoryID = nil
        repositorySearchQuery = ""
        repositoryURL = ""
        directoryName = ""
        isSubmitting = false
        isLoadingProviderOptions = true
        isShowingAdvancedOptions = false
        helperMessage = "Checking GitHub access…"
        errorMessage = nil
        self.destinationParentPath = destinationParentPath
        loadRequestID = UUID()
    }

    mutating func applyGitHubCloneOptions(_ payload: WorkerGitHubCloneOptionsPayload) {
        githubCLIAvailable = payload.cliAvailable
        githubAuthenticated = payload.authenticated
        githubRepositories = payload.repositories
        selectedGitHubRepositoryID = payload.repositories.first?.id
        helperMessage = payload.message
        errorMessage = nil
        isLoadingProviderOptions = false
        sourceMode = payload.authenticated ? .githubPicker : .manualURL
    }

    mutating func showManualURL() {
        sourceMode = .manualURL
        errorMessage = nil
    }

    mutating func showGitHubPicker() {
        guard githubAuthenticated else { return }
        sourceMode = .githubPicker
        errorMessage = nil
    }

    mutating func beginSubmitting() {
        isSubmitting = true
        errorMessage = nil
    }

    mutating func finishSubmitting(errorMessage: String? = nil) {
        isSubmitting = false
        self.errorMessage = errorMessage
    }
}

@MainActor
final class VibeSpaceCloneRepositoryCoordinator: ObservableObject {
    @Published var state = VibeSpaceCloneRepositorySheetState()

    func reset() {
        state = VibeSpaceCloneRepositorySheetState()
    }
}
