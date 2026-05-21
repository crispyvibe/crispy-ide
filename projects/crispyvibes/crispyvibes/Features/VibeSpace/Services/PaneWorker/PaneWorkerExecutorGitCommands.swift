import Foundation

extension PaneWorkerExecutor {
    static func stageGitPath(for rootURL: URL, relativePath: String) throws {
        try assertGitRepositoryAvailable(for: rootURL)
        let normalizedPath = normalizedRelativeGitPath(relativePath)
        _ = try runCheckedGitCommand(arguments: ["-C", rootURL.path, "add", "--", normalizedPath])
    }

    static func unstageGitPath(for rootURL: URL, relativePath: String) throws {
        try assertGitRepositoryAvailable(for: rootURL)
        let normalizedPath = normalizedRelativeGitPath(relativePath)
        try runGitCommandWithFallback(
            primaryArguments: ["-C", rootURL.path, "restore", "--staged", "--", normalizedPath],
            fallbackArguments: ["-C", rootURL.path, "reset", "HEAD", "--", normalizedPath]
        )
    }

    static func unstageAllGitChanges(for rootURL: URL) throws {
        try assertGitRepositoryAvailable(for: rootURL)
        try runGitCommandWithFallback(
            primaryArguments: ["-C", rootURL.path, "restore", "--staged", "--", "."],
            fallbackArguments: ["-C", rootURL.path, "reset", "HEAD", "--", "."]
        )
    }

    static func stageAllGitChanges(for rootURL: URL) throws {
        try assertGitRepositoryAvailable(for: rootURL)
        _ = try runCheckedGitCommand(arguments: ["-C", rootURL.path, "add", "-A"])
    }

    static func discardGitPath(for rootURL: URL, relativePath: String) throws {
        try assertGitRepositoryAvailable(for: rootURL)
        let normalizedPath = normalizedRelativeGitPath(relativePath)
        try runGitCommandWithFallback(
            primaryArguments: ["-C", rootURL.path, "restore", "--worktree", "--", normalizedPath],
            fallbackArguments: ["-C", rootURL.path, "checkout", "--", normalizedPath]
        )
    }

    static func discardAllGitChanges(for rootURL: URL) throws {
        try assertGitRepositoryAvailable(for: rootURL)
        try runGitCommandWithFallback(
            primaryArguments: ["-C", rootURL.path, "restore", "--worktree", "--", "."],
            fallbackArguments: ["-C", rootURL.path, "checkout", "--", "."]
        )
    }

    static func commitGitChanges(for rootURL: URL, message: String) throws {
        try assertGitRepositoryAvailable(for: rootURL)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw PaneWorkerError.workerFailure("Commit message cannot be empty.")
        }
        _ = try runCheckedGitCommand(arguments: ["-C", rootURL.path, "commit", "-m", trimmedMessage])
    }

    static func pushGitChanges(for rootURL: URL) throws {
        try assertGitRepositoryAvailable(for: rootURL)
        _ = try runCheckedGitCommand(arguments: ["-C", rootURL.path, "push"])
    }

    static func pullGitChanges(for rootURL: URL) throws {
        try assertGitRepositoryAvailable(for: rootURL)
        _ = try runCheckedGitCommand(arguments: ["-C", rootURL.path, "pull"])
    }

    static func fetchGitChanges(for rootURL: URL) throws {
        try assertGitRepositoryAvailable(for: rootURL)
        _ = try runCheckedGitCommand(arguments: ["-C", rootURL.path, "fetch"])
    }

    static func checkoutGitBranch(for rootURL: URL, branch: String, isRemote: Bool) throws {
        try assertGitRepositoryAvailable(for: rootURL)
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBranch.isEmpty else {
            throw PaneWorkerError.workerFailure("Branch name cannot be empty.")
        }

        if isRemote {
            let tracking = try runGitCommand(arguments: [
                "-C", rootURL.path,
                "checkout",
                "--track",
                trimmedBranch
            ])
            if tracking.terminationStatus == 0 {
                return
            }

            let fallbackLocal = trimmedBranch.components(separatedBy: "/").dropFirst().joined(separator: "/")
            if !fallbackLocal.isEmpty {
                let fallback = try runGitCommand(arguments: [
                    "-C", rootURL.path,
                    "checkout",
                    fallbackLocal
                ])
                if fallback.terminationStatus == 0 {
                    return
                }
                throw PaneWorkerError.workerFailure(
                    gitCommandErrorDetail(from: fallback.stderrData, stdoutData: fallback.stdoutData)
                )
            }
            throw PaneWorkerError.workerFailure(
                gitCommandErrorDetail(from: tracking.stderrData, stdoutData: tracking.stdoutData)
            )
        }

        _ = try runCheckedGitCommand(arguments: [
            "-C", rootURL.path,
            "checkout",
            trimmedBranch
        ])
    }

    private static func runGitCommandWithFallback(
        primaryArguments: [String],
        fallbackArguments: [String]
    ) throws {
        let primaryResult = try runGitCommand(arguments: primaryArguments)
        if primaryResult.terminationStatus == 0 {
            return
        }

        let fallbackResult = try runGitCommand(arguments: fallbackArguments)
        guard fallbackResult.terminationStatus == 0 else {
            throw PaneWorkerError.workerFailure(
                gitCommandErrorDetail(
                    from: fallbackResult.stderrData,
                    stdoutData: fallbackResult.stdoutData
                )
            )
        }
    }
}
