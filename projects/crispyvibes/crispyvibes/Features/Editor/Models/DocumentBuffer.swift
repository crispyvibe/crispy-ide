import Foundation

/// Manages the in-memory content and lifecycle state of a single open document.
///
/// State transitions follow a strict state machine — each mutation method
/// guards on the current state and is a no-op when the precondition is unmet.
@MainActor
final class DocumentBuffer: ObservableObject, Identifiable {

    /// The document identity string (matches `FileDocumentReference.documentIdentity`).
    let id: String

    /// On-disk location of the document.
    let fileURL: URL

    /// Current buffer lifecycle state.
    @Published private(set) var state: BufferState = .loading

    private var loadTask: Task<Void, Never>?

    /// The token for the in-flight save, if any.
    private(set) var activeSaveToken: SaveToken?

    /// Creates a buffer for the given document identity and file URL.
    init(id: String, fileURL: URL) {
        self.id = id
        self.fileURL = fileURL
    }

    // MARK: - Computed Properties

    /// The content to display in the editor, or empty string when loading/failed.
    var displayContent: String {
        switch state {
        case .clean(let content): return content
        case .dirty(let content, _): return content
        case .saving(let content, _, _): return content
        case .loading, .failed: return ""
        }
    }

    /// Whether the buffer has unsaved edits.
    var isDirty: Bool {
        if case .dirty = state { return true }
        return false
    }

    /// Whether a save is currently in flight.
    var isSaving: Bool {
        if case .saving = state { return true }
        return false
    }

    /// Whether the buffer is currently loading content from disk.
    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    /// Whether the last load attempt failed.
    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// The last-saved baseline content, if available.
    var baseline: String? {
        switch state {
        case .dirty(_, let baseline): return baseline
        case .saving(_, let baseline, _): return baseline
        default: return nil
        }
    }

    /// Whether a read task is already responsible for completing the current loading state.
    var hasActiveLoadTask: Bool {
        loadTask != nil
    }

    // MARK: - Load

    /// Starts an async load, cancelling any previous in-flight load.
    func beginLoad(read: @escaping () async throws -> String) {
        guard case .loading = state else { return }
        cancelLoad()
        state = .loading
        loadTask = Task { [weak self] in
            do {
                let content = try await read()
                guard !Task.isCancelled else { return }
                self?.didLoad(content: content)
            } catch {
                guard !Task.isCancelled else { return }
                self?.didFailLoad(message: error.localizedDescription)
            }
        }
    }

    /// Starts an async load only when no existing load task is attached.
    func beginLoadIfNeeded(read: @escaping () async throws -> String) {
        guard case .loading = state else { return }
        guard !hasActiveLoadTask else { return }
        beginLoad(read: read)
    }

    /// Cancels any in-flight load task.
    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    /// Transitions from `.loading` → `.clean`. No-op otherwise.
    func didLoad(content: String) {
        guard case .loading = state else { return }
        state = .clean(content: content)
    }

    /// Transitions from `.loading` → `.failed`. No-op otherwise.
    func didFailLoad(message: String) {
        guard case .loading = state else { return }
        state = .failed(message: message)
    }

    // MARK: - Edit

    /// Applies an edit from the editor.
    ///
    /// - `.clean` → `.dirty` if content differs from clean content
    /// - `.dirty` → `.clean` if content matches baseline
    /// - `.dirty` → `.dirty` with new content
    /// - `.saving` → `.dirty` (edit arrived during save; keeps activeSaveToken valid)
    /// - `.loading` / `.failed` → no-op
    func applyEdit(_ content: String) {
        switch state {
        case .clean(let current):
            if content != current {
                state = .dirty(content: content, baseline: current)
            }
        case .dirty(_, let baseline):
            if content == baseline {
                state = .clean(content: baseline)
            } else {
                state = .dirty(content: content, baseline: baseline)
            }
        case .saving(_, let baseline, let token):
            state = .dirty(content: content, baseline: baseline)
            // Keep activeSaveToken — the in-flight save is still valid
            activeSaveToken = token
        case .loading, .failed:
            break
        }
    }

    // MARK: - Save

    /// Mints a save token and transitions `.dirty` → `.saving`. Returns `nil` if not dirty.
    func beginSave() -> SaveToken? {
        guard case .dirty(let content, let baseline) = state else { return nil }
        let token = SaveToken(id: UUID(), content: content)
        activeSaveToken = token
        state = .saving(content: content, baseline: baseline, token: token)
        return token
    }

    /// Completes a save. Guards on token match.
    ///
    /// - `.saving` → `.clean(content: token.content)`
    /// - `.dirty` (edit arrived during save) → `.dirty` with baseline updated to saved content
    func didSave(token: SaveToken) {
        guard token == activeSaveToken else { return }
        activeSaveToken = nil
        switch state {
        case .saving:
            state = .clean(content: token.content)
        case .dirty(let content, _):
            state = .dirty(content: content, baseline: token.content)
        default:
            break
        }
    }

    /// Handles a failed save. Guards on token match.
    ///
    /// - `.saving` → `.dirty`
    /// - `.dirty` → no change (already dirty from edit during save)
    func didFailSave(token: SaveToken) {
        guard token == activeSaveToken else { return }
        activeSaveToken = nil
        if case .saving(let content, let baseline, _) = state {
            state = .dirty(content: content, baseline: baseline)
        }
    }

    // MARK: - External

    /// Updates content from an external file-system change. Only applies when `.clean`.
    func externalContentChanged(_ content: String) {
        guard case .clean = state else { return }
        state = .clean(content: content)
    }

    /// Cancels any current load and starts a fresh reload.
    func beginReload(read: @escaping () async throws -> String) {
        cancelLoad()
        state = .loading
        beginLoad(read: read)
    }
}
