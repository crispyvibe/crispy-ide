import SwiftUI

/// Full-screen spotlight overlay showing all diffs for a turn with a file sidebar.
struct ACPDiffSpotlightPanel: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    let rows: [ACPDiffSummaryRow]
    let turnLabel: String
    var vibespaceRoot: String?
    let onDismiss: () -> Void

    @State private var selectedFileID: String?

    private var selectedRow: ACPDiffSummaryRow? {
        rows.first { $0.id == selectedFileID } ?? rows.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                fileSidebar
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
                diffContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.canvasBackgroundColor)
        .onAppear {
            if selectedFileID == nil { selectedFileID = rows.first?.id }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(AppTypographyTokens.body)
                .foregroundStyle(palette.accentColor)
            Text("Changes — \(turnLabel)")
                .font(AppTypographyTokens.headline)
            Spacer()
            let totals = rows.reduce(into: (0, 0)) { $0.0 += $1.additions; $0.1 += $1.deletions }
            HStack(spacing: 6) {
                Text("\(rows.count) files")
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(palette.secondaryTextColor)
                if totals.0 > 0 {
                    Text("+\(totals.0)")
                        .font(AppTypographyTokens.captionMonospacedDigit)
                        .foregroundStyle(palette.accentColor)
                }
                if totals.1 > 0 {
                    Text("-\(totals.1)")
                        .font(AppTypographyTokens.captionMonospacedDigit)
                        .foregroundStyle(.red)
                }
            }
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppTypographyTokens.title3)
                    .foregroundStyle(palette.secondaryTextColor)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.canvasSecondaryBackgroundColor)
    }

    // MARK: - File Sidebar

    private var fileSidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(rows) { row in
                    Button { selectedFileID = row.id } label: {
                        HStack(spacing: 6) {
                            Image(systemName: fileIcon(for: row.diff.path))
                                .font(AppTypographyTokens.scaledIcon(12))
                                .foregroundStyle(palette.secondaryTextColor)
                                .frame(width: uiScale.iconSize(14))
                            Text(row.displayPath(relativeTo: vibespaceRoot))
                                .font(AppTypographyTokens.captionMonospaced)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer(minLength: 4)
                            HStack(spacing: 2) {
                                if row.additions > 0 {
                                    Text("+\(row.additions)")
                                        .foregroundStyle(palette.accentColor)
                                }
                                if row.deletions > 0 {
                                    Text("-\(row.deletions)")
                                        .foregroundStyle(.red)
                                }
                            }
                            .font(AppTypographyTokens.scaledSystem(9).monospacedDigit())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(selectedFileID == row.id ? palette.accentColor.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .background(palette.canvasSecondaryBackgroundColor.opacity(0.5))
    }

    // MARK: - Diff Content

    @ViewBuilder
    private var diffContent: some View {
        if let row = selectedRow {
            let rendered = ACPUnifiedDiffBuilder.render(row.diff)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(row.displayPath(relativeTo: vibespaceRoot))
                        .font(AppTypographyTokens.scaledSystem(14, weight: .medium, design: .monospaced))
                    Spacer()
                    HStack(spacing: 4) {
                        if row.additions > 0 {
                            Text("+\(row.additions)").foregroundStyle(palette.accentColor)
                        }
                        if row.deletions > 0 {
                            Text("-\(row.deletions)").foregroundStyle(.red)
                        }
                    }
                    .font(AppTypographyTokens.captionMonospacedDigit)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(palette.canvasSecondaryBackgroundColor)
                Divider()
                GitDiffPreview(content: rendered)
            }
        } else {
            Text("No files changed")
                .font(AppTypographyTokens.callout)
                .foregroundStyle(palette.secondaryTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fileIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml": return "gearshape"
        case "md", "txt": return "doc.text"
        case "css", "scss": return "paintbrush"
        case "html": return "globe"
        default: return "doc"
        }
    }
}
