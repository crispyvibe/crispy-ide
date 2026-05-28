import Combine
import CoreGraphics
import Foundation

/// F049-v2: a comment surface is anything the user can attach a comment to —
/// a file editor (NSTextView), an HTML preview iframe, or a browser-window
/// WKWebView. Each surface implements this protocol so the panel +
/// coordinator code is surface-agnostic.
///
/// The protocol intentionally keeps the contract small: bridges that don't
/// need a behavior (e.g., browser surfaces don't render gutter rects in
/// SwiftUI) leave it as a no-op.
@MainActor
protocol CommentSurfaceBridge: AnyObject, ObservableObject {

    /// Bumps whenever the surface's geometry changes (scroll, layout). UI
    /// observers re-render highlights when this advances.
    var geometryTick: Int { get }

    /// Capture the user's current selection as a `CommentAnchor`. Returns
    /// nil if there is no usable selection on the surface.
    func captureSelectionAnchor() async -> CommentAnchor?

    /// Bring the comment's anchor into view and (where applicable) select it.
    /// File surfaces highlight the range; browser/HTML surfaces scroll to the
    /// element resolved by the selector.
    func scrollAndSelect(anchor: CommentAnchor) async

    /// Push the current per-surface thread list into the surface so it can
    /// render decorations / gutter buttons. Selected thread is highlighted.
    func syncDecorations(threads: [CommentThread], selectedThreadID: String?)
}

/// Convenience wrapper around `scrollAndSelect` that resolves the thread
/// against a store first. Implemented as a default extension so every
/// surface bridge inherits it.
extension CommentSurfaceBridge {
    func scrollToThread(id: String, in store: VibeSpaceCommentStore, surfaceTarget: String) async {
        guard let thread = store.threads(forFile: surfaceTarget).first(where: { $0.id == id }) else { return }
        await scrollAndSelect(anchor: thread.root.anchor)
    }
}
