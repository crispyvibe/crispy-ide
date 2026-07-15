import SwiftUI

/// F053 — the dockable Todos surface. Adapts to its container instead of
/// demanding a fixed split: wide hosts (spotlight, big panes) show the list
/// beside the detail; narrow panes collapse to a single column where selecting
/// a card pushes the detail with a back button. Themed via the app palette and
/// scaled via `crispyvibesUIScale` so it responds to cmd+/cmd-.
struct TodosSurfaceView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var store: VibeSpaceTodoStore
    let focusedProjectPath: String?
    /// F060: forwarded to the detail pane's Refine button (nil = hidden).
    var onRefine: ((Todo) -> Void)?
    /// F060: opens a linked file in the content viewer (path, line anchor).
    var onOpenFile: ((String, Int?) -> Void)?
    /// F060: jumps to the linked lane task's detail in Vibe Lanes.
    var onOpenLaneTask: ((UUID) -> Void)?

    @State private var selectedTodoID: String?

    private var breakpoint: CGFloat { uiScale.chromeSize(620) }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width < breakpoint {
                compactLayout
            } else {
                regularLayout
            }
        }
        .background(palette.canvasBackgroundColor)
    }

    // MARK: Wide: list + detail side by side

    private var regularLayout: some View {
        HStack(spacing: 0) {
            TodosPanelView(
                store: store,
                focusedProjectPath: focusedProjectPath,
                selectedTodoID: $selectedTodoID
            )
            .frame(width: uiScale.chromeSize(300))

            Divider().overlay(palette.borderColorValue.opacity(0.35))

            detail(showsBack: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Narrow: single column, detail pushes over the list

    @ViewBuilder
    private var compactLayout: some View {
        if let id = selectedTodoID, let todo = store.todo(withID: id) {
            TodoDetailView(
                store: store,
                todo: todo,
                onBack: { selectedTodoID = nil },
                focusedProjectPath: focusedProjectPath,
                onRefine: onRefine,
                onOpenFile: onOpenFile,
                onOpenLaneTask: onOpenLaneTask
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            TodosPanelView(
                store: store,
                focusedProjectPath: focusedProjectPath,
                selectedTodoID: $selectedTodoID
            )
        }
    }

    @ViewBuilder
    private func detail(showsBack: Bool) -> some View {
        if let id = selectedTodoID, let todo = store.todo(withID: id) {
            TodoDetailView(
                store: store,
                todo: todo,
                onBack: showsBack ? { selectedTodoID = nil } : nil,
                focusedProjectPath: focusedProjectPath,
                onRefine: onRefine,
                onOpenFile: onOpenFile,
                onOpenLaneTask: onOpenLaneTask
            )
        } else {
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: uiScale.spacing(8)) {
            Image(systemName: "checklist")
                .font(.system(size: uiScale.iconSize(28)))
                .foregroundStyle(palette.tertiaryTextColor)
            Text(AppStrings.Todos.selectPrompt)
                .font(.system(size: uiScale.textSize(14), weight: .medium))
                .foregroundStyle(palette.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvasBackgroundColor)
    }
}
