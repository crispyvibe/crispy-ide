import AppKit
import SwiftUI

struct VibeSpaceProjectFilesSectionView: View {
    @Environment(\.appThemePalette) private var activeThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme

    let project: AnyProjectSession
    let isExpanded: Bool
    let isFocused: Bool
    let accentColor: Color
    let selectedVibeSpaceCanvasMode: VibeSpaceCanvasMode
    let projectRootURLs: [URL]
    let onFocusAndToggleExpansion: () -> Void
    let onAppearWhenFocused: () -> Void
    let onAction: (FileTreeAction) -> Void
    let onTransferDrop: ([ExplorerItemTransferPlan]) -> Bool

    private var explorerProjectTitle: String {
        if project.metadata.hostLabel != nil {
            return "\(project.title) [ssh]"
        }
        return project.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onFocusAndToggleExpansion) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppTypographyTokens.scaledSystem(10, weight: .semibold))
                        .foregroundStyle(activeThemePalette.secondaryTextColor)

                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(accentColor)

                    Text(explorerProjectTitle)
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(activeThemePalette.primaryTextColor)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    CrispyVibesIconButton(
                        systemName: "arrow.clockwise",
                        variant: .compact,
                        color: activeThemePalette.secondaryTextColor
                    ) {
                        project.ensureExplorerLoaded()
                        project.folderExplorer.refreshTree(trigger: .manual)
                    }
                    .help(AppStrings.Explorer.refreshFileList)

                    CrispyVibesIconButton(
                        systemName: "doc.badge.plus",
                        variant: .compact,
                        color: activeThemePalette.secondaryTextColor
                    ) {
                        project.ensureExplorerLoaded()
                        project.folderExplorer.createNewFileAtSelection()
                    }
                    .help(AppStrings.Explorer.createNewFile)

                    CrispyVibesIconButton(
                        systemName: "folder.badge.plus",
                        variant: .compact,
                        color: activeThemePalette.secondaryTextColor
                    ) {
                        project.ensureExplorerLoaded()
                        project.folderExplorer.createNewFolderAtSelection()
                    }
                    .help(AppStrings.Explorer.createNewFolder)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous)
                        .fill(
                            isFocused
                                ? activeThemePalette.selectionBackgroundColor.opacity(0.30)
                                : Color.clear
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("vibespace.sidebar.project.\(project.id.uuidString)")
            .contextMenu {
                // F021-R13: park the project from the Files-tab right-click menu.
                Button(AppStrings.VibeSpace.parkProjectAction) {
                    NotificationCenter.default.post(
                        name: .parkProjectRequested,
                        object: nil,
                        userInfo: [AppCommandUserInfoKey.projectID: project.id]
                    )
                }
            }

            if isExpanded {
                ProjectFileTreeView(
                    viewModel: project.folderExplorer,
                    projectRootURLs: projectRootURLs,
                    onAction: onAction,
                    onTransferDrop: onTransferDrop
                )
                .padding(.leading, 10)
            }
        }
        .onAppear {
            ensureProjectLoadedIfNeeded()
            if isFocused && selectedVibeSpaceCanvasMode == .detailed {
                onAppearWhenFocused()
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                ensureProjectLoadedIfNeeded()
            }
        }
    }

    private func ensureProjectLoadedIfNeeded() {
        guard isExpanded || isFocused else { return }
        project.activate()
        project.ensureExplorerLoaded()
    }
}

/// Isolated file tree view — only re-renders when THIS project's view model changes.
/// Prevents sibling projects from causing unrelated tree redraws.
struct ProjectFileTreeView: View {
    @Environment(\.appThemePalette) private var activeThemePalette
    @ObservedObject var viewModel: AnyFolderExplorer
    @FocusState private var isExplorerListFocused: Bool

    let projectRootURLs: [URL]
    let onAction: (FileTreeAction) -> Void
    let onTransferDrop: ([ExplorerItemTransferPlan]) -> Bool

    private var shouldShowLoadingState: Bool {
        viewModel.rootURL == nil || (viewModel.workerStatus.level == .busy && viewModel.rootItems.isEmpty)
    }

    private func forwardAction(_ action: FileTreeAction) {
        switch action {
        case .startRenaming, .commitRename, .cancelRename:
            isExplorerListFocused = false
            DispatchQueue.main.async {
                onAction(action)
            }
        default:
            isExplorerListFocused = true
            onAction(action)
        }
    }

    var body: some View {
        if shouldShowLoadingState {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(AppStrings.Explorer.loadingFiles)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(activeThemePalette.secondaryTextColor)
            }
            .padding(.leading, 18)
            .padding(.vertical, 6)
        } else if viewModel.rootItems.isEmpty {
            Text(AppStrings.Explorer.noFilesLoaded)
                .font(AppTypographyTokens.caption)
                .foregroundStyle(activeThemePalette.secondaryTextColor)
                .padding(.leading, 18)
                .padding(.vertical, 6)
        } else {
            AppKitTreeView(
                rootItems: viewModel.displayedItems,
                expandedIDs: viewModel.expandedDirectoryIDs,
                loadingIDs: viewModel.loadingDirectoryIDs,
                selectedID: viewModel.selectedItemID,
                renamingID: viewModel.renamingItemID,
                searchQuery: viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                changedDirectoryIDs: viewModel.changedDirectoryIDs,
                treeMutationRevision: viewModel.treeMutationRevision,
                allowsScrolling: false,
                rootURL: viewModel.rootURL,
                projectRootURLs: projectRootURLs,
                renameText: Binding(
                    get: { viewModel.renameText },
                    set: { viewModel.renameText = $0 }
                ),
                onAction: forwardAction,
                onTransferDrop: onTransferDrop
            )
            .fixedSize(horizontal: false, vertical: true)
            .focusable()
            .focused($isExplorerListFocused)
            .onTapGesture {
                isExplorerListFocused = true
            }
            .onCommand(#selector(NSResponder.insertNewline(_:))) {
                guard isExplorerListFocused else { return }
                if viewModel.renamingItemID != nil {
                    forwardAction(.commitRename)
                } else {
                    viewModel.startRenamingSelectedItem()
                    isExplorerListFocused = false
                }
            }
        }
    }
}
