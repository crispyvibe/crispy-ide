import SwiftUI

extension FolderExplorerView {
    func gitHistorySheet(scope: GitHistoryScope) -> some View {
        NavigationStack {
            gitHistorySheetContent
                .navigationTitle(scope.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppStrings.Common.close) {
                            viewModel.dismissGitHistory()
                        }
                    }
                }
        }
        .frame(minWidth: 620, minHeight: 420)
    }

    @ViewBuilder
    var gitHistorySheetContent: some View {
        if viewModel.gitHistoryIsLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text(AppStrings.SourceControl.loadingHistory)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.gitHistoryEntries.isEmpty {
            ContentUnavailableView(
                "No History Found",
                systemImage: "clock",
                description: Text(AppStrings.SourceControl.noCommitsMatched)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(viewModel.gitHistoryEntries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.subject)
                        .font(AppTypographyTokens.subheadlineSemibold)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(entry.shortHash)
                            .font(AppTypographyTokens.captionMonospacedDigit)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(4), style: .continuous)
                                    .fill(appThemePalette.selectionBackgroundColor.opacity(0.18))
                            )
                        Text(entry.authorName)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                        Text(entry.authoredDate)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(appThemePalette.tertiaryTextColor)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
            .accessibilityIdentifier("explorer.git.history.list")
        }
    }
}
