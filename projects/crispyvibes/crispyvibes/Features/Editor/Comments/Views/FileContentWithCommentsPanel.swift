import SwiftUI

/// F049: docks the comments side-panel to the right of an editor view.
///
/// The editor view itself (e.g. `MarkdownEditorView`) is responsible for
/// rendering the in-editor overlay (gutter dots, content highlights) and
/// the floating glass toggle button. This wrapper just adds the right-edge
/// panel when `panel.isOpen` is true and forwards "Add Comment to
/// Selection" notifications into `CommentsPanelStore` (which encapsulates
/// the payload-parsing + state-transition policy).
@MainActor
struct FileContentWithCommentsPanel<EditorContent: View>: View {
    @ObservedObject var panel: CommentsPanelStore
    let store: VibeSpaceCommentStore?
    let filePath: String
    let editorContent: () -> EditorContent

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                editorContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onReceive(NotificationCenter.default.publisher(for: .commentsRequestAddForSelection)) { note in
                        panel.handleAddForSelectionNotification(note, filePath: filePath)
                    }

                if let store, panel.isOpen {
                    Divider()
                    CommentsPanelView(
                        store: store,
                        panel: panel,
                        filePath: filePath
                    )
                    .frame(width: proxy.size.width * panel.widthFraction)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: panel.isOpen)
        }
    }
}
