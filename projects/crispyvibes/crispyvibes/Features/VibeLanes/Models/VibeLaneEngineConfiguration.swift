import Foundation

// F059 - Authored per-step ACP settings and the immutable settings reported by
// the session for one recorded attempt.

/// Immutable, display-only agent metadata for engine summaries.
///
/// `ACPAgentRegistry.discoverInstalledAgents()` resolves every catalog and custom
/// executable through PATH, so it must never run inside a SwiftUI `body`: engine
/// summaries render once per lane checkpoint and once per recorded attempt, which
/// would repeat that scan many times for a single dashboard pass. Discovery
/// happens once outside the render path and the result is passed in as this value.
struct VibeLaneEngineDisplayCatalog: Sendable, Equatable {
    struct Agent: Sendable, Equatable {
        let title: String
        let supportsDirectIntegration: Bool
    }

    private let agentsByID: [String: Agent]

    init(agentsByID: [String: Agent]) {
        self.agentsByID = agentsByID
    }

    /// Build from discovered agents. Call off the render path (a `.task` or app
    /// startup), never from a view `body`.
    init(discovered: [ACPDiscoveredAgent]) {
        self.init(agentsByID: Dictionary(
            discovered.map {
                ($0.id, Agent(
                    title: $0.title,
                    supportsDirectIntegration: $0.supportsDirectIntegration
                ))
            },
            uniquingKeysWith: { first, _ in first }
        ))
    }

    /// Nothing resolved yet. Summaries fall back to the raw agent id, which keeps
    /// previews and tests free of filesystem probing.
    static let unresolved = VibeLaneEngineDisplayCatalog(agentsByID: [:])

    func agent(id: String) -> Agent? {
        agentsByID[id]
    }
}

struct VibeLaneEngineConfiguration: Codable, Hashable, Sendable {
    var agentID: String?
    var modelID: String?
    var modeID: String?
    var reasoningLevel: AgentReasoningLevel?

    init(
        agentID: String? = nil,
        modelID: String? = nil,
        modeID: String? = nil,
        reasoningLevel: AgentReasoningLevel? = nil
    ) {
        self.agentID = Self.nonEmpty(agentID)
        self.modelID = Self.nonEmpty(modelID)
        self.modeID = Self.nonEmpty(modeID)
        self.reasoningLevel = reasoningLevel
    }

    static let `default` = VibeLaneEngineConfiguration()
    static let enforcedTrustMode = CLITrustMode.fullTrust

    var isDefault: Bool {
        agentID == nil
            && modelID == nil
            && modeID == nil
            && reasoningLevel == nil
    }

    /// Fill the knobs that have app-wide defaults. When a lane explicitly picks
    /// an agent but no model, leave the model unset so that agent chooses its own
    /// default, matching ACP chat.
    func resolvingDefaults(
        legacyAgentID: String? = nil,
        userDefaults: UserDefaults = .standard
    ) -> VibeLaneEngineConfiguration {
        let authoredAgentID = Self.nonEmpty(agentID)
        let legacyAgentID = Self.nonEmpty(legacyAgentID)
        let resolvedAgentID = authoredAgentID
            ?? legacyAgentID
            ?? AppPreferences.acpDefaultAgentID(userDefaults: userDefaults)
        let hasAgentOverride = authoredAgentID != nil || legacyAgentID != nil
        let resolvedModelID = Self.nonEmpty(modelID)
            ?? (hasAgentOverride ? nil : AppPreferences.acpDefaultModelID(userDefaults: userDefaults))

        return VibeLaneEngineConfiguration(
            agentID: resolvedAgentID,
            modelID: resolvedModelID,
            modeID: modeID,
            reasoningLevel: reasoningLevel ?? AppPreferences.acpDefaultReasoningLevel(userDefaults: userDefaults)
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct VibeLaneEngineSnapshot: Codable, Hashable, Sendable {
    var agentID: String
    var agentName: String
    var modelID: String?
    var modelName: String?
    var modeID: String?
    var modeName: String?
    var trustMode: CLITrustMode
    /// nil means the selected agent does not expose a reasoning control.
    var reasoningLevel: AgentReasoningLevel?

    init(
        agentID: String,
        agentName: String,
        modelID: String? = nil,
        modelName: String? = nil,
        modeID: String? = nil,
        modeName: String? = nil,
        trustMode: CLITrustMode,
        reasoningLevel: AgentReasoningLevel? = nil
    ) {
        self.agentID = agentID
        self.agentName = agentName
        self.modelID = modelID
        self.modelName = modelName
        self.modeID = modeID
        self.modeName = modeName
        self.trustMode = trustMode
        self.reasoningLevel = reasoningLevel
    }
}
