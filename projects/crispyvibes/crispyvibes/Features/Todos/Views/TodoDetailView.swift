import Combine
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
    // F060: nil when the pipeline is absent — every pipeline affordance
    // disappears and the pane renders exactly as F053.
    @Environment(\.todoLanePipelineBridgeEnvironment) var pipelineBridge
    @Environment(\.todoTriageCoordinatorEnvironment) var triageCoordinator
    @Environment(\.vibeLaneTaskManagerEnvironment) var laneManager
    @ObservedObject var store: VibeSpaceTodoStore
    let todo: Todo
    /// Present in compact hosts: shows a back chevron that returns to the list.
    var onBack: (() -> Void)?
    /// F060: project used for dispatch when the todo is vibespace-level.
    var focusedProjectPath: String?
    /// F060: opens/reattaches the refine chat for this todo. nil = host can't
    /// present ACP panes (e.g. spotlight) — the button hides.
    var onRefine: ((Todo) -> Void)?
    /// F060: opens a linked file in the content viewer (path, line anchor).
    var onOpenFile: ((String, Int?) -> Void)?
    /// F060: jumps to the linked lane task's detail in the Vibe Lanes surface.
    var onOpenLaneTask: ((UUID) -> Void)?

    @State var isDropTargetedForLinks = false
    /// Environment objects aren't auto-observed; tick on their changes so the
    /// triage indicator and lane-task chip stay live (matches TodoCardView).
    @State private var pipelineTick = 0
    /// F060: shared inline file-search trigger (F038) for the notes editor and
    /// thread composer — same component VibeCast and the ACP chat embed.
    @StateObject var inlineTrigger = TerminalInlineTriggerController()
    @AppStorage(AppPreferences.terminalComposeInlineTriggerKey)
    var configuredInlineTrigger = AppPreferences.defaultTerminalComposeInlineTrigger

    @State private var draftTitle = ""
    // draftBody/isEditingBody are internal (not private) so the +InlineTrigger
    // extension can route insertions into whichever field is being edited.
    @State var draftBody = ""
    @State var isEditingBody = false
    @State private var isHoveringNotes = false
    @State private var confirmDelete = false
    @State private var showDispatchSheet = false
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
                    fileLinksSection
                    notesSection
                    threadSection
                }
                .padding(uiScale.spacing(20))
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.canvasBackgroundColor)
        .overlay {
            if isDropTargetedForLinks {
                RoundedRectangle(cornerRadius: theme.radius(10))
                    .stroke(palette.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(uiScale.spacing(6))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargetedForLinks) { providers in
            handleFileDrop(providers: providers)
        }
        .overlay(alignment: .bottom) {
            inlineTriggerPanel
                .padding(.bottom, uiScale.spacing(64))
        }
        .onChange(of: draftBody) { _, newValue in
            if isEditingBody { inlineTrigger.syncBufferText(newValue) }
        }
        .onChange(of: composerText) { _, newValue in
            if !isEditingBody { inlineTrigger.syncBufferText(newValue) }
        }
        .onKeyPress(phases: .down) { press in
            inlineTriggerKeyHandler(press)
        }
        .onDisappear { inlineTrigger.shutdown() }
        .onReceive(pipelinePulse) { _ in pipelineTick &+= 1 }
        // F060 — detected path links (in notes and thread messages) open in
        // the content viewer like terminal-board paths; web links pass through.
        .environment(\.openURL, OpenURLAction { url in
            ACPTextLinking.handle(
                url: url,
                onLinkTargetActivated: nil,
                onFileSystemTargetActivated: { target in
                    onOpenFile?(target.url.path, target.line)
                }
            )
        })
        .task(id: todo.id) {
            draftTitle = todo.title
            draftBody = todo.body ?? ""
            isEditingBody = false
            confirmDelete = false
            composerText = ""
            configureInlineTrigger()
            inlineTrigger.reconcileBufferText("")
            await store.refreshMessages(todoID: todo.id)
            await store.refreshFileLinks(todoID: todo.id)
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
            pipelineStatus
            if !todo.isCompleted, let onRefine {
                refineButton(onRefine)
            }
            if pipelineBridge != nil, !todo.isCompleted, linkedTask == nil || linkedTask?.isTerminal == true {
                sendToLaneButton
            }
        }
    }

    // MARK: F060 pipeline status

    private var pipelinePulse: AnyPublisher<Void, Never> {
        let triage = triageCoordinator?.objectWillChange.map { _ in () }.eraseToAnyPublisher()
            ?? Empty<Void, Never>().eraseToAnyPublisher()
        let lanes = laneManager?.objectWillChange.map { _ in () }.eraseToAnyPublisher()
            ?? Empty<Void, Never>().eraseToAnyPublisher()
        return triage.merge(with: lanes).eraseToAnyPublisher()
    }

    /// Base for resolving project-relative paths in notes/thread text.
    var linkBaseDirectory: URL? {
        (todo.projectPath ?? focusedProjectPath).map { URL(fileURLWithPath: $0) }
    }

    private var linkedTask: VibeLaneTask? {
        guard let linked = todo.laneTaskID,
              let taskID = UUID(uuidString: linked) else { return nil }
        return laneManager?.task(withID: taskID)
    }

    /// Live pipeline state in the metadata row: triage progress while an agent
    /// analyzes the todo, and the linked lane task as a clickable chip that
    /// jumps to its detail in Vibe Lanes.
    @ViewBuilder private var pipelineStatus: some View {
        if triageCoordinator?.activeTodoIDs.contains(todo.id) == true, linkedTask == nil {
            HStack(spacing: uiScale.spacing(4)) {
                ProgressView().controlSize(.mini)
                Text(AppStrings.TodoPipeline.triagingIndicator)
                    .font(.system(size: uiScale.textSize(10), weight: .medium))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
            .help(AppStrings.TodoPipeline.triagingHelp)
        }
        if let task = linkedTask {
            laneTaskChip(task)
        }
    }

    private func laneTaskChip(_ task: VibeLaneTask) -> some View {
        let laneName = laneManager?.resolvedLane(for: task)?.name ?? AppStrings.VibeLanes.title
        let (label, icon): (String, String) = {
            switch task.state {
            case .running: return (AppStrings.VibeLanes.running, "play.circle")
            case .needsInput: return (AppStrings.VibeLanes.needsYou, "person.crop.circle.badge.exclamationmark")
            case .stopped: return (AppStrings.VibeLanes.stopped, "stop.circle")
            case .done: return (AppStrings.VibeLanes.completed, "checkmark.circle")
            }
        }()
        let urgent = task.state == .needsInput
        return Button {
            onOpenLaneTask?(task.id)
        } label: {
            HStack(spacing: uiScale.spacing(4)) {
                Image(systemName: icon)
                    .font(.system(size: uiScale.iconSize(10)))
                Text("\(label) · \(laneName)")
                    .font(.system(size: uiScale.textSize(10), weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: uiScale.iconSize(7), weight: .semibold))
                    .opacity(0.6)
            }
            .foregroundStyle(urgent ? palette.errorColor : palette.accentColor)
            .padding(.horizontal, uiScale.spacing(7))
            .padding(.vertical, uiScale.spacing(3))
            .background((urgent ? palette.errorColor : palette.accentColor).opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(onOpenLaneTask == nil)
        .help(AppStrings.TodoPipeline.openLaneTaskHelp)
    }

    // F060: opens the seeded refine chat (reattaches when the session lives).
    private func refineButton(_ action: @escaping (Todo) -> Void) -> some View {
        Button {
            action(todo)
        } label: {
            HStack(spacing: uiScale.spacing(3)) {
                Image(systemName: "sparkles")
                    .font(.system(size: uiScale.iconSize(10)))
                Text(todo.refinementSessionID == nil
                     ? AppStrings.TodoPipeline.refine
                     : AppStrings.TodoPipeline.resumeRefine)
                    .font(.system(size: uiScale.textSize(10), weight: .medium))
            }
            .foregroundStyle(palette.secondaryTextColor)
            .padding(.horizontal, uiScale.spacing(7))
            .padding(.vertical, uiScale.spacing(3))
            .background(palette.canvasSecondaryBackgroundColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(AppStrings.TodoPipeline.refineHelp)
    }

    // F060: dispatch entry point. Disabled (with a hint) while a linked lane
    // task is still active; the sheet itself is the same bridge path the CLI uses.
    @ViewBuilder private var sendToLaneButton: some View {
        Button {
            showDispatchSheet = true
        } label: {
            HStack(spacing: uiScale.spacing(3)) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: uiScale.iconSize(10)))
                Text(AppStrings.TodoPipeline.sendToLane)
                    .font(.system(size: uiScale.textSize(10), weight: .medium))
            }
            .foregroundStyle(palette.accentColor)
            .padding(.horizontal, uiScale.spacing(7))
            .padding(.vertical, uiScale.spacing(3))
            .background(palette.accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDispatchSheet) {
            if let bridge = pipelineBridge {
                TodoDispatchSheet(
                    bridge: bridge,
                    todo: todo,
                    fallbackProjectPath: todo.projectPath ?? focusedProjectPath
                )
            }
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
                MarkdownText(todo.body ?? "", placeholder: AppStrings.Todos.bodyPlaceholder, baseDirectory: linkBaseDirectory)
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
