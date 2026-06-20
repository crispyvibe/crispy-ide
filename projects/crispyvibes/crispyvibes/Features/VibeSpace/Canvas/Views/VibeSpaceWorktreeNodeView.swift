import AppKit
import SwiftUI

/// A per-project node for the unified sidebar (F056): a project header that
/// expands to the project's own Files / Source Control / Conversations
/// sub-sections. Reuses `ProjectFileTreeView`, the matching repository view
/// model's changed files, and the project's conversation threads.
struct VibeSpaceWorktreeNodeView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var theme
    @Environment(\.crispyvibesUIScale) private var scale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let project: AnyProjectSession
    let branch: String?
    let indent: Bool
    /// SF Symbol for the node-type glyph. Lets the sidebar distinguish a
    /// repository root (`shippingbox.fill`), a worktree child
    /// (`arrow.triangle.branch`), and a standalone project folder (`folder.fill`)
    /// so they don't all read as the same thing.
    let typeIcon: String?
    /// Whether to show the branch name as a secondary label (suppressed for
    /// non-worktree subdirectory projects, where the repo branch is misleading).
    let showsBranch: Bool
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
        typeIcon: String? = nil,
        showsBranch: Bool = true,
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
        self.typeIcon = typeIcon
        self.showsBranch = showsBranch
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
        if code == "??" { return ("?", palette.gitAddedStatusColor) }   // untracked, distinct from added "A"
        if code.contains("U") { return ("U", palette.gitConflictStatusColor) }
        if code.contains("R") || code.contains("C") { return ("R", palette.gitRenamedStatusColor) }
        if code.contains("D") { return ("D", palette.gitDeletedStatusColor) }
        if code.contains("A") { return ("A", palette.gitAddedStatusColor) }
        if code.contains("M") { return ("M", palette.gitModifiedStatusColor) }
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        return (trimmed.isEmpty ? "?" : trimmed, palette.secondaryTextColor)
    }

    private var resolvedTypeIcon: String {
        typeIcon ?? (indent ? "arrow.triangle.branch" : "shippingbox.fill")
    }

    /// Selection fill — stronger than before, and fully opaque under Reduce
    /// Transparency so the focused row never depends on a faint translucent tint.
    private var selectionFill: Color {
        guard isFocused else { return .clear }
        return reduceTransparency
            ? palette.selectionBackgroundColor
            : palette.selectionBackgroundColor.opacity(0.45)
    }

    private var header: some View {
        HStack(spacing: scale.spacing(8)) {
            Button { toggleExpanded() } label: {
                HStack(spacing: scale.spacing(8)) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppTypographyTokens.scaledSystem(10, weight: .semibold))
                        .foregroundStyle(palette.secondaryTextColor)
                        .frame(width: scale.iconSize(12))
                    Image(systemName: resolvedTypeIcon)
                        // Constrain to the title's cap height so the type glyph
                        // reads as a peer of the label, not louder than it.
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(accentColor)
                    Text(indent ? (branch ?? project.title) : project.title)
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(palette.primaryTextColor)
                        .lineLimit(1)
                    if !indent, showsBranch, let branch {
                        Text(branch)
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.secondaryTextColor)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.Worktree.collapseExpandLabel(indent ? (branch ?? project.title) : project.title))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? AppStrings.Worktree.expandedHint : AppStrings.Worktree.collapsedHint)

            Spacer(minLength: scale.spacing(6))

            createMenu

            // Consistent toggle set on every node — Files / Changes / Chats —
            // so position is predictable; empty Changes/Chats dim but stay
            // reachable (this is the only path to a worktree's first chat).
            viewToggle(.files, system: "doc.text", count: nil,
                       tint: palette.secondaryTextColor,
                       label: AppStrings.Worktree.showFiles, value: nil)
            viewToggle(.changes, system: "plusminus", count: changeCount > 0 ? changeCount : nil,
                       tint: changeCount > 0 ? palette.gitModifiedStatusColor : palette.secondaryTextColor.opacity(0.5),
                       label: AppStrings.Worktree.showChanges(changeCount),
                       value: AppStrings.Worktree.changedFilesValue(changeCount))
            viewToggle(.chats, system: "bubble.left", count: threads.isEmpty ? nil : threads.count,
                       tint: threads.isEmpty ? palette.secondaryTextColor.opacity(0.5) : palette.secondaryTextColor,
                       label: AppStrings.Worktree.showConversations(threads.count), value: nil)
        }
        .padding(.horizontal, scale.spacing(10))
        .padding(.vertical, scale.spacing(8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.radius(10), style: .continuous)
                .fill(selectionFill)
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
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
                // Distinct from the chat "+": a doc-badge glyph marks this as a
                // file/folder creation menu, not an immediate add.
                Image(systemName: "doc.badge.plus").font(AppTypographyTokens.scaledIcon(11))
                    .frame(width: scale.iconSize(22), height: scale.iconSize(22))
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .foregroundStyle(palette.secondaryTextColor)
            .help(AppStrings.Worktree.newFileOrFolderHelp)
            .accessibilityLabel(AppStrings.Worktree.newFileOrFolderHelp)
        } else if activeTab == .chats {
            Button { onNewChat() } label: {
                Image(systemName: "plus.bubble").font(AppTypographyTokens.scaledIcon(11))
                    .frame(width: scale.iconSize(22), height: scale.iconSize(22))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondaryTextColor)
            .help(AppStrings.Worktree.newAgentChat)
            .accessibilityLabel(AppStrings.Worktree.newAgentChat)
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

    private func viewToggle(
        _ view: ProjectPaneTab,
        system: String,
        count: Int?,
        tint: Color,
        label: String,
        value: String?
    ) -> some View {
        let isActive = isExpanded && activeTab == view
        return Button { selectView(view) } label: {
            HStack(spacing: 2) {
                Image(systemName: system).font(AppTypographyTokens.scaledIcon(10))
                if let count { Text("\(count)").font(AppTypographyTokens.caption2MonospacedDigit) }
            }
            .padding(.horizontal, scale.spacing(6))
            .frame(minWidth: scale.iconSize(24), minHeight: scale.iconSize(24))
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isActive ? accentColor.opacity(0.28) : Color.clear)
            )
            .foregroundStyle(isActive ? palette.primaryTextColor : tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
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
            Button { onNewChat() } label: {
                HStack(spacing: scale.spacing(6)) {
                    Image(systemName: "plus.bubble").font(AppTypographyTokens.scaledIcon(11))
                    Text(AppStrings.Worktree.newAgentChat).font(AppTypographyTokens.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(accentColor)
                .padding(.horizontal, scale.spacing(12))
                .padding(.vertical, scale.spacing(5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.Worktree.newAgentChat)
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

