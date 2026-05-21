import Foundation

@MainActor
struct VibeSpaceProjectRoutingUseCase {
    func projectForShortcut(index: Int, in vibespace: VibeSpaceState) -> AnyProjectSession? {
        guard index > 0 else { return nil }
        if let mapped = vibespace.project(forShortcut: index) {
            return mapped
        }
        guard index <= vibespace.projects.count else { return nil }
        return vibespace.projects[index - 1]
    }

    func wrappedIndex(afterShifting index: Int, by shift: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let normalized = (index + shift) % count
        return normalized >= 0 ? normalized : normalized + count
    }

    func terminalProjectMatch(
        for fileURL: URL,
        preferredProjectRootURL: URL?,
        candidates: [(vibespaceID: UUID, project: AnyProjectSession)]
    ) -> (vibespaceID: UUID, project: AnyProjectSession)? {
        let normalizedFilePath = fileURL.standardizedFileURL.path
        let normalizedCandidates = candidates.map { entry in
            (
                vibespaceID: entry.vibespaceID,
                project: entry.project,
                rootPath: entry.project.rootURL.standardizedFileURL.path
            )
        }

        if let preferredProjectRootURL {
            let normalizedPreferredRootPath = preferredProjectRootURL.standardizedFileURL.path
            for entry in normalizedCandidates {
                if entry.rootPath == normalizedPreferredRootPath &&
                    isPath(normalizedFilePath, containedIn: entry.rootPath) {
                    return (entry.vibespaceID, entry.project)
                }
            }
        }

        let matches = normalizedCandidates.filter { entry in
            isPath(normalizedFilePath, containedIn: entry.rootPath)
        }

        return matches.max { lhs, rhs in
            lhs.rootPath.count < rhs.rootPath.count
        }
        .map { ($0.vibespaceID, $0.project) }
    }

    func sourceControlProjectMatch(
        for fileURL: URL,
        repositoryRootURL: URL,
        focusedProject: AnyProjectSession?,
        projects: [AnyProjectSession]
    ) -> AnyProjectSession? {
        let normalizedFilePath = fileURL.standardizedFileURL.path
        let normalizedRepositoryRootPath = repositoryRootURL.standardizedFileURL.path
        let normalizedFocusedProjectRootPath = focusedProject?.rootURL.standardizedFileURL.path

        if let focusedProject,
           let focusedProjectRootPath = normalizedFocusedProjectRootPath,
           isPath(normalizedFilePath, containedIn: focusedProjectRootPath)
            || isPath(focusedProjectRootPath, containedIn: normalizedRepositoryRootPath)
            || isPath(normalizedRepositoryRootPath, containedIn: focusedProjectRootPath) {
            return focusedProject
        }

        let normalizedProjects = projects.map { project in
            (project: project, rootPath: project.rootURL.standardizedFileURL.path)
        }

        let matchingProjects = normalizedProjects.filter { entry in
            isPath(normalizedFilePath, containedIn: entry.rootPath)
                || isPath(entry.rootPath, containedIn: normalizedRepositoryRootPath)
                || isPath(normalizedRepositoryRootPath, containedIn: entry.rootPath)
        }

        return matchingProjects.max { lhs, rhs in
            lhs.rootPath.count < rhs.rootPath.count
        }
        .map(\.project)
    }

    private func isPath(_ filePath: String, containedIn rootPath: String) -> Bool {
        if filePath == rootPath {
            return true
        }

        let rootPrefix = rootPath.hasSuffix("/")
            ? rootPath
            : rootPath + "/"
        return filePath.hasPrefix(rootPrefix)
    }
}
