import Foundation

/// F049: cross-cutting notification names for comment UX flows that don't
/// fit cleanly into a single observable store.
///
/// The store-level "something changed" signal is exposed through
/// `VibeSpaceCommentStore.changes` (Combine) — not a notification — so
/// consumers can scope subscriptions to the specific store instance.
extension Notification.Name {
    /// Posted by the cross-file view when the user clicks a thread row to
    /// jump to its anchored location. UserInfo: `filePath` (String),
    /// `threadID` (String).
    static let commentsNavigateToThread = Notification.Name("comments.navigateToThread")

    /// Posted by the cross-file view when the user clicks a browser-thread
    /// row. UserInfo: `url` (String, canonical), `threadID` (String).
    /// `BrowserPanelViewModel`s observe this and navigate / scroll if the
    /// canonical URL matches their currently-loaded page.
    static let commentsNavigateToBrowserURL = Notification.Name("comments.navigateToBrowserURL")

    /// Posted by the editor when the user invokes "Add Comment to Selection".
    /// UserInfo: see `CommentAnchor.notificationPayload(filePath:)`.
    static let commentsRequestAddForSelection = Notification.Name("comments.requestAddForSelection")

    /// Posted when a file is renamed/moved/deleted in the vibespace.
    /// UserInfo: `oldPath` (String), `newPath` (String?, nil = deleted).
    static let commentsFileLifecycleDidChange = Notification.Name("comments.fileLifecycleDidChange")
}
