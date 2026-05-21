import SwiftUI

struct GitDiffPreview: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    let content: String

    private var document: ParsedGitDiffDocument {
        ParsedGitDiffDocument.parse(content)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if document.sections.isEmpty {
                        fallbackContentView(text: content)
                    } else {
                        ForEach(document.sections) { section in
                            sectionView(section)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
        .background(appThemePalette.canvasBackgroundColor)
    }

    private func sectionView(_ section: ParsedGitDiffSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                Text(section.title)
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                Spacer(minLength: 0)
            }

            if section.files.isEmpty {
                fallbackContentView(text: section.fallbackLines.joined(separator: "\n"))
            } else {
                ForEach(section.files) { file in
                    fileView(file)
                }
            }
        }
    }

    private func fileView(_ file: ParsedGitDiffFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.pathSummary)
                    .font(AppTypographyTokens.subheadlineSemibold)
                    .foregroundStyle(appThemePalette.primaryTextColor)
                if let pathDetail = file.pathDetail {
                    Text(pathDetail)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                }
            }

            if !file.metadataLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(file.metadataLines, id: \.self) { line in
                        Text(line)
                            .font(AppTypographyTokens.monospacedCaption)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                    }
                }
            }

            if file.hunks.isEmpty {
                Text(AppStrings.SourceControl.noDiffContent)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            } else {
                ForEach(file.hunks) { hunk in
                    hunkView(hunk)
                }
            }
        }
    }

    private func hunkView(_ hunk: ParsedGitDiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(AppTypographyTokens.monospacedCaptionSemibold)
                .foregroundStyle(appThemePalette.secondaryTextColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(appThemePalette.windowBackgroundColor.opacity(0.88))

            ForEach(hunk.rows) { row in
                hunkRowView(row)
            }
        }
    }

    private func hunkRowView(_ row: ParsedGitDiffRow) -> some View {
        HStack(spacing: 8) {
            Text(lineNumberText(row.oldLineNumber))
                .font(AppTypographyTokens.monospacedCaption2)
                .foregroundStyle(appThemePalette.secondaryTextColor)
                .frame(width: 44, alignment: .trailing)
            Text(lineNumberText(row.newLineNumber))
                .font(AppTypographyTokens.monospacedCaption2)
                .foregroundStyle(appThemePalette.secondaryTextColor)
                .frame(width: 44, alignment: .trailing)

            Text(row.text)
                .font(AppTypographyTokens.monospacedCaption)
                .textSelection(.enabled)
                .foregroundStyle(appThemePalette.primaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(rowBackgroundColor(row.kind))
    }

    private func fallbackContentView(text: String) -> some View {
        Text(text)
            .font(AppTypographyTokens.monospacedCaption)
            .textSelection(.enabled)
            .foregroundStyle(appThemePalette.primaryTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lineNumberText(_ value: Int?) -> String {
        guard let value else { return " " }
        return "\(value)"
    }

    private func rowBackgroundColor(_ kind: ParsedGitDiffRow.Kind) -> Color {
        switch kind {
        case .addition:
            return appThemePalette.gitAddedStatusColor.opacity(0.20)
        case .deletion:
            return appThemePalette.gitDeletedStatusColor.opacity(0.20)
        case .meta:
            return appThemePalette.warningColor.opacity(0.14)
        case .context:
            return Color.clear
        }
    }
}
