import Combine
import Foundation

extension VibeSpaceSourceControlViewModel {
    func filteredObservedPaths(from changedPaths: Set<String>) -> Set<String> {
        let normalizedSettings = sourceControlSettings.normalized()
        let ignoredDirectoryNames = Set(normalizedSettings.ignoredDirectoryNames.map { $0.lowercased() })

        return changedPaths.reduce(into: Set<String>()) { result, changedPath in
            let normalizedPath = URL(fileURLWithPath: changedPath).standardizedFileURL.path
            guard !isObservedPathIgnored(
                normalizedPath,
                ignoredDirectoryNames: ignoredDirectoryNames
            ) else { return }
            result.insert(normalizedPath)
        }
    }

    func discoverRepositories(for projectReferences: [VibeSpaceSourceControlProjectReference]) async {
        do {
            let sourceControlSettingsJSON = try Self.encodeJSONText(sourceControlSettings)
            var discoveryResults: [(project: VibeSpaceSourceControlProjectReference, payload: WorkerGitRepositoryDiscoveryPayload)] = []
            var discoveryFailures: [VibeSpaceSourceControlDiscoveryFailure] = []

            for project in projectReferences {
                let payload: WorkerGitRepositoryDiscoveryPayload
                do {
                    if let gitExplorer = project.gitExplorer {
                        payload = try await gitExplorer.discoverRepositories(at: project.rootURL.path)
                    } else if project.usesProjectGitBackend {
                        payload = WorkerGitRepositoryDiscoveryPayload(
                            gitAvailable: true,
                            repositories: [],
                            message: nil
                        )
                    } else {
                        let payloadText = try await worker.execute(
                            .gitDiscoverRepositories,
                            arguments: [
                                "rootPath": project.rootURL.path,
                                "sourceControlSettings": sourceControlSettingsJSON
                            ],
                            timeout: 12
                        )
                        payload = try Self.decodeGitRepositoryDiscoveryPayload(from: payloadText)
                    }

                    if payload.gitAvailable {
                        discoveryResults.append((project, payload))
                    } else {
                        discoveryFailures.append(
                            VibeSpaceSourceControlDiscoveryFailure(
                                kind: .gitUnavailable,
                                projectTitle: project.title,
                                message: payload.message
                            )
                        )
                    }
                } catch {
                    discoveryFailures.append(
                        VibeSpaceSourceControlDiscoveryFailure(
                            kind: .error,
                            projectTitle: project.title,
                            message: error.localizedDescription
                        )
                    )
                }

                guard !Task.isCancelled else { return }
                applyDiscoveryProgress(
                    discoveryResults: discoveryResults,
                    discoveryFailures: discoveryFailures,
                    discoveryCompleted: false
                )
            }

            guard !Task.isCancelled else { return }
            applyDiscoveryProgress(
                discoveryResults: discoveryResults,
                discoveryFailures: discoveryFailures,
                discoveryCompleted: true
            )
        } catch {
            guard !Task.isCancelled else { return }
            repositories = []
            discoveredRepositoryRootPaths = []
            state = .error
            message = "Unable to discover repositories: \(error.localizedDescription)"
            presentationMessage = nil
        }
    }

    func applyDiscoveryProgress(
        discoveryResults: [(project: VibeSpaceSourceControlProjectReference, payload: WorkerGitRepositoryDiscoveryPayload)],
        discoveryFailures: [VibeSpaceSourceControlDiscoveryFailure],
        discoveryCompleted: Bool
    ) {
        if discoveryResults.isEmpty, discoveryCompleted, let primaryFailure = discoveryFailures.first {
            repositories = []
            discoveredRepositoryRootPaths = []
            state = primaryFailure.kind == .gitUnavailable ? .gitUnavailable : .error
            message = primaryFailure.displayMessage
            presentationMessage = nil
            return
        }

        let discoveredRepositories = discoveryResults.flatMap { result in
            result.payload.repositories.map { repository in
                (project: result.project, repositoryRootURL: URL(fileURLWithPath: repository.repositoryRootPath).standardizedFileURL)
            }
        }
        let uniqueRepositories = Dictionary(
            discoveredRepositories.map { entry in
                (entry.project.repositoryIdentifier(for: entry.repositoryRootURL), entry)
            },
            uniquingKeysWith: { existing, _ in existing }
        )
        let sortedRepositories = uniqueRepositories.values.sorted { lhs, rhs in
            let lhsSortKey = repositorySortKey(for: lhs.repositoryRootURL.path)
            let rhsSortKey = repositorySortKey(for: rhs.repositoryRootURL.path)
            if lhsSortKey != rhsSortKey {
                return lhsSortKey < rhsSortKey
            }
            return lhs.repositoryRootURL.path.localizedCaseInsensitiveCompare(rhs.repositoryRootURL.path) == .orderedAscending
        }
        let presentedRepositories = Array(
            sortedRepositories.prefix(sourceControlSettings.autoPresentedRepositoryLimit)
        )
        let existingRepositoriesByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
        let nextRepositories = presentedRepositories.map { entry in
            let repositoryID = entry.project.repositoryIdentifier(for: entry.repositoryRootURL)
            return existingRepositoriesByID[repositoryID]
                ?? VibeSpaceSourceControlRepositoryViewModel(
                    id: repositoryID,
                    repositoryRootURL: entry.repositoryRootURL,
                    worker: mutationWorker,
                    gitExplorer: entry.project.usesProjectGitBackend ? entry.project.gitExplorer : nil
                )
        }

        if discoveryCompleted || !sortedRepositories.isEmpty || repositories.isEmpty {
            discoveredRepositoryRootPaths = sortedRepositories.map(\.repositoryRootURL.path)
            repositories = nextRepositories
            applyProjectContextAndOrdering()
            bindRepositoryChanges()
        }

        let newRepositoriesToRefresh = nextRepositories.filter { existingRepositoriesByID[$0.id] == nil }
        activeInitialRefreshTasks = newRepositoriesToRefresh.map { repository in
            Task {
                await repository.refresh()
            }
        }

        if !sortedRepositories.isEmpty {
            state = .ready
        } else if discoveryCompleted {
            state = .ready
        } else if repositories.isEmpty {
            state = .loading
        }

        message = discoveryFailures.isEmpty ? nil : discoveryFailures.map(\.displayMessage).joined(separator: "\n")
        presentationMessage = makePresentationMessage(
            visibleRepositoryCount: nextRepositories.count,
            discoveredRepositoryCount: sortedRepositories.count
        )
    }

    struct VibeSpaceSourceControlDiscoveryFailure {
        enum Kind {
            case gitUnavailable
            case error
        }

        let kind: Kind
        let projectTitle: String
        let message: String?

        var displayMessage: String {
            let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = (trimmedMessage?.isEmpty == false ? trimmedMessage : nil)
            switch kind {
            case .gitUnavailable:
                return detail.map { "Git unavailable for \(projectTitle): \($0)" }
                    ?? "Git unavailable for \(projectTitle)."
            case .error:
                return detail.map { "Unable to discover repositories for \(projectTitle): \($0)" }
                    ?? "Unable to discover repositories for \(projectTitle)."
            }
        }
    }

    func applyProjectContextAndOrdering() {
        repositories.forEach { repository in
            repository.configure(attachedProjects: attachedProjects(for: repository.repositoryRootURL))
        }

        repositories = repositories.sorted { lhs, rhs in
            let lhsSortKey = repositorySortKey(for: lhs)
            let rhsSortKey = repositorySortKey(for: rhs)
            if lhsSortKey != rhsSortKey {
                return lhsSortKey < rhsSortKey
            }
            return lhs.repositoryRootURL.path.localizedCaseInsensitiveCompare(rhs.repositoryRootURL.path) == .orderedAscending
        }
    }

    func attachedProjects(for repositoryRootURL: URL) -> [VibeSpaceSourceControlProjectReference] {
        let repositoryRootPath = repositoryRootURL.standardizedFileURL.path
        return projectReferences.filter { project in
            let projectPath = project.rootURL.path
            return containsPath(repositoryRootPath, candidatePath: projectPath)
                || containsPath(projectPath, candidatePath: repositoryRootPath)
        }
    }

    func bindRepositoryChanges() {
        repositoryChangeCancellables.removeAll()
        repositories.forEach { repository in
            repository.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &repositoryChangeCancellables)
        }
    }

    func bindProjectWatchersIfNeeded(for projects: [AnyProjectSession]) {
        let projectIDs = projects.map(\.id)
        guard projectIDs != observedProjectIDs else { return }

        observedProjectIDs = projectIDs
        projectWatcherCancellables.removeAll()
        let retainedWatchers = Set(projectIDs)
        for (projectID, watcher) in localProjectWatchers where !retainedWatchers.contains(projectID) {
            watcher.invalidate()
            localProjectWatchers.removeValue(forKey: projectID)
        }

        projects.forEach { project in
            if project.metadata.hostLabel == nil {
                let watcher = localProjectWatchers[project.id] ?? DirectoryWatcher(maxWatchedPaths: 1)
                watcher.setOnChange { [weak self] changedPath in
                    Task { @MainActor [weak self] in
                        self?.refreshRepositories(affectedBy: [changedPath])
                    }
                }
                watcher.updateWatchedPaths([project.rootURL.standardizedFileURL.path])
                localProjectWatchers[project.id] = watcher
            } else {
                project.folderExplorer.observedFileSystemChanges
                    .receive(on: RunLoop.main)
                    .sink { [weak self] changedPaths in
                        self?.refreshRepositories(affectedBy: changedPaths)
                    }
                    .store(in: &projectWatcherCancellables)
            }
        }
    }

    func consumeObservedRefreshQueue() {
        pendingObservedRefreshTask = nil
        let changedPaths = pendingObservedPaths
        pendingObservedPaths.removeAll()

        guard state == .ready, !repositories.isEmpty else { return }
        guard !changedPaths.isEmpty else { return }

        var affectedRepositoryIDs = Set<String>()

        for changedPath in changedPaths {
            let normalizedPath = URL(fileURLWithPath: changedPath).standardizedFileURL.path

            if let repository = repositoryOwningPath(normalizedPath) {
                affectedRepositoryIDs.insert(repository.id)
                continue
            }

            if projectReferences.contains(where: { project in
                containsPath(project.rootURL.path, candidatePath: normalizedPath)
                    || containsPath(normalizedPath, candidatePath: project.rootURL.path)
            }) {
                refresh()
                return
            }
        }

        guard !affectedRepositoryIDs.isEmpty else { return }

        activeObservedRefreshTask?.cancel()
        let repositoriesToRefresh = repositories.filter { affectedRepositoryIDs.contains($0.id) }
        activeObservedRefreshTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for repository in repositoriesToRefresh {
                    group.addTask {
                        guard !Task.isCancelled else { return }
                        await repository.refresh()
                    }
                }
            }
            _ = self // prevent unused capture warning
        }
    }

    func repositoryOwningPath(_ path: String) -> VibeSpaceSourceControlRepositoryViewModel? {
        repositories
            .filter { $0.containsPath(path) }
            .max { lhs, rhs in
                lhs.repositoryRootURL.path.count < rhs.repositoryRootURL.path.count
            }
    }

    func repositorySortKey(for repositoryRootPath: String) -> (Int, Int, Int, Int, String) {
        let repositoryRootURL = URL(fileURLWithPath: repositoryRootPath)
        let attachedProjects = attachedProjects(for: repositoryRootURL)
        return repositorySortKey(
            repositoryRootPath: repositoryRootPath,
            attachedProjects: attachedProjects,
            containsSelectedFile: containsSelectedFile(inRepositoryRootPath: repositoryRootPath)
        )
    }

    func repositorySortKey(for repository: VibeSpaceSourceControlRepositoryViewModel) -> (Int, Int, Int, Int, String) {
        repositorySortKey(
            repositoryRootPath: repository.repositoryRootURL.path,
            attachedProjects: repository.attachedProjects,
            containsSelectedFile: containsSelectedFile(in: repository)
        )
    }

    func repositorySortKey(
        repositoryRootPath: String,
        attachedProjects: [VibeSpaceSourceControlProjectReference],
        containsSelectedFile: Bool
    ) -> (Int, Int, Int, Int, String) {
        let selectedFilePriority = containsSelectedFile ? 0 : 1
        let selectedFileSpecificity = selectedFilePriority == 0 ? -repositoryRootPath.count : 0
        let focusedProjectPriority = containsFocusedProject(in: attachedProjects) ? 0 : 1
        let firstAttachedProjectOrder = attachedProjects.map(\.orderIndex).min() ?? Int.max
        return (
            selectedFilePriority,
            selectedFileSpecificity,
            focusedProjectPriority,
            firstAttachedProjectOrder,
            repositoryRootPath
        )
    }

    func containsSelectedFile(in repository: VibeSpaceSourceControlRepositoryViewModel) -> Bool {
        guard let selectedFilePath = selectedFileURL?.path else {
            return false
        }
        return repository.containsPath(selectedFilePath)
    }

    func containsSelectedFile(inRepositoryRootPath repositoryRootPath: String) -> Bool {
        guard let selectedFilePath = selectedFileURL?.path else {
            return false
        }
        return containsPath(repositoryRootPath, candidatePath: selectedFilePath)
    }

    func containsFocusedProject(
        in attachedProjects: [VibeSpaceSourceControlProjectReference]
    ) -> Bool {
        guard let focusedProjectPath else {
            return false
        }
        return attachedProjects.contains(where: { $0.rootURL.path == focusedProjectPath })
    }

    func containsPath(_ rootPath: String, candidatePath: String) -> Bool {
        if rootPath == candidatePath {
            return true
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidatePath.hasPrefix(prefix)
    }

    func isObservedPathIgnored(
        _ path: String,
        ignoredDirectoryNames: Set<String>
    ) -> Bool {
        for project in projectReferences where containsPath(project.rootURL.path, candidatePath: path) {
            if isPath(path, ignoredWithinRootPath: project.rootURL.path, ignoredDirectoryNames: ignoredDirectoryNames) {
                return true
            }
        }

        for repository in repositories where repository.containsPath(path) {
            if isPath(
                path,
                ignoredWithinRootPath: repository.repositoryRootURL.path,
                ignoredDirectoryNames: ignoredDirectoryNames
            ) {
                return true
            }
        }

        return false
    }

    func isPath(
        _ path: String,
        ignoredWithinRootPath rootPath: String,
        ignoredDirectoryNames: Set<String>
    ) -> Bool {
        guard path != rootPath else { return false }

        let rootComponents = URL(fileURLWithPath: rootPath).standardizedFileURL.pathComponents
        let pathComponents = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard pathComponents.count > rootComponents.count else { return false }

        let relativeComponents = Array(pathComponents.dropFirst(rootComponents.count))
        if isGitInternalObservedPath(relativeComponents) {
            return true
        }

        return relativeComponents.contains { component in
            component != ".git" && ignoredDirectoryNames.contains(component.lowercased())
        }
    }

    func isGitInternalObservedPath(_ relativeComponents: [String]) -> Bool {
        guard relativeComponents.first == ".git" else { return false }

        guard relativeComponents.count > 1 else { return true }

        let gitRelativeComponents = Array(relativeComponents.dropFirst())
        let allowedLeadingComponents: Set<String> = [
            "HEAD",
            "FETCH_HEAD",
            "ORIG_HEAD",
            "config",
            "packed-refs",
            "refs"
        ]

        guard let leadingComponent = gitRelativeComponents.first else {
            return true
        }

        return !allowedLeadingComponents.contains(leadingComponent)
    }

    nonisolated static func decodeGitRepositoryDiscoveryPayload(
        from payload: String?
    ) throws -> WorkerGitRepositoryDiscoveryPayload {
        guard let payload,
              let data = payload.data(using: .utf8) else {
            return WorkerGitRepositoryDiscoveryPayload(gitAvailable: true, repositories: [], message: nil)
        }
        return try JSONDecoder().decode(WorkerGitRepositoryDiscoveryPayload.self, from: data)
    }

    nonisolated static func decodeGitRepositoryDiscoveryBatchPayload(
        from payload: String?
    ) throws -> WorkerGitRepositoryDiscoveryBatchPayload {
        guard let payload,
              let data = payload.data(using: .utf8) else {
            return WorkerGitRepositoryDiscoveryBatchPayload(results: [])
        }
        return try JSONDecoder().decode(WorkerGitRepositoryDiscoveryBatchPayload.self, from: data)
    }

    nonisolated static func encodeJSONText<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw PaneWorkerError.invalidResponse
        }
        return text
    }

    func makePresentationMessage(
        visibleRepositoryCount: Int,
        discoveredRepositoryCount: Int
    ) -> String? {
        guard discoveredRepositoryCount > visibleRepositoryCount else { return nil }
        return "Showing \(visibleRepositoryCount) of \(discoveredRepositoryCount) repositories to preserve responsiveness. Adjust Source Control settings to change the limit or ignored folders."
    }
}
