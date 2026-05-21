import SwiftUI

struct VibeSpaceSidebarSessionsPane: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    @StateObject private var viewModel = VibeSpaceSidebarSessionsViewModel()
    let activeVibeSpaceID: UUID?
    let vibespaces: [VibeSpaceState]
    let onPreviewSession: (VibeSpaceSidebarTmuxSession) -> Void
    let onSendSessionToProject: (VibeSpaceSidebarTmuxSession, UUID) -> Void
    let onTerminateSession: (VibeSpaceSidebarTmuxSession) async -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                toolbarRow

                if viewModel.vibespaceGroups.isEmpty,
                   viewModel.hasLoadedSnapshot,
                   !viewModel.isRefreshIndicatorVisible {
                    emptyState
                } else {
                    let currentGroups = viewModel.vibespaceGroups.filter(\.isCurrentVibeSpace)
                    let otherGroups = viewModel.vibespaceGroups.filter { !$0.isCurrentVibeSpace }

                    ForEach(currentGroups) { group in
                        VibeSpaceSidebarSessionsVibeSpaceGroupView(
                            group: group,
                            expandedVibeSpaceIDs: $viewModel.expandedVibeSpaceIDs,
                            expandedSectionIDs: $viewModel.expandedSectionIDs,
                            onPreviewSession: onPreviewSession,
                            onSendSessionToProject: onSendSessionToProject,
                            onTerminateSession: onTerminateSession,
                            onRefreshRequested: viewModel.refresh
                        )
                    }

                    if !otherGroups.isEmpty {
                        Text(AppStrings.Sidebar.Sessions.otherVibeSpaces)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(palette.secondaryTextColor)
                            .padding(.top, currentGroups.isEmpty ? 0 : 4)

                        ForEach(otherGroups) { group in
                            VibeSpaceSidebarSessionsVibeSpaceGroupView(
                                group: group,
                                expandedVibeSpaceIDs: $viewModel.expandedVibeSpaceIDs,
                                expandedSectionIDs: $viewModel.expandedSectionIDs,
                                onPreviewSession: onPreviewSession,
                                onSendSessionToProject: onSendSessionToProject,
                                onTerminateSession: onTerminateSession,
                                onRefreshRequested: viewModel.refresh
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("vibespace.sidebar.sessions")
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            viewModel.start(activeVibeSpaceID: activeVibeSpaceID, vibespaces: vibespaces)
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: signature) { _, _ in
            viewModel.update(activeVibeSpaceID: activeVibeSpaceID, vibespaces: vibespaces)
        }
    }

    private var signature: [String] {
        [
            activeVibeSpaceID?.uuidString ?? "none"
        ] + vibespaces.map { vibespace in
            let projectSignature = vibespace.projects.map { project in
                let connectionState: String
                if let connection = project.sshConnection {
                    switch connection.state {
                    case .connected:
                        connectionState = "connected"
                    case .connecting:
                        connectionState = "connecting"
                    case .disconnected:
                        connectionState = "disconnected"
                    case .failed(let error):
                        connectionState = "failed:\(error)"
                    }
                } else {
                    connectionState = "local"
                }
                return "\(project.id.uuidString)|\(connectionState)"
            }
            return "\(vibespace.id.uuidString)|\(vibespace.name)|\(projectSignature.joined(separator: ","))"
        }
    }

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            Text(AppStrings.Sidebar.Sessions.title)
                .font(AppTypographyTokens.caption)
                .foregroundStyle(palette.secondaryTextColor)

            Spacer(minLength: 12)

            ProgressView()
                .controlSize(.small)
                .opacity(viewModel.isRefreshIndicatorVisible ? 1 : 0)
                .frame(width: uiScale.iconSize(14))

            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(AppStrings.Sidebar.Sessions.refresh)
            .accessibilityIdentifier("vibespace.sidebar.sessions.refresh")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            AppStrings.Sidebar.Sessions.emptyTitle,
            systemImage: "square.stack.3d.up.slash",
            description: Text(AppStrings.Sidebar.Sessions.emptyDescription)
        )
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}
