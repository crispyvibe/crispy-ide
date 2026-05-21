// GitOutputParser.swift — SSH Remote Development
//
// Pure parsing functions for git command output. Used by both local and remote
// git explorers. No side effects, no dependencies on PaneWorker infrastructure.

import Foundation

enum GitOutputParser {

    // MARK: - Status

    static func parseStatus(from data: Data, rootURL: URL) -> [WorkerGitStatusNode] {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return [] }
        let records = text.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        var entries: [WorkerGitStatusNode] = []

        while index < records.count {
            let record = records[index]
            index += 1
            guard record.count >= 3 else { continue }

            let code = String(record.prefix(2))
            let indexStatus = String(code.prefix(1))
            let workTreeStatus = String(code.suffix(1))
            var relativePath = String(record.dropFirst(3))

            if (code.first == "R" || code.first == "C"), index < records.count {
                let dest = records[index]; index += 1
                if !dest.isEmpty { relativePath = dest }
            }
            guard !relativePath.isEmpty else { continue }

            entries.append(WorkerGitStatusNode(
                code: code, indexStatus: indexStatus, workTreeStatus: workTreeStatus,
                path: rootURL.appendingPathComponent(relativePath).standardizedFileURL.path,
                relativePath: relativePath
            ))
        }
        return entries.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }

    // MARK: - Branches

    static func parseLocalBranches(from output: String) -> [WorkerGitBranchNode] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let name = fields.first, !name.isEmpty else { return nil }
            let isCurrent = fields.count > 1 && fields[1].trimmingCharacters(in: .whitespacesAndNewlines) == "*"
            let upstream = fields.count > 2 ? fields[2] : ""
            let displayName = upstream.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? name : "\(name) -> \(upstream)"
            return WorkerGitBranchNode(name: name, displayName: displayName, isCurrent: isCurrent, isRemote: false)
        }
    }

    static func parseRemoteBranches(from output: String) -> [WorkerGitBranchNode] {
        output.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasSuffix("/HEAD") }
            .map { WorkerGitBranchNode(name: $0, displayName: $0, isCurrent: false, isRemote: true) }
    }

    static func sortBranches(_ branches: [WorkerGitBranchNode]) -> [WorkerGitBranchNode] {
        branches.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            if lhs.isRemote != rhs.isRemote { return !lhs.isRemote }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    // MARK: - History

    static func parseHistoryEntries(from data: Data) -> [WorkerGitHistoryEntry] {
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return [] }
        let recordSep = Character(UnicodeScalar(0x1E)!)
        let fieldSep = Character(UnicodeScalar(0x1F)!)
        return output.split(separator: recordSep).compactMap { raw in
            let fields = raw.split(separator: fieldSep, omittingEmptySubsequences: false)
            guard fields.count >= 5 else { return nil }
            return WorkerGitHistoryEntry(
                hash: String(fields[0]), shortHash: String(fields[1]),
                authorName: String(fields[2]), authoredDate: String(fields[3]),
                subject: String(fields[4])
            )
        }
    }

    // MARK: - Current Branch

    static func parseCurrentBranch(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Error Helpers

    static func errorDetail(from stderrData: Data, fallback: String = "Git command failed.") -> String {
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stderr.isEmpty ? fallback : stderr
    }

    static func isEmptyCommitHistoryError(_ stderrData: Data) -> Bool {
        let msg = String(data: stderrData, encoding: .utf8)?.lowercased() ?? ""
        return msg.contains("does not have any commits yet")
    }
}
