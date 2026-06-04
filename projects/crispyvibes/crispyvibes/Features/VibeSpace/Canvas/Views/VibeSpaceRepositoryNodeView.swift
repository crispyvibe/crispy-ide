import AppKit
import SwiftUI

/// A repository node for the unified sidebar (F055/F056): clubs the worktrees
/// of one git repo. Each worktree is rendered as its own collapsible
/// `VibeSpaceWorktreeNodeView` child.
struct VibeSpaceRepositoryNodeView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var theme

    let title: String
    let worktrees: [AnyProjectSession]
    let otherWorktrees: [WorktreeEntry]
    let branchByPath: [String: String?]
    let focusedProjectID: UUID?
    let accentColor: Color
    let projectRootURLs: [URL]
    @ObservedObject var sourceControl: VibeSpaceSourceControlViewModel
    let threadsByProject: [String: [ConversationThreadSummary]]
    let onProjectAction: (AnyProjectSession, FileTreeAction) -> Void
    let onProjectTransferDrop: (AnyProjectSession, [ExplorerItemTransferPlan]) -> Bool
    let onOpenDiff: (VibeSpaceSourceControlRepositoryViewModel, VibeSpaceSourceControlStatusItem) -> Void
    let onOpenThread: (ConversationThreadSummary) -> Void
    let onOpenWorktree: (String) -> Void
    let primaryPath: String?
    let onDeleteWorktree: (String) -> Void
    let onNewChat: (AnyProjectSession) -> Void
    let onNewWorktree: () -> Void

    @State private var isExpanded = true
    @State private var showOtherWorktrees = false

    init(
        title: String,
        worktrees: [AnyProjectSession],
        otherWorktrees: [WorktreeEntry],
        branchByPath: [String: String?],
        primaryPath: String?,
        focusedProjectID: UUID?,
        accentColor: Color,
        projectRootURLs: [URL],
        sourceControl: VibeSpaceSourceControlViewModel,
        threadsByProject: [String: [ConversationThreadSummary]],
        onProjectAction: @escaping (AnyProjectSession, FileTreeAction) -> Void,
        onProjectTransferDrop: @escaping (AnyProjectSession, [ExplorerItemTransferPlan]) -> Bool,
        onOpenDiff: @escaping (VibeSpaceSourceControlRepositoryViewModel, VibeSpaceSourceControlStatusItem) -> Void,
        onOpenThread: @escaping (ConversationThreadSummary) -> Void,
        onOpenWorktree: @escaping (String) -> Void,
        onDeleteWorktree: @escaping (String) -> Void,
        onNewChat: @escaping (AnyProjectSession) -> Void,
        onNewWorktree: @escaping () -> Void
    ) {
        self.title = title
        self.worktrees = worktrees
        self.otherWorktrees = otherWorktrees
        self.branchByPath = branchByPath
        self.primaryPath = primaryPath
        self.focusedProjectID = focusedProjectID
        self.accentColor = accentColor
        self.projectRootURLs = projectRootURLs
        self.sourceControl = sourceControl
        self.threadsByProject = threadsByProject
        self.onProjectAction = onProjectAction
        self.onProjectTransferDrop = onProjectTransferDrop
        self.onOpenDiff = onOpenDiff
        self.onOpenThread = onOpenThread
        self.onOpenWorktree = onOpenWorktree
        self.onDeleteWorktree = onDeleteWorktree
        self.onNewChat = onNewChat
        self.onNewWorktree = onNewWorktree
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header

            if isExpanded {
                ForEach(worktrees) { worktree in
                    VibeSpaceWorktreeNodeView(
                        project: worktree,
                        branch: branchByPath[worktree.projectIdentifier] ?? nil,
                        indent: true,
                        isFocused: worktree.id == focusedProjectID,
                        accentColor: accentColor,
                        projectRootURLs: projectRootURLs,
                        sourceControl: sourceControl,
                        threads: threadsByProject[worktree.projectIdentifier] ?? [],
                        onProjectAction: { onProjectAction(worktree, $0) },
                        onProjectTransferDrop: { onProjectTransferDrop(worktree, $0) },
                        onOpenDiff: onOpenDiff,
                        onOpenThread: onOpenThread,
                        canDelete: worktree.projectIdentifier != primaryPath,
                        onDeleteWorktree: { onDeleteWorktree(worktree.projectIdentifier) },
                        onNewChat: { onNewChat(worktree) }
                    )
                    .padding(.leading, 14)
                }

                if !otherWorktrees.isEmpty {
                    otherWorktreesSection
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("vibespace.sidebar.unified.repo.\(worktrees[0].id.uuidString)")
    }

    @ViewBuilder
    private var otherWorktreesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showOtherWorktrees.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showOtherWorktrees ? "chevron.down" : "chevron.right")
                        .font(AppTypographyTokens.scaledSystem(9, weight: .semibold))
                        .foregroundStyle(palette.secondaryTextColor)
                    Text(AppStrings.Worktree.otherWorktrees(otherWorktrees.count))
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showOtherWorktrees {
                ForEach(otherWorktrees) { worktree in
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(AppTypographyTokens.scaledIcon(10))
                            .foregroundStyle(palette.secondaryTextColor.opacity(0.7))
                        Text(worktree.displayName)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(palette.secondaryTextColor)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Button { onOpenWorktree(worktree.path) } label: {
                            Text(AppStrings.Worktree.open)
                                .font(AppTypographyTokens.caption2Semibold)
                                .foregroundStyle(accentColor)
                        }
                        .buttonStyle(.plain)
                        .help(AppStrings.Worktree.openAsProjectHelp)
                        .accessibilityIdentifier("vibespace.sidebar.unified.open-worktree")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button(AppStrings.Worktree.openAsProject) { onOpenWorktree(worktree.path) }
                        if worktree.path != primaryPath {
                            Button(AppStrings.Worktree.deleteWorktree, role: .destructive) { onDeleteWorktree(worktree.path) }
                        }
                    }
                }
            }
        }
        .padding(.leading, 14)
    }

    // Collapsible "section fence" — folds up the whole repo, styled lighter
    // than a tree row so the hierarchy reads flat.
    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppTypographyTokens.scaledSystem(10, weight: .semibold))
                        .foregroundStyle(palette.secondaryTextColor)
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(accentColor)
                    Text(title)
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(palette.primaryTextColor)
                        .lineLimit(1)
                    Text(AppStrings.Worktree.worktreeCount(worktrees.count + otherWorktrees.count))
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { onNewWorktree() } label: {
                Image(systemName: "plus").font(AppTypographyTokens.scaledIcon(10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondaryTextColor)
            .help(AppStrings.Worktree.newWorktree)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

