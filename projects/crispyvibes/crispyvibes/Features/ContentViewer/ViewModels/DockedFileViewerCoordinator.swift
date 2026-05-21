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
    private var previewGroup: EditorGroupStore?

    @Published var previewFileURL: URL?
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
        let normalized = reference.url
        previewFileURL = normalized
        let group = editorGroupFactory(UUID())
        group.openFileInTab(
            at: normalized,
            documentReference: reference,
            fileContentProvider: fileContentProvider
        )
        previewGroup = group
    }

    func dismissPreview() {
        previewFileURL = nil
        previewGroup = nil
    }

    /// Promotes the live preview editor group into the pinned tile, avoiding a fresh load.
    func promotePreview(to tileID: UUID?) {
        guard let tileID, let group = previewGroup else {
            dismissPreview()
            return
        }
        groups[tileID] = group
        previewFileURL = nil
        previewGroup = nil
    }

    func assignEditorGroup(
        _ group: EditorGroupStore,
        for tileID: UUID?,
        fileURL _: URL
    ) {
        guard let tileID else {
            dismissPreview()
            return
        }
        groups[tileID] = group
        previewFileURL = nil
        previewGroup = nil
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
        let targetTab = ContentViewerTab.file(reference: reference)

        if let existing = groups[tileID] {
            if existing.activeTabID != targetTab.id
                || existing.fileContentProvider(for: targetTab.id) == nil && fileContentProvider != nil {
                existing.openFileInTab(
                    at: reference.url,
                    documentReference: reference,
                    fileContentProvider: fileContentProvider
                )
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
        return group
    }

    func removeGroup(for tileID: UUID) {
        groups.removeValue(forKey: tileID)
    }
}
