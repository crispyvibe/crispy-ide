import SwiftUI

struct VibeSpaceSourceControlView: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var viewModel: VibeSpaceSourceControlViewModel
    let onCloneRequested: () -> Void
    let onOpenDiff: (VibeSpaceSourceControlRepositoryViewModel, VibeSpaceSourceControlStatusItem) -> Void

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                VStack(spacing: 10) {
                    ProgressView()
                    Text(AppStrings.SourceControl.loading)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("vibespace.source-control.loading")

            case .gitUnavailable:
                ContentUnavailableView(
                    AppStrings.SourceControl.gitUnavailable,
                    systemImage: "exclamationmark.triangle",
                    description: Text(viewModel.message ?? AppStrings.SourceControl.gitUnavailableDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("vibespace.source-control.unavailable")

            case .error:
                VStack(spacing: 10) {
                    ContentUnavailableView(
                        AppStrings.SourceControl.unavailable,
                        systemImage: "xmark.octagon",
                        description: Text(viewModel.message ?? "Unable to discover repositories.")
                    )
                    Button(AppStrings.Common.retry) {
                        viewModel.refresh()
                    }
                    .buttonStyle(.crispyvibesText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("vibespace.source-control.error")

            case .ready:
                readyContent
            }
        }
        .background(appThemePalette.canvasBackgroundColor)
        .crispyvibesContainerBorder(opacity: 0.6)
    }

    private var readyContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.repositories.isEmpty {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            AppStrings.SourceControl.noReposFound,
                            systemImage: "arrow.triangle.branch",
                            description: Text(AppStrings.SourceControl.noReposDescription)
                        )
                        Button(AppStrings.SourceControl.cloneRepository, action: onCloneRequested)
                            .buttonStyle(.crispyvibesPrimary)
                            .accessibilityIdentifier("vibespace.source-control.clone")
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .accessibilityIdentifier("vibespace.source-control.empty")
                } else {
                    ForEach(viewModel.repositories) { repository in
                        VibeSpaceSourceControlRepositorySectionView(
                            repository: repository,
                            onOpenDiff: onOpenDiff
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .accessibilityIdentifier("vibespace.source-control.ready")
    }
}

private struct VibeSpaceSourceControlRepositorySectionView: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var repository: VibeSpaceSourceControlRepositoryViewModel
    let onOpenDiff: (VibeSpaceSourceControlRepositoryViewModel, VibeSpaceSourceControlStatusItem) -> Void
    @AppStorage(AppPreferences.vibespaceSourceControlLayoutKey) private var layoutModeRaw = SourceControlSectionLayoutMode.tree.rawValue
    @State private var isDiscardAllAlertPresented = false
    @State private var stagedExpanded = true
    @State private var changeExpanded = true
    @State private var collapsedTreePaths: Set<String> = []
    private let commitComposerLineHeight: CGFloat = 18
    private let commitComposerVerticalPadding: CGFloat = 8
    private let commitComposerMinLines = 1
    private let commitComposerMaxLines = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if repository.isExpanded {
                controlStrip

                if let message = repository.message, !message.isEmpty {
                    repositoryMessageBanner(message)
                }

                if let operationMessage = repository.operationMessage,
                   repository.isOperating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(operationMessage)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("vibespace.source-control.repo.operation.\(repository.id)")
                }

                if repository.loadState == .error {
                    if repository.statusItems.isEmpty {
                        inlineErrorState
                    } else {
                        commitComposer
                        changesContent
                    }
                } else if repository.loadState == .loading && repository.statusItems.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(AppStrings.SourceControl.loadingRepoStatus)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                    }
                    .padding(8)
                } else {
                    commitComposer
                    changesContent
                }
            }
        }
        .sheet(item: historyScopeBinding, onDismiss: {
            repository.dismissHistory()
        }) { scope in
            repositoryHistorySheet(scope: scope)
        }
        .alert(AppStrings.SourceControl.undoAllTitle, isPresented: $isDiscardAllAlertPresented) {
            Button(AppStrings.SourceControl.discardChanges, role: .destructive) {
                repository.discardAllChanges()
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.SourceControl.undoAllMessage)
        }
    }

    private func repositoryMessageBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(appThemePalette.warningColor)
                .padding(.top, 1)

            Text(text)
                .font(AppTypographyTokens.caption)
                .foregroundStyle(appThemePalette.secondaryTextColor)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var header: some View {
        Button {
            repository.isExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: repository.isExpanded ? "chevron.down" : "chevron.right")
                    .font(AppTypographyTokens.scaledSystem(10, weight: .semibold))
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .frame(width: 12)

                Text(repository.displayName)
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(appThemePalette.primaryTextColor)
                    .lineLimit(1)

                if let branchName = repository.branchName, !branchName.isEmpty {
                    Text(branchName)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var controlStrip: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(repository.branchOptions) { branch in
                    Button {
                        repository.checkout(branch)
                    } label: {
                        HStack {
                            Text(branch.displayName)
                            if branch.isCurrent {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(repository.isOperating || branch.isCurrent)
                }
            } label: {
                Label(repository.branchName ?? "Branch", systemImage: "arrow.triangle.branch")
                    .font(AppTypographyTokens.captionSemibold)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .disabled(repository.branchOptions.isEmpty || repository.isOperating)

            Spacer(minLength: 0)

            Button {
                repository.openHistory(scope: .repository)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.crispyvibesText)
            .disabled(repository.isOperating)
            .help(AppStrings.SourceControl.viewCommitHistory)

            Button {
                Task { await repository.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.crispyvibesText)
            .disabled(repository.isOperating)
            .help(AppStrings.SourceControl.refreshRepository)

            HStack(spacing: 2) {
                layoutModeButton(
                    mode: .list,
                    icon: "list.bullet",
                    helpText: "Show files as a flat list"
                )
                layoutModeButton(
                    mode: .tree,
                    icon: "list.bullet.indent",
                    helpText: "Show files grouped by folder"
                )
            }
            .padding(2)
            .background(appThemePalette.chromeBackgroundColor.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(6), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(6), style: .continuous)
                    .stroke(appThemePalette.borderColorValue.opacity(0.75), lineWidth: 1)
            )
            .disabled(repository.isOperating)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private var commitComposer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if repository.commitDraft.isEmpty {
                        Text(AppStrings.SourceControl.commitMessage)
                            .font(AppTypographyTokens.body)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, commitComposerVerticalPadding + 1)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: Binding(
                        get: { repository.commitDraft },
                        set: { repository.commitDraft = $0 }
                    ))
                    .font(AppTypographyTokens.body)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity)
                    .frame(height: commitComposerHeight, alignment: .top)
                    .padding(.horizontal, 2)
                    .disabled(repository.isOperating)
                }
                .background(appThemePalette.canvasBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(6), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(6), style: .continuous)
                        .stroke(appThemePalette.borderColorValue.opacity(0.9), lineWidth: 1)
                )

                Button(AppStrings.SourceControl.commit) {
                    repository.commit()
                }
                .buttonStyle(.crispyvibesPrimary)
                .controlSize(.small)
                .disabled(
                    repository.isOperating ||
                    repository.commitDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    gitActionButton(AppStrings.SourceControl.stageAll, icon: "plus.circle", showLabel: true) { repository.stageAll() }
                        .disabled(repository.isOperating || repository.statusItems.isEmpty)
                    gitActionButton(AppStrings.SourceControl.undoAll, icon: "arrow.uturn.backward.circle", showLabel: true) { isDiscardAllAlertPresented = true }
                        .disabled(repository.isOperating || !repository.hasDiscardableChanges)
                    gitActionButton(AppStrings.SourceControl.push, icon: "arrow.up", showLabel: true) { repository.push() }
                        .disabled(repository.isOperating)
                    gitActionButton(AppStrings.SourceControl.pull, icon: "arrow.down", showLabel: true) { repository.pull() }
                        .disabled(repository.isOperating)
                    gitActionButton(AppStrings.SourceControl.fetch, icon: "arrow.down.to.line", showLabel: true) { repository.fetch() }
                        .disabled(repository.isOperating)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 4) {
                    gitActionButton(AppStrings.SourceControl.stageAll, icon: "plus.circle", showLabel: false) { repository.stageAll() }
                        .disabled(repository.isOperating || repository.statusItems.isEmpty)
                    gitActionButton(AppStrings.SourceControl.undoAll, icon: "arrow.uturn.backward.circle", showLabel: false) { isDiscardAllAlertPresented = true }
                        .disabled(repository.isOperating || !repository.hasDiscardableChanges)
                    gitActionButton(AppStrings.SourceControl.push, icon: "arrow.up", showLabel: false) { repository.push() }
                        .disabled(repository.isOperating)
                    gitActionButton(AppStrings.SourceControl.pull, icon: "arrow.down", showLabel: false) { repository.pull() }
                        .disabled(repository.isOperating)
                    gitActionButton(AppStrings.SourceControl.fetch, icon: "arrow.down.to.line", showLabel: false) { repository.fetch() }
                        .disabled(repository.isOperating)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var commitComposerHeight: CGFloat {
        let lineCount = max(
            commitComposerMinLines,
            repository.commitDraft.split(separator: "\n", omittingEmptySubsequences: false).count
        )
        let visibleLineCount = min(commitComposerMaxLines, lineCount)
        return (CGFloat(visibleLineCount) * commitComposerLineHeight) + (commitComposerVerticalPadding * 2)
    }

    private var changesContent: AnyView {
        if repository.statusItems.isEmpty {
            return AnyView(ContentUnavailableView(
                AppStrings.SourceControl.noChanges,
                systemImage: "checkmark.seal",
                description: Text(AppStrings.SourceControl.noChanges)
            )
            .frame(maxWidth: .infinity, minHeight: 120))
        } else {
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                if !repository.stagedItems.isEmpty {
                    changesSection(
                        title: "Staged",
                        items: repository.stagedItems,
                        isExpanded: $stagedExpanded,
                        sectionKey: "staged"
                    ) {
                        sectionActionButton("Unstage All", icon: "square.and.arrow.down") {
                            repository.unstageAll()
                        }
                        .disabled(repository.isOperating || repository.stagedItems.isEmpty)
                    }
                }
                if !repository.changeItems.isEmpty {
                    changesSection(
                        title: "Changes",
                        items: repository.changeItems,
                        isExpanded: $changeExpanded,
                        sectionKey: "changes"
                    ) {
                        sectionActionButton(AppStrings.SourceControl.stageAll, icon: "square.and.arrow.up") {
                            repository.stageAll()
                        }
                        .disabled(repository.isOperating || repository.changeItems.isEmpty)

                        sectionActionButton(AppStrings.SourceControl.undoAll, icon: "arrow.uturn.backward.circle") {
                            isDiscardAllAlertPresented = true
                        }
                        .disabled(repository.isOperating || !repository.hasDiscardableChanges)
                    }
                }
            }
            .padding(.top, 8))
        }
    }

    private func changesSection(
        title: String,
        items: [VibeSpaceSourceControlStatusItem],
        isExpanded: Binding<Bool>,
        sectionKey: String,
        @ViewBuilder actions: () -> some View
    ) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(AppTypographyTokens.scaledSystem(9, weight: .semibold))
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                        .frame(width: 10)

                    Text(title)
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(appThemePalette.primaryTextColor)

                    Text("\(items.count)")
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(appThemePalette.secondaryTextColor)

                    Spacer(minLength: 0)

                    actions()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                if layoutMode == .list {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            changeRow(item, depth: 0, displayPath: item.relativePath)
                            if index < items.count - 1 {
                                Divider().padding(.leading, 8)
                            }
                        }
                    }
                } else {
                    let tree = makeTreeNodes(for: items, sectionKey: sectionKey)
                    VStack(spacing: 0) {
                        treeRows(tree, depth: 0)
                    }
                }
            }
        }
        .padding(.bottom, 6))
    }

    private func changeRow(
        _ item: VibeSpaceSourceControlStatusItem,
        depth: Int,
        displayPath: String
    ) -> some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: CGFloat(depth) * 14)

            Text(gitBadgeText(for: item.code))
                .font(AppTypographyTokens.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(gitBadgeColor(for: item.code))
                .frame(width: 12, alignment: .leading)

            Text(displayPath)
                .font(AppTypographyTokens.caption)
                .foregroundStyle(appThemePalette.primaryTextColor)
                .lineLimit(1)

            Spacer(minLength: 0)

            if item.canUnstage {
                Button {
                    repository.unstage(item)
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.crispyvibesText)
                .help(AppStrings.SourceControl.unstage)
                .disabled(repository.isOperating)
            }

            if item.canDiscardChanges {
                Button {
                    repository.discard(item)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.crispyvibesText)
                .help(AppStrings.SourceControl.undoChanges)
                .disabled(repository.isOperating)
            }

            if item.canStage {
                Button {
                    repository.stage(item)
                } label: {
                    Image(systemName: "arrow.up.circle")
                }
                .buttonStyle(.crispyvibesText)
                .help(AppStrings.SourceControl.stage)
                .disabled(repository.isOperating)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDiff(repository, item)
        }
    }

    private func treeRows(_ nodes: [SourceControlTreeNode], depth: Int) -> AnyView {
        AnyView(ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
            VStack(spacing: 0) {
                if let item = node.item {
                    changeRow(item, depth: depth, displayPath: item.fileName)
                } else {
                    treeDirectoryRow(node, depth: depth)
                }

                if node.isDirectory == false,
                   index < nodes.count - 1 {
                    Divider().padding(.leading, 8 + CGFloat(depth) * 14)
                }

                if node.isDirectory,
                   !collapsedTreePaths.contains(node.id) {
                    treeRows(node.children, depth: depth + 1)
                }
            }
        })
    }

    private func treeDirectoryRow(_ node: SourceControlTreeNode, depth: Int) -> some View {
        Button {
            if collapsedTreePaths.contains(node.id) {
                collapsedTreePaths.remove(node.id)
            } else {
                collapsedTreePaths.insert(node.id)
            }
        } label: {
            HStack(spacing: 8) {
                Color.clear
                    .frame(width: CGFloat(depth) * 14)

                Image(systemName: collapsedTreePaths.contains(node.id) ? "chevron.right" : "chevron.down")
                    .font(AppTypographyTokens.scaledSystem(9, weight: .semibold))
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .frame(width: 12)

                Text(node.name)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var inlineErrorState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(repository.message ?? "Unable to load repository status.")
                .font(AppTypographyTokens.caption)
                .foregroundStyle(appThemePalette.secondaryTextColor)

            Button(AppStrings.Common.retry) {
                Task { await repository.refresh() }
            }
            .buttonStyle(.crispyvibesText)
            .controlSize(.small)
        }
        .padding(8)
    }

    private var historyScopeBinding: Binding<VibeSpaceSourceControlHistoryScope?> {
        Binding(
            get: { repository.activeHistoryScope },
            set: { nextValue in
                if nextValue == nil {
                    repository.dismissHistory()
                } else {
                    repository.activeHistoryScope = nextValue
                }
            }
        )
    }

    private func repositoryHistorySheet(scope: VibeSpaceSourceControlHistoryScope) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(scope.title)
                    .font(AppTypographyTokens.subheadlineSemibold)
                Spacer(minLength: 0)
            }
            .padding(12)

            Divider()

            if repository.historyIsLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(AppStrings.SourceControl.loadingHistory)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if repository.historyEntries.isEmpty {
                ContentUnavailableView(
                    "No History Found",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(AppStrings.SourceControl.noCommitsMatched)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(repository.historyEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.subject)
                            .font(AppTypographyTokens.body)
                            .foregroundStyle(appThemePalette.primaryTextColor)
                        HStack(spacing: 8) {
                            Text(entry.shortHash)
                            Text(entry.authorName)
                            Text(entry.authoredDate)
                        }
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .background(appThemePalette.canvasBackgroundColor)
    }

    private func gitActionButton(_ title: String, icon: String, showLabel: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if showLabel {
                Label(title, systemImage: icon)
            } else {
                Image(systemName: icon)
            }
        }
        .buttonStyle(.crispyvibesText)
        .controlSize(.small)
        .help(title)
    }

    private func sectionActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(AppTypographyTokens.scaledIcon(11, weight: .semibold))
                .frame(width: uiScale.iconSize(18), height: uiScale.iconSize(18))
        }
        .buttonStyle(.plain)
        .foregroundStyle(appThemePalette.secondaryTextColor)
        .help(title)
    }

    private var layoutMode: SourceControlSectionLayoutMode {
        SourceControlSectionLayoutMode(rawValue: layoutModeRaw) ?? .list
    }

    private var layoutModeBinding: Binding<SourceControlSectionLayoutMode> {
        Binding(
            get: { layoutMode },
            set: { layoutModeRaw = $0.rawValue }
        )
    }

    private func layoutModeButton(
        mode: SourceControlSectionLayoutMode,
        icon: String,
        helpText: String
    ) -> some View {
        let isSelected = layoutMode == mode
        return Button {
            layoutModeBinding.wrappedValue = mode
        } label: {
            Image(systemName: icon)
                .font(AppTypographyTokens.scaledIcon(11, weight: .semibold))
                .foregroundStyle(
                    isSelected
                    ? appThemePalette.primaryTextColor
                    : appThemePalette.secondaryTextColor
                )
                .frame(width: uiScale.chromeSize(26), height: uiScale.chromeSize(22))
                .background(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(4), style: .continuous)
                        .fill(
                            isSelected
                            ? appThemePalette.canvasBackgroundColor
                            : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func makeTreeNodes(
        for items: [VibeSpaceSourceControlStatusItem],
        sectionKey: String
    ) -> [SourceControlTreeNode] {
        SourceControlTreeBuilder.build(items: items, sectionKey: "\(repository.id)|\(sectionKey)")
    }

    private func gitBadgeText(for code: String) -> String {
        if code == "??" { return "A" }
        if code.contains("U") { return "U" }
        if code.contains("R") || code.contains("C") { return "R" }
        if code.contains("D") { return "D" }
        if code.contains("A") { return "A" }
        if code.contains("M") { return "M" }
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : trimmed
    }

    private func gitBadgeColor(for code: String) -> Color {
        if code == "??" || code.contains("A") { return appThemePalette.gitAddedStatusColor }
        if code.contains("M") { return appThemePalette.gitModifiedStatusColor }
        if code.contains("D") { return appThemePalette.gitDeletedStatusColor }
        if code.contains("U") { return appThemePalette.warningColor }
        if code.contains("R") || code.contains("C") { return appThemePalette.gitRenamedStatusColor }
        return appThemePalette.secondaryTextColor
    }
}

private enum SourceControlSectionLayoutMode: String {
    case list
    case tree
}

private struct SourceControlTreeNode: Identifiable {
    let id: String
    let name: String
    let item: VibeSpaceSourceControlStatusItem?
    var children: [SourceControlTreeNode]

    var isDirectory: Bool { item == nil }
}

private enum SourceControlTreeBuilder {
    private struct DirectoryNode {
        var directories: [String: DirectoryNode] = [:]
        var files: [VibeSpaceSourceControlStatusItem] = []
    }

    static func build(items: [VibeSpaceSourceControlStatusItem], sectionKey: String) -> [SourceControlTreeNode] {
        var root = DirectoryNode()

        for item in items.sorted(by: { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }) {
            insert(item: item, into: &root)
        }

        return materialize(directory: root, parentPath: sectionKey)
    }

    private static func insert(item: VibeSpaceSourceControlStatusItem, into root: inout DirectoryNode) {
        let pathComponents = (item.relativePath as NSString).pathComponents
        guard !pathComponents.isEmpty else {
            root.files.append(item)
            return
        }

        insert(item: item, components: Array(pathComponents.dropLast()), into: &root)
    }

    private static func insert(
        item: VibeSpaceSourceControlStatusItem,
        components: [String],
        into directory: inout DirectoryNode
    ) {
        guard let first = components.first else {
            directory.files.append(item)
            directory.files.sort {
                $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
            }
            return
        }

        var child = directory.directories[first] ?? DirectoryNode()
        insert(item: item, components: Array(components.dropFirst()), into: &child)
        directory.directories[first] = child
    }

    private static func materialize(directory: DirectoryNode, parentPath: String) -> [SourceControlTreeNode] {
        let directoryNodes = directory.directories.keys.sorted().map { name in
            let child = directory.directories[name] ?? DirectoryNode()
            let nodePath = "\(parentPath)/\(name)"
            return SourceControlTreeNode(
                id: nodePath,
                name: name,
                item: nil,
                children: materialize(directory: child, parentPath: nodePath)
            )
        }

        let fileNodes = directory.files.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }.map { item in
            SourceControlTreeNode(
                id: "\(parentPath)/\(item.relativePath)",
                name: item.fileName,
                item: item,
                children: []
            )
        }

        return directoryNodes + fileNodes
    }
}
