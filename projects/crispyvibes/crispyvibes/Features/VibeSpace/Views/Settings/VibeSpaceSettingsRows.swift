import SwiftUI

struct VibeSpaceStartupProfileRow: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    let terminalIndex: Int
    let availableTerminalPresets: [TerminalPresetDefinition]
    @Binding var profile: VibeSpaceTerminalStartupProfile
    @State private var selectedInputMode: StartupInputMode = .none

    private var normalizedProfile: VibeSpaceTerminalStartupProfile {
        profile.normalized()
    }

    private var presetOptions: [TerminalPresetDefinition] {
        availableTerminalPresets.isEmpty ? TerminalViewModel.builtInPresets : availableTerminalPresets
    }

    private var inferredInputMode: StartupInputMode {
        if matchedPresetSelection != nil || normalizedProfile.presetID != nil {
            return .preset
        }
        if !normalizedProfile.command.isEmpty {
            return .command
        }
        return .none
    }

    private var matchedPresetSelection: (preset: TerminalPresetDefinition, launchMode: TerminalPresetLaunchMode)? {
        if let presetID = normalizedProfile.presetID,
           let preset = presetOptions.first(where: { $0.id == presetID }) {
            return (preset, .standard)
        }

        for preset in presetOptions {
            if normalizedProfile.command == preset.defaultCommand {
                return (preset, .standard)
            }
            if let fullTrustCommand = preset.fullTrustCommand,
               normalizedProfile.command == fullTrustCommand {
                return (preset, .fullTrust)
            }
        }
        return nil
    }

    private var selectedPresetDefinition: TerminalPresetDefinition? {
        matchedPresetSelection?.preset
            ?? presetOptions.first(where: { $0.id == normalizedProfile.presetID })
    }

    private var selectedPresetLaunchMode: TerminalPresetLaunchMode {
        matchedPresetSelection?.launchMode ?? .standard
    }

    private var inputModeBinding: Binding<StartupInputMode> {
        Binding(
            get: { selectedInputMode },
            set: { mode in
                selectedInputMode = mode
                switch mode {
                case .none:
                    profile = .empty
                case .preset:
                    if let matchedPresetSelection {
                        profile = VibeSpaceTerminalStartupProfile(
                            presetID: nil,
                            command: matchedPresetSelection.preset.command(for: matchedPresetSelection.launchMode)
                        )
                    } else {
                        profile = .empty
                    }
                case .command:
                    profile = VibeSpaceTerminalStartupProfile(
                        presetID: nil,
                        command: normalizedProfile.command
                    )
                }
            }
        )
    }

    private var presetSelectionBinding: Binding<String> {
        Binding(
            get: {
                selectedPresetDefinition?.id ?? VibeSpaceStartupSettings.noPresetSelectionToken
            },
            set: { newPresetSelection in
                selectedInputMode = .preset
                let selectedPresetID =
                    newPresetSelection == VibeSpaceStartupSettings.noPresetSelectionToken
                    ? nil
                    : newPresetSelection
                let selectedPresetDefinition = presetOptions.first(where: { $0.id == selectedPresetID })
                profile = VibeSpaceTerminalStartupProfile(
                    presetID: nil,
                    command: selectedPresetDefinition?.command(
                        for: selectedPresetDefinition?.supportsFullTrust == true
                            ? selectedPresetLaunchMode
                            : .standard
                    ) ?? ""
                )
            }
        )
    }

    private var presetLaunchModeBinding: Binding<TerminalPresetLaunchMode> {
        Binding(
            get: {
                selectedPresetDefinition?.supportsFullTrust == true ? selectedPresetLaunchMode : .standard
            },
            set: { newLaunchMode in
                guard let selectedPresetDefinition else { return }
                selectedInputMode = .preset
                profile = VibeSpaceTerminalStartupProfile(
                    presetID: nil,
                    command: selectedPresetDefinition.command(for: newLaunchMode)
                )
            }
        )
    }

    private var commandBinding: Binding<String> {
        Binding(
            get: { normalizedProfile.command },
            set: { newCommand in
                selectedInputMode = .command
                profile = VibeSpaceTerminalStartupProfile(
                    presetID: nil,
                    command: newCommand
                )
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Terminal \(terminalIndex + 1)")
                .font(AppTypographyTokens.subheadlineSemibold)

            SettingsFieldRow(title: "Mode", detail: nil, labelWidth: 120) {
                Picker("Startup mode", selection: inputModeBinding) {
                    ForEach(StartupInputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("vibespace.settings.profile.\(terminalIndex + 1).mode")
            }

            switch selectedInputMode {
            case .none:
                EmptyView()
            case .preset:
                SettingsFieldRow(title: "Preset", detail: nil, labelWidth: 120) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Preset", selection: presetSelectionBinding) {
                            Text(AppStrings.VibeSpaceCreation.choosePreset).tag(VibeSpaceStartupSettings.noPresetSelectionToken)
                            ForEach(presetOptions) { preset in
                                Text("\(preset.shortLabel) (\(preset.defaultCommand))").tag(preset.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("vibespace.settings.profile.\(terminalIndex + 1).preset")

                        if let selectedPresetDefinition, selectedPresetDefinition.supportsFullTrust {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(AppStrings.VibeSpaceSettings.trustLevel)
                                    .font(AppTypographyTokens.settingsFieldTitle)
                                    .foregroundStyle(appThemePalette.secondaryTextColor)

                                TerminalPresetLaunchModeChipSelector(
                                    selection: presetLaunchModeBinding,
                                    accessibilityIdentifier: "vibespace.settings.profile.\(terminalIndex + 1).trust"
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if let selectedPresetDefinition {
                            PresetCommandSummary(
                                command: selectedPresetDefinition.command(for: presetLaunchModeBinding.wrappedValue),
                                launchMode: presetLaunchModeBinding.wrappedValue,
                                supportsFullTrust: selectedPresetDefinition.supportsFullTrust
                            )
                        }
                    }
                }
            case .command:
                SettingsFieldRow(title: "Command", detail: nil, labelWidth: 120) {
                    TextField(
                        "Command to run on startup",
                        text: commandBinding,
                        axis: .vertical
                    )
                    .textFieldStyle(SquareBorderTextFieldStyle())
                    .lineLimit(1...3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("vibespace.settings.profile.\(terminalIndex + 1).command")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10))
                .fill(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10))
                .stroke(appThemePalette.borderColorValue.opacity(0.62), lineWidth: 1)
        )
        .onAppear {
            selectedInputMode = inferredInputMode
        }
        .onChange(of: profile) { _, _ in
            let inferredMode = inferredInputMode
            if selectedInputMode == .command, inferredMode == .preset {
                return
            }
            if inferredMode != .none || selectedInputMode == .none {
                selectedInputMode = inferredMode
            }
        }
    }
}

struct VibeSpaceProjectStartupOverrideRow: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    let project: VibeSpaceSettingsProjectItem
    let availableTerminalPresets: [TerminalPresetDefinition]
    let availableACPAgents: [ACPDiscoveredAgent]
    @Binding var colorTag: ProjectColorTag?
    @Binding var acpAgentOverrideID: String?
    @Binding var terminalShellOverride: TerminalShellPreference?
    @Binding var shortcutIndex: Int?
    @Binding var startupOverride: VibeSpaceProjectStartupOverride?
    var onRemove: () -> Void = {}
    @State private var isColorPopoverPresented = false

    private var shortcutSelectionBinding: Binding<Int> {
        Binding(
            get: { shortcutIndex ?? 0 },
            set: { newValue in
                shortcutIndex = newValue == 0 ? nil : newValue
            }
        )
    }

    private var normalizedOverride: VibeSpaceProjectStartupOverride {
        startupOverride?.normalized() ?? .empty
    }

    private var terminalShellSelectionBinding: Binding<TerminalShellSelection> {
        Binding(
            get: { TerminalShellSelection(shellPreference: terminalShellOverride) },
            set: { selection in
                terminalShellOverride = selection.shellPreference
            }
        )
    }

    private var projectColorSelection: Binding<Color> {
        Binding(
            get: { colorTag?.color ?? project.colorTag?.color ?? appThemePalette.accentColor },
            set: { newColor in
                colorTag = ProjectColorTag(color: newColor)
            }
        )
    }

    private var overrideModeBinding: Binding<ProjectStartupBehavior> {
        Binding(
            get: { startupOverride == nil ? .inherited : .override },
            set: { mode in
                switch mode {
                case .inherited:
                    startupOverride = nil
                case .override:
                    startupOverride = startupOverride?.normalized() ?? .empty
                }
            }
        )
    }

    private var acpAgentSelectionBinding: Binding<String> {
        Binding(
            get: { acpAgentOverrideID ?? "" },
            set: { newValue in
                acpAgentOverrideID = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private var startupTerminalCountBinding: Binding<Int> {
        Binding(
            get: { normalizedOverride.startupTerminalCount },
            set: { newCount in
                let clampedCount = Swift.max(
                    VibeSpaceProjectStartupOverride.minimumTerminalCount,
                    Swift.min(newCount, VibeSpaceProjectStartupOverride.maximumTerminalCount)
                )
                var updatedOverride = startupOverride?.normalized() ?? .empty
                updatedOverride.startupTerminalCount = clampedCount
                startupOverride = updatedOverride.normalized()
            }
        )
    }

    private var selectedStartupBehavior: ProjectStartupBehavior {
        startupOverride == nil ? .inherited : .override
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(colorTag?.color ?? project.colorTag?.color ?? appThemePalette.accentColor)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(appThemePalette.borderColorValue.opacity(0.75), lineWidth: 0.8)
                            )

                        Label(project.title, systemImage: "folder")
                            .font(AppTypographyTokens.settingsSidebarTitle)
                            .lineLimit(1)
                    }

                    Text(project.path)
                        .font(AppTypographyTokens.settingsFieldDetail)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.crispyvibesText)
                .accessibilityIdentifier("vibespace.settings.project.remove")
            }

            SettingsFieldRow(title: "Color", detail: "Shown in project cards and terminal board accents.", labelWidth: 120) {
                HStack(spacing: 8) {
                    ColorPicker("Project color", selection: projectColorSelection, supportsOpacity: false)
                        .labelsHidden()
                        .frame(maxWidth: 160, alignment: .leading)
                        .accessibilityIdentifier("vibespace.settings.project.color")

                    Button(AppStrings.Common.more) {
                        isColorPopoverPresented = true
                    }
                    .buttonStyle(.crispyvibesText)

                    if colorTag != nil {
                        Button(AppStrings.Common.clear) {
                            colorTag = nil
                        }
                        .buttonStyle(.crispyvibesText)
                        .accessibilityIdentifier("vibespace.settings.project.clear-color")
                    }
                }
                .popover(isPresented: $isColorPopoverPresented, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        ColorPicker("Project Color", selection: projectColorSelection, supportsOpacity: false)
                        if colorTag != nil {
                            Button(AppStrings.Common.clearColor) {
                                colorTag = nil
                            }
                            .buttonStyle(.crispyvibesText)
                        }
                    }
                    .padding(12)
                    .frame(width: 220)
                }
            }

            SettingsFieldRow(
                title: "ACP agent",
                detail: "Overrides the app default structured agent for this project.",
                labelWidth: 120
            ) {
                Picker("Project ACP agent", selection: acpAgentSelectionBinding) {
                    Text("Use App Default").tag("")
                    ForEach(availableACPAgents.filter(\.isAvailable)) { agent in
                        Text(agent.title).tag(agent.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("vibespace.settings.project.acp-agent")
            }

            SettingsFieldRow(
                title: "Shell",
                detail: "Overrides the vibespace default shell for this project.",
                labelWidth: 120
            ) {
                Picker("Project shell", selection: terminalShellSelectionBinding) {
                    ForEach(TerminalShellSelection.allCases) { selection in
                        Text(selection.title(for: .vibespaceDefault)).tag(selection)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("vibespace.settings.project.shell")
            }

            SettingsFieldRow(title: "Shortcut", detail: nil, labelWidth: 120) {
                Picker("Shortcut", selection: shortcutSelectionBinding) {
                    Text(AppStrings.Common.none).tag(0)
                    ForEach(1...9, id: \.self) { slot in
                        Label("\(slot)", systemImage: "command").tag(slot)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsFieldRow(title: "Startup behavior", detail: nil, labelWidth: 120) {
                Picker("Startup behavior", selection: overrideModeBinding) {
                    ForEach(ProjectStartupBehavior.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(
                    "vibespace.settings.project.\(project.id.uuidString).startup-behavior"
                )
            }

            switch selectedStartupBehavior {
            case .inherited:
                Text(AppStrings.VibeSpaceSettings.usesDefaults)
                    .font(AppTypographyTokens.settingsFieldDetail)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            case .override:
                SettingsFieldRow(title: "Startup terminals", detail: nil, labelWidth: 120) {
                    HStack(spacing: 8) {
                        Text("\(normalizedOverride.startupTerminalCount)")
                            .font(AppTypographyTokens.scaledChromeSystem(13, design: .monospaced).monospacedDigit())
                            .frame(minWidth: 28, alignment: .trailing)
                        Stepper(
                            "",
                            value: startupTerminalCountBinding,
                            in: VibeSpaceProjectStartupOverride.minimumTerminalCount...VibeSpaceProjectStartupOverride.maximumTerminalCount
                        )
                        .labelsHidden()
                    }
                    .accessibilityIdentifier("vibespace.settings.project.startup-terminal-count")
                }

                ForEach(Array(0..<normalizedOverride.startupTerminalCount), id: \.self) { terminalIndex in
                    VibeSpaceStartupProfileRow(
                        terminalIndex: terminalIndex,
                        availableTerminalPresets: availableTerminalPresets,
                        profile: startupProfileBinding(for: terminalIndex)
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10))
                .fill(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.44))
        )
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10))
                .stroke(appThemePalette.borderColorValue.opacity(0.62), lineWidth: 1)
        )
    }

    private func startupProfileBinding(
        for terminalIndex: Int
    ) -> Binding<VibeSpaceTerminalStartupProfile> {
        Binding(
            get: {
                normalizedOverride.profile(at: terminalIndex)
            },
            set: { updatedProfile in
                var updatedOverride = startupOverride?.normalized() ?? .empty
                updatedOverride.setProfile(updatedProfile, at: terminalIndex)
                startupOverride = updatedOverride.normalized()
            }
        )
    }
}

private struct TerminalPresetLaunchModeChipSelector: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Binding var selection: TerminalPresetLaunchMode
    let accessibilityIdentifier: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TerminalPresetLaunchMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.title)
                        .font(AppTypographyTokens.scaledChromeSystem(12, weight: .semibold))
                        .foregroundStyle(
                            selection == mode
                                ? appThemePalette.primaryTextColor
                                : appThemePalette.secondaryTextColor
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minWidth: 96)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    selection == mode
                                        ? appThemePalette.selectionBackgroundColor.opacity(0.48)
                                        : appThemePalette.canvasSecondaryBackgroundColor.opacity(0.28)
                                )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    selection == mode
                                        ? appThemePalette.borderColorValue
                                        : appThemePalette.borderColorValue.opacity(0.5),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(accessibilityIdentifier).\(mode.id)")
            }
        }
    }
}

private struct PresetCommandSummary: View {
    @Environment(\.appThemePalette) private var appThemePalette
    let command: String
    let launchMode: TerminalPresetLaunchMode
    let supportsFullTrust: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(supportsFullTrust ? "Runs (\(launchMode.title)):" : "Runs:")
                .font(AppTypographyTokens.settingsFieldDetail)
                .foregroundStyle(appThemePalette.secondaryTextColor)
            Text(command)
                .font(AppTypographyTokens.scaledChromeSystem(11, design: .monospaced).monospacedDigit())
                .textSelection(.enabled)
        }
    }
}

struct VibeSpaceProjectListRow: View {
    @Environment(\.appThemePalette) private var appThemePalette
    let project: VibeSpaceSettingsProjectItem

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(project.colorTag?.color ?? appThemePalette.accentColor)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .font(AppTypographyTokens.settingsSidebarTitle)
                    .lineLimit(1)
                Text(project.path)
                    .font(AppTypographyTokens.settingsFieldDetail)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let shortcutIndex = project.shortcutIndex {
                Text("Cmd+\(shortcutIndex)")
                    .font(AppTypographyTokens.scaledChromeSystem(12, design: .monospaced).monospacedDigit())
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("vibespace.settings.project.list-row")
    }
}
