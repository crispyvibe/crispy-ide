import Foundation

enum CLITrustMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard
    case fullTrust

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "Standard"
        case .fullTrust:
            return "Full Trust"
        }
    }
}

struct CLIResolvedCommand: Equatable, Sendable {
    let executable: String
    let arguments: String

    var commandString: String {
        let trimmedArguments = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArguments.isEmpty else { return executable }
        return "\(executable) \(trimmedArguments)"
    }
}

struct CLIInvocationDefinition: Equatable, Sendable {
    let executable: String
    let standardArguments: String
    let fullTrustArguments: String?
    let defaultPassAgentFlag: Bool

    /// How the CLI receives the prompt in print/one-shot mode.
    enum InputMode: Equatable, Sendable {
        case positionalArg   // prompt appended as last argument
        case stdin           // prompt written to stdin
    }

    init(
        executable: String,
        standardArguments: String = "",
        fullTrustArguments: String? = nil,
        defaultPassAgentFlag: Bool = false,
        printModeArguments: String? = nil,
        printModeInputMode: InputMode = .positionalArg
    ) {
        self.executable = executable
        self.standardArguments = standardArguments
        self.fullTrustArguments = fullTrustArguments
        self.defaultPassAgentFlag = defaultPassAgentFlag
        self.printModeArguments = printModeArguments
        self.printModeInputMode = printModeInputMode
    }

    /// Arguments for one-shot text generation (print mode). Falls back to standardArguments.
    let printModeArguments: String?
    /// How the prompt is delivered in print mode.
    let printModeInputMode: InputMode

    var supportsFullTrust: Bool {
        fullTrustArguments != nil
    }

    func arguments(for trustMode: CLITrustMode) -> String {
        if trustMode == .fullTrust, let fullTrustArguments {
            return fullTrustArguments
        }
        return standardArguments
    }

    func resolvedCommand(for trustMode: CLITrustMode) -> CLIResolvedCommand {
        CLIResolvedCommand(
            executable: executable,
            arguments: arguments(for: trustMode)
        )
    }
}

struct CLITerminalPresentation: Equatable, Sendable {
    let shortLabel: String
    let symbolName: String
    let isCustomIcon: Bool

    init(shortLabel: String, symbolName: String, isCustomIcon: Bool = false) {
        self.shortLabel = shortLabel
        self.symbolName = symbolName
        self.isCustomIcon = isCustomIcon
    }
}

struct TextServiceCLIConfiguration: Equatable, Sendable {
    let profile: TextServiceCLIProfile
    let trustMode: CLITrustMode
    let command: String
    let arguments: String
    let passAgentFlag: Bool
}

struct CLIToolDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let textServiceProfile: TextServiceCLIProfile?
    let terminalPresetID: String?
    let terminalPresentation: CLITerminalPresentation?
    let terminalInvocation: CLIInvocationDefinition?
    let textServiceInvocation: CLIInvocationDefinition?
    let acpCommand: String?
    let acpArguments: [String]?
    let directIntegration: DirectIntegrationType?

    enum DirectIntegrationType: String, Equatable, Sendable {
        case claudeCode
        case codex
    }

    var supportsACP: Bool { acpCommand != nil }
    var supportsDirectIntegration: Bool { directIntegration != nil }
    var supportsAgentSession: Bool { supportsACP || supportsDirectIntegration }
}

enum CLICommandLineParser {
    static func splitArguments(_ rawValue: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var activeQuote: Character?
        var escapeNext = false

        for character in rawValue {
            if escapeNext {
                current.append(character)
                escapeNext = false
                continue
            }

            if character == "\\" {
                if activeQuote == "'" {
                    current.append(character)
                } else {
                    escapeNext = true
                }
                continue
            }

            if let quoteCharacter = activeQuote {
                if character == quoteCharacter {
                    activeQuote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                activeQuote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(character)
        }

        if escapeNext {
            current.append("\\")
        }
        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}

enum CLIToolCatalog {
    static let definitions: [CLIToolDefinition] = [
        CLIToolDefinition(
            id: "kiro",
            title: "Kiro CLI",
            textServiceProfile: .kiro,
            terminalPresetID: "kiro",
            terminalPresentation: CLITerminalPresentation(shortLabel: "Kiro", symbolName: "kiro-icon", isCustomIcon: true),
            terminalInvocation: CLIInvocationDefinition(
                executable: "kiro-cli",
                standardArguments: "",
                fullTrustArguments: "chat --trust-all-tools"
            ),
            textServiceInvocation: CLIInvocationDefinition(
                executable: "kiro-cli",
                standardArguments: "chat --no-interactive --wrap never",
                fullTrustArguments: "chat --no-interactive --trust-all-tools --wrap never",
                defaultPassAgentFlag: true,
                printModeArguments: "chat --no-interactive --wrap never",
                printModeInputMode: .positionalArg
            ),
            acpCommand: "kiro-cli",
            acpArguments: ["acp"],
            directIntegration: nil
        ),
        CLIToolDefinition(
            id: "claudeCode",
            title: "Claude Code",
            textServiceProfile: .claudeCode,
            terminalPresetID: "claude",
            terminalPresentation: CLITerminalPresentation(shortLabel: "Claude", symbolName: "claude-icon", isCustomIcon: true),
            terminalInvocation: CLIInvocationDefinition(
                executable: "claude",
                standardArguments: "",
                fullTrustArguments: "--dangerously-skip-permissions"
            ),
            textServiceInvocation: CLIInvocationDefinition(
                executable: "claude",
                standardArguments: "",
                fullTrustArguments: "--dangerously-skip-permissions",
                printModeArguments: "-p --output-format json",
                printModeInputMode: .stdin
            ),
            acpCommand: nil,
            acpArguments: nil,
            directIntegration: .claudeCode
        ),
        CLIToolDefinition(
            id: "codex",
            title: "Codex",
            textServiceProfile: .codex,
            terminalPresetID: "codex",
            terminalPresentation: CLITerminalPresentation(shortLabel: "Codex", symbolName: "codex-icon", isCustomIcon: true),
            terminalInvocation: CLIInvocationDefinition(
                executable: "codex",
                standardArguments: "",
                fullTrustArguments: "--dangerously-bypass-approvals-and-sandbox"
            ),
            textServiceInvocation: CLIInvocationDefinition(
                executable: "codex",
                standardArguments: "",
                fullTrustArguments: "--dangerously-bypass-approvals-and-sandbox",
                printModeArguments: "exec --ephemeral --skip-git-repo-check -s read-only",
                printModeInputMode: .stdin
            ),
            acpCommand: nil,
            acpArguments: nil,
            directIntegration: .codex
        ),
        CLIToolDefinition(
            id: "gemini",
            title: "Gemini CLI",
            textServiceProfile: .gemini,
            terminalPresetID: "gemini",
            terminalPresentation: CLITerminalPresentation(shortLabel: "Gemini", symbolName: "gemini-icon", isCustomIcon: true),
            terminalInvocation: CLIInvocationDefinition(
                executable: "gemini",
                standardArguments: "",
                fullTrustArguments: "--approval-mode yolo"
            ),
            textServiceInvocation: CLIInvocationDefinition(
                executable: "gemini",
                standardArguments: "",
                fullTrustArguments: "--approval-mode yolo",
                printModeArguments: "",
                printModeInputMode: .positionalArg
            ),
            acpCommand: "gemini",
            acpArguments: ["--acp"],
            directIntegration: nil
        ),
        CLIToolDefinition(
            id: "opencode",
            title: "OpenCode",
            textServiceProfile: .opencode,
            terminalPresetID: "opencode",
            terminalPresentation: CLITerminalPresentation(shortLabel: "OpenCode", symbolName: "opencode-icon", isCustomIcon: true),
            terminalInvocation: CLIInvocationDefinition(executable: "opencode"),
            textServiceInvocation: CLIInvocationDefinition(executable: "opencode"),
            acpCommand: "opencode",
            acpArguments: ["acp"],
            directIntegration: nil
        ),
        CLIToolDefinition(
            id: "copilot",
            title: "GitHub Copilot CLI",
            textServiceProfile: nil,
            terminalPresetID: "copilot",
            terminalPresentation: CLITerminalPresentation(shortLabel: "Copilot", symbolName: "copilot-icon", isCustomIcon: true),
            terminalInvocation: CLIInvocationDefinition(
                executable: "copilot",
                standardArguments: "",
                fullTrustArguments: "--allow-all"
            ),
            textServiceInvocation: nil,
            acpCommand: "copilot",
            acpArguments: ["--acp"],
            directIntegration: nil
        ),
        CLIToolDefinition(
            id: "custom",
            title: "Custom",
            textServiceProfile: .custom,
            terminalPresetID: nil,
            terminalPresentation: nil,
            terminalInvocation: nil,
            textServiceInvocation: nil,
            acpCommand: nil,
            acpArguments: nil,
            directIntegration: nil
        )
    ]

    private static let definitionsByID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })

    private static let textServiceDefinitionsByProfile = Dictionary(
        uniqueKeysWithValues: definitions.compactMap { definition in
            definition.textServiceProfile.map { ($0, definition) }
        }
    )

    private static let terminalDefinitionsByPresetID = Dictionary(
        uniqueKeysWithValues: definitions.compactMap { definition in
            definition.terminalPresetID.map { ($0, definition) }
        }
    )

    static let textServiceDisplayProfiles: [TextServiceCLIProfile] = definitions.compactMap(\.textServiceProfile)

    static func definition(for profile: TextServiceCLIProfile) -> CLIToolDefinition? {
        textServiceDefinitionsByProfile[profile]
    }
    static let acpDefinitions: [CLIToolDefinition] = definitions.filter(\.supportsACP)
    static let agentDefinitions: [CLIToolDefinition] = definitions.filter(\.supportsAgentSession)

    static let terminalPresetDefinitions: [TerminalPresetDefinition] = definitions.compactMap { definition in
        guard let terminalPresetID = definition.terminalPresetID,
              let terminalPresentation = definition.terminalPresentation,
              let terminalInvocation = definition.terminalInvocation else {
            return nil
        }

        return TerminalPresetDefinition(
            id: terminalPresetID,
            title: definition.title,
            shortLabel: terminalPresentation.shortLabel,
            symbolName: terminalPresentation.symbolName,
            isCustomIcon: terminalPresentation.isCustomIcon,
            defaultCommand: terminalInvocation.resolvedCommand(for: .standard).commandString,
            fullTrustCommand: terminalInvocation.supportsFullTrust
                ? terminalInvocation.resolvedCommand(for: .fullTrust).commandString
                : nil
        )
    }

    static func definition(id: String) -> CLIToolDefinition {
        guard let definition = definitionsByID[id] else {
            preconditionFailure("Missing CLI tool definition for \(id)")
        }
        return definition
    }

    static func textServiceDefinition(for profile: TextServiceCLIProfile) -> CLIToolDefinition {
        guard let definition = textServiceDefinitionsByProfile[profile] else {
            preconditionFailure("Missing CLI tool definition for profile \(profile.rawValue)")
        }
        return definition
    }

    static func terminalDefinition(for presetID: String) -> CLIToolDefinition? {
        terminalDefinitionsByPresetID[presetID]
    }

    static func terminalPreset(id: String?) -> TerminalPresetDefinition? {
        guard let id else { return nil }
        return terminalPresetDefinitions.first(where: { $0.id == id })
    }

    static func supportsFullTrust(profile: TextServiceCLIProfile) -> Bool {
        textServiceInvocation(for: profile)?.supportsFullTrust == true
    }

    static func supportedTrustModes(for profile: TextServiceCLIProfile) -> [CLITrustMode] {
        supportsFullTrust(profile: profile) ? CLITrustMode.allCases : [.standard]
    }

    static func textServiceDefaults(
        for profile: TextServiceCLIProfile,
        trustMode: CLITrustMode
    ) -> TextServiceCLIConfiguration? {
        guard let invocation = textServiceInvocation(for: profile) else {
            return nil
        }
        let resolvedCommand = invocation.resolvedCommand(for: trustMode)
        return TextServiceCLIConfiguration(
            profile: profile,
            trustMode: supportedTrustModes(for: profile).contains(trustMode) ? trustMode : .standard,
            command: resolvedCommand.executable,
            arguments: resolvedCommand.arguments,
            passAgentFlag: invocation.defaultPassAgentFlag
        )
    }

    static func terminalCommand(
        for profile: TextServiceCLIProfile,
        trustMode: CLITrustMode
    ) -> String? {
        guard let invocation = textServiceDefinition(for: profile).terminalInvocation else {
            return nil
        }
        return invocation.resolvedCommand(for: trustMode).commandString
    }

    private static func textServiceInvocation(for profile: TextServiceCLIProfile) -> CLIInvocationDefinition? {
        textServiceDefinition(for: profile).textServiceInvocation
    }
}
