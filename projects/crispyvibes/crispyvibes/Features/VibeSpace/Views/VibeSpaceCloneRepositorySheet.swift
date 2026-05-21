import SwiftUI

struct VibeSpaceCloneRepositorySheet: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Binding var state: VibeSpaceCloneRepositorySheetState
    let onChooseDestination: () -> Void
    let onShowGitHubPicker: () -> Void
    let onShowManualURL: () -> Void
    let onRetryProviderCheck: () -> Void
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            sourceModeSwitcher

            Group {
                switch state.sourceMode {
                case .checkingProviders:
                    checkingProvidersView
                case .githubPicker:
                    githubPickerView
                case .manualURL:
                    manualURLView
                }
            }

            destinationSection
            advancedSection

            if let helperMessage = state.helperMessage, !helperMessage.isEmpty {
                Text(helperMessage)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }

            if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.warningColor)
                    .accessibilityIdentifier("vibespace.clone.error")
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(18)
        .frame(width: 560, height: 520)
        .background(appThemePalette.windowBackgroundColor)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.CloneRepository.title)
                .font(AppTypographyTokens.title3Semibold)
                .foregroundStyle(appThemePalette.primaryTextColor)
            Text(AppStrings.CloneRepository.pickRepoOrPasteURL)
                .font(AppTypographyTokens.caption)
                .foregroundStyle(appThemePalette.secondaryTextColor)
        }
    }

    @ViewBuilder
    private var sourceModeSwitcher: some View {
        HStack(spacing: 8) {
            sourceModeButton(
                title: "GitHub",
                isSelected: state.sourceMode == .githubPicker,
                isEnabled: state.githubAuthenticated && !state.isLoadingProviderOptions,
                action: onShowGitHubPicker
            )

            sourceModeButton(
                title: "Repository URL",
                isSelected: state.sourceMode == .manualURL,
                isEnabled: !state.isLoadingProviderOptions,
                action: onShowManualURL
            )

            Spacer(minLength: 0)

            if state.sourceMode != .checkingProviders {
                Button(AppStrings.CloneRepository.refreshGitHubAccess, action: onRetryProviderCheck)
                    .buttonStyle(.crispyvibesText)
                    .font(AppTypographyTokens.caption)
                    .disabled(state.isSubmitting || state.isLoadingProviderOptions)
                    .accessibilityIdentifier("vibespace.clone.refresh-github")
            }
        }
    }

    private func sourceModeButton(
        title: String,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTypographyTokens.captionSemibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minWidth: 96)
                .background(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous)
                        .fill(
                            isSelected
                                ? appThemePalette.accentColor.opacity(0.18)
                                : appThemePalette.canvasSecondaryBackgroundColor
                        )
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isEnabled ? appThemePalette.primaryTextColor : appThemePalette.secondaryTextColor.opacity(0.6)
        )
        .disabled(!isEnabled)
    }

    private var checkingProvidersView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            ProgressView()
            Text(AppStrings.CloneRepository.checkingGitHub)
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(appThemePalette.primaryTextColor)
            Text(AppStrings.CloneRepository.gitHubDescription)
                .font(AppTypographyTokens.caption)
                .foregroundStyle(appThemePalette.secondaryTextColor)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .background(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(12), style: .continuous)
                .fill(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.55))
        )
    }

    private var githubPickerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(AppStrings.CloneRepository.searchGitHub, text: $state.repositorySearchQuery)
                .textFieldStyle(.roundedBorder)
                .disabled(state.isSubmitting || state.isLoadingProviderOptions)
                .accessibilityIdentifier("vibespace.clone.github-search")

            if state.filteredGitHubRepositories.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(AppTypographyTokens.scaledSystem(22, weight: .semibold))
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                    Text(AppStrings.CloneRepository.noGitHubRepos)
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(appThemePalette.primaryTextColor)
                    Button(AppStrings.CloneRepository.pasteURLInstead, action: onShowManualURL)
                        .buttonStyle(.crispyvibesText)
                        .accessibilityIdentifier("vibespace.clone.use-url-from-empty")
                }
                .frame(maxWidth: .infinity, minHeight: 210)
                .background(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(12), style: .continuous)
                        .fill(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.55))
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(state.filteredGitHubRepositories) { repository in
                            GitHubRepositoryRow(
                                repository: repository,
                                isSelected: state.selectedGitHubRepositoryID == repository.id,
                                onSelect: {
                                    state.selectedGitHubRepositoryID = repository.id
                                }
                            )
                        }
                    }
                    .padding(10)
                }
                .frame(minHeight: 210, maxHeight: 240)
                .background(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(12), style: .continuous)
                        .fill(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(12), style: .continuous)
                        .stroke(appThemePalette.borderColorValue.opacity(0.45), lineWidth: 1)
                )
                .accessibilityIdentifier("vibespace.clone.github-list")
            }
        }
    }

    private var manualURLView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.CloneRepository.repositoryURL)
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(appThemePalette.secondaryTextColor)
            TextField("https://github.com/org/repo.git", text: $state.repositoryURL)
                .textFieldStyle(.roundedBorder)
                .disabled(state.isSubmitting || state.isLoadingProviderOptions)
                .accessibilityIdentifier("vibespace.clone.repository-url")

            if !state.githubAuthenticated {
                Text(AppStrings.CloneRepository.gitHubSignInNote)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.CloneRepository.destinationFolder)
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(appThemePalette.secondaryTextColor)

            HStack(spacing: 8) {
                TextField("Choose destination", text: $state.destinationParentPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(state.isSubmitting)
                    .accessibilityIdentifier("vibespace.clone.destination-path")

                Button(AppStrings.CloneRepository.choose, action: onChooseDestination)
                    .buttonStyle(.crispyvibesText)
                    .disabled(state.isSubmitting)
                    .accessibilityIdentifier("vibespace.clone.destination-choose")
            }
        }
    }

    private var advancedSection: some View {
        DisclosureGroup("Advanced", isExpanded: $state.isShowingAdvancedOptions) {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.VibeSpaceCreation.folderNameOverride)
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                TextField(AppStrings.CloneRepository.optionalDefaultsFromRepo, text: $state.directoryName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(state.isSubmitting)
                    .accessibilityIdentifier("vibespace.clone.directory-name")
            }
            .padding(.top, 8)
        }
        .font(AppTypographyTokens.caption)
        .foregroundStyle(appThemePalette.primaryTextColor)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(AppStrings.Common.cancel, action: onCancel)
                .buttonStyle(.crispyvibesText)
                .disabled(state.isSubmitting)
                .accessibilityIdentifier("vibespace.clone.cancel")

            Spacer(minLength: 0)

            Button(action: onSubmit) {
                if state.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: uiScale.iconSize(18), height: uiScale.iconSize(18))
                } else {
                    Text(AppStrings.CloneRepository.clone)
                }
            }
            .buttonStyle(.crispyvibesPrimary)
            .disabled(!state.canSubmit)
            .accessibilityIdentifier("vibespace.clone.submit")
        }
    }
}

private struct GitHubRepositoryRow: View {
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.appThemePalette) private var appThemePalette
    let repository: WorkerGitHubRepositoryNode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(AppTypographyTokens.scaledSystem(14, weight: .semibold))
                    .foregroundStyle(isSelected ? appThemePalette.accentColor : appThemePalette.secondaryTextColor)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(repository.nameWithOwner)
                            .font(AppTypographyTokens.captionSemibold)
                            .foregroundStyle(appThemePalette.primaryTextColor)
                        if repository.isPrivate {
                            Text(AppStrings.CloneRepository.private)
                                .font(AppTypographyTokens.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(appThemePalette.canvasBackgroundColor)
                                .clipShape(Capsule())
                                .foregroundStyle(appThemePalette.secondaryTextColor)
                        }
                    }

                    if let description = repository.description, !description.isEmpty {
                        Text(description)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                            .lineLimit(2)
                    }

                    Text(repository.cloneURL)
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(appThemePalette.secondaryTextColor.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous)
                    .fill(
                        isSelected
                            ? appThemePalette.accentColor.opacity(0.14)
                            : appThemePalette.windowBackgroundColor.opacity(0.7)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous)
                    .stroke(
                        isSelected
                            ? appThemePalette.accentColor.opacity(0.65)
                            : appThemePalette.borderColorValue.opacity(0.4),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vibespace.clone.github-row.\(repository.nameWithOwner)")
    }
}
