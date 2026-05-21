import SwiftUI

struct ShortcutPanelView: View {
    @ObservedObject var provider: VibeSpaceShortcutProvider
    var onRunShortcut: (TerminalShortcutDefinition) -> Void
    var onManageShortcuts: (() -> Void)?

    var body: some View {
        Menu {
            if provider.vibespaceShortcuts.isEmpty && provider.projectShortcuts.isEmpty {
                Text(AppStrings.TerminalShortcuts.noShortcuts)
            } else {
                if !provider.vibespaceShortcuts.isEmpty {
                    Section(AppStrings.VibeSpaceSettings.shortcutScopeVibeSpace) {
                        ForEach(provider.vibespaceShortcuts) { shortcut in
                            Button(shortcut.name) { onRunShortcut(shortcut) }
                        }
                    }
                }
                if !provider.projectShortcuts.isEmpty {
                    Section(AppStrings.VibeSpaceSettings.shortcutScopeProject) {
                        ForEach(provider.projectShortcuts) { shortcut in
                            Button(shortcut.name) { onRunShortcut(shortcut) }
                        }
                    }
                }
            }

            Divider()

            Button(AppStrings.TerminalShortcuts.manageShortcuts) {
                onManageShortcuts?()
            }
        } label: {
            Label(AppStrings.TerminalShortcuts.scopedShortcuts, systemImage: "list.bullet.rectangle.portrait")
                .font(AppTypographyTokens.caption)
        }
        .accessibilityIdentifier("terminal.scoped.shortcuts.menu")
    }
}

struct SpotlightComposeInlinePanelRow: Identifiable {
    enum Kind {
        case path
        case shortcut
    }

    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let isSelected: Bool
    let isDisabled: Bool
    let sectionTitle: String?
    let kind: Kind
}

struct SpotlightComposeInlinePanelAction {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isDisabled: Bool
}

struct SpotlightComposeInlinePanel: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let title: String
    let queryText: String?
    let featuredAction: SpotlightComposeInlinePanelAction?
    let rows: [SpotlightComposeInlinePanelRow]
    let statusText: String
    let hintText: String?
    let actionTitle: String?
    let onAction: (() -> Void)?
    let onFeaturedAction: (() -> Void)?
    let onSelect: (String) -> Void

    private var selectedRowID: String? {
        rows.first(where: \.isSelected)?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(palette.secondaryTextColor)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if queryText?.isEmpty == false || featuredAction != nil {
                HStack(spacing: 8) {
                    if let queryText, !queryText.isEmpty {
                        Text(queryText)
                            .font(AppTypographyTokens.captionSemibold)
                            .foregroundStyle(palette.primaryTextColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }

                    if let featuredAction, let onFeaturedAction {
                        Button {
                            guard !featuredAction.isDisabled else { return }
                            onFeaturedAction()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: featuredAction.systemImage)
                                    .font(AppTypographyTokens.scaledSystem(10, weight: .medium))
                                Text(featuredAction.title)
                                    .font(AppTypographyTokens.captionSemibold)
                            }
                            .foregroundStyle(
                                featuredAction.isDisabled
                                    ? palette.secondaryTextColor.opacity(0.55)
                                    : featuredAction.isSelected
                                        ? palette.accentColor
                                        : palette.primaryTextColor
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        featuredAction.isSelected
                                            ? palette.selectionBackgroundColor.opacity(0.28)
                                            : palette.primaryTextColor.opacity(0.06)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(
                                        featuredAction.isSelected
                                            ? palette.accentColor.opacity(0.32)
                                            : palette.borderColorValue.opacity(0.18),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(featuredAction.isDisabled)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            if rows.isEmpty {
                footerBlock
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(rows) { row in
                                VStack(alignment: .leading, spacing: 4) {
                                    if let sectionTitle = row.sectionTitle {
                                        Text(sectionTitle)
                                            .font(AppTypographyTokens.caption2)
                                            .foregroundStyle(palette.secondaryTextColor)
                                            .padding(.horizontal, 10)
                                            .padding(.top, 4)
                                    }

                                    Button {
                                        guard !row.isDisabled else { return }
                                        onSelect(row.id)
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
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                    .padding(.horizontal, 6)
                    .padding(.bottom, statusText.isEmpty && hintText == nil ? 6 : 4)
                    .onAppear {
                        guard let selectedRowID else { return }
                        proxy.scrollTo(selectedRowID, anchor: .center)
                    }
                    .onChange(of: selectedRowID) { _, newValue in
                        guard let newValue else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }

                if !statusText.isEmpty || hintText != nil || actionTitle != nil {
                    footerBlock
                }
            }
        }
        .background(palette.canvasSecondaryBackgroundColor.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.borderColorValue.opacity(0.8), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var footerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !statusText.isEmpty || hintText != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !statusText.isEmpty {
                        Text(statusText)
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if let hintText, !hintText.isEmpty {
                        Text(hintText)
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.secondaryTextColor)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            if let actionTitle, let onAction {
                Button(actionTitle) {
                    onAction()
                }
                .buttonStyle(.crispyvibesText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}
