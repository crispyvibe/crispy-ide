import SwiftUI

/// F053 — activity thread + composer for `TodoDetailView`. Groups consecutive
/// same-author messages (via `TodoMessageGroup.group`) under one header with a
/// relative timestamp; agent messages carry a leading accent rule + surface
/// fill, user messages stay flat.
extension TodoDetailView {

    // MARK: Thread

    var threadSection: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
            sectionLabel(AppStrings.Todos.thread)
            if messages.isEmpty {
                threadEmpty
            } else {
                ForEach(TodoMessageGroup.group(messages, parseDate: TodoTime.date)) { group in
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
            VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
                ForEach(group.messages) { message in
                    MarkdownText(message.body, placeholder: "")
                        .font(.system(size: uiScale.textSize(14)))
                        .foregroundStyle(palette.secondaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, uiScale.spacing(26))
            .modifier(AgentMessageDecoration(isAgent: isAgent, palette: palette, radius: theme.radius(8), scale: uiScale))
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

    var composer: some View {
        HStack(spacing: uiScale.spacing(8)) {
            TextField(
                "",
                text: $composerText,
                prompt: Text(AppStrings.Todos.messagePlaceholder).foregroundStyle(palette.tertiaryTextColor),
                axis: .vertical
            )
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

    private func sendMessage() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composerText = ""
        Task { await store.addMessage(todoID: todo.id, body: text) }
    }
}

/// Agent messages get a subtle leading accent rule + surface fill; user
/// messages stay flat. The rule hugs the group's content edge so it stays
/// aligned at every UI scale.
struct AgentMessageDecoration: ViewModifier {
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
