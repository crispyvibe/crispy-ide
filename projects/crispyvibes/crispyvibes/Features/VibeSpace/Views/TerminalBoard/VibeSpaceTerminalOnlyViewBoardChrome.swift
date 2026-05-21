import SwiftUI

extension VibeSpaceTerminalOnlyView {
    var boardBackgroundColor: Color {
        appThemePalette.windowBackgroundColor
    }

    var chromeScale: CGFloat {
        AppPreferences.chromeScale(forCodeFontSize: codeFontSize)
    }

    var boardHeader: some View {
        CrispyVibesHeaderChrome(
            style: .panel,
            background: appThemePalette.canvasSecondaryBackgroundColor.opacity(0.94),
            cornerRadii: headerCornerRadii
        ) {
            Text(AppStrings.Terminal.boardTitle)
                .font(CrispyVibesHeaderStyle.panel.titleFont(scale: chromeScale))
                .foregroundStyle(appThemePalette.primaryTextColor)

            if !surfaceLayout.tiles.isEmpty {
                CrispyVibesHeaderBadge(
                    text: "\(surfaceLayout.tiles.count)/\(VibeSpaceTerminalBoardLayout.maximumTileCount)",
                    style: .panel,
                    tint: appThemePalette.secondaryTextColor,
                    emphasis: 0.14
                )
            }

            Spacer(minLength: 8)

            if projects.isEmpty {
                Button {
                    onAddProjectsRequested()
                } label: {
                    Label("Add Project(s)", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.crispyvibesText)
            }

            Button {
                createSheetInitialProjectPath = boardStore.activeProjectPath(surfaceID: surfaceID)
                isCreateSheetPresented = true
            } label: {
                Label(AppStrings.Terminal.newTerminal, systemImage: "plus")
            }
            .buttonStyle(.crispyvibesPrimary)
            .disabled(surfaceLayout.tiles.count >= VibeSpaceTerminalBoardLayout.maximumTileCount)
            .accessibilityIdentifier("vibespace.terminal-board.add")

            if !surfaceLayout.tiles.contains(where: { $0.isVibeCast }) {
                Button {
                    boardStore.addVibeCastTile(surfaceID: surfaceID)
                } label: {
                    Label(AppStrings.VibeCast.title, systemImage: "note.text")
                }
                .buttonStyle(.crispyvibesText)
                .accessibilityIdentifier("vibespace.terminal-board.vibeCast")
            }
        }
    }
}
