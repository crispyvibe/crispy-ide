import Foundation

extension PaneWorkerExecutor {
    static func isGitAvailable() -> Bool {
        let now = Date()
        gitProbeCacheLock.lock()
        pruneGitProbeCachesLocked(now: now)
        if let cachedGitAvailability,
           now.timeIntervalSince(cachedGitAvailability.timestamp) < gitProbeCacheTTL {
            gitProbeCacheLock.unlock()
            return cachedGitAvailability.value
        }
        gitProbeCacheLock.unlock()

        guard let result = try? runGitCommand(
            arguments: ["--version"],
            timeout: gitProbeCommandTimeout
        ) else {
            gitProbeCacheLock.lock()
            cachedGitAvailability = (value: false, timestamp: now)
            gitProbeCacheLock.unlock()
            return false
        }
        let isAvailable = result.terminationStatus == 0
        gitProbeCacheLock.lock()
        cachedGitAvailability = (value: isAvailable, timestamp: now)
        gitProbeCacheLock.unlock()
        return isAvailable
    }

    static func isGitRepository(_ rootURL: URL) -> Bool {
        let now = Date()
        let normalizedRootPath = rootURL.standardizedFileURL.path

        gitProbeCacheLock.lock()
        pruneGitProbeCachesLocked(now: now)
        if let cached = cachedRepositoryState[normalizedRootPath],
           now.timeIntervalSince(cached.timestamp) < gitProbeCacheTTL {
            gitProbeCacheLock.unlock()
            return cached.value
        }
        if cachedRepositoryRootContainingPathLocked(normalizedRootPath) != nil {
            cachedRepositoryState[normalizedRootPath] = (value: true, timestamp: now)
            gitProbeCacheLock.unlock()
            return true
        }
        gitProbeCacheLock.unlock()

        guard let result = try? runGitCommand(
            arguments: [
                "-C", normalizedRootPath,
                "rev-parse",
                "--is-inside-work-tree"
            ],
            timeout: gitProbeCommandTimeout
        ) else {
            gitProbeCacheLock.lock()
            cachedRepositoryState[normalizedRootPath] = (value: false, timestamp: now)
            gitProbeCacheLock.unlock()
            return false
        }

        guard result.terminationStatus == 0,
              let stdout = String(data: result.stdoutData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            gitProbeCacheLock.lock()
            cachedRepositoryState[normalizedRootPath] = (value: false, timestamp: now)
            gitProbeCacheLock.unlock()
            return false
        }

        let isRepository = stdout == "true"
        gitProbeCacheLock.lock()
        cachedRepositoryState[normalizedRootPath] = (value: isRepository, timestamp: now)
        gitProbeCacheLock.unlock()
        return isRepository
    }

    static func gitRepositoryRootURL(for rootURL: URL) -> URL? {
        let now = Date()
        let normalizedRootPath = rootURL.standardizedFileURL.path

        gitProbeCacheLock.lock()
        pruneGitProbeCachesLocked(now: now)
        if let cached = cachedRepositoryRoots[normalizedRootPath],
           now.timeIntervalSince(cached.timestamp) < gitProbeCacheTTL {
            gitProbeCacheLock.unlock()
            return cached.value
        }
        if let cachedContainingRoot = cachedRepositoryRootContainingPathLocked(normalizedRootPath) {
            cachedRepositoryRoots[normalizedRootPath] = (value: cachedContainingRoot, timestamp: now)
            gitProbeCacheLock.unlock()
            return cachedContainingRoot
        }
        gitProbeCacheLock.unlock()

        guard let result = try? runGitCommand(
            arguments: [
                "-C", normalizedRootPath,
                "rev-parse",
                "--show-toplevel"
            ],
            timeout: gitProbeCommandTimeout
        ),
        result.terminationStatus == 0,
        let rootPath = String(data: result.stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
        !rootPath.isEmpty else {
            gitProbeCacheLock.lock()
            cachedRepositoryRoots[normalizedRootPath] = (value: nil, timestamp: now)
            gitProbeCacheLock.unlock()
            return nil
        }
        let resolvedURL = URL(fileURLWithPath: rootPath).standardizedFileURL
        gitProbeCacheLock.lock()
        cachedRepositoryRoots[normalizedRootPath] = (value: resolvedURL, timestamp: now)
        gitProbeCacheLock.unlock()
        return resolvedURL
    }

    static func assertGitRepositoryAvailable(for rootURL: URL) throws {
        guard isGitAvailable() else {
            throw PaneWorkerError.workerFailure("Git is not installed on this machine.")
        }
        guard isGitRepository(rootURL) else {
            throw PaneWorkerError.workerFailure("This folder is not a Git repository.")
        }
    }

    private static func pruneGitProbeCachesLocked(now: Date) {
        guard now.timeIntervalSince(lastPrunedAt) >= gitProbeCacheTTL else { return }
        lastPrunedAt = now
        cachedRepositoryState = pruneCache(cachedRepositoryState, now: now)
        cachedRepositoryRoots = pruneCache(cachedRepositoryRoots, now: now)
    }

    private static func cachedRepositoryRootContainingPathLocked(_ path: String) -> URL? {
        for (_, entry) in cachedRepositoryRoots {
            guard let rootURL = entry.value else { continue }
            let rootPath = rootURL.standardizedFileURL.path
            if path == rootPath {
                return rootURL
            }
            let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if path.hasPrefix(rootPrefix) {
                return rootURL
            }
        }
        return nil
    }

    private static func pruneCache<Value>(
        _ cache: [String: (value: Value, timestamp: Date)],
        now: Date
    ) -> [String: (value: Value, timestamp: Date)] {
        var filtered: [String: (value: Value, timestamp: Date)] = cache.filter { _, entry in
            now.timeIntervalSince(entry.timestamp) < gitProbeCacheTTL
        }
        if filtered.count <= gitProbeCacheMaxEntries {
            return filtered
        }

        let sortedKeys = filtered.keys.sorted { lhs, rhs in
            let lhsTime = filtered[lhs]?.timestamp ?? .distantPast
            let rhsTime = filtered[rhs]?.timestamp ?? .distantPast
            return lhsTime > rhsTime
        }
        let retainedKeys = Set(sortedKeys.prefix(gitProbeCacheMaxEntries))
        filtered = filtered.filter { retainedKeys.contains($0.key) }
        return filtered
    }
}
