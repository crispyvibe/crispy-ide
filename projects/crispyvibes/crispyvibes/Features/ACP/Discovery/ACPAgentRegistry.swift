import AppKit
import Combine
import Foundation

struct ACPAgentDefinition: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let executable: String
    let arguments: [String]
}

struct ACPDiscoveredAgent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let executable: String
    let arguments: [String]
    let supportsACP: Bool
    let directIntegration: CLIToolDefinition.DirectIntegrationType?
    let executablePath: String?

    var isAvailable: Bool { executablePath != nil }
    var supportsDirectIntegration: Bool { directIntegration != nil }

    var agentDefinition: ACPAgentDefinition? {
        guard isAvailable, supportsACP else { return nil }
        return ACPAgentDefinition(id: id, title: title, executable: executable, arguments: arguments)
    }
}

struct CustomACPAgent: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let executable: String
    let arguments: [String]

    init(
        id: String = UUID().uuidString,
        title: String,
        executable: String,
        arguments: [String]
    ) {
        self.id = id
        self.title = title
        self.executable = executable
        self.arguments = arguments
    }
}

enum AgentReasoningLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case low
    case medium
    case high
    case max

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AgentModelCatalog {
    struct ModelOption: Identifiable, Sendable {
        let slug: String
        let name: String

        var id: String { slug }
    }

    static let claudeCode: [ModelOption] = [
        .init(slug: "opus", name: "Claude Opus 4.7"),
        .init(slug: "opus[1m]", name: "Claude Opus 4.7 (1M context)"),
        .init(slug: "sonnet", name: "Claude Sonnet 4.6"),
        .init(slug: "haiku", name: "Claude Haiku 4.5"),
    ]

    static let codex: [ModelOption] = [
        .init(slug: "gpt-5.5", name: "GPT-5.5"),
        .init(slug: "gpt-5.5-fast", name: "GPT-5.5 Fast"),
        .init(slug: "gpt-5.4", name: "GPT-5.4"),
        .init(slug: "gpt-5.4-fast", name: "GPT-5.4 Fast"),
        .init(slug: "gpt-5.4-mini", name: "GPT-5.4 Mini"),
        .init(slug: "gpt-5.3-codex", name: "GPT-5.3 Codex"),
        .init(slug: "gpt-5.3-codex-spark", name: "GPT-5.3 Codex Spark"),
        .init(slug: "gpt-5.2", name: "GPT-5.2"),
    ]

    static func models(for integration: CLIToolDefinition.DirectIntegrationType) -> [ModelOption] {
        switch integration {
        case .claudeCode:
            return claudeCode
        case .codex:
            return codex
        }
    }

    static func defaultModel(for integration: CLIToolDefinition.DirectIntegrationType) -> String {
        switch integration {
        case .claudeCode:
            return "sonnet"
        case .codex:
            return "gpt-5.5"
        }
    }
}

struct ACPAgentEngineOptions: Equatable, Sendable {
    var models: [ACPModelInfo]
    var modes: [ACPModeInfo]
    var supportsReasoning: Bool

    static let empty = ACPAgentEngineOptions(models: [], modes: [], supportsReasoning: false)
}

/// Agent-scoped engine capabilities shared by ACP chat and Vibe Lanes.
/// Direct integrations have a static catalog; protocol agents publish their
/// session-discovered models and modes after connecting.
@MainActor
final class ACPAgentEngineOptionCatalog: ObservableObject {
    typealias OptionDiscovery = @MainActor (String) async throws -> ACPAgentEngineOptions

    @Published private var cached: [String: ACPAgentEngineOptions] = [:]
    @Published private var loadingAgentIDs: Set<String> = []
    @Published private var discoveryErrors: [String: String] = [:]

    private let discoverOptions: OptionDiscovery?
    private var loadedAgentIDs: Set<String> = []

    init(discoverOptions: OptionDiscovery? = nil) {
        self.discoverOptions = discoverOptions
    }

    func options(for agentID: String?) -> ACPAgentEngineOptions {
        guard let agentID else { return .empty }
        if let definition = CLIToolCatalog.agentDefinitions.first(where: { $0.id == agentID }),
           let integration = definition.directIntegration {
            return ACPAgentEngineOptions(
                models: AgentModelCatalog.models(for: integration).map {
                    ACPModelInfo(modelId: $0.slug, name: $0.name, description: nil)
                },
                modes: [
                    ACPModeInfo(modeId: "default", name: "Default", description: nil),
                    ACPModeInfo(modeId: "plan", name: "Plan", description: nil),
                ],
                supportsReasoning: true
            )
        }
        return cached[agentID] ?? .empty
    }

    func isLoading(agentID: String?) -> Bool {
        agentID.map(loadingAgentIDs.contains) ?? false
    }

    func discoveryError(for agentID: String?) -> String? {
        agentID.flatMap { discoveryErrors[$0] }
    }

    /// ACP models and modes are session-scoped capabilities. Probe them once on
    /// demand so non-chat surfaces can offer the same choices as ACP chat.
    func loadOptionsIfNeeded(for agentID: String?) async {
        guard let agentID,
              CLIToolCatalog.agentDefinitions.first(where: { $0.id == agentID })?.directIntegration == nil,
              !loadedAgentIDs.contains(agentID),
              !loadingAgentIDs.contains(agentID),
              let discoverOptions else {
            return
        }

        loadingAgentIDs.insert(agentID)
        discoveryErrors[agentID] = nil
        defer { loadingAgentIDs.remove(agentID) }

        do {
            let options = try await discoverOptions(agentID)
            record(
                agentID: agentID,
                models: options.models,
                modes: options.modes,
                supportsReasoning: options.supportsReasoning
            )
        } catch {
            discoveryErrors[agentID] = error.localizedDescription
        }
    }

    func record(
        agentID: String,
        models: [ACPModelInfo],
        modes: [ACPModeInfo],
        supportsReasoning: Bool
    ) {
        let options = ACPAgentEngineOptions(
            models: models,
            modes: modes,
            supportsReasoning: supportsReasoning
        )
        loadedAgentIDs.insert(agentID)
        discoveryErrors[agentID] = nil
        guard cached[agentID] != options else { return }
        cached[agentID] = options
    }
}

enum ACPAgentRegistry {

    /// Central mapping from agent ID to asset catalog icon name.
    static func agentIconAssetName(for agentId: String) -> String? {
        switch agentId {
        case "claudeCode": return "claude-icon"
        case "kiro": return "kiro-icon"
        case "codex": return "codex-icon"
        case "gemini": return "gemini-icon"
        case "copilot": return "copilot-icon"
        case "opencode": return "opencode-icon"
        default: return nil
        }
    }

    /// Returns a resized NSImage for the agent icon, or nil if not found.
    static func agentIconImage(for agentId: String, size: CGFloat = 16) -> NSImage? {
        guard let name = agentIconAssetName(for: agentId),
              let img = NSImage(named: name) else { return nil }
        let copy = img.copy() as! NSImage
        copy.size = NSSize(width: size, height: size)
        return copy
    }

    static func discoverInstalledAgents(
        userDefaults: UserDefaults = .standard,
        resolveExecutable: (String) -> String? = ACPAgentRegistry.resolveExecutable
    ) -> [ACPDiscoveredAgent] {
        let catalogAgents = CLIToolCatalog.agentDefinitions.map { definition in
            let executable = definition.acpCommand
                ?? definition.terminalInvocation?.executable
                ?? ""
            let arguments = definition.acpArguments ?? []
            return ACPDiscoveredAgent(
                id: definition.id,
                title: definition.title,
                executable: executable,
                arguments: arguments,
                supportsACP: definition.supportsACP,
                directIntegration: definition.directIntegration,
                executablePath: resolveExecutable(executable)
            )
        }
        let customAgents = AppPreferences.customACPAgents(userDefaults: userDefaults).map { entry in
            return ACPDiscoveredAgent(
                id: entry.id,
                title: entry.title,
                executable: entry.executable,
                arguments: entry.arguments,
                supportsACP: true,
                directIntegration: nil,
                executablePath: resolveExecutable(entry.executable)
            )
        }
        return catalogAgents + customAgents
    }

    static func agentDefinition(
        id: String,
        userDefaults: UserDefaults = .standard,
        resolveExecutable: (String) -> String? = ACPAgentRegistry.resolveExecutable
    ) -> ACPAgentDefinition? {
        discoverInstalledAgents(userDefaults: userDefaults, resolveExecutable: resolveExecutable)
            .first(where: { $0.id == id })?
            .agentDefinition
    }

    static func resolveExecutable(_ name: String) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let fileManager = FileManager.default
        let resolvedEnvironment = CommandPathResolver.environmentWithResolvedPath()

        if trimmedName.contains("/") {
            let candidateURL = URL(fileURLWithPath: trimmedName).standardizedFileURL
            let candidatePath = candidateURL.path
            return fileManager.isExecutableFile(atPath: candidatePath) ? candidatePath : nil
        }

        let pathEntries = (resolvedEnvironment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for entry in pathEntries {
            guard !entry.isEmpty else { continue }
            let candidatePath = URL(fileURLWithPath: entry)
                .appendingPathComponent(trimmedName)
                .standardizedFileURL
                .path
            if fileManager.isExecutableFile(atPath: candidatePath) {
                return candidatePath
            }
        }

        return nil
    }
}
