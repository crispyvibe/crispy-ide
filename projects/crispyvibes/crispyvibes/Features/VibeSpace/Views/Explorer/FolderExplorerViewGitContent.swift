import SwiftUI

extension FolderExplorerView {
    @ViewBuilder
    var gitList: some View {
        switch viewModel.gitState {
        case .idle, .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text(AppStrings.SourceControl.loading)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("explorer.git.state.loading")

        case .gitUnavailable:
            ContentUnavailableView(
                AppStrings.SourceControl.gitUnavailable,
                systemImage: "exclamationmark.triangle",
                description: Text(viewModel.gitMessage ?? AppStrings.SourceControl.gitUnavailableDescription)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("explorer.git.state.unavailable")

        case .notRepository:
            ContentUnavailableView(
                "Not a Git Repository",
                systemImage: "tray",
                description: Text(viewModel.gitMessage ?? "This folder does not contain a Git repository.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("explorer.git.state.not-repo")

        case .error:
            VStack(spacing: 10) {
                ContentUnavailableView(
                    AppStrings.SourceControl.unavailable,
                    systemImage: "xmark.octagon",
                    description: Text(viewModel.gitMessage ?? "Unable to read Git status.")
                )
                Button(AppStrings.Common.retry) {
                    viewModel.refreshGitStatus()
                }
                .buttonStyle(.crispyvibesText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("explorer.git.state.error")

        case .ready:
            gitReadyContent
        }
    }

    var gitReadyContent: some View {
        VStack(spacing: 8) {
            gitControlStrip

            if let operationMessage = viewModel.gitOperationMessage,
               viewModel.gitIsOperating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(operationMessage)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .accessibilityIdentifier("explorer.git.operation.message")
            }

            gitCommitComposer

            if gitSections.isEmpty {
                ContentUnavailableView(
                    AppStrings.SourceControl.noChanges,
                    systemImage: "checkmark.seal",
                    description: Text(AppStrings.SourceControl.noChanges)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("explorer.git.state.clean")
            } else {
                List {
                    ForEach(gitSections) { section in
                        Section(section.title) {
                            ForEach(section.items) { item in
                                gitStatusRow(item)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(paneBackgroundColor)
                .accessibilityIdentifier("explorer.git-list")
            }
        }
    }
}
