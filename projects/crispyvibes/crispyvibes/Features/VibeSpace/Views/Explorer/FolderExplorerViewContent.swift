import SwiftUI
import UniformTypeIdentifiers

extension FolderExplorerView {
    var fileList: some View {
        let trimmedSearchQuery = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        return AppKitTreeView(
            rootItems: viewModel.displayedItems,
            expandedIDs: viewModel.expandedDirectoryIDs,
            loadingIDs: viewModel.loadingDirectoryIDs,
            selectedID: viewModel.selectedItemID,
            renamingID: viewModel.renamingItemID,
            searchQuery: trimmedSearchQuery,
            changedDirectoryIDs: viewModel.changedDirectoryIDs,
            treeMutationRevision: viewModel.treeMutationRevision,
            allowsScrolling: true,
            rootURL: viewModel.rootURL,
            projectRootURLs: [viewModel.rootURL].compactMap { $0 },
            renameText: $viewModel.renameText,
            onAction: { handleFileTreeAction($0) },
            onTransferDrop: { handleTransferDrop($0) }
        )
        .background(paneBackgroundColor)
        .accessibilityIdentifier("explorer.file-list")
        .focused($isExplorerListFocused)
        .onTapGesture {
            isExplorerListFocused = true
            isSearchFieldFocused = false
        }
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            handleItemDrop(providers, targetDirectoryURL: viewModel.rootURL)
        }
    }

    private func handleFileTreeAction(_ action: FileTreeAction) {
        switch action {
        case .startRenaming, .commitRename, .cancelRename:
            // Release SwiftUI focus so it doesn't fight the AppKit field editor
            isExplorerListFocused = false
            isSearchFieldFocused = false
        default:
            isExplorerListFocused = true
            isSearchFieldFocused = false
        }
        switch action {
        case .toggleExpansion(let item): viewModel.toggleExpansion(for: item)
        case .select(let item): viewModel.select(item)
        case .openInTab(let item): viewModel.openInTab(item)
        case .openInFinder(let url): vibespaceInteraction.revealInFinder(url)
        case .createNewFile(let item): viewModel.createNewFile(in: item)
        case .createNewFolder(let item): viewModel.createNewFolder(in: item)
        case .startRenaming(let item): viewModel.startRenaming(item: item)
        case .commitRename: viewModel.commitRename()
        case .cancelRename: viewModel.cancelRename()
        case .openInTerminal(let url): onOpenInTerminal(url)
        case .openInSplitHorizontal(let item): viewModel.openInSplitHorizontal(item)
        case .openInSplitVertical(let item): viewModel.openInSplitVertical(item)
        case .requestDelete(let item): pendingDeletion = item
        }
    }

    func handleItemDrop(_ providers: [NSItemProvider], targetDirectoryURL: URL?) -> Bool {
        guard let targetDirectoryURL else { return false }
        ExplorerItemDropPlanner.loadPlans(
            from: providers,
            targetDirectoryURL: targetDirectoryURL,
            projectRootURLs: [viewModel.rootURL].compactMap { $0 }
        ) { plans in
            guard !plans.isEmpty else { return }
            Task { @MainActor in
                viewModel.transferItems(using: plans)
            }
        }
        return true
    }

    func handleTransferDrop(_ plans: [ExplorerItemTransferPlan]) -> Bool {
        guard !plans.isEmpty else { return false }
        viewModel.transferItems(using: plans)
        return true
    }
}
