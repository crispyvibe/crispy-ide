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
    private struct OutstandingFlush {
        let projectIdentifier: String?
        let task: Task<Error?, Never>
    }
    private var outstandingFlushes: [OutstandingFlush] = []

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
        if let previewGroup {
            track(
                previewGroup.closeAllTabsForTeardown(),
                projectIdentifier: previewRootReference?.projectIdentifier
            )
        }
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

    @discardableResult
    func dismissPreview() -> [Task<Error?, Never>] {
        let projectIdentifier = previewRootReference?.projectIdentifier
        let flushTasks = previewGroup?.closeAllTabsForTeardown() ?? []
        track(flushTasks, projectIdentifier: projectIdentifier)
        previewFileURL = nil
        previewGroup = nil
        previewRootReference = nil
        return flushTasks
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
        fileURL: URL,
        documentReference: FileDocumentReference? = nil
    ) {
        guard let tileID else {
            dismissPreview()
            return
        }
        if let previewGroup, previewGroup !== group {
            track(
                previewGroup.closeAllTabsForTeardown(),
                projectIdentifier: previewRootReference?.projectIdentifier
            )
        }
        groups[tileID] = group
        rootReferences[tileID] = documentReference ?? FileDocumentReference(url: fileURL)
        previewFileURL = nil
        previewGroup = nil
        previewRootReference = nil
    }

    var previewEditorGroup: EditorGroupStore? { previewGroup }
    var previewProjectIdentifier: String? { previewRootReference?.projectIdentifier }

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

    @discardableResult
    func removeGroup(
        for tileID: UUID,
        projectIdentifier fallbackProjectIdentifier: String? = nil
    ) -> [Task<Error?, Never>] {
        let group = groups.removeValue(forKey: tileID)
        let projectIdentifier = rootReferences.removeValue(forKey: tileID)?.projectIdentifier
            ?? fallbackProjectIdentifier
        let flushTasks = group?.closeAllTabsForTeardown() ?? []
        track(flushTasks, projectIdentifier: projectIdentifier)
        return flushTasks
    }

    func handleDeletion(_ event: ExplorerDeletionEvent) {
        if let previewGroup {
            previewGroup.closeFileTabs(
                at: event.url,
                includeDescendants: event.isDirectory
            )
            if previewGroup.tabs.isEmpty {
                previewFileURL = nil
                self.previewGroup = nil
                previewRootReference = nil
            }
        }

        for (tileID, group) in groups {
            group.closeFileTabs(
                at: event.url,
                includeDescendants: event.isDirectory
            )
            if group.tabs.isEmpty {
                groups.removeValue(forKey: tileID)
                rootReferences.removeValue(forKey: tileID)
            }
        }
        let rootPath = event.url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        dockedFiles.removeAll { entry in
            let path = entry.fileURL.standardizedFileURL.path
            return path == rootPath || (event.isDirectory && path.hasPrefix(prefix))
        }
    }

    @discardableResult
    func removeAllGroups() -> [Task<Error?, Never>] {
        let existingGroups = groups
        groups.removeAll()
        for (tileID, group) in existingGroups {
            let flushTasks = group.closeAllTabsForTeardown()
            track(
                flushTasks,
                projectIdentifier: rootReferences[tileID]?.projectIdentifier
            )
        }
        rootReferences.removeAll()
        _ = dismissPreview()
        dockedFiles = []
        spotlightOwnershipByHost.removeAll()
        spotlightOwnedTileIDs = []
        let flushTasks = outstandingFlushes.map(\.task)
        outstandingFlushes.removeAll()
        return flushTasks
    }

    func takeOutstandingFlushTasks(
        forProjectIdentifier projectIdentifier: String
    ) -> [Task<Error?, Never>] {
        let matching = outstandingFlushes.filter {
            $0.projectIdentifier == projectIdentifier
        }
        outstandingFlushes.removeAll {
            $0.projectIdentifier == projectIdentifier
        }
        return matching.map(\.task)
    }

    private func track(
        _ tasks: [Task<Error?, Never>],
        projectIdentifier: String?
    ) {
        outstandingFlushes.append(contentsOf: tasks.map {
            OutstandingFlush(projectIdentifier: projectIdentifier, task: $0)
        })
    }
}
