import Foundation

extension PaneWorkerExecutor {
    static func parseGitStatus(from data: Data, rootURL: URL) -> [WorkerGitStatusNode] {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return []
        }

        let records = text.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        var entries: [WorkerGitStatusNode] = []

        while index < records.count {
            let record = records[index]
            index += 1

            if record.isEmpty || record.count < 3 {
                continue
            }

            let code = String(record.prefix(2))
            let indexStatus = String(code.prefix(1))
            let workTreeStatus = String(code.suffix(1))
            var relativePath = String(record.dropFirst(3))

            let indexCharacter = code.first
            if indexCharacter == "R" || indexCharacter == "C" {
                if index < records.count {
                    let renamedDestination = records[index]
                    index += 1
                    if !renamedDestination.isEmpty {
                        relativePath = renamedDestination
                    }
                }
            }

            guard !relativePath.isEmpty else {
                continue
            }

            let absolutePath = rootURL
                .appendingPathComponent(relativePath)
                .standardizedFileURL
                .path
            entries.append(
                WorkerGitStatusNode(
                    code: code,
                    indexStatus: indexStatus,
                    workTreeStatus: workTreeStatus,
                    path: absolutePath,
                    relativePath: relativePath
                )
            )
        }

        return entries.sorted { lhs, rhs in
            lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
        }
    }
}
