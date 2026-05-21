import SwiftUI

struct VibeSpaceCLISelection: Equatable {
    var profile: TextServiceCLIProfile
    var trustMode: CLITrustMode = .standard
    var customCommand: String = ""

    var normalized: VibeSpaceCLISelection {
        VibeSpaceCLISelection(
            profile: profile,
            trustMode: trustMode,
            customCommand: customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var resolvedTextServiceConfiguration: TextServiceCLIConfiguration {
        let selection = normalized
        switch selection.profile {
        case .custom:
            return TextServiceCLIConfiguration(
                profile: .custom,
                trustMode: selection.trustMode,
                command: selection.customCommand,
                arguments: "",
                passAgentFlag: false
            )
        default:
            return AppPreferences.defaultTextServiceCLIConfiguration(
                profile: selection.profile,
                trustMode: selection.trustMode
            )
        }
    }

    var resolvedCommand: String {
        resolvedTextServiceConfiguration.command
    }

    var resolvedStartupCommand: String {
        let selection = normalized
        switch selection.profile {
        case .custom:
            return selection.customCommand
        default:
            return CLIToolCatalog.terminalCommand(
                for: selection.profile,
                trustMode: selection.trustMode
            ) ?? selection.profile.defaultCommand
        }
    }
}

struct VibeSpaceCreationResult {
    var name: String
    var folders: [URL]
    var cliSelection: VibeSpaceCLISelection?
    var projectCLIOverrides: [String: VibeSpaceCLISelection]
}

struct VibeSpaceCreationSheet: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.dismiss) private var dismiss

    let defaultName: String
    let onComplete: (VibeSpaceCreationResult) -> Void

    @State private var step: Step = .name
    @State private var nameDraft: String
    @State private var folders: [URL] = []
    @State private var validationMessage = ""
    @State private var cliProfile: TextServiceCLIProfile?
    @State private var cliTrustMode: CLITrustMode = .standard
    @State private var customCLICommand = ""
    @State private var projectCLIOverrides: [String: TextServiceCLIProfile] = [:]
    @State private var projectCustomCommands: [String: String] = [:]
    @State private var projectTrustModes: [String: CLITrustMode] = [:]

    private enum Step: Int { case name = 0, folders, agent }

    init(defaultName: String, onComplete: @escaping (VibeSpaceCreationResult) -> Void) {
        self.defaultName = defaultName
        self.onComplete = onComplete
        _nameDraft = State(initialValue: defaultName)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stepContent
                    if !validationMessage.isEmpty {
                        Text(validationMessage)
                            .font(AppTypographyTokens.welcomeBody)
                            .foregroundStyle(palette.warningColor)
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 560).frame(minHeight: 420)
        .background(palette.canvasSecondaryBackgroundColor)
        .accessibilityIdentifier("vibespace.creation.sheet")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image("CrispyVibesMonoMark")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: uiScale.iconSize(28), height: uiScale.iconSize(24))
            Text(AppStrings.Home.createVibeSpace)
                .font(AppTypographyTokens.welcomeSectionHeadline)
                .foregroundStyle(palette.primaryTextColor)
            Spacer()
            StepperProgressView(
                stepTitles: ["Name", "Projects", "CLI Agent"],
                currentStep: step.rawValue,
                accentColor: palette.accentColor,
                completedColor: palette.successColor,
                inactiveColor: palette.borderColorValue.opacity(0.5),
                textColor: palette.primaryTextColor,
                secondaryTextColor: palette.secondaryTextColor
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .name: nameStep
        case .folders: foldersStep
        case .agent: agentStep
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.VibeSpaceCreation.nameYourVibeSpace)
                .font(AppTypographyTokens.welcomeFieldLabel)
                .foregroundStyle(palette.secondaryTextColor)

            TextField(AppStrings.VibeSpaceCreation.vibeSpaceName, text: $nameDraft)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous).fill(palette.canvasBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous).stroke(palette.borderColorValue, lineWidth: 1))
                .accessibilityIdentifier("vibespace.creation.name")

            navButtons(
                backLabel: AppStrings.Common.cancel, backAction: { dismiss() },
                nextLabel: "Next: Add Projects", nextAction: {
                    let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { validationMessage = "Enter a name to continue."; return }
                    nameDraft = trimmed
                    validationMessage = ""
                    step = .folders
                }
            )
        }
    }

    private var foldersStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(AppStrings.VibeSpaceCreation.label)
                    .font(AppTypographyTokens.welcomeFieldLabel)
                    .foregroundStyle(palette.secondaryTextColor)
                Text(nameDraft)
                    .font(AppTypographyTokens.welcomeVibeSpaceName)
            }

            Button { chooseFolders() } label: {
                Label("Add Projects", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.crispyvibesText)
            .accessibilityIdentifier("vibespace.creation.add-folders")

            if folders.isEmpty {
                Text(AppStrings.VibeSpace.addProjectToStart)
                    .font(AppTypographyTokens.welcomeBody)
                    .foregroundStyle(palette.secondaryTextColor)
                    .italic()
            } else {
                folderList
            }

            navButtons(
                backLabel: AppStrings.Common.back, backAction: { step = .name; validationMessage = "" },
                nextLabel: "Next: CLI Agent", nextAction: {
                    guard !folders.isEmpty else { validationMessage = "Add at least one folder."; return }
                    validationMessage = ""
                    step = .agent
                },
                nextDisabled: folders.isEmpty
            )
        }
    }

    private var folderList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(folders.enumerated()), id: \.element) { index, url in
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(AppTypographyTokens.welcomeInlineIcon)
                            .foregroundStyle(palette.accentColor)
                        Text(url.lastPathComponent)
                            .font(AppTypographyTokens.welcomeVibeSpaceName)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(url.path)
                            .font(AppTypographyTokens.welcomePath)
                            .lineLimit(1)
                            .foregroundStyle(palette.secondaryTextColor)
                        CrispyVibesIconButton(systemName: "xmark.circle.fill", size: 14, padding: 4, color: palette.secondaryTextColor.opacity(0.7)) {
                            let removed = folders.remove(at: index)
                            projectCLIOverrides.removeValue(forKey: removed.path)
                            projectCustomCommands.removeValue(forKey: removed.path)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxHeight: 140)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous).fill(palette.canvasBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous).stroke(palette.borderColorValue.opacity(0.6), lineWidth: 1))
    }

    private var agentStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.Settings.Services.defaultAgent)
                .font(AppTypographyTokens.welcomeFieldLabel)
                .foregroundStyle(palette.secondaryTextColor)

            agentGrid

            if cliProfile == nil {
                Text(AppStrings.VibeSpaceCreation.noDefaultSelected)
                    .font(AppTypographyTokens.welcomePath)
                    .foregroundStyle(palette.secondaryTextColor)
            }

            if let profile = cliProfile, profile.supportsFullTrust {
                Toggle(isOn: Binding(
                    get: { cliTrustMode == .fullTrust },
                    set: { cliTrustMode = $0 ? .fullTrust : .standard }
                )) {
                    Text("Full Trust")
                        .font(AppTypographyTokens.captionSemibold)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if cliProfile == .custom {
                customCommandField(
                    title: "Custom default command",
                    placeholder: "CLI command",
                    text: $customCLICommand,
                    identifier: "vibespace.creation.custom-command.vibespace"
                )
            }

            if !folders.isEmpty {
                Divider()
                Text(AppStrings.VibeSpaceSettings.perProjectOverrides)
                    .font(AppTypographyTokens.welcomeFieldLabel)
                    .foregroundStyle(palette.secondaryTextColor)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(folders, id: \.self) { url in
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(AppTypographyTokens.welcomeInlineIcon)
                                .foregroundStyle(palette.accentColor)
                            Text(url.lastPathComponent)
                                .font(AppTypographyTokens.captionSemibold)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Picker("", selection: Binding(
                                get: { projectCLIOverrides[url.path] },
                                set: { projectCLIOverrides[url.path] = $0 }
                            )) {
                                Text("VibeSpace Default").tag(nil as TextServiceCLIProfile?)
                                ForEach(CLIToolCatalog.textServiceDisplayProfiles) { profile in
                                    Text(profile.title).tag(profile as TextServiceCLIProfile?)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 160)

                            if let profile = projectCLIOverrides[url.path], profile.supportsFullTrust {
                                Toggle(isOn: Binding(
                                    get: { projectTrustModes[url.path] == .fullTrust },
                                    set: { projectTrustModes[url.path] = $0 ? .fullTrust : .standard }
                                )) {
                                    Text("Trust")
                                        .font(AppTypographyTokens.caption)
                                }
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                            }
                        }
                        .padding(.vertical, 2)

                        if projectCLIOverrides[url.path] == .custom {
                            customCommandField(
                                title: "\(url.lastPathComponent) command",
                                placeholder: "CLI command",
                                text: Binding(
                                    get: { projectCustomCommands[url.path, default: ""] },
                                    set: { projectCustomCommands[url.path] = $0 }
                                ),
                                identifier: projectCustomCommandIdentifier(for: url)
                            )
                            .padding(.leading, 28)
                            .padding(.bottom, 4)
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous).fill(palette.canvasBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous).stroke(palette.borderColorValue.opacity(0.6), lineWidth: 1))
            }

            navButtons(
                backLabel: AppStrings.Common.back, backAction: { step = .folders; validationMessage = "" },
                nextLabel: AppStrings.Home.createVibeSpace, nextAction: {
                    if cliProfile == .custom {
                        let trimmedCommand = customCLICommand.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedCommand.isEmpty else {
                            validationMessage = "Enter a custom default command or choose a packaged CLI."
                            return
                        }
                        customCLICommand = trimmedCommand
                    }

                    for url in folders where projectCLIOverrides[url.path] == .custom {
                        let trimmedCommand = projectCustomCommands[url.path, default: ""]
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedCommand.isEmpty else {
                            validationMessage = "Enter a custom command for \(url.lastPathComponent) or use the VibeSpace default."
                            return
                        }
                        projectCustomCommands[url.path] = trimmedCommand
                    }

                    validationMessage = ""
                    onComplete(VibeSpaceCreationResult(
                        name: nameDraft,
                        folders: folders,
                        cliSelection: vibespaceCLISelection,
                        projectCLIOverrides: resolvedProjectCLIOverrides
                    ))
                    dismiss()
                }
            )
        }
    }

    private var agentGrid: some View {
        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            ForEach(CLIToolCatalog.textServiceDisplayProfiles) { profile in
                let isSelected = cliProfile == profile
                Button {
                    if isSelected {
                        cliProfile = nil
                        cliTrustMode = .standard
                        customCLICommand = ""
                        projectCLIOverrides.removeAll()
                        projectCustomCommands.removeAll()
                        projectTrustModes.removeAll()
                    } else {
                        cliProfile = profile
                        cliTrustMode = .standard
                    }
                } label: {
                    VStack(spacing: 6) {
                        if let iconName = profile.iconName, profile.isCustomIcon {
                            Image(iconName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: uiScale.iconSize(20), height: uiScale.iconSize(20))
                                .foregroundStyle(isSelected ? palette.accentColor : palette.secondaryTextColor)
                        } else {
                            Image(systemName: profile == .custom ? "terminal" : "sparkles")
                                .font(AppTypographyTokens.scaledIcon(18, weight: .medium))
                                .foregroundStyle(isSelected ? palette.accentColor : palette.secondaryTextColor)
                        }
                        Text(profile.title)
                            .font(AppTypographyTokens.captionSemibold)
                            .foregroundStyle(palette.primaryTextColor)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous).fill(palette.canvasBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous).stroke(
                        isSelected ? palette.accentColor : palette.borderColorValue.opacity(0.6),
                        lineWidth: isSelected ? 1.5 : 1
                    ))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func navButtons(
        backLabel: String, backAction: @escaping () -> Void,
        nextLabel: String, nextAction: @escaping () -> Void,
        nextDisabled: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Button(backLabel, action: backAction).buttonStyle(.crispyvibesText).accessibilityIdentifier("vibespace.creation.back")
            Spacer()
            Button(nextLabel, action: nextAction).buttonStyle(.crispyvibesPrimary).disabled(nextDisabled).accessibilityIdentifier("vibespace.creation.next")
        }
    }

    private var vibespaceCLISelection: VibeSpaceCLISelection? {
        guard let cliProfile else { return nil }
        return VibeSpaceCLISelection(
            profile: cliProfile,
            trustMode: cliTrustMode,
            customCommand: customCLICommand
        ).normalized
    }

    private var resolvedProjectCLIOverrides: [String: VibeSpaceCLISelection] {
        var overrides: [String: VibeSpaceCLISelection] = [:]
        for url in folders {
            let path = url.standardizedFileURL.path
            guard let profile = projectCLIOverrides[path] else { continue }
            overrides[path] = VibeSpaceCLISelection(
                profile: profile,
                trustMode: projectTrustModes[path] ?? .standard,
                customCommand: projectCustomCommands[path, default: ""]
            ).normalized
        }
        return overrides
    }

    private func customCommandField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypographyTokens.welcomePath)
                .foregroundStyle(palette.secondaryTextColor)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.canvasBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(palette.borderColorValue.opacity(0.6), lineWidth: 1))
                .accessibilityIdentifier(identifier)
        }
    }

    private func projectCustomCommandIdentifier(for url: URL) -> String {
        let sanitizedPath = url.standardizedFileURL.path.replacingOccurrences(of: "/", with: "_")
        return "vibespace.creation.custom-command.project.\(sanitizedPath)"
    }

    private func chooseFolders() {
        let environment = ProcessInfo.processInfo.environment
        if environment["CRISPYVIBES_UI_TEST_MODE"] == "1",
           let rawPaths = environment["CRISPYVIBES_UI_TEST_VIBESPACE_FOLDERS"] {
            let urls = rawPaths
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)).standardizedFileURL }
            appendSelectedFolders(urls)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add VibeSpace Folder(s)"
        guard panel.runModal() == .OK else { return }
        appendSelectedFolders(panel.urls)
    }

    private func appendSelectedFolders(_ urls: [URL]) {
        var existingPaths = Set(folders.map { $0.standardizedFileURL.path })
        for url in urls {
            let normalized = url.standardizedFileURL
            guard existingPaths.insert(normalized.path).inserted else { continue }
            folders.append(normalized)
        }
        validationMessage = ""
    }
}
