import SwiftUI

/// F049-R04: renders a single thread (root + replies). Compact layout with
/// anchor context, always-visible actions, and same-author grouping.
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            anchorContextBlock
            commentsList
            actionBar
            if isComposingReply {
                replyComposer
            }
        }
        .padding(10)
        .background(threadBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(threadBorderColor, lineWidth: isSelected ? 1.5 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .opacity(thread.root.isResolved ? 0.55 : 1.0)
        .accessibilityIdentifier("comments.thread.\(thread.id)")
        .onChange(of: panel.autoOpenReplyForThreadID) { _, _ in
            if panel.consumeAutoReply(forThreadID: thread.id, isResolved: thread.root.isResolved) {
                isComposingReply = true
            }
        }
        .onAppear {
            if panel.consumeAutoReply(forThreadID: thread.id, isResolved: thread.root.isResolved) {
                isComposingReply = true
            }
        }
    }

    // MARK: - Anchor Context

    @ViewBuilder
    private var anchorContextBlock: some View {
        let text = thread.root.anchor.anchorText
        if !text.isEmpty {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(anchorBorderColor)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    if thread.root.surfaceKind == .file {
                        HStack(spacing: 4) {
                            Text(thread.root.anchor.locationLabel(filePath: thread.root.filePath))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.tertiaryTextColor)
                            if thread.root.isStale {
                                Label("modified", systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(text.prefix(160))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.secondaryTextColor)
                            .lineLimit(2)
                    } else {
                        if thread.root.isStale {
                            Label("anchor modified", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                        Text("\u{201C}\(text.prefix(100))\u{201D}")
                            .font(.system(size: 11))
                            .italic()
                            .foregroundStyle(palette.secondaryTextColor)
                            .lineLimit(2)
                    }
                }
                .padding(.leading, 8)
                .padding(.vertical, 4)
            }
            .padding(6)
            .background(palette.canvasSecondaryBackgroundColor.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.bottom, 8)
        }
    }

    private var anchorBorderColor: Color {
        if thread.root.isStale { return .orange.opacity(0.8) }
        return palette.accentColor.opacity(0.7)
    }

    // MARK: - Comments List

    private var commentsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactCommentRow(thread.root, isRoot: true, previousAuthor: nil)
            ForEach(Array(thread.replies.enumerated()), id: \.element.id) { idx, reply in
                let prev = idx == 0 ? thread.root : thread.replies[idx - 1]
                let prevAuthor = prev.authorLabel ?? prev.authorKind.rawValue
                compactCommentRow(reply, isRoot: false, previousAuthor: prevAuthor)
            }
        }
    }

    @ViewBuilder
    private func compactCommentRow(_ comment: Comment, isRoot: Bool, previousAuthor: String?) -> some View {
        let currentAuthor = comment.authorLabel ?? comment.authorKind.rawValue
        let isSameAuthor = previousAuthor == currentAuthor && !isRoot
        let timeDiff = isRoot ? TimeInterval.greatestFiniteMagnitude :
            comment.createdAt.timeIntervalSince(thread.root.createdAt)
        let isGrouped = isSameAuthor && timeDiff < 300

        VStack(alignment: .leading, spacing: 3) {
            if !isGrouped {
                HStack(spacing: 5) {
                    compactAvatar(for: comment)
                    Text(displayName(for: comment))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.primaryTextColor)
                        .lineLimit(1)
                    if comment.isEdited {
                        Text("(edited)")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.tertiaryTextColor)
                    }
                    Spacer(minLength: 4)
                    Text(relativeTime(comment.updatedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.tertiaryTextColor)
                }
                .frame(height: 22)
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
                bodyText(comment.body)
            }
        }
        .padding(.top, isGrouped ? 2 : (isRoot ? 0 : 8))
    }

    // MARK: - Always-visible Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            ActionPill(
                label: AppStrings.Comments.replyAction,
                icon: "arrowshape.turn.up.left",
                tint: palette.accentColor,
                action: { isComposingReply = true }
            )
            .disabled(thread.root.isResolved)

            ActionPill(
                label: thread.root.isResolved ? AppStrings.Comments.reopen : AppStrings.Comments.resolve,
                icon: thread.root.isResolved ? "arrow.uturn.backward" : "checkmark.circle",
                tint: thread.root.isResolved ? .orange : .green,
                action: { Task { @MainActor in _ = await onResolve() } }
            )

            Spacer()

            ActionPill(
                label: AppStrings.Common.delete,
                icon: "trash",
                tint: .red,
                action: { Task { @MainActor in await onDelete() } }
            )
        }
        .padding(.top, 8)
        .accessibilityIdentifier("comments.thread.\(thread.id).actions")
    }

    // MARK: - Reply Composer

    private var replyComposer: some View {
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
        .padding(.top, 6)
    }

    // MARK: - Avatar (20px)

    private func compactAvatar(for comment: Comment) -> some View {
        ZStack {
            Circle()
                .fill(comment.authorKind == .agent
                      ? palette.accentColor.opacity(0.15)
                      : palette.secondaryTextColor.opacity(0.12))
            Image(systemName: comment.authorKind == .agent ? "sparkle" : "person.fill")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(comment.authorKind == .agent ? palette.accentColor : palette.secondaryTextColor)
        }
        .frame(width: 20, height: 20)
    }

    // MARK: - Body

    @ViewBuilder
    private func bodyText(_ raw: String) -> some View {
        let attributed = (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
        Text(attributed)
            .font(.system(size: 13))
            .foregroundStyle(palette.primaryTextColor)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

    private func displayName(for comment: Comment) -> String {
        if let label = comment.authorLabel, !label.isEmpty { return label }
        return comment.authorKind == .agent ? AppStrings.Comments.agentAnonymous : AppStrings.Comments.userAnonymous
    }

    private var threadBackground: Color {
        if isSelected { return palette.accentColor.opacity(0.06) }
        return palette.canvasSecondaryBackgroundColor.opacity(0.3)
    }

    private var threadBorderColor: Color {
        if thread.root.isResolved { return palette.tertiaryTextColor.opacity(0.2) }
        if thread.root.isStale { return Color.orange.opacity(0.4) }
        if isSelected { return palette.accentColor.opacity(0.6) }
        return palette.tertiaryTextColor.opacity(0.15)
    }

    private func relativeTime(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Action Pill Button

/// Small pill-shaped button with hover highlight and press scale effect.
private struct ActionPill: View {
    let label: String
    let icon: String
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(tint.opacity(isPressed ? 0.18 : (isHovered ? 0.10 : 0)))
                )
                .scaleEffect(isPressed ? 0.94 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.easeOut(duration: 0.08), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
