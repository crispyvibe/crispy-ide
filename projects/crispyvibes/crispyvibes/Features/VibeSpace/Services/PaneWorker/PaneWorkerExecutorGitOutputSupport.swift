import Foundation

extension PaneWorkerExecutor {
    static func runCheckedGitCommand(
        arguments: [String],
        stdinData: Data? = nil,
        timeout: TimeInterval = gitCommandTimeout,
        fallback: String = "Git command failed."
    ) throws -> Data {
        let result = try runGitCommand(arguments: arguments, stdinData: stdinData, timeout: timeout)
        guard result.terminationStatus == 0 else {
            throw PaneWorkerError.workerFailure(
                gitCommandErrorDetail(
                    from: result.stderrData,
                    stdoutData: result.stdoutData,
                    fallback: fallback
                )
            )
        }
        return result.stdoutData
    }

    static func cloneDestinationDirectoryName(
        repositoryURL: String,
        explicitDirectoryName: String?
    ) throws -> String {
        let trimmedExplicitName = explicitDirectoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedExplicitName.isEmpty {
            let sanitizedExplicitName = sanitizedPathComponent(trimmedExplicitName)
            guard !sanitizedExplicitName.isEmpty else {
                throw PaneWorkerError.workerFailure("Destination folder name is invalid.")
            }
            return sanitizedExplicitName
        }

        let trimmedRepositoryURL = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let derivedName = (trimmedRepositoryURL as NSString).lastPathComponent
        let withoutGitSuffix = derivedName.hasSuffix(".git")
            ? String(derivedName.dropLast(4))
            : derivedName
        let sanitizedDerivedName = sanitizedPathComponent(withoutGitSuffix)
        guard !sanitizedDerivedName.isEmpty else {
            return "repository"
        }
        return sanitizedDerivedName
    }

    static func decodeGitHubRepositoryNodes(from data: Data) throws -> [WorkerGitHubRepositoryNode] {
        return try GitHubRepositoryDecoder.decode(data: data)
    }

    static func gitCommandErrorDetail(
        from stderrData: Data,
        stdoutData: Data? = nil,
        fallback: String = "Git command failed."
    ) -> String {
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stderr.isEmpty {
            return stderr
        }

        if let stdoutData,
           let stdout = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stdout.isEmpty {
            return stdout
        }
        return fallback
    }
}

private enum GitHubRepositoryDecoder {
    private static let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func decode(data: Data) throws -> [WorkerGitHubRepositoryNode] {
        struct GitHubRepositoryRecord: Decodable {
            let nameWithOwner: String
            let description: String?
            let isPrivate: Bool
            let updatedAt: String?
        }

        guard !data.isEmpty else { return [] }

        let decoded = try JSONDecoder().decode([GitHubRepositoryRecord].self, from: data)
        return decoded
            .map { record in
                WorkerGitHubRepositoryNode(
                    nameWithOwner: record.nameWithOwner,
                    cloneURL: "https://github.com/\(record.nameWithOwner).git",
                    description: record.description,
                    isPrivate: record.isPrivate,
                    updatedAt: record.updatedAt
                )
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.updatedAt.flatMap { iso8601Date(from: $0) }
                let rhsDate = rhs.updatedAt.flatMap { iso8601Date(from: $0) }
                switch (lhsDate, rhsDate) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.nameWithOwner.localizedCaseInsensitiveCompare(rhs.nameWithOwner) == .orderedAscending
            }
    }

    private static func iso8601Date(from value: String) -> Date? {
        if let date = fractionalSecondsFormatter.date(from: value) {
            return date
        }
        return internetDateTimeFormatter.date(from: value)
    }
}
