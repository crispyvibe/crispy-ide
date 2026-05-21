import Foundation

extension PaneWorkerExecutor {
    static func nestedGitRepositoryRoots(
        under rootURL: URL,
        settings: VibeSpaceSourceControlSettings
    ) -> [URL] {
        let normalizedRootURL = rootURL.standardizedFileURL
        let rootPath = normalizedRootURL.path
        let rootComponentCount = normalizedRootURL.pathComponents.count
        let ignoredDirectoryNames = Set(
            (Array(gitRepositoryScanSkippedDirectoryNames) + settings.ignoredDirectoryNames)
                .map { $0.lowercased() }
        )
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .isHiddenKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: normalizedRootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var repositoryRoots: [URL] = []
        var seenPaths = Set<String>()

        for case let candidateURL as URL in enumerator {
            let standardizedURL = candidateURL.standardizedFileURL
            let relativeDepth = standardizedURL.pathComponents.count - rootComponentCount
            let lastComponent = standardizedURL.lastPathComponent
            let resourceValues = try? standardizedURL.resourceValues(forKeys: resourceKeys)
            let isDirectory = resourceValues?.isDirectory ?? false
            let isRegularFile = resourceValues?.isRegularFile ?? false
            let isSymbolicLink = resourceValues?.isSymbolicLink ?? false
            let isPackage = resourceValues?.isPackage ?? false
            let isHidden = resourceValues?.isHidden ?? false

            if lastComponent == ".git", isDirectory || isRegularFile {
                let repositoryRootURL = standardizedURL.deletingLastPathComponent().standardizedFileURL
                let repositoryRootPath = repositoryRootURL.path
                if repositoryRootPath != rootPath,
                   seenPaths.insert(repositoryRootPath).inserted {
                    repositoryRoots.append(repositoryRootURL)
                    if repositoryRoots.count >= settings.scanMaxRepositories {
                        break
                    }
                }
                enumerator.skipDescendants()
                continue
            }

            guard isDirectory else { continue }

            if isSymbolicLink || isPackage {
                enumerator.skipDescendants()
                continue
            }

            if relativeDepth >= settings.scanMaxDepth {
                enumerator.skipDescendants()
                continue
            }

            if relativeDepth > 0 && (
                isHidden ||
                ignoredDirectoryNames.contains(lastComponent.lowercased())
            ) {
                enumerator.skipDescendants()
            }
        }

        return repositoryRoots.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    static func gitIgnoredAbsolutePaths(
        for rootURL: URL,
        candidateURLs: [URL]
    ) -> Set<String> {
        guard !candidateURLs.isEmpty,
              let repositoryRootURL = gitRepositoryRootURL(for: rootURL) else {
            return []
        }

        let repositoryPrefix = repositoryRootURL.path.hasSuffix("/")
            ? repositoryRootURL.path
            : repositoryRootURL.path + "/"

        let relativeCandidates: [String] = candidateURLs.compactMap { candidate in
            let standardizedPath = candidate.standardizedFileURL.path
            guard standardizedPath.hasPrefix(repositoryPrefix) else {
                return nil
            }
            return String(standardizedPath.dropFirst(repositoryPrefix.count))
        }
        if relativeCandidates.count > 2_000 {
            return []
        }
        guard !relativeCandidates.isEmpty else { return [] }

        let stdinPayload = relativeCandidates.joined(separator: "\n") + "\n"
        guard let stdinData = stdinPayload.data(using: .utf8),
              let result = try? runGitCommand(
                  arguments: [
                      "-C", repositoryRootURL.path,
                      "check-ignore",
                      "--stdin"
                  ],
                  stdinData: stdinData,
                  timeout: gitBackgroundCommandTimeout
              ),
              result.terminationStatus == 0 || result.terminationStatus == 1,
              let output = String(data: result.stdoutData, encoding: .utf8) else {
            return []
        }

        let ignoredRelativePaths = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }

        var ignoredAbsolutePaths: Set<String> = []
        ignoredAbsolutePaths.reserveCapacity(ignoredRelativePaths.count)
        for relativePath in ignoredRelativePaths {
            let absolute = repositoryRootURL
                .appendingPathComponent(relativePath)
                .standardizedFileURL
                .path
            ignoredAbsolutePaths.insert(absolute)
        }
        return ignoredAbsolutePaths
    }
}
