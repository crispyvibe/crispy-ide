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
                    panelResizeHandle(totalWidth: proxy.size.width)
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

    private func panelResizeHandle(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let panelWidth = totalWidth - value.location.x
                        let fraction = panelWidth / totalWidth
                        panel.widthFraction = min(
                            CommentsPanelStore.maxWidthFraction,
                            max(CommentsPanelStore.minWidthFraction, fraction)
                        )
                    }
            )
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
            )
    }
}
