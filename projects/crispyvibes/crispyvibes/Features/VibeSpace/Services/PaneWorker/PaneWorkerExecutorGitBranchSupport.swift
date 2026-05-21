import Foundation

extension PaneWorkerExecutor {
    static func loadLocalBranchNodes(rootURL: URL) throws -> [WorkerGitBranchNode] {
        let outputData = try runCheckedGitCommand(
            arguments: [
                "-C", rootURL.path,
                "for-each-ref",
                "--format=%(refname:short)%09%(HEAD)%09%(upstream:short)",
                "refs/heads"
            ],
            timeout: gitBackgroundCommandTimeout
        )
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw PaneWorkerError.workerFailure("Git command returned invalid branch data.")
        }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> WorkerGitBranchNode? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard let name = fields.first, !name.isEmpty else { return nil }
                let isCurrent = fields.count > 1 && fields[1].trimmingCharacters(in: .whitespacesAndNewlines) == "*"
                let upstream = fields.count > 2 ? fields[2] : ""
                let displayName = upstream.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? name
                    : "\(name) -> \(upstream)"
                return WorkerGitBranchNode(
                    name: name,
                    displayName: displayName,
                    isCurrent: isCurrent,
                    isRemote: false
                )
            }
    }

    static func loadBranchSnapshot(rootURL: URL) throws -> (currentBranch: String?, branches: [WorkerGitBranchNode]) {
        let outputData = try runCheckedGitCommand(
            arguments: [
                "-C", rootURL.path,
                "for-each-ref",
                "--format=%(refname:short)%09%(HEAD)%09%(upstream:short)%09%(refname)",
                "refs/heads",
                "refs/remotes"
            ],
            timeout: gitBackgroundCommandTimeout
        )
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw PaneWorkerError.workerFailure("Git command returned invalid branch data.")
        }

        var currentBranch: String?
        var branches: [WorkerGitBranchNode] = []

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { continue }
            let shortName = fields[0]
            let headMarker = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let upstream = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let fullRefName = fields[3]
            guard !shortName.isEmpty, !fullRefName.isEmpty else { continue }

            if fullRefName.hasPrefix("refs/heads/") {
                let isCurrent = headMarker == "*"
                if isCurrent {
                    currentBranch = shortName
                }
                let displayName = upstream.isEmpty ? shortName : "\(shortName) -> \(upstream)"
                branches.append(
                    WorkerGitBranchNode(
                        name: shortName,
                        displayName: displayName,
                        isCurrent: isCurrent,
                        isRemote: false
                    )
                )
                continue
            }

            if fullRefName.hasPrefix("refs/remotes/"), !shortName.hasSuffix("/HEAD") {
                branches.append(
                    WorkerGitBranchNode(
                        name: shortName,
                        displayName: shortName,
                        isCurrent: false,
                        isRemote: true
                    )
                )
            }
        }

        if currentBranch == nil {
            currentBranch = resolveDetachedHeadName(rootURL: rootURL)
        }

        let sortedBranches = branches.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent {
                return lhs.isCurrent && !rhs.isCurrent
            }
            if lhs.isRemote != rhs.isRemote {
                return !lhs.isRemote && rhs.isRemote
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        return (currentBranch, sortedBranches)
    }

    static func loadRemoteBranchNodes(rootURL: URL) throws -> [WorkerGitBranchNode] {
        let outputData = try runCheckedGitCommand(
            arguments: [
                "-C", rootURL.path,
                "for-each-ref",
                "--format=%(refname:short)",
                "refs/remotes"
            ],
            timeout: gitBackgroundCommandTimeout
        )
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw PaneWorkerError.workerFailure("Git command returned invalid branch data.")
        }

        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasSuffix("/HEAD") }
            .map { branchName in
                WorkerGitBranchNode(
                    name: branchName,
                    displayName: branchName,
                    isCurrent: false,
                    isRemote: true
                )
            }
    }

    static func resolveCurrentBranchName(rootURL: URL) -> String? {
        if let result = try? runGitCommand(
            arguments: ["-C", rootURL.path, "branch", "--show-current"],
            timeout: gitProbeCommandTimeout
        ),
           result.terminationStatus == 0,
           let branchName = String(data: result.stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !branchName.isEmpty {
            return branchName
        }

        return resolveDetachedHeadName(rootURL: rootURL)
    }

    static func resolveDetachedHeadName(rootURL: URL) -> String? {
        if let detached = try? runGitCommand(
            arguments: ["-C", rootURL.path, "rev-parse", "--short", "HEAD"],
            timeout: gitProbeCommandTimeout
        ),
           detached.terminationStatus == 0,
           let shortHash = String(data: detached.stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !shortHash.isEmpty {
            return "detached@\(shortHash)"
        }

        return nil
    }
}
