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
            searchAndFilterRow
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
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
