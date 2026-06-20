import SwiftUI

@MainActor
struct HomeShellContext {
    private let store: AppShellStore

    init(store: AppShellStore) {
        self.store = store
    }

    var hasActiveVibeSpace: Bool {
        store.activeVibeSpaceID != nil
    }

    var vibespaceSidebarTab: FolderExplorerViewModel.SidebarTab {
        store.vibespaceSidebarTab
    }

    var canReturnToVibeSpace: Bool {
        store.isShowingHome && store.activeVibeSpaceID != nil
    }

    var vibeSpaceCreationSheetBinding: Binding<Bool> {
        Binding(
            get: { store.activeModalSheet == .vibeSpaceCreation },
            set: { isPresented in
                if isPresented {
                    store.presentVibeSpaceCreationSheet()
                } else if store.activeModalSheet == .vibeSpaceCreation {
                    store.dismissModalSheet(.vibeSpaceCreation)
                }
            }
        )
    }

    func activeAppSideMenuItem(
        hasAnyVibeSpace: Bool,
        showsVibeSpaceSidebar: Bool,
        walkthroughPresented: Bool
    ) -> AppSideMenuItem? {
        if walkthroughPresented {
            return nil
        }
        if case let .appSettings(category) = store.activeSurface {
            return category == .account ? .account : .crispyvibesSettings
        }
        if case .vibespaceSettings = store.activeSurface {
            return .vibespaceSettings
        }
        if store.isShowingHome || !hasAnyVibeSpace {
            return .home
        }
        guard showsVibeSpaceSidebar else { return nil }
        if store.vibespaceSidebarUnified {
            return .workspace
        }
        switch store.vibespaceSidebarTab {
        case .files:
            return .files
        case .git:
            return .git
        case .sessions:
            return .sessions
        case .conversations:
            return .conversations
        }
    }

    func showVibeSpace(_ vibespaceID: UUID) {
        store.showVibeSpace(vibespaceID)
    }

    func selectVibeSpace(_ vibespaceID: UUID?) {
        store.selectVibeSpace(vibespaceID)
    }

    func clearVibeSpaceSelection() {
        store.clearVibeSpaceSelection()
    }

    func showHome() {
        store.showHome()
    }

    func dismissHome() {
        store.dismissHome()
    }

    func presentVibeSpaceSettingsForActiveVibeSpace(
        _ category: VibeSpaceSettingsCategory = .vibespace
    ) {
        store.presentVibeSpaceSettingsForActiveVibeSpace(category)
    }

    func presentAppSettings(_ category: AppSettingsCategory) {
        store.presentAppSettings(category)
    }

    func dismissSurface() {
        store.dismissSurface()
    }

    func presentVibeSpaceCreationSheet() {
        store.presentVibeSpaceCreationSheet()
    }

    func dismissVibeSpaceCreationSheet() {
        store.dismissModalSheet(.vibeSpaceCreation)
    }

    func resetForFreshStart() {
        store.resetForFreshStart()
    }

    func showVibeSpaceSidebar(_ tab: FolderExplorerViewModel.SidebarTab) {
        store.showVibeSpaceSidebar(tab)
    }

    func hideVibeSpaceSidebar() {
        store.hideVibeSpaceSidebar()
    }
}

extension ContentView {
    var homeShell: HomeShellContext {
        HomeShellContext(store: appShellStore)
    }
}
