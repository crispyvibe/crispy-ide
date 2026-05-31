import SwiftUI

extension VibeSpaceTerminalOnlyView {
    func accentColor(for projectPath: String?) -> Color? {
        guard let projectPath else { return nil }
        return projectColorTagsByPath[projectPath]?.color
    }

    /// F051-R07: resolves the SFTP content provider for a docked file that
    /// belongs to a remote project, so pinned file tiles load remote files over
    /// SSH instead of the local filesystem. Returns nil for local files (which
    /// keep the default local read path).
    func fileContentProvider(forDockedFileURL fileURL: URL) -> (any FileContentProviding)? {
        let path = fileURL.standardizedFileURL.path
        let owner = projects
            .filter { project in
                let root = project.rootURL.standardizedFileURL.path
                return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
            }
            .max { $0.rootURL.standardizedFileURL.path.count < $1.rootURL.standardizedFileURL.path.count }
        return owner?.sshConnection != nil ? owner?.fileContent : nil
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
