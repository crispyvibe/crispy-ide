import Foundation

extension PaneWorkerExecutor {
    static func cloneGitRepository(
        repositoryURL: String,
        destinationParentURL: URL,
        directoryName: String?
    ) throws -> URL {
        guard isGitAvailable() else {
            throw PaneWorkerError.workerFailure("Git is not installed on this machine.")
        }

        let normalizedDestinationParentURL = destinationParentURL.standardizedFileURL
        var destinationParentIsDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: normalizedDestinationParentURL.path,
            isDirectory: &destinationParentIsDirectory
        ), destinationParentIsDirectory.boolValue else {
            throw PaneWorkerError.workerFailure("Destination folder does not exist.")
        }

        let destinationName = try cloneDestinationDirectoryName(
            repositoryURL: repositoryURL,
            explicitDirectoryName: directoryName
        )
        let destinationURL = normalizedDestinationParentURL.appendingPathComponent(destinationName, isDirectory: true)

        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw PaneWorkerError.workerFailure("Destination already contains a folder named \(destinationName).")
        }

        let result = try runGitCommand(
            arguments: ["clone", "--", repositoryURL, destinationURL.path],
            timeout: gitCloneCommandTimeout
        )

        guard result.terminationStatus == 0 else {
            throw PaneWorkerError.workerFailure(
                gitCommandErrorDetail(from: result.stderrData, stdoutData: result.stdoutData)
            )
        }

        return destinationURL
    }

    static func loadGitHubCloneOptions() throws -> WorkerGitHubCloneOptionsPayload {
        let versionResult = try runToolCommand(
            tool: "gh",
            arguments: ["--version"],
            timeout: gitProbeCommandTimeout
        )
        guard versionResult.terminationStatus == 0 else {
            return WorkerGitHubCloneOptionsPayload(
                cliAvailable: false,
                authenticated: false,
                repositories: [],
                message: "Paste a repository URL, or install GitHub CLI to browse your GitHub repositories."
            )
        }

        let authStatusResult = try runToolCommand(
            tool: "gh",
            arguments: ["auth", "status", "--hostname", "github.com"],
            timeout: gitProbeCommandTimeout
        )
        guard authStatusResult.terminationStatus == 0 else {
            return WorkerGitHubCloneOptionsPayload(
                cliAvailable: true,
                authenticated: false,
                repositories: [],
                message: "GitHub CLI is not signed in. Paste a repository URL, or run `gh auth login` to browse repositories."
            )
        }

        let repositoryListResult = try runToolCommand(
            tool: "gh",
            arguments: [
                "repo", "list", "@me",
                "--limit", "100",
                "--json", "nameWithOwner,description,isPrivate,updatedAt"
            ],
            timeout: gitHubCommandTimeout
        )
        guard repositoryListResult.terminationStatus == 0 else {
            throw PaneWorkerError.workerFailure(
                gitCommandErrorDetail(
                    from: repositoryListResult.stderrData,
                    stdoutData: repositoryListResult.stdoutData,
                    fallback: "Unable to load GitHub repositories."
                )
            )
        }

        let repositories = try decodeGitHubRepositoryNodes(from: repositoryListResult.stdoutData)
        return WorkerGitHubCloneOptionsPayload(
            cliAvailable: true,
            authenticated: true,
            repositories: repositories,
            message: repositories.isEmpty
                ? "No GitHub repositories were returned for this account. Paste a repository URL to continue."
                : nil
        )
    }
}
