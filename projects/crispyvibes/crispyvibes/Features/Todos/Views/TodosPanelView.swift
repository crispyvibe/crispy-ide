import SwiftUI

/// F053 — master list of todo cards for the dockable Todos surface. Themed via
/// the app palette and scaled via `crispyvibesUIScale` (responds to cmd+/cmd-):
/// tight card stack, accent-tinted selection with a leading bar, reveal-on-hover
/// delete, and a quiet quick-add.
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
    @FocusState private var quickAddFocused: Bool

    private var visibleTodos: [Todo] {
        let scoped = showAllInVibeSpace ? store.todos : store.filtered(byProject: focusedProjectPath)
        return scoped.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            quickAdd
            content
        }
        .background(palette.canvasBackgroundColor)
        .task { await store.refresh() }
    }

    private var header: some View {
        HStack(spacing: uiScale.spacing(8)) {
            Text(AppStrings.Todos.title)
                .font(.system(size: uiScale.textSize(13), weight: .semibold))
                .foregroundStyle(palette.primaryTextColor)
            Spacer()
            scopeToggle
        }
        .padding(.horizontal, uiScale.spacing(16))
        .padding(.top, uiScale.spacing(14))
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
        .frame(height: uiScale.chromeSize(36))
        .background(palette.canvasSecondaryBackgroundColor, in: RoundedRectangle(cornerRadius: theme.radius(8)))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(8))
                .stroke(quickAddFocused ? palette.accentColor.opacity(0.5) : palette.borderColorValue.opacity(0.4), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: quickAddFocused)
        .padding(.horizontal, uiScale.spacing(12))
        .padding(.bottom, uiScale.spacing(8))
    }

    @ViewBuilder
    private var content: some View {
        if visibleTodos.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: uiScale.spacing(2)) {
                    ForEach(visibleTodos) { todo in
                        TodoCardView(
                            todo: todo,
                            isSelected: todo.id == selectedTodoID,
                            onSelect: { selectedTodoID = todo.id },
                            onToggle: { toggle(todo) },
                            onDelete: { delete(todo) }
                        )
                    }
                }
                .padding(.horizontal, uiScale.spacing(12))
                .padding(.bottom, uiScale.spacing(12))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: uiScale.spacing(6)) {
            Image(systemName: "checklist")
                .font(.system(size: uiScale.iconSize(26)))
                .foregroundStyle(palette.tertiaryTextColor)
            Text(AppStrings.Todos.emptyTitle)
                .font(.system(size: uiScale.textSize(14), weight: .medium))
                .foregroundStyle(palette.secondaryTextColor)
            Text(AppStrings.Todos.emptyHint)
                .font(.system(size: uiScale.textSize(12)))
                .foregroundStyle(palette.tertiaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

    private func delete(_ todo: Todo) {
        if selectedTodoID == todo.id { selectedTodoID = nil }
        Task { await store.delete(id: todo.id) }
    }
}

/// A single todo row. Selection = accent-tinted fill + leading accent bar
/// (no loud full-border ring); delete reveals on hover.
private struct TodoCardView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var theme
    @Environment(\.crispyvibesUIScale) private var uiScale
    let todo: Todo
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: uiScale.spacing(10)) {
            Button(action: onToggle) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: uiScale.iconSize(16)))
                    .foregroundStyle(todo.isCompleted ? palette.accentColor : palette.tertiaryTextColor)
            }
            .buttonStyle(.plain)
            .help(AppStrings.Todos.complete)

            VStack(alignment: .leading, spacing: uiScale.spacing(2)) {
                Text(todo.title)
                    .font(.system(size: uiScale.textSize(14), weight: .medium))
                    .strikethrough(todo.isCompleted, color: palette.tertiaryTextColor)
                    .foregroundStyle(todo.isCompleted ? palette.tertiaryTextColor : palette.primaryTextColor)
                    .lineLimit(2)
                if let body = todo.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: uiScale.textSize(12)))
                        .foregroundStyle(palette.tertiaryTextColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: uiScale.iconSize(12)))
                        .foregroundStyle(palette.tertiaryTextColor)
                }
                .buttonStyle(.plain)
                .help(AppStrings.Todos.delete)
                .transition(.opacity)
            }
        }
        .padding(.vertical, uiScale.spacing(8))
        .padding(.horizontal, uiScale.spacing(10))
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(palette.accentColor)
                    .frame(width: uiScale.spacing(3))
                    .padding(.vertical, uiScale.spacing(6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(8)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            palette.accentColor.opacity(0.10)
        } else if isHovering {
            Color.primary.opacity(0.05)
        } else {
            Color.clear
        }
    }
}
