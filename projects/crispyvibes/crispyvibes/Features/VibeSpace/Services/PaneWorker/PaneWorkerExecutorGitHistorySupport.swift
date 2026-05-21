import Foundation

extension PaneWorkerExecutor {
    private static let gitHistoryPrettyFormat = "%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1e"

    static func loadGitCommitHistory(for rootURL: URL, limit: Int) throws -> WorkerGitHistoryPayload {
        try loadGitHistoryPayload(for: rootURL, limit: limit, additionalArguments: [])
    }

    static func loadGitFileHistory(
        for rootURL: URL,
        relativePath: String,
        limit: Int
    ) throws -> WorkerGitHistoryPayload {
        try loadGitHistoryPayload(
            for: rootURL,
            limit: limit,
            additionalArguments: ["--", normalizedRelativeGitPath(relativePath)]
        )
    }

    static func parseGitHistoryEntries(from data: Data) -> [WorkerGitHistoryEntry] {
        guard !data.isEmpty,
              let output = String(data: data, encoding: .utf8),
              !output.isEmpty else {
            return []
        }

        let recordSeparator = Character(UnicodeScalar(0x1E)!)
        let fieldSeparator = Character(UnicodeScalar(0x1F)!)
        return output
            .split(separator: recordSeparator)
            .compactMap { rawRecord -> WorkerGitHistoryEntry? in
                let fields = rawRecord.split(separator: fieldSeparator, omittingEmptySubsequences: false)
                guard fields.count >= 5 else { return nil }
                let fullHash = String(fields[0])
                return WorkerGitHistoryEntry(
                    hash: fullHash,
                    shortHash: String(fields[1]),
                    authorName: String(fields[2]),
                    authoredDate: String(fields[3]),
                    subject: String(fields[4])
                )
            }
    }

    static func isEmptyCommitHistoryError(_ stderrData: Data) -> Bool {
        let message = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return message.contains("does not have any commits yet")
    }

    static func loadGitFileContent(
        for rootURL: URL,
        relativePath: String
    ) throws -> String {
        try assertGitRepositoryAvailable(for: rootURL)
        let outputData = try runCheckedGitCommand(arguments: [
            "-C", rootURL.path,
            "show",
            "HEAD:\(normalizedRelativeGitPath(relativePath))"
        ])

        guard let content = String(data: outputData, encoding: .utf8) else {
            throw PaneWorkerError.workerFailure("Previous revision is a binary file and cannot be shown inline.")
        }

        return content
    }

    static func loadGitDiff(for rootURL: URL, relativePath: String) throws -> String {
        try assertGitRepositoryAvailable(for: rootURL)
        let normalizedPath = normalizedRelativeGitPath(relativePath)
        let rootPath = rootURL.path

        // Run unstaged and staged diffs in parallel to halve latency.
        var unstagedText = ""
        var stagedText = ""
        var unstagedError: Error?
        var stagedError: Error?
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                unstagedText = try gitDiffText(arguments: [
                    "-C", rootPath, "diff", "--no-color", "--", normalizedPath
                ])
            } catch { unstagedError = error }
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                stagedText = try gitDiffText(arguments: [
                    "-C", rootPath, "diff", "--no-color", "--cached", "--", normalizedPath
                ])
            } catch { stagedError = error }
            group.leave()
        }

        group.wait()
        if let error = unstagedError ?? stagedError { throw error }

        var sections: [String] = []
        if !stagedText.isEmpty {
            sections.append("### Staged Changes\n\(stagedText)")
        }
        if !unstagedText.isEmpty {
            sections.append("### Working Tree Changes\n\(unstagedText)")
        }

        if !sections.isEmpty {
            return sections.joined(separator: "\n\n")
        }

        let statusOutput = try runCheckedGitCommand(arguments: [
            "-C", rootURL.path,
            "status",
            "--porcelain=v1",
            "--",
            normalizedPath
        ])
        let statusText = String(data: statusOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if statusText.isEmpty {
            return "No diff output is currently available for \(normalizedPath)."
        }

        return """
        ### Git Status
        \(statusText)

        No textual diff is available for this file revision.
        """
    }

    private static func loadGitHistoryPayload(
        for rootURL: URL,
        limit: Int,
        additionalArguments: [String]
    ) throws -> WorkerGitHistoryPayload {
        try assertGitRepositoryAvailable(for: rootURL)
        let clampedLimit = max(1, min(limit, 500))
        let result = try runGitCommand(arguments: [
            "-C", rootURL.path,
            "log",
            "--date=iso-strict",
            "--pretty=format:\(gitHistoryPrettyFormat)",
            "-n",
            String(clampedLimit)
        ] + additionalArguments)

        if result.terminationStatus != 0 {
            if isEmptyCommitHistoryError(result.stderrData) {
                return WorkerGitHistoryPayload(entries: [])
            }
            throw PaneWorkerError.workerFailure(
                gitCommandErrorDetail(from: result.stderrData, stdoutData: result.stdoutData)
            )
        }

        return WorkerGitHistoryPayload(entries: parseGitHistoryEntries(from: result.stdoutData))
    }

    private static func gitDiffText(arguments: [String]) throws -> String {
        let outputData = try runCheckedGitCommand(arguments: arguments)
        return String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
