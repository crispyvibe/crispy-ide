import SwiftUI

/// F053 — detail pane for a selected todo. Themed via the app palette and
/// scaled via `crispyvibesUIScale`: editable title (commits on Return *and*
/// focus loss), sticky-color picker, created/completed metadata, an attached
/// file chip, a markdown notes block with a visible edit affordance, and the
/// activity thread + composer (see `TodoDetailView+Thread.swift`).
struct TodoDetailView: View {
    @Environment(\.appThemePalette) var palette
    @Environment(\.crispyvibesTheme) var theme
    @Environment(\.crispyvibesUIScale) var uiScale
    @ObservedObject var store: VibeSpaceTodoStore
    let todo: Todo
    /// Present in compact hosts: shows a back chevron that returns to the list.
    var onBack: (() -> Void)?

    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var isEditingBody = false
    @State private var isHoveringNotes = false
    @State private var confirmDelete = false
    @State var composerText = ""
    @FocusState private var titleFocused: Bool
    @FocusState var composerFocused: Bool

    var messages: [TodoMessage] { store.messages(forTodo: todo.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if onBack != nil { compactBar }
            ScrollView {
                VStack(alignment: .leading, spacing: uiScale.spacing(18)) {
                    header
                    metadata
                    notesSection
                    threadSection
                }
                .padding(uiScale.spacing(20))
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.canvasBackgroundColor)
        .task(id: todo.id) {
            draftTitle = todo.title
            draftBody = todo.body ?? ""
            isEditingBody = false
            confirmDelete = false
            composerText = ""
            await store.refreshMessages(todoID: todo.id)
        }
    }

    // MARK: Compact navigation

    private var compactBar: some View {
        HStack {
            Button(action: { onBack?() }) {
                HStack(spacing: uiScale.spacing(3)) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: uiScale.iconSize(11), weight: .semibold))
                    Text(AppStrings.Todos.back)
                        .font(.system(size: uiScale.textSize(12), weight: .medium))
                }
                .foregroundStyle(palette.secondaryTextColor)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.top, uiScale.spacing(12))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: uiScale.spacing(10)) {
            Button {
                Task { await store.setCompleted(id: todo.id, completed: !todo.isCompleted) }
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: uiScale.iconSize(18)))
                    .foregroundStyle(todo.isCompleted ? palette.accentColor : palette.tertiaryTextColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(todo.isCompleted ? AppStrings.Todos.reopen : AppStrings.Todos.complete)

            TextField("", text: $draftTitle, prompt: Text(AppStrings.Todos.titlePlaceholder).foregroundStyle(palette.tertiaryTextColor))
                .font(.system(size: uiScale.textSize(20), weight: .semibold))
                .foregroundStyle(palette.primaryTextColor)
                .textFieldStyle(.plain)
                .strikethrough(todo.isCompleted, color: palette.tertiaryTextColor)
                .focused($titleFocused)
                .onSubmit(commitTitle)
                .onChange(of: titleFocused) { _, focused in
                    if !focused { commitTitle() }
                }

            if confirmDelete {
                // Inline confirm in place of the trash — no dialog, no mouse travel.
                HStack(spacing: uiScale.spacing(5)) {
                    Text(AppStrings.Todos.deleteConfirmShort)
                        .font(.system(size: uiScale.textSize(11), weight: .medium))
                        .foregroundStyle(palette.errorColor)
                    Button(action: performDelete) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: uiScale.iconSize(15)))
                            .foregroundStyle(palette.errorColor)
                    }
                    .buttonStyle(.plain)
                    .help(AppStrings.Todos.deleteConfirmMessage)
                    Button { confirmDelete = false } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: uiScale.iconSize(15)))
                            .foregroundStyle(palette.tertiaryTextColor)
                    }
                    .buttonStyle(.plain)
                    .help(AppStrings.Todos.cancel)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: uiScale.iconSize(13)))
                        .foregroundStyle(palette.tertiaryTextColor)
                }
                .buttonStyle(.plain)
                .help(AppStrings.Todos.delete)
            }
        }
        .animation(.easeOut(duration: 0.12), value: confirmDelete)
    }

    private func performDelete() {
        confirmDelete = false
        let id = todo.id
        let back = onBack
        Task {
            await store.delete(id: id)
            back?()
        }
    }

    // MARK: Metadata

    private var metadata: some View {
        HStack(spacing: uiScale.spacing(10)) {
            colorPicker
            metaText("\(AppStrings.Todos.createdLabel) \(TodoTime.relative(todo.createdAt))")
            if todo.isCompleted, let completedAt = todo.completedAt {
                metaText("· \(AppStrings.Todos.completedLabel) \(TodoTime.relative(completedAt))")
            }
            if let projectName = todo.projectPath.map({ ($0 as NSString).lastPathComponent }) {
                metaChip(projectName, systemImage: "folder")
            }
            if let filePath = todo.filePath, !filePath.isEmpty {
                metaChip((filePath as NSString).lastPathComponent, systemImage: "doc")
                    .help("\(AppStrings.Todos.attachedFile): \(filePath)")
            }
            Spacer()
        }
    }

    private var colorPicker: some View {
        HStack(spacing: uiScale.spacing(4)) {
            ForEach(TodoStickyColor.allCases, id: \.self) { color in
                Button {
                    let next = todo.stickyColor == color ? "" : color.rawValue
                    Task { await store.update(id: todo.id, colorTag: next) }
                } label: {
                    Circle()
                        .fill(color.color.opacity(todo.stickyColor == color ? 1.0 : 0.45))
                        .frame(width: uiScale.iconSize(12), height: uiScale.iconSize(12))
                        .overlay {
                            if todo.stickyColor == color {
                                Circle().stroke(palette.primaryTextColor.opacity(0.6), lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(color.displayName)
            }
        }
    }

    private func metaText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: uiScale.textSize(11)))
            .foregroundStyle(palette.tertiaryTextColor)
    }

    private func metaChip(_ text: String, systemImage: String) -> some View {
        HStack(spacing: uiScale.spacing(3)) {
            Image(systemName: systemImage).font(.system(size: uiScale.iconSize(9)))
            Text(text).font(.system(size: uiScale.textSize(10), weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(palette.secondaryTextColor)
        .padding(.horizontal, uiScale.spacing(6))
        .padding(.vertical, uiScale.spacing(2))
        .background(palette.canvasSecondaryBackgroundColor, in: Capsule())
    }

    // MARK: Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(6)) {
            sectionLabel(AppStrings.Todos.notesLabel)
            if isEditingBody {
                notesEditor
            } else {
                notesPreview
            }
        }
    }

    private var notesEditor: some View {
        VStack(alignment: .trailing, spacing: uiScale.spacing(8)) {
            TextEditor(text: $draftBody)
                .font(.system(size: uiScale.textSize(14)))
                .foregroundStyle(palette.primaryTextColor)
                .scrollContentBackground(.hidden)
                .frame(minHeight: uiScale.chromeSize(90))
                .padding(uiScale.spacing(8))
                .background(palette.canvasSecondaryBackgroundColor, in: RoundedRectangle(cornerRadius: theme.radius(8)))
                .overlay(RoundedRectangle(cornerRadius: theme.radius(8)).stroke(palette.accentColor.opacity(0.35), lineWidth: 1))
                .onExitCommand(perform: cancelBodyEdit)
            HStack(spacing: uiScale.spacing(8)) {
                Button(AppStrings.Todos.cancel, action: cancelBodyEdit)
                    .buttonStyle(.crispyvibesText)
                Button(AppStrings.Todos.save, action: commitBody)
                    .buttonStyle(.crispyvibesPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var notesPreview: some View {
        Button { isEditingBody = true } label: {
            HStack(alignment: .top, spacing: uiScale.spacing(8)) {
                MarkdownText(todo.body ?? "", placeholder: AppStrings.Todos.bodyPlaceholder)
                    .font(.system(size: uiScale.textSize(14)))
                    .foregroundStyle((todo.body ?? "").isEmpty ? palette.tertiaryTextColor : palette.secondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isHoveringNotes {
                    HStack(spacing: uiScale.spacing(3)) {
                        Image(systemName: "pencil").font(.system(size: uiScale.iconSize(10)))
                        Text(AppStrings.Todos.editNotes).font(.system(size: uiScale.textSize(11), weight: .medium))
                    }
                    .foregroundStyle(palette.accentColor)
                    .transition(.opacity)
                }
            }
            .padding(uiScale.spacing(8))
            .background(
                isHoveringNotes ? palette.canvasSecondaryBackgroundColor.opacity(0.6) : Color.clear,
                in: RoundedRectangle(cornerRadius: theme.radius(8))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHoveringNotes = hovering }
        }
    }

    // MARK: Helpers

    func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: uiScale.textSize(11), weight: .medium))
            .tracking(0.5)
            .foregroundStyle(palette.tertiaryTextColor)
    }

    private func commitTitle() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != todo.title else {
            draftTitle = todo.title
            return
        }
        Task { await store.update(id: todo.id, title: trimmed) }
    }

    private func cancelBodyEdit() {
        draftBody = todo.body ?? ""
        isEditingBody = false
    }

    private func commitBody() {
        isEditingBody = false
        Task { await store.update(id: todo.id, body: draftBody) }
    }
}
