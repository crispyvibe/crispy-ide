import SwiftUI

extension AppSettingsSheetView {
    var acpAgentCategoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ACPAgentDefaultsCard()
            TodoPipelineSettingsCard()
        }
    }
}

/// F060 — todo pipeline knobs: auto-triage mode and done-completion behavior.
private struct TodoPipelineSettingsCard: View {
    @AppStorage(AppPreferences.todoTriageModeKey) private var triageModeRaw = TodoTriageMode.projectTodosOnly.rawValue
    @AppStorage(AppPreferences.todoAutoCompleteOnDoneKey) private var autoCompleteOnDone = false

    var body: some View {
        SettingsCard(
            title: AppStrings.TodoPipeline.settingsCardTitle,
            description: AppStrings.TodoPipeline.settingsCardDescription
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsFieldRow(
                    title: AppStrings.TodoPipeline.settingsTriageModeTitle,
                    detail: AppStrings.TodoPipeline.settingsTriageModeDetail
                ) {
                    Picker("", selection: Binding(
                        get: { TodoTriageMode(rawValue: triageModeRaw) ?? .projectTodosOnly },
                        set: { triageModeRaw = $0.rawValue }
                    )) {
                        Text(AppStrings.TodoPipeline.settingsTriageOff).tag(TodoTriageMode.off)
                        Text(AppStrings.TodoPipeline.settingsTriageProjectOnly).tag(TodoTriageMode.projectTodosOnly)
                        Text(AppStrings.TodoPipeline.settingsTriageAll).tag(TodoTriageMode.allTodos)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280)
                    .accessibilityIdentifier("app.settings.todo-triage-mode")
                }
                Toggle(isOn: $autoCompleteOnDone) {
                    Text(AppStrings.TodoPipeline.settingsAutoCompleteTitle)
                }
                .accessibilityIdentifier("app.settings.todo-auto-complete")
            }
        }
    }
}

private struct ACPAgentDefaultsCard: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @AppStorage(AppPreferences.acpDefaultAgentIDKey) private var defaultAgentID = ""
    @AppStorage(AppPreferences.acpDefaultTrustModeKey) private var defaultTrustMode = CLITrustMode.standard.rawValue
    @AppStorage(AppPreferences.acpDefaultModelKey) private var defaultModel = ""
    @AppStorage(AppPreferences.acpDefaultReasoningLevelKey) private var defaultReasoningLevel = AgentReasoningLevel.medium.rawValue

    @State private var discoveredAgents: [ACPDiscoveredAgent] = []
    @State private var customAgents: [CustomACPAgent] = []
    @State private var newTitle = ""
    @State private var newExecutable = ""
    @State private var newArguments = ""

    private var selectedDefinition: CLIToolDefinition? {
        CLIToolCatalog.agentDefinitions.first(where: { $0.id == defaultAgentID })
    }

    private var directIntegrationType: CLIToolDefinition.DirectIntegrationType? {
        selectedDefinition?.directIntegration
    }

    var body: some View {
        SettingsCard(
            title: AppStrings.Settings.ACPAgent.cardTitle,
            description: AppStrings.Settings.ACPAgent.cardDescription
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.Settings.ACPAgent.defaultAgentTitle)
                        .font(AppTypographyTokens.settingsFieldTitle)
                    Picker("", selection: $defaultAgentID) {
                        Text(AppStrings.Settings.ACPAgent.defaultAgentEmpty).tag("")
                        ForEach(discoveredAgents.filter(\.isAvailable)) { agent in
                            Text(agent.title).tag(agent.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280)
                    .onChange(of: defaultAgentID) { _, newValue in
                        if let integration = CLIToolCatalog.agentDefinitions.first(where: { $0.id == newValue })?.directIntegration {
                            defaultModel = AgentModelCatalog.defaultModel(for: integration)
                        } else {
                            defaultModel = ""
                        }
                    }
                }

                if let directIntegrationType {
                    Divider()
                    directIntegrationOptions(for: directIntegrationType)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text(AppStrings.Settings.ACPAgent.customAgentsTitle)
                        .font(AppTypographyTokens.settingsFieldTitle)

                    ForEach(customAgents) { agent in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.title)
                                    .font(AppTypographyTokens.subheadlineSemibold)
                                Text(([agent.executable] + agent.arguments).joined(separator: " "))
                                    .font(AppTypographyTokens.caption)
                                    .foregroundStyle(appThemePalette.secondaryTextColor)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                customAgents.removeAll { $0.id == agent.id }
                                saveAndRefresh()
                            } label: {
                                Label(AppStrings.Common.delete, systemImage: "trash")
                            }
                            .buttonStyle(.crispyvibesText)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(
                            AppStrings.Settings.ACPAgent.customAgentName,
                            text: $newTitle
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)

                        TextField(
                            AppStrings.Settings.ACPAgent.customAgentExecutable,
                            text: $newExecutable
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)

                        TextField(
                            AppStrings.Settings.ACPAgent.customAgentArguments,
                            text: $newArguments
                        )
                        .textFieldStyle(.roundedBorder)

                        Button(AppStrings.Common.add) {
                            let arguments = newArguments
                                .split(whereSeparator: { $0.isWhitespace })
                                .map(String.init)
                            customAgents.append(
                                CustomACPAgent(
                                    title: newTitle,
                                    executable: newExecutable,
                                    arguments: arguments
                                )
                            )
                            newTitle = ""
                            newExecutable = ""
                            newArguments = ""
                            saveAndRefresh()
                        }
                        .buttonStyle(.crispyvibesText)
                        .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || newExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        customAgents = AppPreferences.customACPAgents()
        discoveredAgents = ACPAgentRegistry.discoverInstalledAgents()
        if !defaultAgentID.isEmpty,
           !discoveredAgents.filter(\.isAvailable).contains(where: { $0.id == defaultAgentID }) {
            defaultAgentID = ""
        }
    }

    private func saveAndRefresh() {
        AppPreferences.setCustomACPAgents(customAgents)
        discoveredAgents = ACPAgentRegistry.discoverInstalledAgents()
    }

    @ViewBuilder
    private func directIntegrationOptions(for integration: CLIToolDefinition.DirectIntegrationType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.Settings.ACPAgent.trustModeTitle)
                    .font(AppTypographyTokens.settingsFieldTitle)
                Picker("", selection: Binding(
                    get: { CLITrustMode(rawValue: defaultTrustMode) ?? .standard },
                    set: { defaultTrustMode = $0.rawValue }
                )) {
                    ForEach(CLITrustMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.Settings.ACPAgent.modelTitle)
                    .font(AppTypographyTokens.settingsFieldTitle)
                Picker("", selection: $defaultModel) {
                    ForEach(AgentModelCatalog.models(for: integration)) { model in
                        Text(model.name).tag(model.slug)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.Settings.ACPAgent.reasoningTitle)
                    .font(AppTypographyTokens.settingsFieldTitle)
                Picker("", selection: Binding(
                    get: { AgentReasoningLevel(rawValue: defaultReasoningLevel) ?? .medium },
                    set: { defaultReasoningLevel = $0.rawValue }
                )) {
                    ForEach(AgentReasoningLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }
        }
    }
}
