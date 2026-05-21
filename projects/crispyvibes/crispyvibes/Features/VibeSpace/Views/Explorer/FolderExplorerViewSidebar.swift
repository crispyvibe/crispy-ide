import SwiftUI

extension FolderExplorerView {
    var headerControls: some View {
        ViewThatFits(in: .horizontal) {
            headerControlsRow(compactTabs: false)
            headerControlsRow(compactTabs: true)
        }
    }

    func headerControlsRow(compactTabs: Bool) -> some View {
        HStack(spacing: 6) {
            sidebarTabSwitcher(compact: compactTabs)

            if viewModel.activeSidebarTab == .files {
                CrispyVibesIconButton(
                    systemName: "arrow.clockwise",
                    variant: .panel,
                    color: appThemePalette.secondaryTextColor
                ) {
                    viewModel.refreshTree()
                }
                .help(AppStrings.Explorer.refreshFileList)
                .accessibilityIdentifier("explorer.files.refresh")

                CrispyVibesIconButton(
                    systemName: "doc.badge.plus",
                    variant: .panel,
                    color: appThemePalette.secondaryTextColor,
                    accessibilityLabel: AppStrings.Explorer.createNewFile
                ) {
                    viewModel.createNewFileAtSelection()
                }
                .help(AppStrings.Explorer.createNewFile)
                .accessibilityIdentifier("explorer.create.file")

                CrispyVibesIconButton(
                    systemName: "folder.badge.plus",
                    variant: .panel,
                    color: appThemePalette.secondaryTextColor,
                    accessibilityLabel: AppStrings.Explorer.createNewFolder
                ) {
                    viewModel.createNewFolderAtSelection()
                }
                .help(AppStrings.Explorer.createNewFolder)
                .accessibilityIdentifier("explorer.create.folder")
            }

            if viewModel.activeSidebarTab == .git {
                CrispyVibesIconButton(
                    systemName: "arrow.clockwise",
                    variant: .panel,
                    color: appThemePalette.secondaryTextColor
                ) {
                    viewModel.refreshGitStatus()
                }
                .help(AppStrings.SourceControl.refreshGitStatus)
                .accessibilityIdentifier("explorer.git.refresh")
            }
        }
    }

    func sidebarTabSwitcher(compact: Bool) -> some View {
        HStack(spacing: 4) {
            sidebarTabButton(for: .files, compact: compact)
            sidebarTabButton(for: .git, compact: compact)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous)
                .fill(tabSwitcherBackgroundColor.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous)
                .stroke(appThemePalette.borderColorValue.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: appThemePalette.canvasBackgroundColor.opacity(0.20), radius: 1, y: 1)
    }

    func sidebarTabButton(
        for tab: FolderExplorerViewModel.SidebarTab,
        compact: Bool
    ) -> some View {
        let isActive = viewModel.activeSidebarTab == tab

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.activeSidebarTab = tab
            }
        } label: {
            HStack(spacing: compact ? 0 : 6) {
                Image(systemName: sidebarIcon(for: tab))
                    .font(AppTypographyTokens.captionSemibold)

                if !compact {
                    Text(tab.title)
                        .font(AppTypographyTokens.captionSemibold)
                        .lineLimit(1)
                }

                if !compact,
                   tab == .git,
                   let gitChangeCount {
                    CrispyVibesHeaderBadge(
                        text: "\(gitChangeCount)",
                        style: .compact,
                        tint: appThemePalette.primaryTextColor,
                        emphasis: isActive ? 0.26 : 0.16
                    )
                }
            }
            .foregroundStyle(isActive ? appThemePalette.primaryTextColor : appThemePalette.secondaryTextColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, compact ? 7 : 9)
            .background(
                Group {
                    if isActive {
                        Capsule(style: .continuous)
                            .fill(tabActiveBackgroundColor)
                            .matchedGeometryEffect(id: "explorer.sidebar.active-tab", in: sidebarTabSelectionNamespace)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(tabBorderColor(isActive: true), lineWidth: 1)
                            )
                    } else {
                        Capsule(style: .continuous)
                            .fill(tabInactiveBackgroundColor.opacity(0.52))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(tabBorderColor(isActive: false), lineWidth: 1)
                            )
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isActive ? "Selected" : "Not selected")
        .accessibilityIdentifier("explorer.tab.\(tab.rawValue)")
    }

    var gitChangeCount: Int? {
        guard viewModel.gitState == .ready else { return nil }
        return viewModel.gitStatusItems.isEmpty ? nil : viewModel.gitStatusItems.count
    }

    func sidebarIcon(for tab: FolderExplorerViewModel.SidebarTab) -> String {
        switch tab {
        case .files:
            return "folder.fill"
        case .git:
            return "arrow.triangle.branch"
        case .sessions:
            return "square.stack.3d.up"
        case .conversations:
            return "bubble.left.and.bubble.right"
        }
    }
}
