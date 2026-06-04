import AppKit
import SwiftUI

/// A per-project node for the unified sidebar (F053): a project header that
/// expands to the project's own Files / Source Control / Conversations
/// sub-sections. Reuses `ProjectFileTreeView`, the matching repository view
/// model's changed files, and the project's conversation threads.
struct VibeSpaceWorktreeNodeView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var theme

    let project: AnyProjectSession
    let branch: String?
    let indent: Bool
    let isFocused: Bool
    let accentColor: Color
    let projectRootURLs: [URL]
    @ObservedObject var sourceControl: VibeSpaceSourceControlViewModel
    let threads: [ConversationThreadSummary]
    let onProjectAction: (FileTreeAction) -> Void
    let onProjectTransferDrop: ([ExplorerItemTransferPlan]) -> Bool
    let onOpenDiff: (VibeSpaceSourceControlRepositoryViewModel, VibeSpaceSourceControlStatusItem) -> Void
    let onOpenThread: (ConversationThreadSummary) -> Void
    let canDelete: Bool
    let onDeleteWorktree: () -> Void
    let onNewChat: () -> Void

    @State private var activeTab: ProjectPaneTab = .files
    @State private var isExpanded: Bool

    enum ProjectPaneTab: Hashable { case files, changes, chats }

    init(
        project: AnyProjectSession,
        branch: String?,
        indent: Bool = false,
        isFocused: Bool,
        accentColor: Color,
        projectRootURLs: [URL],
        sourceControl: VibeSpaceSourceControlViewModel,
        threads: [ConversationThreadSummary],
        onProjectAction: @escaping (FileTreeAction) -> Void,
        onProjectTransferDrop: @escaping ([ExplorerItemTransferPlan]) -> Bool,
        onOpenDiff: @escaping (VibeSpaceSourceControlRepositoryViewModel, VibeSpaceSourceControlStatusItem) -> Void,
        onOpenThread: @escaping (ConversationThreadSummary) -> Void,
        canDelete: Bool = false,
        onDeleteWorktree: @escaping () -> Void = {},
        onNewChat: @escaping () -> Void = {}
    ) {
        self.project = project
        self.branch = branch
        self.indent = indent
        self.isFocused = isFocused
        self.accentColor = accentColor
        self.projectRootURLs = projectRootURLs
        self.sourceControl = sourceControl
        self.threads = threads
        self.onProjectAction = onProjectAction
        self.onProjectTransferDrop = onProjectTransferDrop
        self.onOpenDiff = onOpenDiff
        self.onOpenThread = onOpenThread
        self.canDelete = canDelete
        self.onDeleteWorktree = onDeleteWorktree
        self.onNewChat = onNewChat
        _isExpanded = State(initialValue: isFocused)
    }

    private var repository: VibeSpaceSourceControlRepositoryViewModel? {
        let path = project.rootURL.standardizedFileURL.path
        return sourceControl.repositories.first {
            $0.repositoryRootURL.standardizedFileURL.path == path
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if indent {
                header.contextMenu { worktreeContextMenu }
            } else {
                header
            }

            if isExpanded {
                switch activeTab {
                case .files:
                    ProjectFileTreeView(
                        viewModel: project.folderExplorer,
                        projectRootURLs: projectRootURLs,
                        onAction: onProjectAction,
                        onTransferDrop: onProjectTransferDrop
                    )
                    .padding(.leading, 4)
                case .changes:
                    changesList
                case .chats:
                    chatsList
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("vibespace.sidebar.unified.project.\(project.id.uuidString)")
        .onAppear {
            if isExpanded {
                project.activate()
                project.ensureExplorerLoaded()
            }
        }
    }

    private var changeCount: Int { visibleChanges.count }

    @ViewBuilder
    private var worktreeContextMenu: some View {
        Button(AppStrings.Worktree.closeWorktree) {
            NotificationCenter.default.post(
                name: .removeProjectRequested,
                object: nil,
                userInfo: [AppCommandUserInfoKey.projectID: project.id]
            )
        }
        if canDelete {
            Button(AppStrings.Worktree.deleteWorktree, role: .destructive) { onDeleteWorktree() }
        }
    }

    private func toggleExpanded() {
        if !isExpanded { project.activate(); project.ensureExplorerLoaded() }
        withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
    }

    /// Expand (if needed) and switch the body to the chosen view. Files is the
    /// default body, so the header view-toggles act like lightweight tabs
    /// without a dedicated tab-strip row.
    private func selectView(_ view: ProjectPaneTab) {
        if !isExpanded {
            project.activate()
            project.ensureExplorerLoaded()
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded = true }
        }
        activeTab = view
    }

    /// OS / tooling junk that never makes sense to surface as a change.
    private static let ignoredChangeFileNames: Set<String> = [".DS_Store", "Thumbs.db", ".localized"]

    /// Meaningful changes only, ordered so modified/deleted/renamed surface
    /// above newly added/untracked files.
    private var visibleChanges: [VibeSpaceSourceControlStatusItem] {
        (repository?.statusItems ?? [])
            .filter {
                !Self.ignoredChangeFileNames.contains($0.fileName)
                    && !$0.relativePath.contains(".ipynb_checkpoints/")
            }
            .sorted {
                let r0 = changeRank($0), r1 = changeRank($1)
                if r0 != r1 { return r0 < r1 }
                return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
            }
    }

    private func changeRank(_ item: VibeSpaceSourceControlStatusItem) -> Int {
        if item.code.contains("M") { return 0 }
        if item.code.contains("D") { return 1 }
        if item.code.contains("R") || item.code.contains("C") { return 2 }
        return 3
    }

    /// Friendly colored badge mirroring the classic Source Control view.
    private func changeBadge(_ code: String) -> (text: String, color: Color) {
        if code == "??" { return ("A", palette.gitAddedStatusColor) }
        if code.contains("U") { return ("U", palette.gitConflictStatusColor) }
        if code.contains("R") || code.contains("C") { return ("R", palette.gitRenamedStatusColor) }
        if code.contains("D") { return ("D", palette.gitDeletedStatusColor) }
        if code.contains("A") { return ("A", palette.gitAddedStatusColor) }
        if code.contains("M") { return ("M", palette.gitModifiedStatusColor) }
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        return (trimmed.isEmpty ? "?" : trimmed, palette.secondaryTextColor)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { toggleExpanded() } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppTypographyTokens.scaledSystem(10, weight: .semibold))
                        .foregroundStyle(palette.secondaryTextColor)
                    Image(systemName: indent ? "arrow.triangle.branch" : "shippingbox.fill")
                        .foregroundStyle(accentColor)
                    Text(indent ? (branch ?? project.title) : project.title)
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(palette.primaryTextColor)
                        .lineLimit(1)
                    if !indent, let branch {
                        Text(branch)
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.secondaryTextColor)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 6)

            createMenu

            viewToggle(.files, system: "doc.text", count: nil, tint: palette.secondaryTextColor)
            if changeCount > 0 {
                viewToggle(.changes, system: "plusminus", count: changeCount, tint: palette.gitModifiedStatusColor)
            }
            if !threads.isEmpty {
                viewToggle(.chats, system: "bubble.left", count: threads.count, tint: palette.secondaryTextColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.radius(10), style: .continuous)
                .fill(isFocused ? palette.selectionBackgroundColor.opacity(0.30) : Color.clear)
        )
    }

    @ViewBuilder
    private var createMenu: some View {
        if activeTab == .files {
            Menu {
                Button(AppStrings.Worktree.newFile) { createInFiles(folder: false) }
                Button(AppStrings.Worktree.newFolder) { createInFiles(folder: true) }
                Divider()
                Button(AppStrings.Worktree.refresh) { project.folderExplorer.refreshTree(trigger: .manual) }
            } label: {
                Image(systemName: "plus").font(AppTypographyTokens.scaledIcon(10))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(palette.secondaryTextColor)
            .help(AppStrings.Worktree.newFileOrFolderHelp)
        } else if activeTab == .chats {
            Button { onNewChat() } label: {
                Image(systemName: "plus").font(AppTypographyTokens.scaledIcon(10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondaryTextColor)
            .help(AppStrings.Worktree.newAgentChat)
        }
    }

    private func createInFiles(folder: Bool) {
        selectView(.files)
        if folder {
            project.folderExplorer.createNewFolderAtSelection()
        } else {
            project.folderExplorer.createNewFileAtSelection()
        }
    }

    private func viewToggle(_ view: ProjectPaneTab, system: String, count: Int?, tint: Color) -> some View {
        let isActive = isExpanded && activeTab == view
        return Button { selectView(view) } label: {
            HStack(spacing: 2) {
                Image(systemName: system).font(AppTypographyTokens.scaledIcon(10))
                if let count { Text("\(count)").font(AppTypographyTokens.caption2MonospacedDigit) }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isActive ? accentColor.opacity(0.28) : Color.clear)
            )
            .foregroundStyle(isActive ? palette.primaryTextColor : tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var changesList: some View {
        if repository == nil {
            emptyRow(AppStrings.Worktree.notAGitRepository)
        } else if visibleChanges.isEmpty {
            emptyRow(AppStrings.Worktree.noChanges)
        } else if let repo = repository {
            ForEach(visibleChanges) { item in
                Button { onOpenDiff(repo, item) } label: {
                    HStack(spacing: 8) {
                        let badge = changeBadge(item.code)
                        Text(badge.text)
                            .font(AppTypographyTokens.caption2Semibold)
                            .foregroundStyle(badge.color)
                            .frame(width: 14, alignment: .center)
                        Text(item.fileName)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(palette.primaryTextColor)
                            .lineLimit(1)
                        if let parent = item.parentRelativePath {
                            Text(parent)
                                .font(AppTypographyTokens.caption2)
                                .foregroundStyle(palette.secondaryTextColor)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var chatsList: some View {
        if threads.isEmpty {
            emptyRow(AppStrings.Worktree.noConversations)
        } else {
            ForEach(threads) { thread in
                Button { onOpenThread(thread) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left")
                            .font(AppTypographyTokens.scaledIcon(11))
                            .foregroundStyle(palette.secondaryTextColor)
                        Text(thread.title.isEmpty ? AppStrings.Worktree.untitledThread : thread.title)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(palette.primaryTextColor)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(thread.relativeTime)
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.secondaryTextColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(AppTypographyTokens.caption)
            .foregroundStyle(palette.secondaryTextColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

