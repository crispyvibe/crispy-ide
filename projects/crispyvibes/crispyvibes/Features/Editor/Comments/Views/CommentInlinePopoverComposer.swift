import SwiftUI

/// F049-UX: lightweight inline comment composer shown as a popover anchored
/// near the selection, avoiding the need to open the full side panel for
/// quick comments. Matches the Google Docs / JetBrains pattern.
@MainActor
struct CommentInlinePopoverComposer: View {
    @Environment(\.appThemePalette) private var palette

    let anchor: CommentAnchor
    let onSubmit: (String) async -> Bool
    let onCancel: () -> Void
    /// Open the full panel instead (for long threads / browsing).
    let onExpandToPanel: () -> Void

    @State private var draft = ""
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            anchorPreview
            editorField
            actionRow
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { isFocused = true }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var anchorPreview: some View {
        if !anchor.anchorText.isEmpty {
            Text(anchor.anchorText.prefix(120))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(3)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.canvasSecondaryBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var editorField: some View {
        ZStack(alignment: .topLeading) {
            if draft.isEmpty {
                Text(AppStrings.Comments.composerPlaceholder)
                    .foregroundStyle(palette.tertiaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $draft)
                .focused($isFocused)
                .font(.body)
                .foregroundStyle(palette.primaryTextColor)
                .frame(minHeight: 48, maxHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .onExitCommand { onCancel() }
        }
        .background(palette.canvasSecondaryBackgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(palette.tertiaryTextColor.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: onExpandToPanel) {
                Image(systemName: "sidebar.right")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help(AppStrings.Comments.toolbarToggleHelp)
            Spacer()
            Button(AppStrings.Common.cancel, action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(action: submit) {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Text(AppStrings.Comments.submit)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(trimmed.isEmpty || isSubmitting)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func submit() {
        let text = trimmed
        guard !text.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        Task { @MainActor in
            let ok = await onSubmit(text)
            isSubmitting = false
            if ok { onCancel() }
        }
    }
}
