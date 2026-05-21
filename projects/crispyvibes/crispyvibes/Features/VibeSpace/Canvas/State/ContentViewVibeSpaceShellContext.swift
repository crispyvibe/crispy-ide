import SwiftUI

@MainActor
struct VibeSpaceShellContext {
    private let store: AppShellStore

    init(store: AppShellStore) {
        self.store = store
    }

    var activeVibeSpaceID: UUID? {
        store.activeVibeSpaceID
    }

    var sidebarTab: FolderExplorerViewModel.SidebarTab {
        store.vibespaceSidebarTab
    }

    var isCloneRepositorySheetPresented: Bool {
        store.activeModalSheet == .cloneRepository
    }

    var cloneRepositorySheetBinding: Binding<Bool> {
        Binding(
            get: { store.activeModalSheet == .cloneRepository },
            set: { isPresented in
                if !isPresented, store.activeModalSheet == .cloneRepository {
                    store.dismissModalSheet(.cloneRepository)
                }
            }
        )
    }

    var isAppSettingsPresented: Bool {
        if case .appSettings = store.activeSurface {
            return true
        }
        return false
    }

    var appSettingsCategoryBinding: Binding<AppSettingsCategory> {
        Binding(
            get: { store.activeAppSettingsCategory },
            set: { category in
                store.updatePresentedAppSettingsCategory(category)
            }
        )
    }

    var vibespaceSettingsCategoryBinding: Binding<VibeSpaceSettingsCategory> {
        Binding(
            get: { store.activeVibeSpaceSettingsCategory },
            set: { category in
                store.updatePresentedVibeSpaceSettingsCategory(category)
            }
        )
    }

    func showVibeSpace(_ vibespaceID: UUID) {
        store.showVibeSpace(vibespaceID)
    }

    func prepareForVibeSpacePresentation() {
        store.dismissHome()
    }

    func dismissSurface() {
        store.dismissSurface()
    }

    func presentVibeSpaceSettings(_ category: VibeSpaceSettingsCategory = .vibespace) {
        store.presentVibeSpaceSettingsForActiveVibeSpace(category)
    }

    func presentCloneRepositorySheet() {
        store.presentCloneRepositorySheet()
    }

    func dismissCloneRepositorySheet() {
        store.dismissModalSheet(.cloneRepository)
    }
}

extension ContentView {
    var vibespaceShell: VibeSpaceShellContext {
        VibeSpaceShellContext(store: appShellStore)
    }
}
