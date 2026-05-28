import AppKit
import SwiftUI

/// F049-R06: SwiftUI overlay drawn on top of the code editor that renders
/// gutter dots and content-range highlights using the
/// `CodeEditorCommentBridge` for pixel-accurate geometry.
///
/// The overlay re-renders whenever the bridge's `geometryTick` advances
/// (scroll, font change, content edit). We *read* `geometryTick` inside
/// `body` to declare the dependency without using `.id(...)` (which would
/// destroy and recreate the entire view tree on every scroll event — a
/// known SwiftUI anti-pattern that caused prior performance hangs).
@MainActor
struct CommentsCodeEditorOverlay: View {
    @ObservedObject var bridge: CodeEditorCommentBridge
    @ObservedObject var commentStore: VibeSpaceCommentStore
    @ObservedObject var panel: CommentsPanelStore
    let filePath: String

    var body: some View {
        // Read geometryTick to make this view depend on it WITHOUT changing
        // the identity of any subview. On scroll/frame changes, only the
        // computed rect math reruns; child views diff in place.
        let _ = bridge.geometryTick
        let scrollOrigin = bridge.enclosingScroll?.contentView.bounds.origin ?? .zero
        let threads = commentStore.threads(forFile: filePath)

        return ZStack(alignment: .topLeading) {
            ForEach(threads) { thread in
                decoration(
                    for: thread,
                    scrollOrigin: scrollOrigin,
                    isActive: panel.selectedThreadID == thread.id
                )
            }
        }
        .allowsHitTesting(true)
    }

    // MARK: - Decoration per thread

    @ViewBuilder
    private func decoration(
        for thread: CommentThread,
        scrollOrigin: CGPoint,
        isActive: Bool
    ) -> some View {
        let rects = bridge.rects(
            startLine: thread.root.anchor.startLine,
            startColumn: thread.root.anchor.startColumn,
            endLine: thread.root.anchor.endLine,
            endColumn: thread.root.anchor.endColumn
        )
        let isStale = thread.root.isStale
        let isResolved = thread.root.isResolved

        // Stable identity: thread.id + rect index. Avoids `.offset` (which
        // shifts under insertion) and avoids hashing CGRect by floating-
        // point value (sub-pixel deltas would cause spurious re-mounts).
        let identifiedRects = rects.enumerated().map { idx, rect in
            (id: "\(thread.id)-rect-\(idx)", rect: rect)
        }

        ForEach(identifiedRects, id: \.id) { entry in
            let display = entry.rect.offsetBy(dx: -scrollOrigin.x, dy: -scrollOrigin.y)
            highlightShape(isActive: isActive, isStale: isStale, isResolved: isResolved)
                .frame(width: max(2, display.width), height: max(2, display.height))
                .position(x: display.midX, y: display.midY)
                .onTapGesture {
                    panel.reveal(threadID: thread.id)
                }
                .accessibilityIdentifier("comments.editor-highlight.\(thread.id)")
        }

        // Gutter button at the start line — placed at the left edge of
        // the first rect.
        if let first = rects.first {
            let display = first.offsetBy(dx: -scrollOrigin.x, dy: -scrollOrigin.y)
            CommentGutterIndicator(
                status: thread.status,
                isAgentAuthored: thread.root.authorKind == .agent,
                isSelected: isActive,
                onTap: { panel.revealForReply(threadID: thread.id) }
            )
            .position(x: 8, y: display.midY)
        }
    }

    @ViewBuilder
    private func highlightShape(isActive: Bool, isStale: Bool, isResolved: Bool) -> some View {
        if isStale {
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .foregroundStyle(.orange.opacity(0.7))
        } else if isResolved {
            Rectangle().fill(Color.gray.opacity(0.06))
        } else if isActive {
            Rectangle()
                .fill(Color.accentColor.opacity(0.22))
                .overlay(Rectangle().stroke(Color.accentColor.opacity(0.6), lineWidth: 1))
        } else {
            Rectangle().fill(Color.accentColor.opacity(0.10))
        }
    }
}
