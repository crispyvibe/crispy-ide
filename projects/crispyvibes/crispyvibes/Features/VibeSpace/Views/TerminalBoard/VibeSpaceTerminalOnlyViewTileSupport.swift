import SwiftUI

extension VibeSpaceTerminalOnlyView {
    func accentColor(for projectPath: String?) -> Color? {
        guard let projectPath else { return nil }
        return projectColorTagsByPath[projectPath]?.color
    }

    func projectURL(for projectPath: String?) -> URL? {
        guard let projectPath else { return nil }
        return URL(fileURLWithPath: projectPath)
    }

    func openTerminalInEditorPane(projectPath: String?, terminalTabID: UUID) {
        guard let projectPath,
              let project = boardStore.projectsByPath[projectPath] else {
            return
        }
        onOpenTerminalInEditorPane?(project.id, terminalTabID)
    }

    func resolveACPPaneStore(from snapshot: ACPStandalonePaneSnapshot) -> ACPStandaloneSessionStore? {
        if let existing = acpStoreLookup?(snapshot.id) {
            return existing
        }
        return restoreACPPaneStore?(snapshot)
    }

    func syncACPPaneStores() {
        let snapshots = (surfaceLayout.tiles + surfaceLayout.minimizedTiles).compactMap(\.acpSnapshot)
        var didResolve = false
        for snapshot in snapshots {
            if acpStoreLookup?(snapshot.id) == nil {
                if resolveACPPaneStore(from: snapshot) != nil {
                    didResolve = true
                }
            }
        }
        // If stores were newly created, the board store needs to publish so tile
        // cards re-query acpStoreLookup and render the now-available store.
        if didResolve {
            boardStore.objectWillChange.send()
        }
    }

    func addACPTileAction() {
        guard let createACPPaneStore else { return }
        let store = createACPPaneStore()
        _ = boardStore.addACPTile(snapshot: store.snapshot, surfaceID: surfaceID)
    }
}
