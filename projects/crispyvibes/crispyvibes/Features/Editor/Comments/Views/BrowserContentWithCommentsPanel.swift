import SwiftUI

/// F049-v2: docks the comments side-panel to the right of a browser view.
///
/// Mirrors `FileContentWithCommentsPanel` but targets the browser surface:
/// `filePath` here is the canonical URL of the page, and the
/// `BrowserPanelViewModel` provides both the panel store and the
/// underlying surface bridge.
@MainActor
struct BrowserContentWithCommentsPanel<BrowserContent: View>: View {
    @ObservedObject var panel: CommentsPanelStore
    @ObservedObject var viewModel: BrowserPanelViewModel
    let store: VibeSpaceCommentStore?
    let browserContent: () -> BrowserContent

    /// Canonical URL of the currently-loaded page — the comment-anchor key
    /// for browser surfaces.
    private var canonicalURL: String? {
        viewModel.currentURL.map { BrowserCommentURLNormalizer.canonicalize($0) }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                browserContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let store, panel.isOpen, let url = canonicalURL {
                    Divider()
                    CommentsPanelView(
                        store: store,
                        panel: panel,
                        filePath: url,
                        surfaceKind: .browser
                    )
                    .frame(width: proxy.size.width * panel.widthFraction)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: panel.isOpen)
        }
    }
}
