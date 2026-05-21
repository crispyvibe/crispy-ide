import SwiftUI

struct BoardInlinePickerOverlayPresentation {
    let title: String
    let queryText: String?
    let featuredAction: SpotlightComposeInlinePanelAction?
    let rows: [SpotlightComposeInlinePanelRow]
    let statusText: String
    let hintText: String?
    let actionTitle: String?
    let onAction: (() -> Void)?
    let onFeaturedAction: (() -> Void)?
    let onDismiss: (() -> Void)?
    let onSelect: (String) -> Void
}

@MainActor
final class BoardInlinePickerOverlayController: ObservableObject {
    @Published private(set) var presentation: BoardInlinePickerOverlayPresentation?

    private var ownerID: String?

    func update(ownerID: String, presentation: BoardInlinePickerOverlayPresentation) {
        self.ownerID = ownerID
        self.presentation = presentation
    }

    func clear(ownerID: String) {
        guard self.ownerID == ownerID else { return }
        self.ownerID = nil
        presentation = nil
    }
}

private struct BoardInlinePickerOverlayControllerKey: EnvironmentKey {
    static let defaultValue: BoardInlinePickerOverlayController? = nil
}

extension EnvironmentValues {
    var boardInlinePickerOverlayController: BoardInlinePickerOverlayController? {
        get { self[BoardInlinePickerOverlayControllerKey.self] }
        set { self[BoardInlinePickerOverlayControllerKey.self] = newValue }
    }
}

struct BoardInlinePickerOverlayView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    let presentation: BoardInlinePickerOverlayPresentation

    private var fileRows: [SpotlightComposeInlinePanelRow] {
        presentation.rows.filter { $0.kind == .path }
    }

    private var shortcutRows: [SpotlightComposeInlinePanelRow] {
        presentation.rows.filter { $0.kind == .shortcut }
    }

    private var actionCount: Int {
        (presentation.featuredAction == nil ? 0 : 1)
            + shortcutRows.count
            + ((presentation.actionTitle != nil && presentation.onAction != nil) ? 1 : 0)
    }

    private var selectedFileRowID: String? {
        fileRows.first(where: \.isSelected)?.id
    }

    private var selectedShortcutRowID: String? {
        shortcutRows.first(where: \.isSelected)?.id
    }

    private var fileCountText: String? {
        fileRows.isEmpty ? nil : AppStrings.Terminal.ComposeTriggers.pathResultCount(fileRows.count)
    }

    private var actionCountText: String? {
        actionCount == 0 ? nil : "\(actionCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(presentation.title)
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(palette.secondaryTextColor)
                Spacer(minLength: 8)
                if let onDismiss = presentation.onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppTypographyTokens.scaledIcon(11, weight: .semibold))
                            .foregroundStyle(palette.secondaryTextColor)
                            .frame(width: uiScale.iconSize(24), height: uiScale.iconSize(24))
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(palette.primaryTextColor.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(AppStrings.Common.close)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if let queryText = presentation.queryText {
                let displayText = queryText.isEmpty ? AppStrings.Terminal.ComposeTriggers.typeToSearch : queryText
                Text(displayText)
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(
                        queryText.isEmpty
                            ? palette.secondaryTextColor
                            : palette.primaryTextColor
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            } else {
                Text(AppStrings.Terminal.ComposeTriggers.typeToSearch)
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            Rectangle()
                .fill(palette.borderColorValue.opacity(0.65))
                .frame(height: 1)

            HStack(spacing: 0) {
                boardPane(
                    title: AppStrings.Terminal.ComposeTriggers.pathsSection,
                    countText: fileCountText
                ) {
                    fileList
                }

                Rectangle()
                    .fill(palette.borderColorValue.opacity(0.55))
                    .frame(width: 1)

                boardPane(
                    title: AppStrings.Terminal.ComposeTriggers.actionsSection,
                    countText: actionCountText
                ) {
                    actionList
                }
                .frame(width: 280)
            }
            .frame(minHeight: 320, maxHeight: 420)

            Rectangle()
                .fill(palette.borderColorValue.opacity(0.65))
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !presentation.statusText.isEmpty {
                    Text(presentation.statusText)
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let hintText = presentation.hintText, !hintText.isEmpty {
                    Text(hintText)
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: 860)
        .scrollAssistGlassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private func boardPane<Content: View>(
        title: String,
        countText: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(palette.secondaryTextColor)
                if let countText, !countText.isEmpty {
                    Text(countText)
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor.opacity(0.75))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            content()
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    private var fileList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    if fileRows.isEmpty {
                        emptyState(text: AppStrings.Terminal.ComposeTriggers.noResults)
                    } else {
                        ForEach(fileRows) { row in
                            resultRow(row)
                        }
                    }
                }
            }
            .onAppear {
                scrollSelectionIfNeeded(
                    selectedRowID: selectedFileRowID,
                    using: proxy
                )
            }
            .onChange(of: selectedFileRowID) { _, newValue in
                scrollSelectionIfNeeded(
                    selectedRowID: newValue,
                    using: proxy
                )
            }
        }
    }

    private var actionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    if let featuredAction = presentation.featuredAction {
                        featuredActionRow(featuredAction)
                    }

                    if !shortcutRows.isEmpty {
                        ForEach(shortcutRows) { row in
                            resultRow(row)
                        }
                    }

                    if let actionTitle = presentation.actionTitle,
                       let onAction = presentation.onAction {
                        auxiliaryActionRow(title: actionTitle, action: onAction)
                    }
                }
            }
            .onAppear {
                scrollSelectionIfNeeded(
                    selectedRowID: selectedShortcutRowID,
                    using: proxy
                )
            }
            .onChange(of: selectedShortcutRowID) { _, newValue in
                scrollSelectionIfNeeded(
                    selectedRowID: newValue,
                    using: proxy
                )
            }
        }
    }

    private func resultRow(_ row: SpotlightComposeInlinePanelRow) -> some View {
        Button {
            presentation.onSelect(row.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: row.systemImage)
                    .font(AppTypographyTokens.scaledIcon(11, weight: .medium))
                    .foregroundStyle(
                        row.isDisabled
                            ? palette.secondaryTextColor.opacity(0.4)
                            : palette.accentColor
                    )
                    .frame(width: uiScale.iconSize(14))

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(
                            row.isDisabled
                                ? palette.secondaryTextColor.opacity(0.65)
                                : palette.primaryTextColor
                        )
                        .lineLimit(row.subtitle == nil ? 2 : 1)
                        .truncationMode(.middle)
                    if let subtitle = row.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.secondaryTextColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        row.isSelected
                            ? palette.selectionBackgroundColor.opacity(0.28)
                            : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(row.isDisabled)
        .id(row.id)
    }

    private func featuredActionRow(_ action: SpotlightComposeInlinePanelAction) -> some View {
        Button {
            presentation.onFeaturedAction?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: action.systemImage)
                    .font(AppTypographyTokens.scaledIcon(11, weight: .medium))
                    .foregroundStyle(
                        action.isDisabled
                            ? palette.secondaryTextColor.opacity(0.4)
                            : palette.accentColor
                    )
                    .frame(width: uiScale.iconSize(14))

                Text(action.title)
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(
                        action.isDisabled
                            ? palette.secondaryTextColor.opacity(0.65)
                            : palette.primaryTextColor
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        action.isSelected
                            ? palette.selectionBackgroundColor.opacity(0.28)
                            : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(action.isDisabled)
        .padding(.bottom, shortcutRows.isEmpty && presentation.actionTitle == nil ? 0 : 2)
    }

    private func auxiliaryActionRow(title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(AppTypographyTokens.scaledIcon(11, weight: .semibold))
                    .foregroundStyle(palette.secondaryTextColor)
                    .frame(width: uiScale.iconSize(22))

                Text(title)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(palette.primaryTextColor)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.selectionBackgroundColor.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .padding(.top, shortcutRows.isEmpty ? 0 : 4)
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(AppTypographyTokens.caption)
            .foregroundStyle(palette.secondaryTextColor)
            .frame(maxWidth: .infinity, minHeight: 180)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
    }

    private func scrollSelectionIfNeeded(
        selectedRowID: String?,
        using proxy: ScrollViewProxy
    ) {
        guard let selectedRowID else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.12)) {
                proxy.scrollTo(selectedRowID, anchor: .center)
            }
        }
    }
}
