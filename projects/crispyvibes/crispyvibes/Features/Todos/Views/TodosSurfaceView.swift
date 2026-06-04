import SwiftUI

/// F053 — the dockable Todos surface. Master list on the left, detail with
/// notes + activity thread on the right. Themed via the app palette and scaled
/// via `crispyvibesUIScale` so it responds to cmd+/cmd-.
struct TodosSurfaceView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var store: VibeSpaceTodoStore
    let focusedProjectPath: String?

    @State private var selectedTodoID: String?

    var body: some View {
        HSplitView {
            TodosPanelView(
                store: store,
                focusedProjectPath: focusedProjectPath,
                selectedTodoID: $selectedTodoID
            )
            .frame(minWidth: uiScale.chromeSize(240), idealWidth: uiScale.chromeSize(300), maxHeight: .infinity)

            detail
                .frame(minWidth: uiScale.chromeSize(340), maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.canvasBackgroundColor)
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedTodoID, let todo = store.todo(withID: id) {
            TodoDetailView(store: store, todo: todo)
        } else {
            VStack(spacing: uiScale.spacing(6)) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: uiScale.iconSize(26)))
                    .foregroundStyle(palette.tertiaryTextColor)
                Text(AppStrings.Todos.selectPrompt)
                    .font(.system(size: uiScale.textSize(14), weight: .medium))
                    .foregroundStyle(palette.secondaryTextColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.canvasBackgroundColor)
        }
    }
}
