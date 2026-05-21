import SwiftUI

struct ACPToolCallGroupView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    let calls: [ACPToolCallState]
    var vibespaceRoot: String?
    let onLinkTargetActivated: ((URL) -> Void)?
    let onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?
    @State private var expandedDiffIDs = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(calls) { call in
                toolCallCard(call)
            }
        }
    }

    private func toolCallCard(_ call: ACPToolCallState) -> some View {
        let inlineContent = call.content.filter { if case .diff = $0 { return false }; return true }
        let diffRows = diffSummaryRows(for: call)

        return VStack(alignment: .leading, spacing: 6) {
            // Header with icon, title, kind, status
            HStack(spacing: 8) {
                toolCallIcon(call)
                Text(call.title)
                    .font(AppTypographyTokens.subheadlineSemibold)
                if let kind = call.kind, !kind.isEmpty {
                    Text(kind)
                        .font(AppTypographyTokens.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palette.secondaryTextColor.opacity(0.1))
                        .clipShape(Capsule())
                        .foregroundStyle(palette.secondaryTextColor)
                }
                Spacer()
                toolCallStatusBadge(call.status)
            }

            // Inline content
            ForEach(Array(inlineContent.enumerated()), id: \.offset) { _, content in
                switch content {
                case .text(let text):
                    ACPSelectableText(
                        text: text,
                        font: .caption,
                        foregroundColor: palette.secondaryTextColor,
                        onLinkTargetActivated: onLinkTargetActivated,
                        onFileSystemTargetActivated: onFileSystemTargetActivated
                    )
                case .terminal(let terminalID):
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(palette.secondaryTextColor)
                        Text(terminalID)
                            .font(AppTypographyTokens.captionMonospaced)
                            .foregroundStyle(palette.secondaryTextColor)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.secondaryTextColor.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                case .diff:
                    EmptyView()
                }
            }

            // Diff summary
            if !diffRows.isEmpty {
                ACPChangedFilesSummaryView(
                    rows: diffRows,
                    vibespaceRoot: vibespaceRoot,
                    expandedDiffIDs: $expandedDiffIDs,
                    onLinkTargetActivated: onLinkTargetActivated,
                    onFileSystemTargetActivated: onFileSystemTargetActivated
                )
            }

            // File locations
            if !call.locations.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(call.locations.enumerated()), id: \.offset) { _, location in
                        ACPSelectableText(
                            text: location.path + (location.line.map { ":\($0)" } ?? ""),
                            font: .caption2,
                            foregroundColor: palette.secondaryTextColor,
                            onLinkTargetActivated: onLinkTargetActivated,
                            onFileSystemTargetActivated: onFileSystemTargetActivated
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.secondaryTextColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Tool Call Icon

    @ViewBuilder
    private func toolCallIcon(_ call: ACPToolCallState) -> some View {
        let iconName = toolCallIconName(call)
        Image(systemName: iconName)
            .font(AppTypographyTokens.scaledIcon(12, weight: .semibold))
            .foregroundStyle(palette.accentColor)
            .frame(width: uiScale.iconSize(20), height: uiScale.iconSize(20))
    }

    private func toolCallIconName(_ call: ACPToolCallState) -> String {
        // Check content first — diff-bearing calls are file changes regardless of kind
        if call.content.contains(where: { if case .diff = $0 { return true }; return false }) {
            return "doc.text"
        }
        switch call.kind?.lowercased() {
        case "command", "terminal", "bash", "shell": return "terminal"
        case "write", "edit", "file_write", "create": return "square.and.pencil"
        case "read", "file_read", "view": return "eye"
        case "search", "grep", "find", "web_search", "glob": return "magnifyingglass"
        case "mcp", "mcp_tool_call": return "puzzlepiece"
        case "browser", "fetch", "url": return "globe"
        default: return "wrench"
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func toolCallStatusBadge(_ status: ACPToolCallStatus) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .pending:
                Image(systemName: "clock").font(AppTypographyTokens.caption2)
            case .inProgress:
                ProgressView().controlSize(.mini)
            case .completed:
                Image(systemName: "checkmark.circle.fill").font(AppTypographyTokens.caption2)
            case .error:
                Image(systemName: "xmark.circle.fill").font(AppTypographyTokens.caption2)
            case .cancelled:
                Image(systemName: "slash.circle").font(AppTypographyTokens.caption2)
            }
            Text(status.displayLabel)
                .font(AppTypographyTokens.caption2)
        }
        .foregroundStyle(statusColor(status))
    }

    private func statusColor(_ status: ACPToolCallStatus) -> Color {
        switch status {
        case .completed: return palette.accentColor
        case .error: return .red
        case .cancelled: return palette.secondaryTextColor
        case .pending, .inProgress: return palette.secondaryTextColor
        }
    }

    private func diffSummaryRows(for call: ACPToolCallState) -> [ACPDiffSummaryRow] {
        call.content.enumerated().compactMap { index, content in
            guard case .diff(let diff) = content else { return nil }
            let stats = ACPDiffStats(diff: diff)
            return ACPDiffSummaryRow(
                id: "\(call.id):\(index):\(diff.path)",
                diff: diff,
                additions: stats.additions,
                deletions: stats.deletions
            )
        }
    }
}

// MARK: - Status Display Label

extension ACPToolCallStatus {
    var displayLabel: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "Running"
        case .completed: return "Done"
        case .error: return "Error"
        case .cancelled: return "Cancelled"
        }
    }
}

struct ACPDiffSummaryRow: Identifiable, Equatable {
    let id: String
    let diff: ACPDiff
    let additions: Int
    let deletions: Int
    var path: String { diff.path }

    /// Returns the path relative to the given vibespace root, or the original path if not under the root.
    func displayPath(relativeTo vibespaceRoot: String?) -> String {
        guard let root = vibespaceRoot, !root.isEmpty else { return path }
        let normalizedRoot = root.hasSuffix("/") ? root : root + "/"
        if path.hasPrefix(normalizedRoot) {
            return String(path.dropFirst(normalizedRoot.count))
        }
        return path
    }
}

struct ACPChangedFilesSummaryView: View {
    @Environment(\.appThemePalette) private var palette
    let rows: [ACPDiffSummaryRow]
    var vibespaceRoot: String?
    @Binding var expandedDiffIDs: Set<String>
    let onLinkTargetActivated: ((URL) -> Void)?
    let onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?
    var onViewDiff: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text").font(AppTypographyTokens.caption).foregroundStyle(palette.secondaryTextColor)
                Text("Changed files (\(rows.count))")
                    .font(AppTypographyTokens.captionSemibold)
                Spacer()
                let totals = rows.reduce(into: (0, 0)) { $0.0 += $1.additions; $0.1 += $1.deletions }
                if totals.0 > 0 || totals.1 > 0 {
                    HStack(spacing: 4) {
                        Text("+\(totals.0)").foregroundStyle(palette.accentColor)
                        Text("-\(totals.1)").foregroundStyle(.red)
                    }
                    .font(AppTypographyTokens.caption2MonospacedDigit)
                }
                if let onViewDiff {
                    Button { onViewDiff() } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "rectangle.expand.vertical")
                                .font(AppTypographyTokens.scaledSystem(9))
                            Text("View diff")
                                .font(AppTypographyTokens.caption2)
                        }
                        .foregroundStyle(palette.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button { toggle(row.id) } label: {
                            Image(systemName: expandedDiffIDs.contains(row.id) ? "chevron.down" : "chevron.right")
                                .font(AppTypographyTokens.captionSemibold)
                                .foregroundStyle(palette.secondaryTextColor)
                        }
                        .buttonStyle(.plain)

                        Text(row.displayPath(relativeTo: vibespaceRoot))
                            .font(AppTypographyTokens.captionMonospaced)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()
                        HStack(spacing: 4) {
                            if row.additions > 0 { Text("+\(row.additions)").foregroundStyle(palette.accentColor) }
                            if row.deletions > 0 { Text("-\(row.deletions)").foregroundStyle(.red) }
                        }
                        .font(AppTypographyTokens.caption2MonospacedDigit)
                    }

                    if expandedDiffIDs.contains(row.id) {
                        ACPDiffView(
                            diff: row.diff,
                            onLinkTargetActivated: onLinkTargetActivated,
                            onFileSystemTargetActivated: onFileSystemTargetActivated
                        )
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.secondaryTextColor.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func toggle(_ id: String) {
        if expandedDiffIDs.contains(id) { expandedDiffIDs.remove(id) }
        else { expandedDiffIDs.insert(id) }
    }
}

struct ACPDiffStats {
    let additions: Int
    let deletions: Int

    init(diff: ACPDiff) {
        if let parsed = Self.parseUnifiedDiff(diff.newText) {
            additions = parsed.additions; deletions = parsed.deletions; return
        }
        additions = Self.countMeaningfulLines(diff.newText)
        deletions = diff.oldText.map(Self.countMeaningfulLines) ?? 0
    }

    private static func parseUnifiedDiff(_ text: String) -> (additions: Int, deletions: Int)? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.contains(where: { $0.hasPrefix("@@") || $0.hasPrefix("diff ") }) else { return nil }
        var a = 0, d = 0
        for line in lines {
            if line.hasPrefix("+++") || line.hasPrefix("---") { continue }
            if line.hasPrefix("+") { a += 1 } else if line.hasPrefix("-") { d += 1 }
        }
        return (a, d)
    }

    private static func countMeaningfulLines(_ text: String) -> Int {
        max(text.split(separator: "\n", omittingEmptySubsequences: false).count, text.isEmpty ? 0 : 1)
    }
}
