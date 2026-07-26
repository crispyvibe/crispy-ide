import SwiftUI

@MainActor
struct VibeLaneEngineEditor: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    @Binding var configuration: VibeLaneEngineConfiguration
    @State private var agents: [ACPDiscoveredAgent] = []
    @ObservedObject private var optionCatalog: ACPAgentEngineOptionCatalog

    init(
        configuration: Binding<VibeLaneEngineConfiguration>,
        optionCatalog: ACPAgentEngineOptionCatalog
    ) {
        _configuration = configuration
        _optionCatalog = ObservedObject(wrappedValue: optionCatalog)
    }

    private var effectiveAgentID: String? {
        configuration.agentID ?? AppPreferences.acpDefaultAgentID()
    }

    private var options: ACPAgentEngineOptions {
        optionCatalog.options(for: effectiveAgentID)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideGrid
            compactGrid
        }
        .onAppear(perform: refreshAgents)
        .task(id: effectiveAgentID) {
            await optionCatalog.loadOptionsIfNeeded(for: effectiveAgentID)
        }
    }

    private var wideGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: uiScale.spacing(14), verticalSpacing: uiScale.spacing(10)) {
            GridRow {
                fieldLabel(AppStrings.VibeLanes.agent)
                agentPicker
                fieldLabel(AppStrings.VibeLanes.model)
                modelPicker
            }
            GridRow {
                fieldLabel(AppStrings.VibeLanes.mode)
                modePicker
                fieldLabel(AppStrings.VibeLanes.reasoning)
                reasoningPicker
            }
        }
    }

    private var compactGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: uiScale.spacing(12), verticalSpacing: uiScale.spacing(10)) {
            GridRow {
                fieldLabel(AppStrings.VibeLanes.agent)
                agentPicker
            }
            GridRow {
                fieldLabel(AppStrings.VibeLanes.model)
                modelPicker
            }
            GridRow {
                fieldLabel(AppStrings.VibeLanes.mode)
                modePicker
            }
            GridRow {
                fieldLabel(AppStrings.VibeLanes.reasoning)
                reasoningPicker
            }
        }
    }

    private var agentPicker: some View {
        Picker("", selection: $configuration.agentID) {
            Text(defaultAgentLabel).tag(String?.none)
            ForEach(agents.filter { $0.isAvailable && ($0.supportsACP || $0.supportsDirectIntegration) }) { agent in
                Text(agent.title).tag(String?.some(agent.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 220, alignment: .leading)
        .onChange(of: configuration.agentID) { _, _ in
            configuration.modelID = nil
            configuration.modeID = nil
            if configuration.agentID != nil, !options.supportsReasoning {
                configuration.reasoningLevel = nil
            }
        }
    }

    private var modelPicker: some View {
        HStack(spacing: uiScale.spacing(6)) {
            Picker("", selection: $configuration.modelID) {
                Text(AppStrings.VibeLanes.agentDefault).tag(String?.none)
                ForEach(options.models) { model in
                    Text(model.name).tag(String?.some(model.modelId))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(optionCatalog.isLoading(agentID: effectiveAgentID))

            optionDiscoveryStatus
        }
        .frame(maxWidth: 220, alignment: .leading)
    }

    private var modePicker: some View {
        Picker("", selection: $configuration.modeID) {
            Text(AppStrings.VibeLanes.agentDefault).tag(String?.none)
            ForEach(options.modes) { mode in
                Text(mode.name).tag(String?.some(mode.modeId))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 220, alignment: .leading)
    }

    @ViewBuilder
    private var optionDiscoveryStatus: some View {
        if optionCatalog.isLoading(agentID: effectiveAgentID) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(AppStrings.VibeLanes.loadingEngineOptions)
        } else if let error = optionCatalog.discoveryError(for: effectiveAgentID) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(palette.warningColor)
                .help(error)
                .accessibilityLabel(AppStrings.VibeLanes.engineOptionsUnavailable)
        }
    }

    private var reasoningPicker: some View {
        Picker("", selection: $configuration.reasoningLevel) {
            Text(AppStrings.VibeLanes.appDefault).tag(AgentReasoningLevel?.none)
            ForEach(AgentReasoningLevel.allCases) { level in
                Text(level.title).tag(AgentReasoningLevel?.some(level))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 220, alignment: .leading)
        .disabled(effectiveAgentID != nil && !options.supportsReasoning)
    }

    private var defaultAgentLabel: String {
        let defaultID = AppPreferences.acpDefaultAgentID()
        let name = agents.first(where: { $0.id == defaultID })?.title ?? defaultID
        return AppStrings.VibeLanes.defaultAgent(name ?? AppStrings.VibeLanes.notConfigured)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: uiScale.textSize(11), weight: .semibold))
            .foregroundStyle(palette.tertiaryTextColor)
    }

    private func refreshAgents() {
        agents = ACPAgentRegistry.discoverInstalledAgents()
    }
}

@MainActor
struct VibeLaneEngineSummaryView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    var configuration: VibeLaneEngineConfiguration?
    var snapshot: VibeLaneEngineSnapshot?

    @Environment(\.vibeLaneEngineDisplayCatalog) private var engineCatalog

    var body: some View {
        Label(summary, systemImage: "cpu")
            .font(.system(size: uiScale.textSize(11)))
            .foregroundStyle(palette.secondaryTextColor)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var summary: String {
        if let snapshot {
            return VibeLaneEnginePresentation.summary(snapshot)
        }
        return VibeLaneEnginePresentation.summary(
            configuration ?? .default,
            catalog: engineCatalog
        )
    }
}

@MainActor
struct VibeLaneAttemptRow: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let attempt: VibeLaneAttempt

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: uiScale.spacing(6)) {
                Text(AppStrings.VibeLanes.attemptLabel(attempt.index + 1))
                    .font(.system(size: uiScale.textSize(11), weight: .semibold))
                    .foregroundStyle(palette.secondaryTextColor)
                if let result = attempt.result {
                    resultChip(passed: result.passed)
                }
            }
            if let feedback = nonEmpty(attempt.result?.feedback) {
                detailText(feedback)
            }
            if let detail = nonEmpty(attempt.result?.detail) {
                detailText(detail)
            }
            if let engine = attempt.engine {
                VibeLaneEngineSummaryView(snapshot: engine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultChip(passed: Bool) -> some View {
        Text(passed ? AppStrings.VibeLanes.pass : AppStrings.VibeLanes.fail)
            .font(.system(size: uiScale.textSize(10), weight: .bold))
            .foregroundStyle(passed ? .green : .orange)
            .padding(.horizontal, uiScale.spacing(5))
            .padding(.vertical, uiScale.spacing(1))
            .background(Capsule().fill((passed ? Color.green : Color.orange).opacity(0.14)))
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: uiScale.textSize(11), design: .monospaced))
            .foregroundStyle(palette.secondaryTextColor)
            .textSelection(.enabled)
            .lineLimit(8)
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

enum VibeLaneEnginePresentation {
    static func summary(
        _ configuration: VibeLaneEngineConfiguration,
        catalog: VibeLaneEngineDisplayCatalog
    ) -> String {
        let resolved = configuration.resolvingDefaults()
        let agentDisplay = resolved.agentID.flatMap { catalog.agent(id: $0) }
        let agent = agentDisplay?.title
            ?? resolved.agentID
            ?? AppStrings.VibeLanes.notConfigured
        let model = configuration.modelID
            ?? (configuration.agentID == nil ? resolved.modelID : nil)
            ?? AppStrings.VibeLanes.agentDefault
        let mode = configuration.modeID ?? AppStrings.VibeLanes.agentDefault
        let trust = VibeLaneEngineConfiguration.enforcedTrustMode.title
        let reasoning = agentDisplay?.supportsDirectIntegration == true
            ? (resolved.reasoningLevel ?? .medium).title
            : AppStrings.VibeLanes.agentDefault
        return [agent, model, mode, trust, reasoning].joined(separator: " / ")
    }

    static func summary(_ snapshot: VibeLaneEngineSnapshot) -> String {
        let model = snapshot.modelName ?? snapshot.modelID ?? AppStrings.VibeLanes.agentDefault
        let mode = snapshot.modeName ?? snapshot.modeID ?? AppStrings.VibeLanes.agentDefault
        let reasoning = snapshot.reasoningLevel?.title ?? AppStrings.VibeLanes.agentDefault
        return [snapshot.agentName, model, mode, snapshot.trustMode.title, reasoning].joined(separator: " / ")
    }
}

@MainActor
struct VibeLaneRerunSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.crispyvibesUIScale) private var uiScale

    let checkpointTitle: String
    let optionCatalog: ACPAgentEngineOptionCatalog
    let onRun: (VibeLaneEngineConfiguration) -> Void
    @State private var engine: VibeLaneEngineConfiguration

    init(
        checkpointTitle: String,
        engine: VibeLaneEngineConfiguration,
        optionCatalog: ACPAgentEngineOptionCatalog,
        onRun: @escaping (VibeLaneEngineConfiguration) -> Void
    ) {
        self.checkpointTitle = checkpointTitle
        self.optionCatalog = optionCatalog
        self.onRun = onRun
        _engine = State(initialValue: engine)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(16)) {
            Text(AppStrings.VibeLanes.rerunStep)
                .font(.system(size: uiScale.textSize(17), weight: .semibold))
            Text(checkpointTitle)
                .font(.system(size: uiScale.textSize(13)))
            VibeLaneEngineEditor(configuration: $engine, optionCatalog: optionCatalog)
            HStack {
                Spacer()
                Button(AppStrings.VibeLanes.cancel) { dismiss() }
                Button {
                    onRun(engine)
                    dismiss()
                } label: {
                    Label(AppStrings.VibeLanes.rerun, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(uiScale.spacing(20))
        .frame(minWidth: 620)
    }
}
