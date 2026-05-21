import SwiftUI

/// Python editor wrapper that reuses shared code editor rendering/theming.
struct PythonFileViewer: View {
    let fileURL: URL
    var isBufferLoading: Bool = false
    var pendingSourceSelection: MarkdownViewModel.SourceSelection? = nil
    var onPendingSourceSelectionConsumed: (() -> Void)? = nil
    @Binding var content: String
    let onContentChange: (String) -> Void

    var body: some View {
        CodeEditorView(
            fileURL: fileURL,
            language: PythonLanguage(),
            pendingSourceSelection: pendingSourceSelection,
            onPendingSourceSelectionConsumed: onPendingSourceSelectionConsumed,
            isBufferLoading: isBufferLoading,
            content: $content,
            onContentChange: onContentChange
        )
    }
}
