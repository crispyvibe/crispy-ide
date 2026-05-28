import SwiftUI

/// F049-R04: renders a single thread (root + replies). Handles reply,
/// resolve, edit, delete actions through callbacks. Markdown body rendered
/// via SwiftUI's native AttributedString markdown parser (R09 — safe subset
/// only; no WKWebView).
@MainActor
struct CommentThreadView: View {
    @Environment(\.appThemePalette) private var palette
    @ObservedObject var panel: CommentsPanelStore

    let thread: CommentThread
    let isSelected: Bool
    let onSelect: () -> Void
    let onReply: (String) async -> Bool
    let onEdit: (String, String) async -> Bool
    let onResolve: () async -> Bool
    let onDelete: () async -> Void

    @State private var isComposingReply = false
    @State private var editingCommentID: String?

    /// Shared formatter — cached statically to avoid per-row allocator churn
    /// inside the panel's `LazyVStack`.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            commentRow(thread.root, isRoot: true)
            if !thread.replies.isEmpty {
                ForEach(thread.replies) { reply in
                    commentRow(reply, isRoot: false)
                        .padding(.leading, 16)
                }
            }
            if isSelected, !thread.root.isResolved {
                replyRow
            }
        }
        .padding(8)
        .background(threadBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(threadBorderColor, lineWidth: isSelected ? 1.5 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .accessibilityIdentifier("comments.thread.\(thread.id)")
        .onChange(of: panel.autoOpenReplyForThreadID) { _, _ in
            // Delegate the consume-and-clear policy to the panel store.
            if panel.consumeAutoReply(forThreadID: thread.id, isResolved: thread.root.isResolved) {
                isComposingReply = true
            }
        }
        .onAppear {
            // The store's auto-reply request may have arrived before this
            // row mounted (e.g. when the panel just opened). Same flow.
            if panel.consumeAutoReply(forThreadID: thread.id, isResolved: thread.root.isResolved) {
                isComposingReply = true
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func commentRow(_ comment: Comment, isRoot: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                authorBadge(for: comment)
                if comment.isEdited {
                    Text(AppStrings.Comments.editedBadge)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryTextColor)
                }
                Spacer()
                Text(relativeTime(comment.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryTextColor)
                if isRoot { rootActions }
            }
            if editingCommentID == comment.id {
                CommentComposerView(
                    placeholder: "",
                    initialText: comment.body,
                    isReply: false,
                    onSubmit: { newBody in
                        let ok = await onEdit(comment.id, newBody)
                        if ok { editingCommentID = nil }
                        return ok
                    },
                    onCancel: { editingCommentID = nil }
                )
            } else {
                bodyText(comment.body, isStale: comment.isStale)
            }
            if comment.isStale, isRoot {
                staleBadge(anchorText: comment.anchor.anchorText)
            }
        }
    }

    private var replyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isComposingReply {
                CommentComposerView(
                    placeholder: AppStrings.Comments.replyPlaceholder,
                    isReply: true,
                    onSubmit: { body in
                        let ok = await onReply(body)
                        if ok { isComposingReply = false }
                        return ok
                    },
                    onCancel: { isComposingReply = false }
                )
            } else {
                Button(AppStrings.Comments.replyAction) {
                    isComposingReply = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(palette.accentColor)
                .accessibilityIdentifier("comments.thread.\(thread.id).reply-button")
            }
        }
    }

    @ViewBuilder
    private var rootActions: some View {
        Menu {
            Button(thread.root.isResolved ? AppStrings.Comments.reopen : AppStrings.Comments.resolve) {
                Task { @MainActor in _ = await onResolve() }
            }
            Button(AppStrings.Common.delete, role: .destructive) {
                Task { @MainActor in await onDelete() }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .frame(width: 18)
        .accessibilityIdentifier("comments.thread.\(thread.id).menu")
    }

    @ViewBuilder
    private func authorBadge(for comment: Comment) -> some View {
        HStack(spacing: 4) {
            Image(systemName: comment.authorKind == .agent ? "sparkle" : "person.crop.circle")
                .font(.caption)
                .foregroundStyle(comment.authorKind == .agent ? palette.accentColor : palette.secondaryTextColor)
            Text(comment.authorLabel ?? (comment.authorKind == .agent
                                         ? AppStrings.Comments.agentAnonymous
                                         : AppStrings.Comments.userAnonymous))
                .font(.caption)
                .foregroundStyle(palette.primaryTextColor)
        }
    }

    @ViewBuilder
    private func bodyText(_ raw: String, isStale: Bool) -> some View {
        let attributed = (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
        Text(attributed)
            .font(.body)
            .foregroundStyle(isStale ? palette.secondaryTextColor : palette.primaryTextColor)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func staleBadge(anchorText: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(AppStrings.Comments.staleLabel, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            if !anchorText.isEmpty {
                Text(AppStrings.Comments.staleOriginalAnchor)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryTextColor)
                Text(anchorText.prefix(120))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(palette.secondaryTextColor)
                    .padding(4)
                    .background(palette.canvasSecondaryBackgroundColor)
                    .cornerRadius(4)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var threadBackground: Color {
        if thread.root.isResolved {
            return palette.canvasSecondaryBackgroundColor.opacity(0.5)
        }
        return isSelected
            ? palette.accentColor.opacity(0.08)
            : palette.canvasSecondaryBackgroundColor
    }

    private var threadBorderColor: Color {
        if thread.root.isResolved { return palette.tertiaryTextColor.opacity(0.3) }
        if thread.root.isStale { return Color.orange.opacity(0.6) }
        return isSelected ? palette.accentColor : palette.tertiaryTextColor.opacity(0.3)
    }

    private func relativeTime(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
