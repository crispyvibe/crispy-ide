import SwiftUI

/// F049-R06: floating Liquid Glass entry point for the comments panel,
/// matching the terminal scroll-assist pattern (F046).
///
/// Placement: `.overlay(alignment: .bottomTrailing)` on the file content
/// area. Single tap toggles the panel for the active pane. Shows the
/// active comment count when non-zero.
@MainActor
struct CommentsFloatingButton: View {
    @ObservedObject var panel: CommentsPanelStore
    let activeCount: Int
    let isAvailable: Bool

    var body: some View {
        if isAvailable {
            ScrollAssistGlassContainer(spacing: 6) {
                Button(action: { panel.togglePanel() }) {
                    HStack(spacing: 4) {
                        Image(systemName: panel.isOpen
                              ? "quote.bubble.fill"
                              : "quote.bubble")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.85))
                        if activeCount > 0 {
                            Text("\(activeCount)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary.opacity(0.85))
                                .padding(.trailing, 2)
                        }
                    }
                    .padding(.horizontal, activeCount > 0 ? 10 : 8)
                    .frame(height: 28)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .scrollAssistGlassBackground(in: Capsule())
                .help(panel.isOpen
                      ? AppStrings.Comments.closePanel
                      : AppStrings.Comments.toolbarToggleHelp)
                .accessibilityIdentifier("comments.floating.toggle")
            }
            .padding(12)
        }
    }
}
