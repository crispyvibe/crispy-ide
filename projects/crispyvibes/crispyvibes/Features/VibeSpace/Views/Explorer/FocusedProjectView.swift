import SwiftUI

struct FocusedProjectView: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @ObservedObject var project: AnyProjectSession
    let onClose: () -> Void
    let projectColorTag: ProjectColorTag?
    let onProjectColorTagChanged: (ProjectColorTag?) -> Void
    let headerCornerRadii: RectangleCornerRadii
    let isTerminalTrayCollapsed: Bool
    let onToggleTerminalTrayCollapsed: () -> Void
    let onTerminalSpotlightRequested: (UUID) -> Void
    let onTemporaryTerminalRequested: (URL) -> Void
    let onTemporaryShortcutRequested: (TerminalShortcutDefinition, URL) -> Void
    let onOpenTerminalInEditorPaneRequested: (UUID) -> Void
    let onManageShortcutsRequested: () -> Void
    let onLinkTargetActivated: (URL) -> Void
    let onFileSystemTargetActivated: (TerminalFileSystemTarget) -> Void
    var shortcutProvider: VibeSpaceShortcutProvider?

    private var canvasBackgroundColor: Color {
        appThemePalette.canvasBackgroundColor
    }

    var body: some View {
        VStack(spacing: 0) {
            if let color = projectColorTag?.color {
                color.frame(height: 2)
            }

            TerminalView(
                viewModel: project.terminalViewModel,
                defaultDirectory: project.rootURL,
                onSessionDoubleClicked: onTerminalSpotlightRequested,
                onTemporaryTerminalRequested: { tab in
                    onTemporaryTerminalRequested(tab.workingDirectory.standardizedFileURL)
                },
                onTemporaryShortcutRequested: onTemporaryShortcutRequested,
                onOpenInEditorPaneRequested: { tab in
                    onOpenTerminalInEditorPaneRequested(tab.id)
                },
                onLinkTargetActivated: onLinkTargetActivated,
                onFileSystemTargetActivated: onFileSystemTargetActivated,
                onManageShortcutsRequested: onManageShortcutsRequested,
                headerLayout: .embedded,
                embeddedHeaderCornerRadii: headerCornerRadii,
                showsHeaderSummaryActivityIndicator: false,
                showsInlineTerminalActions: true,
                showsSplitPresentationToggle: false,
                additionalHeaderControls: AnyView(
                    CrispyVibesIconButton(
                        systemName: isTerminalTrayCollapsed ? "chevron.up" : "chevron.down",
                        variant: .card,
                        color: appThemePalette.secondaryTextColor,
                        accessibilityLabel: isTerminalTrayCollapsed ? "Expand Terminal Tray" : "Collapse Terminal Tray"
                    ) {
                        onToggleTerminalTrayCollapsed()
                    }
                ),
                shortcutProvider: shortcutProvider,
                dragContentViewerTabProvider: { tab in
                    .terminal(projectID: project.id, tabID: tab.id)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(canvasBackgroundColor)
    }
}
