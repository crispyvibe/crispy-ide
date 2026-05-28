import SwiftUI

/// F049: SwiftUI environment key for the per-pane code editor comment
/// bridge. When non-nil, `CodeEditorView` registers its NSTextView with
/// the bridge so SwiftUI overlays can render gutter dots and content
/// highlights using accurate text geometry.
private struct CodeEditorCommentBridgeKey: EnvironmentKey {
    static let defaultValue: CodeEditorCommentBridge? = nil
}

private struct VibeSpaceCommentStoreKey: EnvironmentKey {
    static let defaultValue: VibeSpaceCommentStore? = nil
}

private struct CommentsPanelStoreKey: EnvironmentKey {
    static let defaultValue: CommentsPanelStore? = nil
}

private struct CommentsFilePathKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var codeEditorCommentBridge: CodeEditorCommentBridge? {
        get { self[CodeEditorCommentBridgeKey.self] }
        set { self[CodeEditorCommentBridgeKey.self] = newValue }
    }

    /// F049: comment store for the active vibespace; consumed by rich-mode
    /// editors (markdown/HTML in WKWebView) that need to read threads
    /// directly to drive JS-side decorations.
    var vibespaceCommentStoreEnvironment: VibeSpaceCommentStore? {
        get { self[VibeSpaceCommentStoreKey.self] }
        set { self[VibeSpaceCommentStoreKey.self] = newValue }
    }

    /// F049: per-pane comments panel state; rich-mode editors read
    /// `selectedThreadID` to drive decoration emphasis.
    var commentsPanelEnvironment: CommentsPanelStore? {
        get { self[CommentsPanelStoreKey.self] }
        set { self[CommentsPanelStoreKey.self] = newValue }
    }

    /// F049: file path of the currently-displayed file in the active pane.
    /// Used by rich-mode editors to filter threads.
    var commentsFilePathEnvironment: String? {
        get { self[CommentsFilePathKey.self] }
        set { self[CommentsFilePathKey.self] = newValue }
    }
}
