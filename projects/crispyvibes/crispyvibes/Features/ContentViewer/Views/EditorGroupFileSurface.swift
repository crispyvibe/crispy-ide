import SwiftUI

/// Compact file surface for an editor group without exposing the full tab bar.
@MainActor
struct EditorGroupFileSurface: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.vibespaceCommentStoreEnvironment) private var commentStore
    @ObservedObject private var group: EditorGroupStore
    @ObservedObject private var markdownViewModel: MarkdownViewModel

    init(group: EditorGroupStore) {
        self.group = group
        _markdownViewModel = ObservedObject(wrappedValue: group.markdownViewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()
            fileContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var navigationBar: some View {
        HStack(spacing: 6) {
            navigationButton(
                systemName: "chevron.left",
                label: AppStrings.Editor.navigateBack,
                isEnabled: group.canNavigateBack,
                shortcut: "[",
                action: group.navigateBack
            )
            navigationButton(
                systemName: "chevron.right",
                label: AppStrings.Editor.navigateForward,
                isEnabled: group.canNavigateForward,
                shortcut: "]",
                action: group.navigateForward
            )

            Divider()
                .frame(height: 14)

            Image(systemName: "doc.text")
                .font(AppTypographyTokens.scaledSystem(10))
                .foregroundStyle(appThemePalette.secondaryTextColor)

            Text(activeFileName)
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(appThemePalette.primaryTextColor)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(appThemePalette.canvasSecondaryBackgroundColor)
    }

    @ViewBuilder
    private var fileContent: some View {
        if let reference = group.activeFileDocumentReference {
            let filePath = reference.url.standardizedFileURL.path
            FileContentWithCommentsPanel(
                panel: group.commentsPanel,
                store: commentStore,
                filePath: filePath,
                editorContent: {
                    MarkdownEditorView(
                        viewModel: markdownViewModel,
                        showsTopBar: false,
                        headerLayout: .embedded
                    )
                    .environment(\.vibespaceCommentStoreEnvironment, commentStore)
                    .environment(\.commentsPanelEnvironment, group.commentsPanel)
                    .environment(\.commentsFilePathEnvironment, filePath)
                }
            )
            .id(reference.documentIdentity)
            .environment(\.commentsPanelEnvironment, group.commentsPanel)
            .environment(\.commentsFilePathEnvironment, filePath)
        } else {
            ContentUnavailableView(markdownViewModel.title, systemImage: "doc")
        }
    }

    private var activeFileName: String {
        guard let url = group.activeFileDocumentReference?.url else {
            return markdownViewModel.title
        }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    private func navigationButton(
        systemName: String,
        label: String,
        isEnabled: Bool,
        shortcut: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(AppTypographyTokens.scaledSystem(10, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isEnabled
                ? appThemePalette.secondaryTextColor
                : appThemePalette.secondaryTextColor.opacity(0.35)
        )
        .disabled(!isEnabled)
        .keyboardShortcut(shortcut, modifiers: [.command])
        .help(label)
        .accessibilityLabel(label)
    }
}
