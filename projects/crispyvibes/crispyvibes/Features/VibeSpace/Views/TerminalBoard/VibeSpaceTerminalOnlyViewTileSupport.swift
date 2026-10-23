import SwiftUI

extension VibeSpaceTerminalOnlyView {
    func accentColor(for projectPath: String?) -> Color? {
        guard let projectPath else { return nil }
        let colorKey = boardStore.projectsByIdentifier[projectPath]?
            .rootURL.standardizedFileURL.path ?? projectPath
        return projectColorTagsByPath[colorKey]?.color
    }

    func fileOpenContext(
        forDockedFileURL fileURL: URL,
        projectIdentifier: String? = nil
    ) -> (reference: FileDocumentReference, provider: (any FileContentProviding)?) {
        let path = fileURL.standardizedFileURL.path
        let owner = projectIdentifier.flatMap { projectsByIdentifier in
            projects.first(where: { $0.projectIdentifier == projectsByIdentifier })
        } ?? projects
            .filter { project in
                let root = project.rootURL.standardizedFileURL.path
                return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
            }
            .max {
                $0.rootURL.standardizedFileURL.path.count
                    < $1.rootURL.standardizedFileURL.path.count
            }
        return (
            reference: FileDocumentReference(
                url: fileURL,
                projectIdentifier: owner?.projectIdentifier
            ),
            provider: owner?.sshConnection != nil ? owner?.fileContent : nil
        )
    }

    func projectURL(for projectPath: String?) -> URL? {
        guard let projectPath else { return nil }
        return boardStore.projectsByIdentifier[projectPath]?.rootURL
            ?? URL(fileURLWithPath: projectPath)
    }

    func openTerminalInEditorPane(projectPath: String?, terminalTabID: UUID) {
        guard let projectPath,
              let project = boardStore.projectsByIdentifier[projectPath]
                ?? boardStore.projectsByPath[projectPath] else {
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
