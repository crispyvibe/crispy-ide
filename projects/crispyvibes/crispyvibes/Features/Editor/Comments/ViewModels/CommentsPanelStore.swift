import Combine
import CoreGraphics
import Foundation

/// F049-R06: per-pane panel state. Each `EditorGroupStore` (one per pane)
/// owns its own instance so split layouts maintain independent panel
/// visibility, width, selection, and filter.
///
/// All state transitions go through named methods (no direct property
/// mutation from views). State that is bound to a SwiftUI `Binding`
/// (`searchQuery`, `statusFilter`, `widthFraction`) remains `var` because
/// the framework needs two-way write access.
@MainActor
final class CommentsPanelStore: ObservableObject {

    struct NavigationRequest: Equatable, Identifiable {
        let id = UUID()
        let threadID: String
    }

    // MARK: - Constants

    /// Minimum panel width as a fraction of the parent pane width.
    static let minWidthFraction: CGFloat = 0.20
    /// Maximum panel width as a fraction of the parent pane width.
    static let maxWidthFraction: CGFloat = 0.50

    // MARK: - Published state (read-only externally)

    /// Whether the side panel is shown for this pane.
    @Published private(set) var isOpen: Bool = false

    /// Currently-selected thread (drives the active highlight + scroll).
    @Published private(set) var selectedThreadID: String?

    /// One-shot row-click navigation. This is separate from `selectedThreadID`
    /// so clicking the already-selected thread still scrolls back to its anchor.
    @Published private(set) var navigationRequest: NavigationRequest?

    /// Active draft selection range for a brand-new comment (set when the
    /// user clicks "Add Comment" on a selection in the editor).
    @Published private(set) var pendingComposerAnchor: CommentAnchor?

    /// Thread ID to auto-open the reply composer for. Used by the gutter
    /// icon click flow to give a one-tap "quick reply" UX.
    @Published private(set) var autoOpenReplyForThreadID: String?

    // MARK: - Bindable state (two-way bound to SwiftUI controls)

    /// Fraction of the pane width occupied by the panel (clamped to
    /// `[minWidthFraction, maxWidthFraction]`).
    @Published var widthFraction: CGFloat = 0.30 {
        didSet {
            widthFraction = min(Self.maxWidthFraction, max(Self.minWidthFraction, widthFraction))
        }
    }

    /// Current visibility filter — defaults to active comments only.
    @Published var statusFilter: CommentStatusFilter = .active

    /// Free-text query bound to the panel search field.
    @Published var searchQuery: String = ""

    // MARK: - State transitions

    /// Toggle the panel open/closed.
    func togglePanel() {
        isOpen.toggle()
    }

    /// Force the panel closed.
    func close() {
        isOpen = false
    }

    /// Update the focused thread without changing panel visibility.
    func select(threadID: String?) {
        selectedThreadID = threadID
        if let threadID {
            navigationRequest = NavigationRequest(threadID: threadID)
        }
    }

    /// Open the panel and focus a specific thread.
    func reveal(threadID: String) {
        isOpen = true
        selectedThreadID = threadID
    }

    /// Open the panel, focus a thread, and request that its reply composer
    /// auto-open. Used by the gutter-icon "quick reply" flow.
    func revealForReply(threadID: String) {
        isOpen = true
        selectedThreadID = threadID
        autoOpenReplyForThreadID = threadID
    }

    /// Consume an auto-reply request: returns `true` and clears the flag
    /// iff `threadID` matches and the thread is not resolved. Called from
    /// `CommentThreadView` to flip its local composer state.
    func consumeAutoReply(forThreadID threadID: String, isResolved: Bool) -> Bool {
        guard autoOpenReplyForThreadID == threadID, !isResolved else { return false }
        autoOpenReplyForThreadID = nil
        return true
    }

    /// Open the panel with a composer pre-seeded for the given anchor.
    func startComposer(for anchor: CommentAnchor) {
        isOpen = true
        pendingComposerAnchor = anchor
        selectedThreadID = nil
    }

    /// Open a "blank" composer at the default anchor (line 1, no text).
    /// Triggered by the `+` button in the panel header.
    func startNewComment() {
        startComposer(for: .wholeLine(1, lineText: ""))
    }

    /// Cancel a pending composer.
    func cancelComposer() {
        pendingComposerAnchor = nil
    }

    /// Clear the composer + select the newly-created thread. Called from
    /// `submitNewComment` after a successful write.
    func completeNewComment(createdID: String) {
        pendingComposerAnchor = nil
        selectedThreadID = createdID
    }

    // MARK: - Notification handling

    /// Handles a `.commentsRequestAddForSelection` notification: parses the
    /// payload, builds a `CommentAnchor`, and opens the composer iff the
    /// notification's file path matches the active file. Encapsulating
    /// this here keeps the view layer free of payload-parsing logic.
    func handleAddForSelectionNotification(_ note: Notification, filePath: String) {
        guard let info = note.userInfo as? [String: Any] else { return }
        let notePath = info["filePath"] as? String
        guard notePath == nil || notePath == filePath else { return }
        let anchor = CommentAnchor.fromNotificationPayload(info)
        startComposer(for: anchor)
    }

    // MARK: - Filtering

    /// Apply a search/filter combination.
    func filteredThreads(_ allThreads: [CommentThread]) -> [CommentThread] {
        Self.filter(allThreads, status: statusFilter, query: searchQuery)
    }

    /// Shared filter helper used by both this store and the workspace-wide
    /// cross-file view. Centralizing the filter rules avoids drift between
    /// the panel and the global comments list.
    static func filter(
        _ threads: [CommentThread],
        status: CommentStatusFilter,
        query: String
    ) -> [CommentThread] {
        let lowerQuery = query.lowercased()
        return threads.filter { thread in
            switch status {
            case .active:
                if thread.status != .active { return false }
            case .resolved:
                if thread.status != .resolved { return false }
            case .stale:
                if thread.status != .stale { return false }
            case .all:
                break
            }
            if !lowerQuery.isEmpty {
                let matches = thread.allComments.contains { c in
                    c.body.lowercased().contains(lowerQuery)
                        || (c.authorLabel?.lowercased().contains(lowerQuery) ?? false)
                }
                if !matches { return false }
            }
            return true
        }
    }

    // MARK: - Multi-store write coordination
    //
    // These methods compose `VibeSpaceCommentStore` operations with panel
    // state transitions so views never need to coordinate two stores
    // themselves. Each returns a `Bool` indicating whether the write
    // succeeded; `submitNewComment` returns the created thread ID.

    /// Submit a brand-new comment. On success, the composer is dismissed
    /// and the new thread becomes the panel's selection. Defaults to
    /// `.file` surface; pass `.browser` for browser-window comments.
    func submitNewComment(
        body: String,
        filePath: String,
        anchor: CommentAnchor,
        store: VibeSpaceCommentStore,
        surfaceKind: CommentSurfaceKind = .file
    ) async -> Bool {
        guard let created = await store.add(
            filePath: filePath,
            anchor: anchor,
            body: body,
            surfaceKind: surfaceKind
        ) else {
            return false
        }
        completeNewComment(createdID: created.id)
        return true
    }

    /// Submit a reply to an existing thread. Reply target is the most
    /// recent reply (chain-style) or the root if no replies exist.
    func submitReply(
        body: String,
        thread: CommentThread,
        store: VibeSpaceCommentStore
    ) async -> Bool {
        let target = thread.replies.last?.id ?? thread.id
        let reply = await store.add(
            filePath: thread.root.filePath,
            anchor: thread.root.anchor,
            body: body,
            parentID: target,
            surfaceKind: thread.root.surfaceKind
        )
        return reply != nil
    }

    /// Edit an existing comment's body.
    func editComment(
        id: String,
        body: String,
        store: VibeSpaceCommentStore
    ) async -> Bool {
        await store.update(id: id, body: body)
    }

    /// Toggle thread resolution.
    func resolveThread(
        _ thread: CommentThread,
        store: VibeSpaceCommentStore
    ) async -> Bool {
        await store.resolve(id: thread.id, unresolve: thread.root.isResolved)
    }

    /// Delete a thread (cascades to all replies).
    func deleteThread(
        _ thread: CommentThread,
        store: VibeSpaceCommentStore
    ) async {
        _ = await store.delete(id: thread.id)
    }
}
