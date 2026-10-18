import Foundation

struct DockedFileEntry: Identifiable {
    let id: UUID
    let fileURL: URL
}

/// Owns EditorGroupStore lifecycle for docked file tiles and the floating preview.
/// Lives in the content-viewer layer so the terminal board never touches editor state.
@MainActor
final class DockedFileViewerCoordinator: ObservableObject {
    private let editorGroupFactory: @MainActor (UUID) -> EditorGroupStore
    private var groups: [UUID: EditorGroupStore] = [:]
    private var rootReferences: [UUID: FileDocumentReference] = [:]
    private var previewGroup: EditorGroupStore?
    private var previewRootReference: FileDocumentReference?
    private var spotlightOwnershipByHost: [String: Set<UUID>] = [:]

    @Published var previewFileURL: URL?
    @Published private(set) var spotlightOwnedTileIDs: Set<UUID> = []
    /// Tile identity list kept in sync by the board view — no editor state here.
    var dockedFiles: [DockedFileEntry] = []

    init(editorGroupFactory: @escaping @MainActor (UUID) -> EditorGroupStore) {
        self.editorGroupFactory = editorGroupFactory
    }

    // MARK: - Floating Preview

    func showPreview(
        for fileURL: URL,
        documentReference: FileDocumentReference? = nil,
        fileContentProvider: (any FileContentProviding)? = nil
    ) {
        let reference = documentReference ?? FileDocumentReference(url: fileURL)
        previewFileURL = reference.url
        previewRootReference = reference
        let group = editorGroupFactory(UUID())
        group.openFileInTab(
            at: reference.url,
            documentReference: reference,
            fileContentProvider: fileContentProvider
        )
        previewGroup = group
    }

    func dismissPreview() {
        previewFileURL = nil
        previewGroup = nil
        previewRootReference = nil
    }

    /// Promotes the live preview editor group into the pinned tile, avoiding a fresh load.
    func promotePreview(to tileID: UUID?) {
        guard let tileID, let group = previewGroup, let rootReference = previewRootReference else {
            dismissPreview()
            return
        }
        groups[tileID] = group
        rootReferences[tileID] = rootReference
        previewFileURL = nil
        previewGroup = nil
        previewRootReference = nil
    }

    func assignEditorGroup(
        _ group: EditorGroupStore,
        for tileID: UUID?,
        fileURL: URL
    ) {
        guard let tileID else {
            dismissPreview()
            return
        }
        groups[tileID] = group
        rootReferences[tileID] = FileDocumentReference(url: fileURL)
        previewFileURL = nil
        previewGroup = nil
        previewRootReference = nil
    }

    var previewEditorGroup: EditorGroupStore? { previewGroup }

    // MARK: - Pinned Tile Groups

    func editorGroup(
        for tileID: UUID,
        fileURL: URL,
        documentReference: FileDocumentReference? = nil,
        fileContentProvider: (any FileContentProviding)? = nil
    ) -> EditorGroupStore {
        let reference = documentReference ?? FileDocumentReference(url: fileURL)

        if let existing = groups[tileID] {
            if let rootReference = rootReferences[tileID],
               rootReference.url == reference.url,
               rootReference.projectIdentifier == nil,
               reference.projectIdentifier != nil {
                existing.upgradeFileReference(
                    from: rootReference,
                    to: reference,
                    fileContentProvider: fileContentProvider
                )
                rootReferences[tileID] = reference
            } else {
                existing.updateFileContentProvider(fileContentProvider, for: reference)
                if rootReferences[tileID] == nil {
                    rootReferences[tileID] = reference
                }
            }
            return existing
        }

        let group = editorGroupFactory(tileID)
        group.openFileInTab(
            at: reference.url,
            documentReference: reference,
            fileContentProvider: fileContentProvider
        )
        groups[tileID] = group
        rootReferences[tileID] = reference
        return group
    }

    func assignedEditorGroup(for tileID: UUID) -> EditorGroupStore? {
        groups[tileID]
    }

    /// Updates one Spotlight host lease and publishes the union used by board tiles.
    func setSpotlightOwnedTileIDs(_ tileIDs: Set<UUID>, ownerID: String) {
        if tileIDs.isEmpty {
            spotlightOwnershipByHost.removeValue(forKey: ownerID)
        } else {
            spotlightOwnershipByHost[ownerID] = tileIDs
        }
        let combined = spotlightOwnershipByHost.values.reduce(into: Set<UUID>()) { $0.formUnion($1) }
        guard spotlightOwnedTileIDs != combined else { return }
        spotlightOwnedTileIDs = combined
    }

    func removeGroup(for tileID: UUID) {
        groups.removeValue(forKey: tileID)
        rootReferences.removeValue(forKey: tileID)
    }
}
