import SwiftUI

/// F049-R03: composer for new comments and replies. Submits via the supplied
/// async closure; clears on success.
@MainActor
struct CommentComposerView: View {
    @Environment(\.appThemePalette) private var palette

    let placeholder: String
    let initialText: String
    let isReply: Bool
    let onSubmit: (String) async -> Bool
    var onCancel: (() -> Void)?

    @State private var draft: String = ""
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    init(
        placeholder: String,
        initialText: String = "",
        isReply: Bool = false,
        onSubmit: @escaping (String) async -> Bool,
        onCancel: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self.initialText = initialText
        self.isReply = isReply
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(palette.secondaryTextColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundStyle(palette.primaryTextColor)
                    .frame(minHeight: 60, maxHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .onExitCommand { performCancel() }
            }
            .background(palette.canvasSecondaryBackgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(palette.tertiaryTextColor.opacity(0.3), lineWidth: 0.5)
            )
            .accessibilityIdentifier("comments.composer.field")

            HStack(spacing: 8) {
                Spacer()
                if onCancel != nil {
                    Button(AppStrings.Common.cancel, action: performCancel)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("comments.composer.cancel")
                }
                Button(action: submit) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(isReply ? AppStrings.Comments.reply : AppStrings.Comments.submit)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedDraft.isEmpty || isSubmitting)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("comments.composer.submit")
            }
        }
        .padding(8)
        .onAppear {
            draft = initialText
            isFocused = true
        }
    }

    private func submit() {
        let trimmed = trimmedDraft
        guard !trimmed.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        Task { @MainActor in
            let ok = await onSubmit(trimmed)
            isSubmitting = false
            if ok { draft = "" }
        }
    }

    private func performCancel() {
        guard let onCancel else { return }
        draft = ""
        onCancel()
    }
}
