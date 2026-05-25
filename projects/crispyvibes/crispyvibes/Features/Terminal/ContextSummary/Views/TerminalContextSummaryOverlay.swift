import SwiftUI

/// Container that owns the per-mount view model as `@StateObject` and binds it to the
/// shared per-terminal `TerminalContextSummarySession`. The session itself is injected
/// from the host view (it lives on `TerminalSession`), so headline + timeline + LLM
/// state survive surface transitions. F041-R11.
struct TerminalContextSummaryOverlayContainer: View {
    let summarySession: TerminalContextSummarySession
    let isHovering: Bool

    @StateObject private var viewModel: TerminalContextSummaryViewModel

    nonisolated init(summarySession: TerminalContextSummarySession, isHovering: Bool) {
        self.summarySession = summarySession
        self.isHovering = isHovering
        _viewModel = StateObject(wrappedValue: MainActor.assumeIsolated {
            TerminalContextSummaryViewModel(session: summarySession)
        })
    }

    var body: some View {
        TerminalContextSummaryOverlay(viewModel: viewModel, isHovering: isHovering)
    }
}

/// Floating overlay showing AI-generated context summary for a terminal tile.
/// Collapsed: one-line headline pill. Expanded: recent activity timeline.
struct TerminalContextSummaryOverlay: View {
    @ObservedObject var viewModel: TerminalContextSummaryViewModel
    let isHovering: Bool

    @State private var autoDismissWork: DispatchWorkItem?
    @State private var isPanelHovered = false

    var body: some View {
        Group {
            if isHovering || viewModel.isExpanded, viewModel.headline != nil {
                VStack(spacing: 0) {
                    collapsedPill(headline: viewModel.headline ?? "")
                        .onTapGesture { viewModel.toggle() }

                    if viewModel.isExpanded {
                        Divider()
                            .padding(.horizontal, 8)
                        ContextSummaryTimelineView(entries: viewModel.timelineEntries)
                    }
                }
                .scrollAssistGlassBackground(in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: viewModel.isExpanded ? 420 : 320)
                .padding(.top, 6)
                .onHover { hovering in
                    isPanelHovered = hovering
                    if !hovering && viewModel.isExpanded {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak viewModel] in
                            guard let viewModel, !self.isPanelHovered else { return }
                            viewModel.collapse()
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isHovering)
        .animation(.spring(duration: 0.25), value: viewModel.isExpanded)
        .onChange(of: isHovering) { _, hovering in
            if hovering {
                startAutoDismiss()
            } else if !viewModel.isExpanded {
                cancelAutoDismiss()
            }
        }
    }

    private func collapsedPill(headline: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: phaseIcon(viewModel.phase))
                .font(AppTypographyTokens.caption2)
                .foregroundStyle(phaseColor(viewModel.phase))

            Text(headline)
                .font(AppTypographyTokens.captionMonospaced)
                .lineLimit(1)
                .truncationMode(.tail)

            if viewModel.isGenerating {
                ProgressView()
                    .controlSize(.mini)
            }

            Image(systemName: viewModel.isExpanded ? "chevron.up" : "chevron.down")
                .font(AppTypographyTokens.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func phaseIcon(_ phase: String) -> String {
        switch phase {
        case "building": return "hammer"
        case "testing": return "checkmark.circle"
        case "debugging": return "ant"
        case "deploying": return "arrow.up.circle"
        case "reviewing": return "eye"
        case "editing": return "pencil"
        case "searching": return "magnifyingglass"
        default: return "circle"
        }
    }

    private func phaseColor(_ phase: String) -> Color {
        switch phase {
        case "building", "deploying": return .orange
        case "testing": return .green
        case "debugging": return .red
        case "reviewing", "searching": return .blue
        case "editing": return .purple
        default: return .secondary
        }
    }

    // MARK: - Auto-Dismiss

    private func startAutoDismiss() {
        cancelAutoDismiss()
        let item = DispatchWorkItem { [weak viewModel] in
            guard let viewModel, !viewModel.isExpanded else { return }
            viewModel.collapse()
        }
        autoDismissWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: item)
    }

    private func cancelAutoDismiss() {
        autoDismissWork?.cancel()
        autoDismissWork = nil
    }
}
