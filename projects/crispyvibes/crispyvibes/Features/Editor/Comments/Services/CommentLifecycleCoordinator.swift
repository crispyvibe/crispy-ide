import Foundation
import OSLog

/// F049-R05 + F049-R13: orchestrates comment anchor relocation when files
/// are saved/reloaded, and adapts comment storage when files are
/// renamed/moved/deleted.
///
/// Listens to `vibespaceFileDidSave` (existing app notification). For
/// rename events, callers should invoke `handleFileRenamed(oldURL:newURL:)`
/// directly — there is no longer a static notification poster, since that
/// pattern hides the dependency from the call site.
///
/// Despite the historical "Coordinator" suffix the role is service-shaped
/// (no `ObservableObject`, no observed-by-views, no published state). The
/// type was kept to minimize call-site churn but is documented as a service.
@MainActor
final class CommentLifecycleCoordinator {

    private let store: VibeSpaceCommentStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app",
                                category: "comments.lifecycle")
    private var observers: [NSObjectProtocol] = []

    init(store: VibeSpaceCommentStore) {
        self.store = store
        observers.append(NotificationCenter.default.addObserver(
            forName: .vibespaceFileDidSave,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let url = note.object as? URL else { return }
            Task { @MainActor [weak self] in self?.handleFileChanged(url: url) }
        })
    }

    /// Explicit teardown for app-lifetime services per coding-guidelines:
    /// "Explicit `shutdown()` methods on types with long-lived resources".
    func shutdown() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
    }

    deinit {
        for o in observers {
            NotificationCenter.default.removeObserver(o)
        }
    }

    /// File saved (or externally reloaded). Re-anchor every comment on
    /// this file. Runs off the main actor for I/O, then hops back to MA
    /// to persist.
    private func handleFileChanged(url: URL) {
        let path = url.standardizedFileURL.path
        let threads = store.threads(forFile: path)
        guard !threads.isEmpty else { return }

        Task.detached(priority: .utility) { [weak store] in
            guard let store else { return }
            // Read the file off-main
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
            let lines = content.components(separatedBy: "\n")
            // Compute relocations
            var actions: [(id: String, anchor: CommentAnchor, isStale: Bool)] = []
            for thread in threads {
                let outcome = CommentAnchorRelocator.relocate(anchor: thread.root.anchor, in: lines)
                switch outcome {
                case .unchanged:
                    if thread.root.isStale {
                        // anchor matched again — clear stale
                        actions.append((thread.root.id, thread.root.anchor, false))
                    }
                case .relocated(let newAnchor, _):
                    actions.append((thread.root.id, newAnchor, false))
                case .stale:
                    if !thread.root.isStale {
                        actions.append((thread.root.id, thread.root.anchor, true))
                    }
                }
            }
            // Apply results back on the main actor.
            await MainActor.run {
                Task { @MainActor in
                    for action in actions {
                        await store.relocate(id: action.id, newAnchor: action.anchor, isStale: action.isStale)
                    }
                    if let vsID = store.threads(forFile: path).first?.root.vibespaceID {
                        await store.refreshFile(vibespaceID: vsID, filePath: path)
                    }
                }
            }
        }
    }

    /// Direct call from `VibeSpaceCanvasFileOpenUseCase` (and any other
    /// rename source) so file moves/renames propagate to the comment store.
    /// Replaces the previous `static postRename` + `NotificationCenter`
    /// roundtrip — dependencies are now visible at the call site.
    func handleFileRenamed(oldURL: URL, newURL: URL?) {
        let oldPath = oldURL.standardizedFileURL.path
        let newPath = newURL?.standardizedFileURL.path
        let threads = store.threads(forFile: oldPath)
        guard !threads.isEmpty else { return }
        logger.info(
            "comments lifecycle rename: oldPath=\(oldPath, privacy: .public) → newPath=\(newPath ?? "<deleted>", privacy: .public), threads=\(threads.count, privacy: .public)"
        )
        guard let newPath else {
            // File deleted — refresh so orphaned comments surface.
            Task { @MainActor [weak store] in await store?.refreshAll() }
            return
        }
        // Migrate comments to the new path via the persistence helper.
        Task { @MainActor [weak store] in
            guard let store, let vsID = store.currentVibeSpaceID() else { return }
            let params = CommentRPCEncoder.encodeMovePath(
                vibespaceID: vsID,
                oldPath: oldPath,
                newPath: newPath,
                surfaceKind: .file
            )
            _ = await store.conversationStore.send(method: "comment.movePath", params: params)
            await store.refreshAll()
        }
    }
}
