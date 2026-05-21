import SwiftUI
import UniformTypeIdentifiers

struct FolderExplorerView: View {
    @Environment(\.appThemePalette) var appThemePalette
    @Environment(\.crispyvibesTheme) var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) var uiScale
    @ObservedObject var viewModel: FolderExplorerViewModel
    let vibespaceInteraction: VibeSpaceInteractionService
    let onOpenInTerminal: (URL) -> Void
    let showsHeaderControls: Bool
    let tabOverride: FolderExplorerViewModel.SidebarTab?

    @State var pendingDeletion: FileItem?
    @Namespace var sidebarTabSelectionNamespace
    @FocusState var isExplorerListFocused: Bool
    @FocusState var isSearchFieldFocused: Bool

    init(
        viewModel: FolderExplorerViewModel,
        vibespaceInteraction: VibeSpaceInteractionService,
        onOpenInTerminal: @escaping (URL) -> Void,
        showsHeaderControls: Bool = true,
        tabOverride: FolderExplorerViewModel.SidebarTab? = nil
    ) {
        self.viewModel = viewModel
        self.vibespaceInteraction = vibespaceInteraction
        self.onOpenInTerminal = onOpenInTerminal
        self.showsHeaderControls = showsHeaderControls
        self.tabOverride = tabOverride
    }

    var selectedSidebarTab: FolderExplorerViewModel.SidebarTab {
        tabOverride ?? viewModel.activeSidebarTab
    }

    var tabSwitcherBackgroundColor: Color {
        appThemePalette.canvasSecondaryBackgroundColor
    }

    var tabActiveBackgroundColor: Color {
        appThemePalette.selectionBackgroundColor.opacity(0.56)
    }

    var tabInactiveBackgroundColor: Color {
        appThemePalette.windowBackgroundColor.opacity(0.68)
    }

    var paneBackgroundColor: Color {
        appThemePalette.canvasBackgroundColor
    }

    func tabBorderColor(isActive: Bool) -> Color {
        appThemePalette.borderColorValue.opacity(isActive ? 1.0 : 0.62)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeaderControls {
                CrispyVibesHeaderChrome(
                    style: .panel,
                    background: appThemePalette.canvasSecondaryBackgroundColor
                ) {
                    headerControls
                    Spacer(minLength: 8)
                }

                Divider()
            }

            if selectedSidebarTab == .files {
                TextField(AppStrings.Explorer.searchFiles, text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFieldFocused)
                    .onTapGesture {
                        isExplorerListFocused = false
                    }
                    .accessibilityIdentifier("explorer.search")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                Divider()
            }

            if viewModel.rootURL == nil {
                ContentUnavailableView(
                    AppStrings.Explorer.noFolderSelected,
                    systemImage: "folder",
                    description: Text(AppStrings.Explorer.chooseFolderToBrowse)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if selectedSidebarTab == .files {
                    fileList
                } else {
                    gitList
                }
            }
        }
        .background(paneBackgroundColor)
        .crispyvibesContainerBorder(opacity: 0.6)
        .accessibilityIdentifier("explorer.active-tab.\(selectedSidebarTab.rawValue)")
        .onChange(of: selectedSidebarTab) { _, selectedTab in
            if selectedTab == .git {
                isExplorerListFocused = false
                isSearchFieldFocused = false
                viewModel.refreshGitStatus()
            }
        }
        .sheet(item: $viewModel.gitActiveHistoryScope, onDismiss: {
            viewModel.dismissGitHistory()
        }) { scope in
            gitHistorySheet(scope: scope)
        }
        .alert(
            AppStrings.Explorer.deleteItemTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { pendingDeletion = nil }
                }
            ),
            presenting: pendingDeletion
        ) { item in
            Button(AppStrings.Common.delete, role: .destructive) {
                viewModel.deleteItem(item)
                pendingDeletion = nil
            }
            Button(AppStrings.Common.cancel, role: .cancel) {
                pendingDeletion = nil
            }
        } message: { item in
            Text("Are you sure you want to delete \"\(item.displayName)\"?")
        }
        .alert(
            AppStrings.Explorer.errorTitle,
            isPresented: Binding(
                get: { viewModel.userFacingError != nil },
                set: { isPresented in
                    if !isPresented { viewModel.clearError() }
                }
            )
        ) {
            Button(AppStrings.Common.ok, role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.userFacingError ?? "")
        }
        .onCommand(#selector(NSResponder.insertNewline(_:))) {
            guard isExplorerListFocused, selectedSidebarTab == .files else { return }
            if viewModel.renamingItemID != nil {
                viewModel.commitRename()
            } else {
                viewModel.startRenamingSelectedItem()
            }
        }
    }
}
