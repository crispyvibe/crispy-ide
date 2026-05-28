import SwiftUI

/// F049-R15: workspace-wide comments view. Shows all comments across the
/// active vibespace, grouped by surface kind (Files / Browsers), with
/// status filtering and click-to-navigate. The filter/group/sort pipeline
/// lives in `CrossFileCommentsViewModel` — this view is render-only.
@MainActor
struct CrossFileCommentsView: View {
    @Environment(\.appThemePalette) private var palette
    @StateObject private var viewModel: CrossFileCommentsViewModel

    /// Called when the user clicks a thread on a file surface.
    let onNavigateFile: (String, String) -> Void  // (filePath, threadID)
    /// Called when the user clicks a thread on a browser surface.
    let onNavigateBrowser: (String, String) -> Void  // (canonical URL, threadID)

    init(
        store: VibeSpaceCommentStore,
        onNavigateFile: @escaping (String, String) -> Void,
        onNavigateBrowser: @escaping (String, String) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: CrossFileCommentsViewModel(store: store))
        self.onNavigateFile = onNavigateFile
        self.onNavigateBrowser = onNavigateBrowser
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.sections.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.sections) { section in
                            sectionHeader(section)
                            ForEach(section.groups) { group in
                                surfaceSection(for: group)
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .background(palette.canvasBackgroundColor)
        .accessibilityIdentifier("comments.cross-file")
        .task { await viewModel.refresh() }
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(spacing: 12) {
            Text(AppStrings.Comments.crossFileTitle)
                .font(.title3)
                .foregroundStyle(palette.primaryTextColor)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.secondaryTextColor)
                TextField(AppStrings.Comments.searchPlaceholder, text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 220)
                    .onExitCommand { viewModel.searchQuery = "" }
            }
            Picker("", selection: $viewModel.statusFilter) {
                Text(AppStrings.Comments.filterActive).tag(CommentStatusFilter.active)
                Text(AppStrings.Comments.filterResolved).tag(CommentStatusFilter.resolved)
                Text(AppStrings.Comments.filterStale).tag(CommentStatusFilter.stale)
                Text(AppStrings.Comments.filterAll).tag(CommentStatusFilter.all)
            }
            .pickerStyle(.menu)
            .frame(width: 100)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func sectionHeader(_ section: CrossFileCommentsViewModel.Section) -> some View {
        HStack(spacing: 6) {
            Image(systemName: section.surfaceKind == .browser ? "globe" : "folder")
                .foregroundStyle(palette.secondaryTextColor)
            Text(section.title)
                .font(.headline)
                .foregroundStyle(palette.secondaryTextColor)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func surfaceSection(for group: CrossFileCommentsViewModel.FileGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: group.surfaceKind == .browser ? "link" : "doc.text")
                    .foregroundStyle(palette.secondaryTextColor)
                Text(group.fileLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(group.threads.count)")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryTextColor)
            }
            ForEach(group.threads) { thread in
                row(for: thread, group: group)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func row(for thread: CommentThread, group: CrossFileCommentsViewModel.FileGroup) -> some View {
        Button(action: {
            switch group.surfaceKind {
            case .file: onNavigateFile(group.filePath, thread.id)
            case .browser: onNavigateBrowser(group.filePath, thread.id)
            }
        }) {
            HStack(alignment: .top, spacing: 8) {
                statusGlyph(for: thread)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(thread.root.authorLabel ?? defaultLabel(for: thread.root))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryTextColor)
                        if group.surfaceKind == .file {
                            Text(AppStrings.Comments.lineLabel(thread.root.anchor.startLine))
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryTextColor)
                        }
                        if thread.replies.count > 0 {
                            Text(String(format: AppStrings.Comments.repliesCount, thread.replies.count))
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryTextColor)
                        }
                    }
                    Text(thread.root.body)
                        .font(.body)
                        .lineLimit(2)
                        .foregroundStyle(palette.primaryTextColor)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryTextColor)
            }
            .contentShape(Rectangle())
            .padding(8)
            .background(palette.canvasSecondaryBackgroundColor.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(palette.tertiaryTextColor.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("comments.cross-file.row.\(thread.id)")
    }

    @ViewBuilder
    private func statusGlyph(for thread: CommentThread) -> some View {
        switch thread.status {
        case .active:
            Circle().fill(thread.root.authorKind == .agent ? palette.accentColor : Color.blue).frame(width: 8, height: 8)
        case .resolved:
            Image(systemName: "checkmark.circle").foregroundStyle(.green)
        case .stale:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .all:
            EmptyView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left").font(.largeTitle).foregroundStyle(palette.tertiaryTextColor)
            Text(AppStrings.Comments.crossFileEmptyTitle)
                .font(.headline)
                .foregroundStyle(palette.secondaryTextColor)
            Text(AppStrings.Comments.crossFileEmptyBody)
                .font(.caption)
                .foregroundStyle(palette.tertiaryTextColor)
                .multilineTextAlignment(.center)
        }
    }

    private func defaultLabel(for c: Comment) -> String {
        c.authorKind == .agent
            ? AppStrings.Comments.agentAnonymous
            : AppStrings.Comments.userAnonymous
    }
}
