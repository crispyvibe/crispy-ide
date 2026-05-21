import SwiftUI

extension FolderExplorerView {
    var gitControlStrip: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(viewModel.gitBranchOptions) { branch in
                    Button {
                        viewModel.checkoutGitBranch(branch)
                    } label: {
                        HStack {
                            Text(branch.displayName)
                            if branch.isCurrent {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(viewModel.gitIsOperating || branch.isCurrent)
                }
            } label: {
                Label(
                    viewModel.gitCurrentBranchName ?? "Branch",
                    systemImage: "arrow.triangle.branch"
                )
                .font(AppTypographyTokens.captionSemibold)
                .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .disabled(viewModel.gitBranchOptions.isEmpty || viewModel.gitIsOperating)
            .accessibilityIdentifier("explorer.git.branch.menu")

            Spacer(minLength: 6)

            Button {
                viewModel.openGitHistory(scope: .repository)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.crispyvibesText)
            .disabled(viewModel.gitIsOperating)
            .help(AppStrings.SourceControl.viewCommitHistory)
            .accessibilityIdentifier("explorer.git.history")

            Button {
                viewModel.refreshGitStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.crispyvibesText)
            .disabled(viewModel.gitIsOperating)
            .help(AppStrings.SourceControl.refreshGitStatus)
            .accessibilityIdentifier("explorer.git.refresh.inline")
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    var gitCommitComposer: some View {
        VStack(spacing: 6) {
            TextField(AppStrings.SourceControl.commitMessage, text: $viewModel.gitCommitMessageDraft)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.gitIsOperating)
                .accessibilityIdentifier("explorer.git.commit.message")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    explorerGitActionButton(AppStrings.SourceControl.stageAll, icon: "plus.circle", showLabel: true) { viewModel.stageAllGitChanges() }
                        .disabled(viewModel.gitIsOperating || viewModel.gitStatusItems.isEmpty)
                        .accessibilityIdentifier("explorer.git.stage-all")
                    explorerGitActionButton(AppStrings.SourceControl.push, icon: "arrow.up", showLabel: true) { viewModel.pushGitChanges() }
                        .disabled(viewModel.gitIsOperating)
                        .accessibilityIdentifier("explorer.git.push")
                    explorerGitActionButton(AppStrings.SourceControl.pull, icon: "arrow.down", showLabel: true) { viewModel.pullGitChanges() }
                        .disabled(viewModel.gitIsOperating)
                        .accessibilityIdentifier("explorer.git.pull")
                    explorerGitActionButton(AppStrings.SourceControl.fetch, icon: "arrow.down.to.line", showLabel: true) { viewModel.fetchGitChanges() }
                        .disabled(viewModel.gitIsOperating)
                        .accessibilityIdentifier("explorer.git.fetch")
                    Spacer(minLength: 0)
                }

                HStack(spacing: 4) {
                    explorerGitActionButton(AppStrings.SourceControl.stageAll, icon: "plus.circle", showLabel: false) { viewModel.stageAllGitChanges() }
                        .disabled(viewModel.gitIsOperating || viewModel.gitStatusItems.isEmpty)
                        .accessibilityIdentifier("explorer.git.stage-all")
                    explorerGitActionButton(AppStrings.SourceControl.push, icon: "arrow.up", showLabel: false) { viewModel.pushGitChanges() }
                        .disabled(viewModel.gitIsOperating)
                        .accessibilityIdentifier("explorer.git.push")
                    explorerGitActionButton(AppStrings.SourceControl.pull, icon: "arrow.down", showLabel: false) { viewModel.pullGitChanges() }
                        .disabled(viewModel.gitIsOperating)
                        .accessibilityIdentifier("explorer.git.pull")
                    explorerGitActionButton(AppStrings.SourceControl.fetch, icon: "arrow.down.to.line", showLabel: false) { viewModel.fetchGitChanges() }
                        .disabled(viewModel.gitIsOperating)
                        .accessibilityIdentifier("explorer.git.fetch")
                    Spacer(minLength: 0)
                }
            }

            Button(AppStrings.SourceControl.commit) {
                viewModel.commitGitChanges()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.crispyvibesPrimary)
            .controlSize(.small)
            .disabled(
                viewModel.gitIsOperating ||
                viewModel.gitCommitMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityIdentifier("explorer.git.commit")
        }
        .padding(.horizontal, 8)
    }

    private func explorerGitActionButton(_ title: String, icon: String, showLabel: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if showLabel {
                Label(title, systemImage: icon)
            } else {
                Image(systemName: icon)
            }
        }
        .buttonStyle(.crispyvibesText)
        .controlSize(.small)
        .help(title)
    }

    func gitStatusRow(_ item: GitStatusItem) -> some View {
        let badge = gitBadgePresentation(for: item.code)

        return HStack(spacing: 8) {
            Text(badge.text)
                .font(AppTypographyTokens.caption2)
                .fontWeight(.semibold)
                .frame(width: uiScale.iconSize(18), height: uiScale.iconSize(18))
                .background(badge.color.opacity(0.2))
                .foregroundStyle(badge.color)
                .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(4)))

            Text(item.relativePath)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                viewModel.openGitHistory(scope: .file(relativePath: item.relativePath))
            } label: {
                Image(systemName: "clock")
            }
            .buttonStyle(.crispyvibesText)
            .help(AppStrings.SourceControl.viewFileHistory)
            .accessibilityIdentifier("explorer.git.file-history.\(item.id)")

            if item.canUnstage {
                Button {
                    viewModel.unstageGitItem(item)
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.crispyvibesText)
                .help(AppStrings.SourceControl.unstage)
                .disabled(viewModel.gitIsOperating)
                .accessibilityIdentifier("explorer.git.unstage.\(item.id)")
            }

            if item.canStage {
                Button {
                    viewModel.stageGitItem(item)
                } label: {
                    Image(systemName: "arrow.up.circle")
                }
                .buttonStyle(.crispyvibesText)
                .help(AppStrings.SourceControl.stage)
                .disabled(viewModel.gitIsOperating)
                .accessibilityIdentifier("explorer.git.stage.\(item.id)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectGitStatusItem(item)
        }
    }
}
