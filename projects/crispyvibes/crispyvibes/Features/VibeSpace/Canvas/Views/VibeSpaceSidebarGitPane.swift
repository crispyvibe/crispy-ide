import SwiftUI

private struct VibeSpaceSourceControlContext: Equatable {
    let vibespaceID: UUID?
    let projectPaths: [String]
    let focusedProjectID: UUID?
    let selectedFilePath: String?
    let sourceControlSettings: VibeSpaceSourceControlSettings
}

struct VibeSpaceSidebarGitPane: View {
    let projects: [AnyProjectSession]
    let focusedProjectID: UUID?
    let activeVibeSpaceID: UUID?
    let sourceControlSelectedFileURL: URL?
    let sourceControlSettings: VibeSpaceSourceControlSettings
    @ObservedObject var viewModel: VibeSpaceSourceControlViewModel
    let onCloneRequested: () -> Void
    let onOpenDiff: (VibeSpaceSourceControlRepositoryViewModel, VibeSpaceSourceControlStatusItem) -> Void
    let onSyncSourceControlContext: () -> Void

    private var sourceControlContext: VibeSpaceSourceControlContext {
        VibeSpaceSourceControlContext(
            vibespaceID: activeVibeSpaceID,
            projectPaths: projects.map { $0.rootURL.standardizedFileURL.path },
            focusedProjectID: focusedProjectID,
            selectedFilePath: sourceControlSelectedFileURL?.standardizedFileURL.path,
            sourceControlSettings: sourceControlSettings
        )
    }

    var body: some View {
        Group {
            if projects.isEmpty {
                ContentUnavailableView(
                    AppStrings.VibeSpace.noProjects,
                    systemImage: "arrow.triangle.branch",
                    description: Text(AppStrings.SourceControl.openVibeSpaceToInspect)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("vibespace.sidebar.git.empty")
            } else {
                VStack(spacing: 0) {
                    if viewModel.state == .ready {
                        sourceControlSummaryBar
                    }
                    VibeSpaceSourceControlView(
                        viewModel: viewModel,
                        onCloneRequested: onCloneRequested,
                        onOpenDiff: onOpenDiff
                    )
                    .accessibilityIdentifier("vibespace.sidebar.git")
                }
            }
        }
        .task(id: sourceControlContext) {
            onSyncSourceControlContext()
        }
    }

    private var sourceControlSummaryBar: some View {
        let repositorySummary = viewModel.isRepositoryPresentationLimited
            ? "\(viewModel.visibleRepositoryCount)/\(viewModel.repositoryCount) repos"
            : "\(viewModel.repositoryCount) repos"
        return HStack(spacing: 0) {
            Text("\(repositorySummary) • \(viewModel.totalPendingChangeCount) changes")
                .font(AppTypographyTokens.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.3))
        .accessibilityIdentifier("vibespace.sidebar.git.summary")
    }
}
