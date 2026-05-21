import Foundation

struct ParsedGitDiffDocument {
    let sections: [ParsedGitDiffSection]

    static func parse(_ content: String) -> ParsedGitDiffDocument {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let rawSections = splitSections(lines)

        let parsedSections = rawSections.enumerated().map { index, rawSection -> ParsedGitDiffSection in
            let parsedFiles = parseFiles(in: rawSection.lines)
            return ParsedGitDiffSection(
                id: "section-\(index)",
                title: rawSection.title,
                files: parsedFiles,
                fallbackLines: rawSection.lines.filter { !$0.isEmpty || rawSection.lines.count == 1 }
            )
        }

        return ParsedGitDiffDocument(sections: parsedSections)
    }

    private static func splitSections(_ lines: [String]) -> [(title: String, lines: [String])] {
        var sections: [(title: String, lines: [String])] = []
        var currentTitle = "Changes"
        var currentLines: [String] = []

        for line in lines {
            if let heading = sectionHeadingTitle(for: line) {
                if !currentLines.isEmpty {
                    sections.append((title: currentTitle, lines: currentLines))
                    currentLines = []
                }
                currentTitle = heading
                continue
            }
            currentLines.append(line)
        }

        if !currentLines.isEmpty || sections.isEmpty {
            sections.append((title: currentTitle, lines: currentLines))
        }

        return sections.filter { !$0.lines.isEmpty || sections.count == 1 }
    }

    private static func sectionHeadingTitle(for line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("### ") else { return nil }
        let title = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func parseFiles(in lines: [String]) -> [ParsedGitDiffFile] {
        var files: [ParsedGitDiffFile] = []
        var index = 0

        while index < lines.count {
            guard lines[index].hasPrefix("diff --git ") else {
                index += 1
                continue
            }

            var block: [String] = [lines[index]]
            index += 1
            while index < lines.count && !lines[index].hasPrefix("diff --git ") {
                block.append(lines[index])
                index += 1
            }
            files.append(parseFileBlock(block, fileIndex: files.count))
        }

        return files
    }

    private static func parseFileBlock(_ block: [String], fileIndex: Int) -> ParsedGitDiffFile {
        var metadata: [String] = []
        var hunks: [ParsedGitDiffHunk] = []
        var oldPath: String?
        var newPath: String?

        var index = 0
        while index < block.count {
            let line = block[index]

            if line.hasPrefix("@@ ") || line.hasPrefix("@@") {
                let hunkParse = parseHunk(in: block, startIndex: index, fileIndex: fileIndex, hunkIndex: hunks.count)
                hunks.append(hunkParse.hunk)
                index = hunkParse.nextIndex
                continue
            }

            if line.hasPrefix("--- ") {
                oldPath = String(line.dropFirst(4))
            } else if line.hasPrefix("+++ ") {
                newPath = String(line.dropFirst(4))
            } else if !line.isEmpty {
                metadata.append(line)
            }

            index += 1
        }

        let diffHeader = block.first ?? "diff --git"
        let summary = pathSummary(oldPath: oldPath, newPath: newPath, header: diffHeader)
        let detail = pathDetail(oldPath: oldPath, newPath: newPath)
        let cleanMetadata = metadata.filter { !$0.hasPrefix("--- ") && !$0.hasPrefix("+++ ") }

        return ParsedGitDiffFile(
            id: "file-\(fileIndex)",
            pathSummary: summary,
            pathDetail: detail,
            metadataLines: cleanMetadata,
            hunks: hunks
        )
    }

    private static func parseHunk(
        in lines: [String],
        startIndex: Int,
        fileIndex: Int,
        hunkIndex: Int
    ) -> (hunk: ParsedGitDiffHunk, nextIndex: Int) {
        let header = lines[startIndex]
        let starts = parseHunkStarts(header)
        var oldLine = starts.old
        var newLine = starts.new
        var rows: [ParsedGitDiffRow] = []
        var index = startIndex + 1
        var rowIndex = 0

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("@@ ") || line.hasPrefix("@@") || line.hasPrefix("diff --git ") {
                break
            }

            let rowID = "file-\(fileIndex)-hunk-\(hunkIndex)-row-\(rowIndex)"
            rowIndex += 1

            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                rows.append(
                    ParsedGitDiffRow(
                        id: rowID,
                        kind: .addition,
                        oldLineNumber: nil,
                        newLineNumber: newLine,
                        text: line
                    )
                )
                newLine += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                rows.append(
                    ParsedGitDiffRow(
                        id: rowID,
                        kind: .deletion,
                        oldLineNumber: oldLine,
                        newLineNumber: nil,
                        text: line
                    )
                )
                oldLine += 1
            } else if line.hasPrefix(" ") {
                rows.append(
                    ParsedGitDiffRow(
                        id: rowID,
                        kind: .context,
                        oldLineNumber: oldLine,
                        newLineNumber: newLine,
                        text: line
                    )
                )
                oldLine += 1
                newLine += 1
            } else {
                rows.append(
                    ParsedGitDiffRow(
                        id: rowID,
                        kind: .meta,
                        oldLineNumber: nil,
                        newLineNumber: nil,
                        text: line
                    )
                )
            }

            index += 1
        }

        return (
            ParsedGitDiffHunk(
                id: "file-\(fileIndex)-hunk-\(hunkIndex)",
                header: header,
                rows: rows
            ),
            index
        )
    }

    private static func parseHunkStarts(_ header: String) -> (old: Int, new: Int) {
        let pattern = "@@ -([0-9]+)(?:,[0-9]+)? \\+([0-9]+)(?:,[0-9]+)? @@"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (0, 0)
        }

        let range = NSRange(location: 0, length: (header as NSString).length)
        guard let match = regex.firstMatch(in: header, options: [], range: range),
              match.numberOfRanges >= 3 else {
            return (0, 0)
        }

        let oldString = (header as NSString).substring(with: match.range(at: 1))
        let newString = (header as NSString).substring(with: match.range(at: 2))
        return (Int(oldString) ?? 0, Int(newString) ?? 0)
    }

    private static func pathSummary(oldPath: String?, newPath: String?, header: String) -> String {
        let normalizedOld = normalizedPathToken(oldPath)
        let normalizedNew = normalizedPathToken(newPath)

        if let normalizedOld, let normalizedNew {
            if normalizedOld == normalizedNew {
                return normalizedNew
            }
            return "\(normalizedOld) -> \(normalizedNew)"
        }
        if let normalizedNew {
            return normalizedNew
        }
        if let normalizedOld {
            return normalizedOld
        }
        return header.replacingOccurrences(of: "diff --git ", with: "")
    }

    private static func pathDetail(oldPath: String?, newPath: String?) -> String? {
        let normalizedOld = normalizedPathToken(oldPath)
        let normalizedNew = normalizedPathToken(newPath)
        guard let normalizedOld, let normalizedNew, normalizedOld != normalizedNew else { return nil }
        return "from \(normalizedOld) to \(normalizedNew)"
    }

    private static func normalizedPathToken(_ token: String?) -> String? {
        guard var token else { return nil }
        token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        if token == "/dev/null" { return token }
        if token.hasPrefix("a/") || token.hasPrefix("b/") {
            return String(token.dropFirst(2))
        }
        return token
    }
}

struct ParsedGitDiffSection: Identifiable {
    let id: String
    let title: String
    let files: [ParsedGitDiffFile]
    let fallbackLines: [String]
}

struct ParsedGitDiffFile: Identifiable {
    let id: String
    let pathSummary: String
    let pathDetail: String?
    let metadataLines: [String]
    let hunks: [ParsedGitDiffHunk]
}

struct ParsedGitDiffHunk: Identifiable {
    let id: String
    let header: String
    let rows: [ParsedGitDiffRow]
}

struct ParsedGitDiffRow: Identifiable {
    enum Kind {
        case context
        case addition
        case deletion
        case meta
    }

    let id: String
    let kind: Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
}
