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

            // F021-R09: if the path is parked, activate (unpark) it instead of
            // treating it as a duplicate-skip or creating a separate entry.
            if parkedProjectPaths.contains(normalized.path) {
                if let unparked = unparkProject(path: normalized.path) {
                    addedOrMatched = unparked
                }
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

    /// F021-R10 Park Lifecycle.
    ///
    /// Parks the project with the given session ID:
    /// - shuts down the live `ProjectSession` (terminates terminals, file watchers, etc.)
    /// - removes the session from `projects`
    /// - appends the project's normalized path to `parkedProjectPaths`
    /// - if the project was focused, focus falls back to the last remaining live project
    ///
    /// Per-project state (color tag, shortcuts, overrides) is preserved — parked
    /// projects retain their `ProjectConfigFile` for restoration via `unparkProject`.
    /// Browser cleanup and snapshot capture are handled by the calling coordinator
    /// (Phase 3) before invoking this method.
    ///
    /// - Returns: the normalized project path that was parked, or `nil` if no live
    ///   session matched the given id.
    @discardableResult
    mutating func parkProject(id: UUID) -> String? {
        guard let removingIndex = projects.firstIndex(where: { $0.id == id }) else { return nil }
        let parking = projects.remove(at: removingIndex)
        let parkedPath = parking.projectIdentifier
        parking.shutdown()

        if !parkedProjectPaths.contains(parkedPath) {
            parkedProjectPaths.append(parkedPath)
        }

        if focusedProjectID == id {
            focusedProjectID = projects.last?.id
        }
        storedProjectPaths = projects.map(\.projectIdentifier) + unresolvedProjectPaths
        storedFocusedProjectPath = focusedProject?.projectIdentifier
        return parkedPath
    }

    /// F021-R11 Unpark Restoration.
    ///
    /// Activates a parked project at the given normalized path:
    /// - removes the path from `parkedProjectPaths`
    /// - creates a fresh `ProjectSession` via the session factory
    /// - appends the new session to `projects`
    /// - sets the new session as focused
    ///
    /// The new session activates lazily — the existing `ProjectSession` activation
    /// flow (`activateIfNeeded` → `restoreLocalSessionState`) reads the persisted
    /// `terminalEntries` from `ProjectConfigFile`, so terminals are recreated from
    /// the saved snapshot. Browser restoration is handled by the calling coordinator
    /// using `browserSessionEntries` (Phase 3).
    ///
    /// - Returns: the new live session, or `nil` if the path is not parked or the
    ///   directory no longer exists on disk.
    @discardableResult
    mutating func unparkProject(path: String) -> AnyProjectSession? {
        let normalized = Self.normalizedPath(from: path)
        guard let parkIndex = parkedProjectPaths.firstIndex(of: normalized) else { return nil }

        // For local paths, verify the directory still exists. SSH paths bypass the check.
        let isRemote = normalized.hasPrefix("ssh://")
        if !isRemote, !Self.isExistingDirectory(path: normalized) {
            return nil
        }

        parkedProjectPaths.remove(at: parkIndex)

        let session: AnyProjectSession
        if isRemote, let remoteSession = makeIdentifierSession(identifier: normalized) {
            session = remoteSession
        } else {
            session = makeProjectSession(rootURL: URL(fileURLWithPath: normalized))
        }
        projects.append(session)
        focusedProjectID = session.id
        storedProjectPaths = projects.map(\.projectIdentifier) + unresolvedProjectPaths
        storedFocusedProjectPath = session.projectIdentifier
        return session
    }

    /// True if the given normalized path is currently parked.
    func isProjectParked(path: String) -> Bool {
        parkedProjectPaths.contains(Self.normalizedPath(from: path))
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

    /// F021-R19 Remove Parked Project.
    ///
    /// Drops a parked project at the given normalized path from
    /// `parkedProjectPaths` and clears its associated per-project state,
    /// without activating it. Mirrors `removeUnresolvedProject` for the
    /// parked collection. No-op if the path is not parked.
    mutating func removeParkedProject(path: String) {
        let normalized = Self.normalizedPath(from: path)
        parkedProjectPaths.removeAll(where: { $0 == normalized })
        removeProjectAssociatedState(for: normalized)
        storedProjectPaths = projects.map(\.projectIdentifier) + unresolvedProjectPaths
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
