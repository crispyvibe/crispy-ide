import Darwin
import Foundation

extension PaneWorkerExecutor {
    static let gitCommandTimeout: TimeInterval = 15
    static let gitBackgroundCommandTimeout: TimeInterval = 8
    static let gitCloneCommandTimeout: TimeInterval = 90
    static let gitHubCommandTimeout: TimeInterval = 12
    static let gitProbeCommandTimeout: TimeInterval = 4
    static let gitProbeCacheTTL: TimeInterval = 4
    static let gitProbeCacheMaxEntries = 256
    static let gitRepositoryScanMaxDepth = 8
    static let gitRepositoryScanMaxRepositories = 64
    static let gitRepositoryScanSkippedDirectoryNames: Set<String> = [
        ".build",
        ".cache",
        ".next",
        ".nuxt",
        ".swiftpm",
        "DerivedData",
        "Pods",
        "build",
        "dist",
        "node_modules",
        "out"
    ]
    static let gitProbeCacheLock = NSLock()
    static var cachedGitAvailability: (value: Bool, timestamp: Date)?
    static var cachedRepositoryState: [String: (value: Bool, timestamp: Date)] = [:]
    static var cachedRepositoryRoots: [String: (value: URL?, timestamp: Date)] = [:]
    static var lastPrunedAt: Date = .distantPast

    static func normalizedRelativeGitPath(_ relativePath: String) -> String {
        relativePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
    }

    static func discoverGitRepositories(
        for projectRootURL: URL,
        settings: VibeSpaceSourceControlSettings = .default
    ) throws -> WorkerGitRepositoryDiscoveryPayload {
        guard isGitAvailable() else {
            return WorkerGitRepositoryDiscoveryPayload(
                gitAvailable: false,
                repositories: [],
                message: "Git is not installed on this machine."
            )
        }

        let normalizedSettings = settings.normalized()
        let normalizedProjectRootURL = projectRootURL.standardizedFileURL
        var discoveredRepositoryPaths = Set<String>()

        guard let containingRootURL = gitRepositoryRootURL(for: normalizedProjectRootURL) else {
            return WorkerGitRepositoryDiscoveryPayload(
                gitAvailable: true,
                repositories: [],
                message: nil
            )
        }

        discoveredRepositoryPaths.insert(containingRootURL.path)

        for nestedRootURL in nestedGitRepositoryRoots(
            under: normalizedProjectRootURL,
            settings: normalizedSettings
        ) {
            discoveredRepositoryPaths.insert(nestedRootURL.path)
            if discoveredRepositoryPaths.count >= normalizedSettings.scanMaxRepositories {
                break
            }
        }

        let repositories = discoveredRepositoryPaths
            .sorted()
            .map(WorkerGitRepositoryNode.init(repositoryRootPath:))

        return WorkerGitRepositoryDiscoveryPayload(
            gitAvailable: true,
            repositories: repositories,
            message: nil
        )
    }

    static func discoverGitRepositoriesBatch(
        for projectRootURLs: [URL],
        settings: VibeSpaceSourceControlSettings = .default
    ) throws -> WorkerGitRepositoryDiscoveryBatchPayload {
        let normalizedSettings = settings.normalized()
        let results = try projectRootURLs.map { projectRootURL in
            let normalizedProjectRootURL = projectRootURL.standardizedFileURL
            let payload = try discoverGitRepositories(
                for: normalizedProjectRootURL,
                settings: normalizedSettings
            )
            return WorkerGitRepositoryDiscoveryBatchEntry(
                projectRootPath: normalizedProjectRootURL.path,
                payload: payload
            )
        }
        return WorkerGitRepositoryDiscoveryBatchPayload(results: results)
    }

    static func loadGitStatus(for rootURL: URL) throws -> WorkerGitStatusPayload {
        guard isGitAvailable() else {
            return WorkerGitStatusPayload(
                gitAvailable: false,
                repository: false,
                entries: [],
                message: "Git is not installed on this machine."
            )
        }

        guard isGitRepository(rootURL) else {
            return WorkerGitStatusPayload(
                gitAvailable: true,
                repository: false,
                entries: [],
                message: "This folder is not a Git repository."
            )
        }

        let result = try runGitCommand(
            arguments: [
                "-C", rootURL.path,
                "status",
                "--porcelain=v1",
                "-z",
                "-uall"
            ],
            timeout: gitBackgroundCommandTimeout
        )

        guard result.terminationStatus == 0 else {
            throw PaneWorkerError.workerFailure(gitCommandErrorDetail(from: result.stderrData, stdoutData: result.stdoutData))
        }

        let entries = parseGitStatus(from: result.stdoutData, rootURL: rootURL)
        return WorkerGitStatusPayload(
            gitAvailable: true,
            repository: true,
            entries: entries,
            message: nil
        )
    }

    static func loadGitRepositorySnapshot(for rootURL: URL) throws -> WorkerGitRepositorySnapshotPayload {
        guard isGitAvailable() else {
            return WorkerGitRepositorySnapshotPayload(
                gitAvailable: false,
                repository: false,
                entries: [],
                currentBranch: nil,
                branches: [],
                message: "Git is not installed on this machine."
            )
        }

        guard isGitRepository(rootURL) else {
            return WorkerGitRepositorySnapshotPayload(
                gitAvailable: true,
                repository: false,
                entries: [],
                currentBranch: nil,
                branches: [],
                message: "This folder is not a Git repository."
            )
        }

        let statusResult = try runGitCommand(
            arguments: [
                "-C", rootURL.path,
                "status",
                "--porcelain=v1",
                "-z",
                "-uall"
            ],
            timeout: gitBackgroundCommandTimeout
        )

        guard statusResult.terminationStatus == 0 else {
            throw PaneWorkerError.workerFailure(
                gitCommandErrorDetail(from: statusResult.stderrData, stdoutData: statusResult.stdoutData)
            )
        }

        let entries = parseGitStatus(from: statusResult.stdoutData, rootURL: rootURL)
        let branchSnapshot = try loadBranchSnapshot(rootURL: rootURL)
        return WorkerGitRepositorySnapshotPayload(
            gitAvailable: true,
            repository: true,
            entries: entries,
            currentBranch: branchSnapshot.currentBranch,
            branches: branchSnapshot.branches,
            message: nil
        )
    }

    static func loadGitBranches(for rootURL: URL) throws -> WorkerGitBranchesPayload {
        guard isGitAvailable() else {
            return WorkerGitBranchesPayload(
                gitAvailable: false,
                repository: false,
                currentBranch: nil,
                branches: [],
                message: "Git is not installed on this machine."
            )
        }

        guard isGitRepository(rootURL) else {
            return WorkerGitBranchesPayload(
                gitAvailable: true,
                repository: false,
                currentBranch: nil,
                branches: [],
                message: "This folder is not a Git repository."
            )
        }

        let snapshot = try loadBranchSnapshot(rootURL: rootURL)

        return WorkerGitBranchesPayload(
            gitAvailable: true,
            repository: true,
            currentBranch: snapshot.currentBranch,
            branches: snapshot.branches,
            message: nil
        )
    }

}
