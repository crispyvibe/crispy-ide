import SwiftUI

/// F053 — detail pane for a selected todo. Themed via the app palette and
/// scaled via `crispyvibesUIScale` (responds to cmd+/cmd-): large editable
/// title, a quiet markdown notes block (edit/preview), and a flat activity
/// thread that groups consecutive same-author messages under a single header
/// with a relative timestamp. Custom composer (no system ring).
struct TodoDetailView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var theme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var store: VibeSpaceTodoStore
    let todo: Todo

    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var isEditingBody = false
    @State private var composerText = ""
    @FocusState private var composerFocused: Bool

    private var messages: [TodoMessage] { store.messages(forTodo: todo.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: uiScale.spacing(20)) {
                    header
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
            composerText = ""
            await store.refreshMessages(todoID: todo.id)
        }
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
            }
            .buttonStyle(.plain)
            .help(AppStrings.Todos.complete)

            TextField("", text: $draftTitle, prompt: Text(AppStrings.Todos.titlePlaceholder).foregroundStyle(palette.tertiaryTextColor))
                .font(.system(size: uiScale.textSize(20), weight: .semibold))
                .foregroundStyle(palette.primaryTextColor)
                .textFieldStyle(.plain)
                .strikethrough(todo.isCompleted, color: palette.tertiaryTextColor)
                .onSubmit(commitTitle)
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(6)) {
            sectionLabel(AppStrings.Todos.notesLabel)
            if isEditingBody {
                VStack(alignment: .trailing, spacing: uiScale.spacing(8)) {
                    TextEditor(text: $draftBody)
                        .font(.system(size: uiScale.textSize(14)))
                        .foregroundStyle(palette.primaryTextColor)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: uiScale.chromeSize(90))
                        .padding(uiScale.spacing(8))
                        .background(palette.canvasSecondaryBackgroundColor, in: RoundedRectangle(cornerRadius: theme.radius(8)))
                        .overlay(RoundedRectangle(cornerRadius: theme.radius(8)).stroke(palette.borderColorValue.opacity(0.4), lineWidth: 1))
                    HStack(spacing: uiScale.spacing(8)) {
                        Button(AppStrings.Todos.cancel) {
                            draftBody = todo.body ?? ""
                            isEditingBody = false
                        }
                        .buttonStyle(.crispyvibesText)
                        Button(AppStrings.Todos.save, action: commitBody)
                            .buttonStyle(.crispyvibesPrimary)
                            .keyboardShortcut(.return, modifiers: .command)
                    }
                }
            } else {
                Button { isEditingBody = true } label: {
                    MarkdownText(todo.body ?? "", placeholder: AppStrings.Todos.bodyPlaceholder)
                        .font(.system(size: uiScale.textSize(14)))
                        .foregroundStyle((todo.body ?? "").isEmpty ? palette.tertiaryTextColor : palette.secondaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Thread

    private var threadSection: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
            sectionLabel(AppStrings.Todos.thread)
            if messages.isEmpty {
                threadEmpty
            } else {
                ForEach(groupMessages(messages)) { group in
                    messageGroup(group)
                }
            }
        }
    }

    private func messageGroup(_ group: TodoMessageGroup) -> some View {
        let isAgent = group.authorKind == "agent"
        return VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
            HStack(spacing: uiScale.spacing(6)) {
                ZStack {
                    Circle()
                        .fill(isAgent ? palette.accentColor.opacity(0.15) : palette.secondaryTextColor.opacity(0.12))
                        .frame(width: uiScale.iconSize(20), height: uiScale.iconSize(20))
                    Image(systemName: isAgent ? "sparkles" : "person.fill")
                        .font(.system(size: uiScale.iconSize(10)))
                        .foregroundStyle(isAgent ? palette.accentColor : palette.secondaryTextColor)
                }
                Text(isAgent ? AppStrings.Todos.authorAgent : AppStrings.Todos.authorYou)
                    .font(.system(size: uiScale.textSize(13), weight: .medium))
                    .foregroundStyle(palette.primaryTextColor)
                Text(TodoTime.relative(group.messages.first?.createdAt ?? ""))
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
            ForEach(group.messages) { message in
                MarkdownText(message.body, placeholder: "")
                    .font(.system(size: uiScale.textSize(14)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, uiScale.spacing(26))
                    .modifier(AgentMessageDecoration(isAgent: isAgent, palette: palette, radius: theme.radius(8), scale: uiScale))
            }
        }
    }

    private var threadEmpty: some View {
        VStack(spacing: uiScale.spacing(4)) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: uiScale.iconSize(24)))
                .foregroundStyle(palette.tertiaryTextColor)
            Text(AppStrings.Todos.threadEmpty)
                .font(.system(size: uiScale.textSize(13)))
                .foregroundStyle(palette.tertiaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, uiScale.spacing(24))
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: uiScale.spacing(8)) {
            TextField("", text: $composerText, prompt: Text(AppStrings.Todos.messagePlaceholder).foregroundStyle(palette.tertiaryTextColor), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: uiScale.textSize(13)))
                .foregroundStyle(palette.primaryTextColor)
                .lineLimit(1...5)
                .focused($composerFocused)
                .onSubmit(sendMessage)
            if !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: uiScale.iconSize(13), weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: uiScale.iconSize(28), height: uiScale.iconSize(28))
                        .background(palette.accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, uiScale.spacing(12))
        .padding(.vertical, uiScale.spacing(8))
        .background(palette.canvasSecondaryBackgroundColor, in: RoundedRectangle(cornerRadius: theme.radius(10)))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(10))
                .stroke(composerFocused ? palette.accentColor.opacity(0.4) : palette.borderColorValue.opacity(0.4), lineWidth: 1)
        )
        .padding(uiScale.spacing(12))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: composerText.isEmpty)
    }

    // MARK: Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: uiScale.textSize(11), weight: .medium))
            .tracking(0.5)
            .foregroundStyle(palette.tertiaryTextColor)
    }

    private func commitTitle() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != todo.title else { return }
        Task { await store.update(id: todo.id, title: trimmed) }
    }

    private func commitBody() {
        isEditingBody = false
        Task { await store.update(id: todo.id, body: draftBody) }
    }

    private func sendMessage() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composerText = ""
        Task { await store.addMessage(todoID: todo.id, body: text) }
    }

    private func groupMessages(_ msgs: [TodoMessage]) -> [TodoMessageGroup] {
        var groups: [TodoMessageGroup] = []
        for message in msgs {
            if var last = groups.last,
               last.authorKind == message.authorKind,
               let lastDate = TodoTime.date(last.messages.last?.createdAt ?? ""),
               let thisDate = TodoTime.date(message.createdAt),
               thisDate.timeIntervalSince(lastDate) < 300 {
                last.messages.append(message)
                groups[groups.count - 1] = last
            } else {
                groups.append(TodoMessageGroup(id: message.id, authorKind: message.authorKind, messages: [message]))
            }
        }
        return groups
    }
}

private struct TodoMessageGroup: Identifiable {
    let id: String
    let authorKind: String
    var messages: [TodoMessage]
}

/// Agent messages get a subtle leading accent rule + surface fill; user
/// messages stay flat. Keeps the thread calm without chat bubbles.
private struct AgentMessageDecoration: ViewModifier {
    let isAgent: Bool
    let palette: AppThemePalette
    let radius: CGFloat
    let scale: CrispyVibesUIScale

    func body(content: Content) -> some View {
        if isAgent {
            content
                .padding(.vertical, scale.spacing(6))
                .padding(.trailing, scale.spacing(8))
                .background(palette.canvasSecondaryBackgroundColor.opacity(0.5), in: RoundedRectangle(cornerRadius: radius))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(palette.accentColor.opacity(0.4))
                        .frame(width: scale.spacing(2))
                        .padding(.vertical, scale.spacing(4))
                        .padding(.leading, scale.spacing(18))
                }
        } else {
            content
        }
    }
}

private enum TodoTime {
    static let iso = ISO8601DateFormatter()
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func date(_ string: String) -> Date? { iso.date(from: string) }

    static func relative(_ string: String) -> String {
        guard let date = iso.date(from: string) else { return "" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Renders inline markdown (bold/italic/code/links), preserving whitespace;
/// falls back to plain text. Shows a placeholder when empty.
struct MarkdownText: View {
    private let attributed: AttributedString
    private let isEmpty: Bool
    private let placeholder: String

    init(_ markdown: String, placeholder: String) {
        self.placeholder = placeholder
        self.isEmpty = markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.attributed = (try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }

    var body: some View {
        if isEmpty {
            Text(placeholder)
        } else {
            Text(attributed).textSelection(.enabled)
        }
    }
}
