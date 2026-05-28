import AppKit
import SwiftUI

extension AppSettingsSheetView {
    /// VibeSpaces management panel: search, multi-select Table, open + delete.
    @ViewBuilder
    var vibespacesCategoryContent: some View {
        if let context = vibespacesContext {
            VibeSpacesSettingsPanel(
                vibespaceManagement: context.vibespaceManagement,
                onOpenVibeSpace: { config in
                    context.onOpenVibeSpace(config)
                    onClose()
                },
                onDeleteVibeSpaces: context.onDeleteVibeSpaces
            )
        } else {
            SettingsCard(
                title: AppStrings.Settings.VibeSpaces.cardTitle,
                description: AppStrings.Settings.VibeSpaces.cardDescription
            ) {
                Text(AppStrings.Settings.VibeSpaces.emptyTitle)
                    .font(AppTypographyTokens.settingsFieldDetail)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }
        }
    }
}

/// Self-contained panel — owns its `ManageVibeSpacesViewModel`, search field,
/// Table, toolbar, and confirmation alert. Lives inside
/// `AppSettingsSheetView`'s `SettingsDetailPanel` so it inherits the system
/// settings chrome (Liquid Glass on macOS 26).
private struct VibeSpacesSettingsPanel: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @StateObject private var viewModel: ManageVibeSpacesViewModel
    @State private var pendingDeletionIDs: Set<UUID> = []
    @State private var isShowingDeleteConfirmation: Bool = false

    init(
        vibespaceManagement: VibeSpaceManaging,
        onOpenVibeSpace: @escaping (VibeSpaceConfigFile) -> Void,
        onDeleteVibeSpaces: @escaping (Set<UUID>) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: ManageVibeSpacesViewModel(
                vibespaceManagement: vibespaceManagement,
                onOpenVibeSpace: onOpenVibeSpace,
                onDeleteVibeSpaces: onDeleteVibeSpaces
            )
        )
    }

    var body: some View {
        SettingsCard(
            title: AppStrings.Settings.VibeSpaces.cardTitle,
            description: AppStrings.Settings.VibeSpaces.cardDescription
        ) {
            VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
                searchAndToolbar
                tableSection
                footer
            }
        }
        .alert(
            AppStrings.Settings.VibeSpaces.deleteAlertTitle,
            isPresented: $isShowingDeleteConfirmation,
            actions: {
                Button(AppStrings.Settings.VibeSpaces.deleteAlertCancel, role: .cancel) {
                    pendingDeletionIDs = []
                }
                Button(AppStrings.Settings.VibeSpaces.deleteAlertConfirm, role: .destructive) {
                    confirmDeletion()
                }
            },
            message: {
                Text(AppStrings.Settings.VibeSpaces.deleteAlertMessage(pendingDeletionIDs.count))
            }
        )
    }

    // MARK: - Subviews

    private var searchAndToolbar: some View {
        HStack(spacing: uiScale.spacing(8)) {
            HStack(spacing: uiScale.spacing(6)) {
                Image(systemName: "magnifyingglass")
                    .font(AppTypographyTokens.scaledIcon(11, weight: .regular))
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                TextField(
                    AppStrings.Settings.VibeSpaces.searchPlaceholder,
                    text: $viewModel.searchQuery
                )
                .textFieldStyle(.plain)
                .font(AppTypographyTokens.scaledChromeSystem(13))
                .accessibilityIdentifier("app.settings.vibespaces.search")
            }
            .padding(.horizontal, uiScale.spacing(8))
            .padding(.vertical, uiScale.spacing(5))
            .background(
                RoundedRectangle(cornerRadius: uiScale.chromeSize(6), style: .continuous)
                    .fill(appThemePalette.canvasBackgroundColor.opacity(appThemePalette.prefersDarkWindowChrome ? 0.4 : 0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: uiScale.chromeSize(6), style: .continuous)
                    .stroke(appThemePalette.borderColorValue.opacity(0.4), lineWidth: 1)
            )
            .frame(maxWidth: uiScale.chromeSize(260))

            Spacer()

            Button(AppStrings.Settings.VibeSpaces.openSelected) {
                viewModel.openSelected()
            }
            .controlSize(uiScale.controlSize)
            .disabled(viewModel.selection.count != 1)
            .accessibilityIdentifier("app.settings.vibespaces.open")

            Button(AppStrings.Settings.VibeSpaces.deleteSelected, role: .destructive) {
                pendingDeletionIDs = viewModel.selection
                isShowingDeleteConfirmation = !pendingDeletionIDs.isEmpty
            }
            .controlSize(uiScale.controlSize)
            .disabled(viewModel.selection.isEmpty)
            .accessibilityIdentifier("app.settings.vibespaces.delete")
        }
    }

    @ViewBuilder
    private var tableSection: some View {
        let filtered = viewModel.filteredEntries

        if viewModel.entries.isEmpty && !viewModel.isLoading {
            emptyState(
                title: AppStrings.Settings.VibeSpaces.emptyTitle,
                subtitle: AppStrings.Settings.VibeSpaces.emptySubtitle
            )
        } else if filtered.isEmpty && !viewModel.searchQuery.isEmpty {
            emptyState(
                title: AppStrings.Settings.VibeSpaces.emptySearchTitle,
                subtitle: nil
            )
        } else {
            Table(filtered, selection: $viewModel.selection) {
                TableColumn(AppStrings.Settings.VibeSpaces.columnName) { entry in
                    Text(entry.name)
                        .font(AppTypographyTokens.scaledChromeSystem(13))
                        .lineLimit(1)
                }
                TableColumn(AppStrings.Settings.VibeSpaces.columnProjectFolders) { entry in
                    VibeSpacesProjectFoldersCell(paths: entry.projectPaths)
                }
                TableColumn(AppStrings.Settings.VibeSpaces.columnActions) { entry in
                    HStack(spacing: uiScale.spacing(6)) {
                        Button {
                            viewModel.open(entry)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(AppTypographyTokens.scaledIcon(13, weight: .semibold))
                                .foregroundStyle(appThemePalette.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .help(AppStrings.Settings.VibeSpaces.openRowTooltip)
                        .accessibilityLabel(AppStrings.Settings.VibeSpaces.openRowTooltip)
                        .accessibilityIdentifier("app.settings.vibespaces.row.open.\(entry.id.uuidString)")

                        Button {
                            pendingDeletionIDs = [entry.id]
                            isShowingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(AppTypographyTokens.scaledIcon(13, weight: .semibold))
                                .foregroundStyle(appThemePalette.errorColor)
                        }
                        .buttonStyle(.borderless)
                        .help(AppStrings.Settings.VibeSpaces.deleteRowTooltip)
                        .accessibilityLabel(AppStrings.Settings.VibeSpaces.deleteRowTooltip)
                        .accessibilityIdentifier("app.settings.vibespaces.row.delete.\(entry.id.uuidString)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: uiScale.chromeSize(64), ideal: uiScale.chromeSize(72), max: uiScale.chromeSize(96))
            }
            .font(AppTypographyTokens.scaledChromeSystem(13))
            .frame(
                minHeight: uiScale.chromeSize(240),
                idealHeight: uiScale.chromeSize(360),
                maxHeight: uiScale.chromeSize(480)
            )
            .contextMenu(forSelectionType: UUID.self) { ids in
                if ids.count == 1, let id = ids.first,
                   let entry = viewModel.entries.first(where: { $0.id == id }) {
                    Button(AppStrings.Settings.VibeSpaces.openSelected) {
                        viewModel.open(entry)
                    }
                }
                Button(AppStrings.Settings.VibeSpaces.deleteSelected, role: .destructive) {
                    pendingDeletionIDs = ids
                    isShowingDeleteConfirmation = !pendingDeletionIDs.isEmpty
                }
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first,
                   let entry = viewModel.entries.first(where: { $0.id == id }) {
                    viewModel.open(entry)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(uiScale.controlSize)
                Text(AppStrings.Settings.VibeSpaces.loadingFooter)
                    .font(AppTypographyTokens.settingsFieldDetail)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            } else if !viewModel.selection.isEmpty {
                Text(AppStrings.Settings.VibeSpaces.selectionFooter(viewModel.selection.count, viewModel.entries.count))
                    .font(AppTypographyTokens.settingsFieldDetail)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            } else {
                Text(AppStrings.Settings.VibeSpaces.countFooter(viewModel.entries.count))
                    .font(AppTypographyTokens.settingsFieldDetail)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }
            Spacer()
        }
    }

    private func emptyState(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
            Text(title)
                .font(AppTypographyTokens.settingsCardTitle)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(AppTypographyTokens.settingsFieldDetail)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity, minHeight: uiScale.chromeSize(120), alignment: .leading)
        .padding(.vertical, uiScale.spacing(16))
    }

    // MARK: - Actions

    private func confirmDeletion() {
        let ids = pendingDeletionIDs
        pendingDeletionIDs = []
        viewModel.deleteIDs(ids)
    }
}

/// Renders a vibespace's project paths as a horizontally-laid-out list of
/// clickable directory names. Each name links to that folder in Finder and
/// shows the full path as a hover tooltip.
private struct VibeSpacesProjectFoldersCell: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let paths: [String]

    var body: some View {
        if paths.isEmpty {
            Text("—")
                .font(AppTypographyTokens.scaledChromeSystem(13))
                .foregroundStyle(appThemePalette.secondaryTextColor)
        } else {
            HStack(spacing: uiScale.spacing(0)) {
                ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                    if index > 0 {
                        Text(", ")
                            .font(AppTypographyTokens.scaledChromeSystem(13))
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                    }
                    Button {
                        openInFinder(path)
                    } label: {
                        Text(displayName(for: path))
                            .font(AppTypographyTokens.scaledChromeSystem(13))
                            .lineLimit(1)
                    }
                    .buttonStyle(.link)
                    .controlSize(uiScale.controlSize)
                    .help(path)
                    .accessibilityLabel(path)
                }
            }
        }
    }

    private func displayName(for path: String) -> String {
        let component = URL(fileURLWithPath: path).lastPathComponent
        return component.isEmpty ? path : component
    }

    private func openInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
}
