import Foundation

@MainActor
extension VibeSpaceState {
    func availabilityReconciliationPaths() -> [String] {
        let candidatePaths = unresolvedProjectPaths + projects.map { $0.projectIdentifier }
        return candidatePaths.reduce(into: (ordered: [String](), seen: Set<String>())) { state, rawPath in
            let normalizedPath = Self.normalizedPath(from: rawPath)
            guard state.seen.insert(normalizedPath).inserted else { return }
            state.ordered.append(normalizedPath)
        }.ordered
    }

    mutating func addProjects(from urls: [URL]) -> AnyProjectSession? {
        var addedOrMatched: AnyProjectSession?
        var seenPaths = Set(projects.map { $0.projectIdentifier } + unresolvedProjectPaths)

        for url in urls {
            let normalized = url.standardizedFileURL

            if let existing = projects.first(where: { $0.projectIdentifier == normalized.path }) {
                addedOrMatched = existing
                continue
            }

            guard seenPaths.insert(normalized.path).inserted else { continue }
            unresolvedProjectPaths.removeAll(where: { $0 == normalized.path })

            if Self.isExistingDirectory(path: normalized.path) {
                let session = makeProjectSession(rootURL: normalized)
                projects.append(session)
                assignAutoColorTagIfNeeded(forPath: normalized.path)
                addedOrMatched = session
            } else {
                unresolvedProjectPaths.append(normalized.path)
                assignAutoColorTagIfNeeded(forPath: normalized.path)
            }
        }

        if focusedProjectID == nil {
            focusedProjectID = projects.first?.id
        }

        storedProjectPaths = projects.map(\.projectIdentifier) + unresolvedProjectPaths
        storedFocusedProjectPath = focusedProject?.projectIdentifier
        pruneColorTags()
        return addedOrMatched
    }

    mutating func removeProject(id: UUID) {
        guard let removingIndex = projects.firstIndex(where: { $0.id == id }) else { return }
        let removing = projects.remove(at: removingIndex)
        removing.shutdown()
        removeProjectAssociatedState(for: removing.projectIdentifier)
        if focusedProjectID == id {
            focusedProjectID = projects.last?.id
        }
        storedProjectPaths = projects.map(\.projectIdentifier) + unresolvedProjectPaths
        storedFocusedProjectPath = focusedProject?.projectIdentifier
        normalizeProjectShortcuts()
    }

    mutating func moveProjects(fromOffsets sourceOffsets: IndexSet, toOffset destinationOffset: Int) {
        guard !sourceOffsets.isEmpty else { return }

        let orderedOffsets = sourceOffsets.sorted()
        let movingProjects = orderedOffsets.map { projects[$0] }

        for offset in orderedOffsets.reversed() {
            projects.remove(at: offset)
        }

        let removedBeforeDestination = orderedOffsets.filter { $0 < destinationOffset }.count
        let adjustedDestination = max(0, min(destinationOffset - removedBeforeDestination, projects.count))
        projects.insert(contentsOf: movingProjects, at: adjustedDestination)
        reindexProjectShortcutsByProjectOrder()
    }

    mutating func removeUnresolvedProject(path: String) {
        let normalized = Self.normalizedPath(from: path)
        unresolvedProjectPaths.removeAll(where: { $0 == normalized })
        removeProjectAssociatedState(for: normalized)
        pruneColorTags()
    }

    mutating func relinkUnresolvedProject(path: String, to replacementURL: URL) -> AnyProjectSession? {
        let normalizedMissingPath = Self.normalizedPath(from: path)
        guard let unresolvedIndex = unresolvedProjectPaths.firstIndex(of: normalizedMissingPath) else {
            return nil
        }

        let replacementPath = replacementURL.standardizedFileURL.path

        if replacementPath == normalizedMissingPath {
            if Self.isExistingDirectory(path: replacementPath) {
                let recovered = makeProjectSession(rootURL: URL(fileURLWithPath: replacementPath))
                projects.append(recovered)
                unresolvedProjectPaths.remove(at: unresolvedIndex)
                assignAutoColorTagIfNeeded(forPath: replacementPath)
                if focusedProjectID == nil {
                    focusedProjectID = recovered.id
                }
                pruneColorTags()
                return recovered
            }
            return nil
        }

        if let existingProject = projects.first(where: { $0.projectIdentifier == replacementPath }) {
            moveProjectAssociatedState(
                from: normalizedMissingPath,
                to: replacementPath,
                onlyIfDestinationMissing: true
            )
            unresolvedProjectPaths.remove(at: unresolvedIndex)
            removeProjectAssociatedState(for: normalizedMissingPath)
            pruneColorTags()
            return existingProject
        }

        if let duplicateUnresolvedIndex = unresolvedProjectPaths.firstIndex(of: replacementPath) {
            moveProjectAssociatedState(
                from: normalizedMissingPath,
                to: replacementPath,
                onlyIfDestinationMissing: true,
                includeShortcut: false
            )
            unresolvedProjectPaths.remove(at: max(unresolvedIndex, duplicateUnresolvedIndex))
            unresolvedProjectPaths.remove(at: min(unresolvedIndex, duplicateUnresolvedIndex))
            removeProjectAssociatedState(for: normalizedMissingPath)
            pruneColorTags()
            return nil
        }

        guard Self.isExistingDirectory(path: replacementPath) else {
            unresolvedProjectPaths[unresolvedIndex] = replacementPath
            moveProjectAssociatedState(
                from: normalizedMissingPath,
                to: replacementPath,
                onlyIfDestinationMissing: false
            )
            removeProjectAssociatedState(for: normalizedMissingPath)
            assignAutoColorTagIfNeeded(forPath: replacementPath)
            pruneColorTags()
            return nil
        }

        let recovered = makeProjectSession(rootURL: replacementURL.standardizedFileURL)
        projects.append(recovered)
        unresolvedProjectPaths.remove(at: unresolvedIndex)
        moveProjectAssociatedState(
            from: normalizedMissingPath,
            to: replacementPath,
            onlyIfDestinationMissing: true
        )
        removeProjectAssociatedState(for: normalizedMissingPath)
        assignAutoColorTagIfNeeded(forPath: replacementPath)
        if focusedProjectID == nil {
            focusedProjectID = recovered.id
        }
        pruneColorTags()
        return recovered
    }

    mutating func rename(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        name = trimmed
    }

    mutating func reconcileProjectAvailability(using existingDirectoryPaths: Set<String>) {
        var recoveredPaths: [String] = []
        var stillUnresolved: [String] = []

        for path in unresolvedProjectPaths {
            if existingDirectoryPaths.contains(path) {
                recoveredPaths.append(path)
            } else {
                stillUnresolved.append(path)
            }
        }

        unresolvedProjectPaths = stillUnresolved

        let liveProjects = projects
        projects.removeAll()
        for project in liveProjects {
            let normalizedPath = project.projectIdentifier
            if existingDirectoryPaths.contains(normalizedPath) {
                projects.append(project)
            } else {
                project.shutdown()
                if !unresolvedProjectPaths.contains(normalizedPath) {
                    unresolvedProjectPaths.append(normalizedPath)
                }
            }
        }

        if !recoveredPaths.isEmpty {
            let recoveredURLs = recoveredPaths.map { URL(fileURLWithPath: $0) }
            _ = addProjects(from: recoveredURLs)
        }

        if let focusedProjectID,
           !projects.contains(where: { $0.id == focusedProjectID }) {
            self.focusedProjectID = projects.first?.id
        }

        pruneColorTags()
    }

    mutating func reconcileProjectAvailability() {
        let existingDirectoryPaths = Set(
            availabilityReconciliationPaths().filter { path in
                Self.isExistingDirectory(path: path)
            }
        )
        reconcileProjectAvailability(using: existingDirectoryPaths)
    }

    mutating func reconcileProjectAvailabilityAsync() async {
        let existingDirectoryPaths = await Self.existingDirectoryPaths(
            for: availabilityReconciliationPaths()
        )
        reconcileProjectAvailability(using: existingDirectoryPaths)
    }
}
