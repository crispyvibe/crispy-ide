import Foundation
import SwiftUI

@MainActor
final class AppShellStore: ObservableObject {
    enum ActiveSurface: Equatable {
        case automation
        case vibespaceSettings(UUID, VibeSpaceSettingsCategory)
        case appSettings(AppSettingsCategory)
    }

    enum ActiveModalSheet: Equatable {
        case cloneRepository
        case vibeSpaceCreation
    }

    @Published var activeVibeSpaceID: UUID?
    @Published var isShowingHome = false
    @Published var activeSurface: ActiveSurface?
    @Published var activeModalSheet: ActiveModalSheet?
    @Published var vibespaceSidebarTab: FolderExplorerViewModel.SidebarTab = .files
    /// F056: the unified Workspace panel is the default side-panel layout;
    /// selecting a classic rail tab (Files/Git/…) switches to the classic panel.
    @Published private(set) var vibespaceSidebarUnified = true
    @Published var isVibeSpaceSidebarVisible = true

    var operationMetricsStore: OperationMetricsStore?

    var activeVibeSpaceSettingsVibeSpaceID: UUID? {
        guard case let .vibespaceSettings(vibespaceID, _) = activeSurface else { return nil }
        return vibespaceID
    }

    var activeVibeSpaceSettingsCategory: VibeSpaceSettingsCategory {
        guard case let .vibespaceSettings(_, category) = activeSurface else { return .vibespace }
        return category
    }

    var activeAppSettingsCategory: AppSettingsCategory {
        guard case let .appSettings(category) = activeSurface else { return .general }
        return category
    }

    var isPresentingSurface: Bool {
        activeSurface != nil
    }

    func selectVibeSpace(_ vibespaceID: UUID?) {
        activeVibeSpaceID = vibespaceID
        if vibespaceID != nil {
            isShowingHome = false
        }
    }

    func showVibeSpace(_ vibespaceID: UUID) {
        activeVibeSpaceID = vibespaceID
        isShowingHome = false
    }

    func clearVibeSpaceSelection() {
        activeVibeSpaceID = nil
    }

    func showHome() {
        activeSurface = nil
        isShowingHome = true
    }

    func dismissHome() {
        isShowingHome = false
    }

    func presentVibeSpaceSettingsForActiveVibeSpace(
        _ category: VibeSpaceSettingsCategory = .vibespace
    ) {
        guard let activeVibeSpaceID else { return }
        activeSurface = .vibespaceSettings(activeVibeSpaceID, category)
        isShowingHome = false
    }

    func updatePresentedVibeSpaceSettingsCategory(_ category: VibeSpaceSettingsCategory) {
        guard case let .vibespaceSettings(vibespaceID, _) = activeSurface else { return }
        activeSurface = .vibespaceSettings(vibespaceID, category)
    }

    func presentAppSettings(_ category: AppSettingsCategory) {
        activeSurface = .appSettings(category)
        isShowingHome = false
    }

    func presentAutomation() {
        activeSurface = .automation
        isShowingHome = false
    }

    func updatePresentedAppSettingsCategory(_ category: AppSettingsCategory) {
        guard case .appSettings = activeSurface else { return }
        activeSurface = .appSettings(category)
    }

    func dismissSurface() {
        activeSurface = nil
    }

    func presentCloneRepositorySheet() {
        activeModalSheet = .cloneRepository
    }

    func presentVibeSpaceCreationSheet() {
        activeModalSheet = .vibeSpaceCreation
    }

    func dismissModalSheet(_ sheet: ActiveModalSheet? = nil) {
        guard let sheet else {
            activeModalSheet = nil
            return
        }
        if activeModalSheet == sheet {
            activeModalSheet = nil
        }
    }

    func resetForFreshStart() {
        activeVibeSpaceID = nil
        isShowingHome = false
        activeSurface = nil
        activeModalSheet = nil
        vibespaceSidebarTab = .files
        isVibeSpaceSidebarVisible = true
        vibespaceSidebarUnified = true
    }

    func showVibeSpaceSidebar(_ tab: FolderExplorerViewModel.SidebarTab) {
        let startTime = Date()
        activeSurface = nil
        isShowingHome = false
        isVibeSpaceSidebarVisible = true
        vibespaceSidebarTab = tab
        // F056: selecting a classic rail tab exits the unified layout.
        vibespaceSidebarUnified = false
        operationMetricsStore?.recordOperation(name: "sidebar.toggle", startTime: startTime)
    }

    /// F056: toggle the opt-in unified sidebar layout.
    func setVibeSpaceSidebarUnified(_ on: Bool) {
        vibespaceSidebarUnified = on
    }

    func hideVibeSpaceSidebar() {
        let startTime = Date()
        isVibeSpaceSidebarVisible = false
        operationMetricsStore?.recordOperation(name: "sidebar.toggle", startTime: startTime)
    }
}
