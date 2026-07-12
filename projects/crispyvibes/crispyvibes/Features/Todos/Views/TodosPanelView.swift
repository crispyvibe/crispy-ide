import SwiftUI

/// F053 — master list of todo cards for the dockable Todos surface. Themed via
/// the app palette and scaled via `crispyvibesUIScale` (responds to cmd+/cmd-).
/// Active and completed todos live in separate sections with counts; sorting is
/// stable (creation order) so cards never jump while you work. Sticky colors
/// paint a leading edge on each card. Errors surface in a dismissible banner,
/// deletes confirm, and ↑/↓/⌫/⎋ work once the list has focus.
struct TodosPanelView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var theme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var store: VibeSpaceTodoStore
    /// Focused project path; `nil` ⇒ vibespace-level scope.
    let focusedProjectPath: String?
    @Binding var selectedTodoID: String?

    @State private var showAllInVibeSpace = false
    @State private var draftTitle = ""
    @State private var searchQuery = ""
    @State private var showCompleted = false
    @State private var confirmingDeleteID: String?
    @FocusState private var quickAddFocused: Bool
    @FocusState private var listFocused: Bool

    private var sections: (active: [Todo], completed: [Todo]) {
        TodoListSections.shape(
            store.todos,
            projectPath: focusedProjectPath,
            includeAllProjects: showAllInVibeSpace,
            query: searchQuery
        )
    }

    var body: some View {
        let shaped = sections
        VStack(spacing: 0) {
            header(active: shaped.active.count, completed: shaped.completed.count)
            if let error = store.lastErrorMessage {
                errorBanner(error)
            }
            quickAdd
            searchField
            content(shaped)
        }
        .background(palette.canvasBackgroundColor)
        .task(id: focusedProjectPath) { await store.refresh() }
    }

    // MARK: Header

    private func header(active: Int, completed: Int) -> some View {
        HStack(spacing: uiScale.spacing(8)) {
            VStack(alignment: .leading, spacing: uiScale.spacing(1)) {
                Text(AppStrings.Todos.title)
                    .font(.system(size: uiScale.textSize(13), weight: .semibold))
                    .foregroundStyle(palette.primaryTextColor)
                Text("\(active) \(AppStrings.Todos.activeSection.lowercased()) · \(completed) \(AppStrings.Todos.completedSection.lowercased())")
                    .font(.system(size: uiScale.textSize(10)))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
            Spacer()
            scopeToggle
        }
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.top, uiScale.spacing(12))
        .padding(.bottom, uiScale.spacing(10))
    }

    private var scopeToggle: some View {
        HStack(spacing: 0) {
            scopeSegment(AppStrings.Todos.scopeProject, active: !showAllInVibeSpace) { showAllInVibeSpace = false }
            scopeSegment(AppStrings.Todos.scopeAll, active: showAllInVibeSpace) { showAllInVibeSpace = true }
        }
        .padding(2)
        .background(palette.canvasSecondaryBackgroundColor, in: Capsule())
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showAllInVibeSpace)
    }

    private func scopeSegment(_ title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: uiScale.textSize(11), weight: .medium))
                .foregroundStyle(active ? palette.primaryTextColor : palette.tertiaryTextColor)
                .padding(.horizontal, uiScale.spacing(10))
                .padding(.vertical, uiScale.spacing(3))
                .background {
                    if active { Capsule().fill(Color.primary.opacity(0.10)) }
                }
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: uiScale.spacing(6)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: uiScale.iconSize(11)))
                .foregroundStyle(palette.warningColor)
            Text(message)
                .font(.system(size: uiScale.textSize(11)))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(AppStrings.Todos.dismissError) { store.clearLastError() }
                .buttonStyle(.plain)
                .font(.system(size: uiScale.textSize(11), weight: .medium))
                .foregroundStyle(palette.accentColor)
        }
        .padding(.horizontal, uiScale.spacing(10))
        .padding(.vertical, uiScale.spacing(6))
        .background(palette.warningColor.opacity(0.10), in: RoundedRectangle(cornerRadius: theme.radius(6)))
        .padding(.horizontal, uiScale.spacing(12))
        .padding(.bottom, uiScale.spacing(8))
    }

    // MARK: Quick add + search

    private var quickAdd: some View {
        HStack(spacing: uiScale.spacing(8)) {
            Image(systemName: "plus")
                .font(.system(size: uiScale.iconSize(12), weight: .medium))
                .foregroundStyle(palette.tertiaryTextColor)
            TextField("", text: $draftTitle, prompt: Text(AppStrings.Todos.quickAddPlaceholder).foregroundStyle(palette.tertiaryTextColor))
                .textFieldStyle(.plain)
                .font(.system(size: uiScale.textSize(13)))
                .foregroundStyle(palette.primaryTextColor)
                .focused($quickAddFocused)
                .onSubmit(submitDraft)
        }
        .padding(.horizontal, uiScale.spacing(12))
        .frame(height: uiScale.chromeSize(34))
        .background(palette.canvasSecondaryBackgroundColor, in: RoundedRectangle(cornerRadius: theme.radius(8)))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(8))
                .stroke(quickAddFocused ? palette.accentColor.opacity(0.5) : palette.borderColorValue.opacity(0.4), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: quickAddFocused)
        .padding(.horizontal, uiScale.spacing(12))
        .padding(.bottom, uiScale.spacing(6))
    }

    @ViewBuilder
    private var searchField: some View {
        if store.todos.count > 5 || !searchQuery.isEmpty {
            HStack(spacing: uiScale.spacing(6)) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: uiScale.iconSize(11)))
                    .foregroundStyle(palette.tertiaryTextColor)
                TextField("", text: $searchQuery, prompt: Text(AppStrings.Todos.searchPlaceholder).foregroundStyle(palette.tertiaryTextColor))
                    .textFieldStyle(.plain)
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(palette.primaryTextColor)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: uiScale.iconSize(11)))
                            .foregroundStyle(palette.tertiaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, uiScale.spacing(12))
            .frame(height: uiScale.chromeSize(28))
            .padding(.horizontal, uiScale.spacing(12))
            .padding(.bottom, uiScale.spacing(4))
        }
    }

    // MARK: List

    @ViewBuilder
    private func content(_ shaped: (active: [Todo], completed: [Todo])) -> some View {
        if shaped.active.isEmpty, shaped.completed.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: uiScale.spacing(4)) {
                    ForEach(shaped.active) { todo in
                        card(todo)
                    }
                    if !shaped.completed.isEmpty {
                        completedHeader(count: shaped.completed.count)
                        if showCompleted {
                            ForEach(shaped.completed) { todo in
                                card(todo)
                            }
                        }
                    }
                }
                .padding(.horizontal, uiScale.spacing(12))
                .padding(.top, uiScale.spacing(4))
                .padding(.bottom, uiScale.spacing(12))
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onMoveCommand(perform: moveSelection)
            .onDeleteCommand(perform: deleteCommand)
            .onExitCommand {
                if confirmingDeleteID != nil {
                    confirmingDeleteID = nil
                } else {
                    selectedTodoID = nil
                }
            }
        }
    }

    private func card(_ todo: Todo) -> some View {
        TodoCardView(
            todo: todo,
            isSelected: todo.id == selectedTodoID,
            isConfirmingDelete: todo.id == confirmingDeleteID,
            onSelect: {
                selectedTodoID = todo.id
                confirmingDeleteID = nil
                listFocused = true
            },
            onToggle: { toggle(todo) },
            onRequestDelete: { confirmingDeleteID = todo.id },
            onConfirmDelete: { performDelete(todo) },
            onCancelDelete: { confirmingDeleteID = nil },
            onColor: { color in Task { await store.update(id: todo.id, colorTag: color?.rawValue ?? "") } }
        )
    }

    private func completedHeader(count: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { showCompleted.toggle() }
        } label: {
            HStack(spacing: uiScale.spacing(5)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: uiScale.iconSize(9), weight: .semibold))
                    .rotationEffect(.degrees(showCompleted ? 90 : 0))
                Text("\(AppStrings.Todos.completedSection) (\(count))")
                    .font(.system(size: uiScale.textSize(11), weight: .medium))
                Spacer()
            }
            .foregroundStyle(palette.tertiaryTextColor)
            .padding(.horizontal, uiScale.spacing(4))
            .padding(.top, uiScale.spacing(10))
            .padding(.bottom, uiScale.spacing(2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: uiScale.spacing(6)) {
            Image(systemName: searchQuery.isEmpty ? "checklist" : "magnifyingglass")
                .font(.system(size: uiScale.iconSize(26)))
                .foregroundStyle(palette.tertiaryTextColor)
            Text(searchQuery.isEmpty ? AppStrings.Todos.emptyTitle : AppStrings.Todos.noMatches)
                .font(.system(size: uiScale.textSize(14), weight: .medium))
                .foregroundStyle(palette.secondaryTextColor)
            if searchQuery.isEmpty {
                Text(AppStrings.Todos.emptyHint)
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func submitDraft() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        draftTitle = ""
        let project = showAllInVibeSpace ? nil : focusedProjectPath
        Task {
            if let created = await store.add(title: title, projectPath: project) {
                selectedTodoID = created.id
            }
        }
    }

    private func toggle(_ todo: Todo) {
        Task { await store.setCompleted(id: todo.id, completed: !todo.isCompleted) }
    }

    private func performDelete(_ todo: Todo) {
        confirmingDeleteID = nil
        if selectedTodoID == todo.id { selectedTodoID = nil }
        Task { await store.delete(id: todo.id) }
    }

    /// First ⌦ arms the inline confirm on the selected card; a second ⌦ commits.
    private func deleteCommand() {
        guard let todo = selectedTodo() else { return }
        if confirmingDeleteID == todo.id {
            performDelete(todo)
        } else {
            confirmingDeleteID = todo.id
        }
    }

    private func selectedTodo() -> Todo? {
        guard let id = selectedTodoID else { return nil }
        return store.todo(withID: id)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let shaped = sections
        let ordered = shaped.active + (showCompleted ? shaped.completed : [])
        guard !ordered.isEmpty else { return }
        let currentIndex = ordered.firstIndex { $0.id == selectedTodoID }
        switch direction {
        case .down:
            let next = currentIndex.map { min($0 + 1, ordered.count - 1) } ?? 0
            selectedTodoID = ordered[next].id
            confirmingDeleteID = nil
        case .up:
            let previous = currentIndex.map { max($0 - 1, 0) } ?? (ordered.count - 1)
            selectedTodoID = ordered[previous].id
            confirmingDeleteID = nil
        default:
            break
        }
    }
}

/// Sticky-note swatch colors (content colors, like project color tags).
extension TodoStickyColor {
    var color: Color {
        switch self {
        case .yellow: return Color(.sRGB, red: 0.95, green: 0.78, blue: 0.25)
        case .green: return Color(.sRGB, red: 0.45, green: 0.77, blue: 0.45)
        case .blue: return Color(.sRGB, red: 0.35, green: 0.62, blue: 0.93)
        case .pink: return Color(.sRGB, red: 0.93, green: 0.51, blue: 0.67)
        case .purple: return Color(.sRGB, red: 0.66, green: 0.53, blue: 0.93)
        case .orange: return Color(.sRGB, red: 0.95, green: 0.60, blue: 0.29)
        }
    }

    var displayName: String { rawValue.capitalized }
}
