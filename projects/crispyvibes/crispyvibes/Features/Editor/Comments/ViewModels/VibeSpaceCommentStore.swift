import Combine
import Foundation
import OSLog

/// F049 — central store for all comments in the active vibespace.
///
/// Wraps the existing `AgentConversationStore` (which owns the persistence
/// helper subprocess). All `comment.*` JSON-RPC calls go through that single
/// helper. The store is `@MainActor` and exposes `@Published` state consumed
/// by per-pane panels and the workspace-wide cross-file view.
@MainActor
final class VibeSpaceCommentStore: ObservableObject {

    // MARK: - Public state

    /// All comments in the active vibespace, indexed by file path. Replies
    /// are nested under their root via `CommentThread`.
    @Published private(set) var threadsByFile: [CommentFileKey: [CommentThread]] = [:]

    /// Bumps on every successful write so views can coalesce-refresh (R11).
    @Published private(set) var lastChangeID: UUID = UUID()

    /// Latest user-visible error from a write attempt. Structured (not a
    /// raw string) per coding-guidelines: "User-facing errors should be
    /// structured types, not raw strings." The legacy `lastErrorMessage`
    /// computed property is preserved for view binding.
    @Published private(set) var lastError: CommentStoreError?

    /// Convenience for views that want to display the error verbatim. A
    /// computed property — does not duplicate state.
    var lastErrorMessage: String? { lastError?.userFacingMessage }

    /// Combine subject that fires whenever the store mutates. Subscribers
    /// (e.g. `MarkupRenderedEditor.Coordinator`) use it to re-sync without
    /// going through `NotificationCenter`.
    let changes = PassthroughSubject<Void, Never>()

    // MARK: - Dependencies

    let conversationStore: AgentConversationStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app",
                                category: "comments")
    private weak var activeVibeSpaceProvider: AnyObject?
    private var resolveActiveVibeSpaceID: (@MainActor () -> String?)?

    // MARK: - Init

    init(conversationStore: AgentConversationStore) {
        self.conversationStore = conversationStore
    }

    /// Late-bound binding to the currently-active vibespace ID. The store
    /// reads this on every operation so it always targets the live vibespace.
    ///
    /// Idempotent: only the first call wins. `makeContentViewDependencies`
    /// runs on every `ContentView.init` and constructs a fresh catalog each
    /// time, but only the first one is retained by `@StateObject`. If we
    /// rebind on every call, the closure ends up referencing a discarded
    /// catalog (weak ref → nil → "no active vibespace" errors at runtime).
    func bindActiveVibeSpace(provider: AnyObject, resolver: @escaping @MainActor () -> String?) {
        guard activeVibeSpaceProvider == nil, resolveActiveVibeSpaceID == nil else {
            return
        }
        self.activeVibeSpaceProvider = provider
        self.resolveActiveVibeSpaceID = resolver
    }

    /// Public read of the currently-active vibespace ID as the bound
    /// resolver sees it. Used by views that need to scope reads/writes
    /// without re-implementing the lookup.
    func currentVibeSpaceID() -> String? {
        resolveActiveVibeSpaceID?()
    }

    // MARK: - Public API: write operations

    /// Add a top-level comment (or reply if `parentID` is non-nil).
    @discardableResult
    func add(
        filePath: String,
        anchor: CommentAnchor,
        body: String,
        authorKind: CommentAuthorKind = .user,
        authorLabel: String? = nil,
        parentID: String? = nil,
        surfaceKind: CommentSurfaceKind = .file,
        vibespaceIDOverride: String? = nil
    ) async -> Comment? {
        guard let vibespaceID = vibespaceIDOverride ?? resolveActiveVibeSpaceID?() else {
            recordError(.noActiveVibeSpace); return nil
        }
        let id = UUID().uuidString
        let params = CommentRPCEncoder.encodeAdd(
            id: id,
            vibespaceID: vibespaceID,
            filePath: filePath,
            parentID: parentID,
            body: body,
            authorKind: authorKind,
            authorLabel: authorLabel,
            anchor: anchor,
            surfaceKind: surfaceKind
        )
        guard let result = await conversationStore.send(method: "comment.add", params: params) else {
            recordError(.helperUnavailable); return nil
        }
        if let err = result.errorMessage {
            recordError(.classify(err)); return nil
        }
        guard let value = result.value, let created = CommentRPCDecoder.decodeComment(value) else {
            recordError(.decodeFailed); return nil
        }
        await refreshFile(vibespaceID: vibespaceID, filePath: filePath)
        bumpChange()
        return created
    }

    /// Update the body of an existing comment.
    func update(id: String, body: String) async -> Bool {
        guard let result = await conversationStore.send(
            method: "comment.update",
            params: ["id": id, "body": body]
        ) else { recordError(.helperUnavailable); return false }
        if let err = result.errorMessage {
            recordError(.classify(err)); return false
        }
        await refreshAll()
        bumpChange()
        return true
    }

    /// Mark a comment thread resolved (or reopen it via `unresolve = true`).
    func resolve(id: String, unresolve: Bool = false) async -> Bool {
        guard let result = await conversationStore.send(
            method: "comment.resolve",
            params: ["id": id, "unresolve": unresolve]
        ) else { recordError(.helperUnavailable); return false }
        if let err = result.errorMessage {
            recordError(.classify(err)); return false
        }
        await refreshAll()
        bumpChange()
        return true
    }

    /// Delete a comment (cascades to all replies).
    @discardableResult
    func delete(id: String) async -> Int {
        guard let result = await conversationStore.send(
            method: "comment.delete",
            params: ["id": id]
        ) else { recordError(.helperUnavailable); return 0 }
        if let err = result.errorMessage {
            recordError(.classify(err)); return 0
        }
        let count = (result.value?["deletedCount"] as? Int) ?? 0
        await refreshAll()
        bumpChange()
        return count
    }

    /// Persist an anchor relocation result.
    func relocate(id: String, newAnchor: CommentAnchor, isStale: Bool) async {
        let params = CommentRPCEncoder.encodeRelocate(id: id, anchor: newAnchor, isStale: isStale)
        _ = await conversationStore.send(method: "comment.relocate", params: params)
        bumpChange()
    }

    /// Server-side full-text search via FTS5 (Rust `comment.search` RPC).
    /// Used by the agent CLI search handler so the SQL side does the heavy
    /// lifting instead of fetching everything and filtering in Swift.
    func search(
        query: String,
        filePrefix: String? = nil,
        status: CommentStatusFilter = .active,
        surfaceKind: CommentSurfaceKind? = nil
    ) async -> [Comment] {
        guard let vibespaceID = resolveActiveVibeSpaceID?() else {
            recordError(.noActiveVibeSpace); return []
        }
        var params: [String: Any] = [
            "vibespaceId": vibespaceID,
            "status": status.rawValue,
        ]
        if !query.isEmpty { params["query"] = query }
        if let filePrefix, !filePrefix.isEmpty { params["filePrefix"] = filePrefix }
        if let surfaceKind { params["surfaceKind"] = surfaceKind.rawValue }
        guard let result = await conversationStore.send(method: "comment.search", params: params) else {
            recordError(.helperUnavailable); return []
        }
        if let err = result.errorMessage {
            recordError(.classify(err)); return []
        }
        return decodeList(result.value)
    }

    // MARK: - Public API: read

    /// All threads for a file in the active vibespace.
    func threads(forFile filePath: String) -> [CommentThread] {
        guard let vsID = resolveActiveVibeSpaceID?() else { return [] }
        return threadsByFile[CommentFileKey(vibespaceID: vsID, filePath: filePath)] ?? []
    }

    /// Total active comment count (excluding resolved/stale) for a file.
    func activeCount(forFile filePath: String) -> Int {
        threads(forFile: filePath).filter { $0.status == .active }.count
    }

    /// O(1) thread-by-id lookup across the whole vibespace cache. Returns
    /// the thread (which may be a root or contain a reply with that id).
    func thread(withID id: String) -> CommentThread? {
        for threads in threadsByFile.values {
            if let hit = threads.first(where: { $0.id == id || $0.replies.contains(where: { $0.id == id }) }) {
                return hit
            }
        }
        return nil
    }

    /// O(1) parent comment lookup — used by the agent CLI reply handler
    /// to inherit file path + anchor.
    func comment(withID id: String) -> Comment? {
        for threads in threadsByFile.values {
            for thread in threads {
                if thread.root.id == id { return thread.root }
                if let reply = thread.replies.first(where: { $0.id == id }) { return reply }
            }
        }
        return nil
    }

    // MARK: - Refresh

    /// Reload the cache for a single file.
    func refreshFile(vibespaceID: String, filePath: String) async {
        guard let result = await conversationStore.send(
            method: "comment.list",
            params: CommentRPCEncoder.encodeList(vibespaceID: vibespaceID, filePath: filePath, status: .all)
        ) else { return }
        let comments = decodeList(result.value)
        let threads = Self.buildThreads(from: comments)
        let key = CommentFileKey(vibespaceID: vibespaceID, filePath: filePath)
        threadsByFile[key] = threads
    }

    /// Reload all comments for the active vibespace (used after broad changes).
    func refreshAll() async {
        guard let vsID = resolveActiveVibeSpaceID?() else { return }
        guard let result = await conversationStore.send(
            method: "comment.list",
            params: CommentRPCEncoder.encodeList(vibespaceID: vsID, filePath: nil, status: .all)
        ) else { return }
        let comments = decodeList(result.value)
        let threads = Self.buildThreads(from: comments)
        var grouped: [CommentFileKey: [CommentThread]] = [:]
        for thread in threads {
            let key = CommentFileKey(vibespaceID: thread.root.vibespaceID, filePath: thread.root.filePath)
            grouped[key, default: []].append(thread)
        }
        threadsByFile = grouped
    }

    /// UI-side "dismiss" for the latest error banner.
    func clearLastError() {
        lastError = nil
    }

    // MARK: - Internal helpers (also see VibeSpaceCommentStore+Helpers.swift)

    fileprivate func decodeList(_ value: [String: Any]?) -> [Comment] {
        guard let arr = value?["comments"] as? [[String: Any]] else { return [] }
        return arr.compactMap { CommentRPCDecoder.decodeComment($0) }
    }

    fileprivate func bumpChange() {
        lastChangeID = UUID()
        changes.send(())
    }

    fileprivate func recordError(_ error: CommentStoreError) {
        logger.warning("comment op error: \(error.userFacingMessage, privacy: .public)")
        lastError = error
    }
}
