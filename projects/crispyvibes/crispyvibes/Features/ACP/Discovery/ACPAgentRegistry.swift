import AppKit
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
