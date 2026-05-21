import SwiftUI

struct ACPDiffView: View {
    let diff: ACPDiff
    let onLinkTargetActivated: ((URL) -> Void)?
    let onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?

    var body: some View {
        let rendered = ACPUnifiedDiffBuilder.render(diff)
        let lineCount = rendered.components(separatedBy: "\n").count
        let estimatedHeight = min(max(CGFloat(lineCount * 20 + 32), 100), 320)

        VStack(alignment: .leading, spacing: 6) {
            ACPSelectableText(
                text: diff.path,
                font: .caption.weight(.semibold),
                onLinkTargetActivated: onLinkTargetActivated,
                onFileSystemTargetActivated: onFileSystemTargetActivated
            )
            GitDiffPreview(content: rendered)
                .frame(height: estimatedHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

enum ACPUnifiedDiffBuilder {
    static func render(_ diff: ACPDiff) -> String {
        if let patch = normalizedPatchIfPresent(diff) {
            return patch
        }

        return buildUnifiedDiff(
            path: diff.path,
            oldText: diff.oldText ?? "",
            newText: diff.newText,
            oldExists: diff.oldText != nil
        )
    }

    private static func normalizedPatchIfPresent(_ diff: ACPDiff) -> String? {
        guard diff.oldText == nil, looksLikePatch(diff.newText) else { return nil }

        let trimmed = diff.newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("diff --git ") {
            return trimmed
        }

        let normalizedPath = normalizedPath(diff.path)
        if trimmed.contains("\n--- ") || trimmed.hasPrefix("--- ") || trimmed.contains("\n+++ ") || trimmed.hasPrefix("+++ ") {
            return "diff --git a/\(normalizedPath) b/\(normalizedPath)\n" + trimmed
        }

        return nil
    }

    private static func looksLikePatch(_ text: String) -> Bool {
        text.contains("diff --git ")
            || text.contains("\n@@ ")
            || text.hasPrefix("@@ ")
            || text.contains("\n+++ ")
            || text.hasPrefix("+++ ")
            || text.contains("\n--- ")
            || text.hasPrefix("--- ")
    }

    private static func buildUnifiedDiff(path: String, oldText: String, newText: String, oldExists: Bool) -> String {
        let normalizedPath = normalizedPath(path)
        let oldLines = splitLines(oldText)
        let newLines = splitLines(newText)
        let operations = diffOperations(oldLines: oldLines, newLines: newLines)

        var lines: [String] = [
            "diff --git a/\(normalizedPath) b/\(normalizedPath)",
            oldExists ? "--- a/\(normalizedPath)" : "--- /dev/null",
            "+++ b/\(normalizedPath)",
            "@@ -\(oldExists ? 1 : 0),\(oldLines.count) +\(newLines.isEmpty ? 0 : 1),\(newLines.count) @@"
        ]

        lines.append(contentsOf: operations.map(\.renderedLine))
        return lines.joined(separator: "\n")
    }

    private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func normalizedPath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return String(path.dropFirst())
        }
        return path
    }

    private static func diffOperations(oldLines: [String], newLines: [String]) -> [Operation] {
        let complexity = (oldLines.count + 1) * (newLines.count + 1)
        if complexity > 160_000 {
            return fallbackOperations(oldLines: oldLines, newLines: newLines)
        }

        var lcs = Array(
            repeating: Array(repeating: 0, count: newLines.count + 1),
            count: oldLines.count + 1
        )

        if !oldLines.isEmpty, !newLines.isEmpty {
            for oldIndex in stride(from: oldLines.count - 1, through: 0, by: -1) {
                for newIndex in stride(from: newLines.count - 1, through: 0, by: -1) {
                    if oldLines[oldIndex] == newLines[newIndex] {
                        lcs[oldIndex][newIndex] = lcs[oldIndex + 1][newIndex + 1] + 1
                    } else {
                        lcs[oldIndex][newIndex] = max(
                            lcs[oldIndex + 1][newIndex],
                            lcs[oldIndex][newIndex + 1]
                        )
                    }
                }
            }
        }

        var operations: [Operation] = []
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count,
               newIndex < newLines.count,
               oldLines[oldIndex] == newLines[newIndex] {
                operations.append(.context(oldLines[oldIndex]))
                oldIndex += 1
                newIndex += 1
            } else if newIndex < newLines.count,
                      (oldIndex == oldLines.count || lcs[oldIndex][newIndex + 1] >= lcs[oldIndex + 1][newIndex]) {
                operations.append(.addition(newLines[newIndex]))
                newIndex += 1
            } else if oldIndex < oldLines.count {
                operations.append(.deletion(oldLines[oldIndex]))
                oldIndex += 1
            }
        }

        return operations
    }

    private static func fallbackOperations(oldLines: [String], newLines: [String]) -> [Operation] {
        oldLines.map(Operation.deletion) + newLines.map(Operation.addition)
    }

    private enum Operation {
        case context(String)
        case addition(String)
        case deletion(String)

        var renderedLine: String {
            switch self {
            case .context(let line):
                return " " + line
            case .addition(let line):
                return "+" + line
            case .deletion(let line):
                return "-" + line
            }
        }
    }
}
