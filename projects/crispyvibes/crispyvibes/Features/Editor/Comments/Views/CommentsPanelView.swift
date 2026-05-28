import AppKit
import SwiftUI

/// F049-R06: side panel docked to the right edge of the file viewer pane.
/// Per-pane state via `CommentsPanelStore`. Bidirectional linking with the
/// editor highlight and gutter through `selectedThreadID`.
@MainActor
struct CommentsPanelView: View {
    @Environment(\.appThemePalette) private var palette
    @ObservedObject var store: VibeSpaceCommentStore
    @ObservedObject var panel: CommentsPanelStore

    /// Path / canonical URL of the surface this panel is anchored to.
    let filePath: String

    /// Surface kind — `.file` (default) for file editors, `.browser` for
    /// browser-window panes. Forwarded to write operations so the
    /// persistence helper records the correct discriminator.
    var surfaceKind: CommentSurfaceKind = .file

    var body: some View {
        // Compute the filtered list once and reuse — avoids re-running
        // the filter on every body sub-view evaluation.
        let visible = panel.filteredThreads(store.threads(forFile: filePath))
        let activeCount = visible.filter { $0.status == .active }.count

        return VStack(spacing: 0) {
            header(visibleCount: visible.count, activeCount: activeCount)
            Divider()
            bulkActionsRow(threads: store.threads(forFile: filePath))
            Divider()
            searchAndFilterRow
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if let pendingAnchor = panel.pendingComposerAnchor {
                        composerCard(anchor: pendingAnchor)
                    }
                    ForEach(visible) { thread in
                        threadRow(thread)
                    }
                    if visible.isEmpty && panel.pendingComposerAnchor == nil {
                        emptyState
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error = store.lastErrorMessage {
                errorBanner(error)
            }
        }
        .background(palette.canvasBackgroundColor)
        .accessibilityIdentifier("comments.panel")
    }

    // MARK: - Sub-views

    private func header(visibleCount: Int, activeCount: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "quote.bubble")
                .foregroundStyle(palette.secondaryTextColor)
            Text(AppStrings.Comments.panelTitle)
                .font(.headline)
                .foregroundStyle(palette.primaryTextColor)
            Spacer()
            Text(AppStrings.Comments.threadCountLabel(active: activeCount, total: visibleCount))
                .font(.caption)
                .foregroundStyle(palette.secondaryTextColor)
            Button(action: { panel.startNewComment() }) {
                Image(systemName: "plus")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help(AppStrings.Comments.toolbarAddHelp)
            .accessibilityIdentifier("comments.panel.add")
            Button(action: { panel.close() }) {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help(AppStrings.Comments.closePanel)
            .accessibilityIdentifier("comments.panel.close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.canvasSecondaryBackgroundColor)
    }

    private var searchAndFilterRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.secondaryTextColor)
            TextField(AppStrings.Comments.searchPlaceholder, text: $panel.searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(palette.primaryTextColor)
                .accessibilityIdentifier("comments.panel.search")
                .onExitCommand { panel.searchQuery = "" }
            Picker("", selection: $panel.statusFilter) {
                Text(AppStrings.Comments.filterActive).tag(CommentStatusFilter.active)
                Text(AppStrings.Comments.filterResolved).tag(CommentStatusFilter.resolved)
                Text(AppStrings.Comments.filterStale).tag(CommentStatusFilter.stale)
                Text(AppStrings.Comments.filterAll).tag(CommentStatusFilter.all)
            }
            .pickerStyle(.menu)
            .frame(width: 100)
            .accessibilityIdentifier("comments.panel.filter")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Bulk Actions

    private func bulkActionsRow(threads: [CommentThread]) -> some View {
        HStack(spacing: 6) {
            Menu {
                Button("Copy All") {
                    copyToClipboard(threads: threads)
                }
                Button("Copy Unresolved") {
                    copyToClipboard(threads: threads.filter { $0.status != .resolved })
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Button("Delete Resolved", role: .destructive) {
                    let resolved = threads.filter { $0.status == .resolved }
                    Task { @MainActor in
                        for thread in resolved {
                            await panel.deleteThread(thread, store: store)
                        }
                    }
                }
                Button("Delete All", role: .destructive) {
                    Task { @MainActor in
                        for thread in threads {
                            await panel.deleteThread(thread, store: store)
                        }
                    }
                }
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func copyToClipboard(threads: [CommentThread]) {
        guard !threads.isEmpty else { return }
        var lines: [String] = []
        lines.append("# Comments: \(filePath)")
        lines.append("")

        for (threadIdx, thread) in threads.enumerated() {
            let root = thread.root
            let heading: String
            if root.surfaceKind == .browser {
                heading = "#\(threadIdx + 1) \(root.filePath)"
                if let selector = root.anchor.domSelector {
                    lines.append("## \(heading)")
                    lines.append("Selector: `\(selector)`")
                } else {
                    lines.append("## \(heading)")
                }
            } else {
                let loc: String
                if root.anchor.startLine == root.anchor.endLine {
                    loc = "L\(root.anchor.startLine)"
                } else {
                    loc = "L\(root.anchor.startLine)-\(root.anchor.endLine)"
                }
                let status = root.isResolved ? " [RESOLVED]" : (root.isStale ? " [STALE]" : "")
                lines.append("## #\(threadIdx + 1) \(loc)\(status)")
            }

            if !root.anchor.anchorText.isEmpty {
                lines.append("> \(root.anchor.anchorText.prefix(300))")
            }

            let author = root.authorLabel ?? (root.authorKind == .agent ? "Agent" : "Comment")
            lines.append("- \(author): \(root.body)")

            for reply in thread.replies {
                let replyAuthor = reply.authorLabel ?? (reply.authorKind == .agent ? "Agent" : "Reply")
                lines.append("  - \(replyAuthor): \(reply.body)")
            }
            lines.append("")
        }

        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f
    }()

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.title)
                .foregroundStyle(palette.tertiaryTextColor)
            Text(AppStrings.Comments.emptyStateTitle)
                .font(.headline)
                .foregroundStyle(palette.secondaryTextColor)
            Text(AppStrings.Comments.emptyStateBody)
                .font(.caption)
                .foregroundStyle(palette.tertiaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .accessibilityIdentifier("comments.panel.empty")
    }

    private func threadRow(_ thread: CommentThread) -> some View {
        CommentThreadView(
            panel: panel,
            thread: thread,
            isSelected: panel.selectedThreadID == thread.id,
            onSelect: { panel.select(threadID: thread.id) },
            onReply: { body in await panel.submitReply(body: body, thread: thread, store: store) },
            onEdit: { id, body in await panel.editComment(id: id, body: body, store: store) },
            onResolve: { await panel.resolveThread(thread, store: store) },
            onDelete: { await panel.deleteThread(thread, store: store) }
        )
    }

    private func composerCard(anchor: CommentAnchor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.Comments.composerHeading(forLine: anchor.startLine))
                .font(.caption)
                .foregroundStyle(palette.secondaryTextColor)
            CommentComposerView(
                placeholder: AppStrings.Comments.composerPlaceholder,
                onSubmit: { body in
                    await panel.submitNewComment(
                        body: body,
                        filePath: filePath,
                        anchor: anchor,
                        store: store,
                        surfaceKind: surfaceKind
                    )
                },
                onCancel: { panel.cancelComposer() }
            )
        }
        .padding(8)
        .background(palette.accentColor.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(palette.accentColor.opacity(0.4), lineWidth: 1)
        )
        .accessibilityIdentifier("comments.panel.composer")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(palette.primaryTextColor)
            Spacer()
            Button(AppStrings.Common.close) {
                store.clearLastError()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(8)
        .background(Color.orange.opacity(0.15))
    }
}
