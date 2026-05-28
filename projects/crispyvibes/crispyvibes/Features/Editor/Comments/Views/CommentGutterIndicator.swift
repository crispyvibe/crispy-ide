import SwiftUI

/// F049-R06: gutter indicator for a line that has comments. Shape and color
/// reflect status: filled bubble for active, outlined for resolved, warning
/// for stale.
@MainActor
struct CommentGutterIndicator: View {
    @Environment(\.appThemePalette) private var palette

    let status: CommentStatusFilter
    let isAgentAuthored: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            iconView
                .frame(width: 14, height: 14)
                .padding(2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("comments.gutter.\(status.rawValue)")
        .help(tooltip)
    }

    @ViewBuilder
    private var iconView: some View {
        switch status {
        case .active:
            Image(systemName: "quote.bubble.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(isAgentAuthored ? palette.accentColor : Color.blue)
                .overlay(
                    isSelected
                        ? RoundedRectangle(cornerRadius: 3)
                            .stroke(palette.primaryTextColor, lineWidth: 1.2)
                            .padding(-1)
                        : nil
                )
        case .resolved:
            Image(systemName: "quote.bubble")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(palette.secondaryTextColor)
        case .stale:
            Image(systemName: "quote.bubble.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.orange)
        case .all:
            Image(systemName: "quote.bubble.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.blue)
        }
    }

    private var tooltip: String {
        switch status {
        case .active: return AppStrings.Comments.gutterActiveTooltip
        case .resolved: return AppStrings.Comments.gutterResolvedTooltip
        case .stale: return AppStrings.Comments.gutterStaleTooltip
        case .all: return ""
        }
    }
}

/// Compact horizontal strip of gutter indicators displayed at the start of a
/// line. Used in the editor's left-margin column.
@MainActor
struct CommentGutterStrip: View {
    let threads: [CommentThread]
    let selectedThreadID: String?
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(threads.prefix(3)) { thread in
                CommentGutterIndicator(
                    status: thread.status,
                    isAgentAuthored: thread.root.authorKind == .agent,
                    isSelected: selectedThreadID == thread.id,
                    onTap: { onSelect(thread.id) }
                )
            }
            if threads.count > 3 {
                Text(AppStrings.Comments.gutterOverflow(threads.count - 3))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
    }
}
