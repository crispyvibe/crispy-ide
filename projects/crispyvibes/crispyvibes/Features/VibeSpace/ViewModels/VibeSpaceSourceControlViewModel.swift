import Combine
import Foundation

@MainActor
final class VibeSpaceSourceControlViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case gitUnavailable
        case error
    }

    @Published var repositories: [VibeSpaceSourceControlRepositoryViewModel] = []
    @Published var state: State = .idle
    @Published var message: String?
    @Published var presentationMessage: String?

    let worker: any PaneWorkerExecuting
    let mutationWorker: any PaneWorkerExecuting
    let workerFactory: PaneWorkerFactory
    var projectReferences: [VibeSpaceSourceControlProjectReference] = []
    var focusedProjectPath: String?
    var selectedFileURL: URL?
    var sourceControlSettings: VibeSpaceSourceControlSettings = .default
    var discoveredRepositoryRootPaths: [String] = []
    var refreshTask: Task<Void, Never>?
    var repositoryChangeCancellables = Set<AnyCancellable>()
    var projectWatcherCancellables = Set<AnyCancellable>()
    var appEventCancellables = Set<AnyCancellable>()
    var observedProjectIDs: [UUID] = []
    var localProjectWatchers: [UUID: DirectoryWatcher] = [:]
    var pendingObservedPaths: Set<String> = []
    var pendingObservedRefreshTask: Task<Void, Never>?
    var activeObservedRefreshTask: Task<Void, Never>?
    var activeInitialRefreshTasks: [Task<Void, Never>] = []

    init(workerFactory: @escaping PaneWorkerFactory) {
        self.workerFactory = workerFactory
        self.worker = workerFactory(.sourceControl)
        self.mutationWorker = workerFactory(.sourceControl)
        NotificationCenter.default.publisher(for: .vibespaceFileDidSave)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                guard let fileURL = notification.object as? URL else { return }
                self.refreshRepositories(affectedBy: [fileURL.standardizedFileURL.path])
            }
            .store(in: &appEventCancellables)
    }

    var repositoryCount: Int {
        discoveredRepositoryRootPaths.count
    }

    var visibleRepositoryCount: Int {
        repositories.count
    }

    var hiddenRepositoryCount: Int {
        max(0, repositoryCount - visibleRepositoryCount)
    }

    var isRepositoryPresentationLimited: Bool {
        hiddenRepositoryCount > 0
    }

    var totalPendingChangeCount: Int {
        repositories.reduce(0) { partialResult, repository in
            partialResult + repository.pendingChangeCount
        }
    }

    func updateVibeSpace(
        projects: [AnyProjectSession],
        focusedProject: AnyProjectSession?,
        selectedFileURL: URL?,
        sourceControlSettings: VibeSpaceSourceControlSettings = .default
    ) {
        bindProjectWatchersIfNeeded(for: projects)

        let nextProjectReferences = projects.enumerated().map { index, project in
            VibeSpaceSourceControlProjectReference(
                rootURL: project.rootURL.standardizedFileURL,
                title: project.title,
                orderIndex: index,
                projectIdentifier: project.projectIdentifier,
                usesProjectGitBackend: project.metadata.hostLabel != nil,
                gitExplorer: project.metadata.hostLabel != nil ? project.gitExplorer : nil
            )
        }
        let projectPathsChanged = nextProjectReferences.map(\.rootURL.path) != projectReferences.map(\.rootURL.path)
        let sourceControlSettingsChanged = sourceControlSettings != self.sourceControlSettings

        projectReferences = nextProjectReferences
        focusedProjectPath = focusedProject?.rootURL.standardizedFileURL.path
        self.selectedFileURL = selectedFileURL?.standardizedFileURL
        self.sourceControlSettings = sourceControlSettings

        if projectPathsChanged || sourceControlSettingsChanged {
            refresh()
        } else {
            applyProjectContextAndOrdering()
        }
    }

    func refresh() {
        refreshTask?.cancel()
        pendingObservedRefreshTask?.cancel()
        pendingObservedRefreshTask = nil
        activeObservedRefreshTask?.cancel()
        activeObservedRefreshTask = nil
        activeInitialRefreshTasks.forEach { $0.cancel() }
        activeInitialRefreshTasks.removeAll()
        pendingObservedPaths.removeAll()

        guard !projectReferences.isEmpty else {
            repositories = []
            discoveredRepositoryRootPaths = []
            state = .idle
            message = nil
            presentationMessage = nil
            return
        }

        if repositories.isEmpty {
            state = .loading
        }

        let projectReferences = self.projectReferences
        refreshTask = Task { [weak self] in
            await self?.discoverRepositories(for: projectReferences)
        }
    }

    func refreshRepositories(affectedBy changedPaths: Set<String>) {
        let filteredPaths = filteredObservedPaths(from: changedPaths)
        guard !filteredPaths.isEmpty else { return }

        pendingObservedRefreshTask?.cancel()
        pendingObservedPaths.formUnion(filteredPaths)

        pendingObservedRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.consumeObservedRefreshQueue()
        }
    }

    deinit {
        refreshTask?.cancel()
        pendingObservedRefreshTask?.cancel()
        activeObservedRefreshTask?.cancel()
        activeInitialRefreshTasks.forEach { $0.cancel() }
        localProjectWatchers.values.forEach { $0.invalidate() }
    }
}
