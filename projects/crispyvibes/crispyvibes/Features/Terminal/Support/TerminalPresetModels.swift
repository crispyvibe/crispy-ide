import Foundation

typealias TerminalPresetLaunchMode = CLITrustMode

struct TerminalPresetDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let shortLabel: String
    let symbolName: String
    let isCustomIcon: Bool
    let defaultCommand: String
    let fullTrustCommand: String?
    let supportsFullTrust: Bool

    init(
        id: String,
        title: String,
        shortLabel: String,
        symbolName: String,
        isCustomIcon: Bool = false,
        defaultCommand: String,
        fullTrustCommand: String? = nil
    ) {
        self.id = id
        self.title = title
        self.shortLabel = shortLabel
        self.symbolName = symbolName
        self.isCustomIcon = isCustomIcon
        self.defaultCommand = defaultCommand
        self.fullTrustCommand = fullTrustCommand
        self.supportsFullTrust = fullTrustCommand != nil
    }

    func command(for mode: TerminalPresetLaunchMode) -> String {
        if mode == .fullTrust, let fullTrustCommand {
            return fullTrustCommand
        }
        return defaultCommand
    }
}

enum TerminalShortcutLaunchBehavior: String, Codable, CaseIterable, Identifiable {
    case currentTerminal
    case newPermanentTerminal
    case newTemporaryTerminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentTerminal:
            return AppStrings.TerminalShortcuts.currentTerminal
        case .newPermanentTerminal:
            return AppStrings.TerminalShortcuts.newTerminal
        case .newTemporaryTerminal:
            return AppStrings.TerminalShortcuts.temporaryTerminal
        }
    }
}

struct TerminalShortcutDefinition: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var command: String
    var launchBehavior: TerminalShortcutLaunchBehavior

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case command
        case launchBehavior
    }

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        launchBehavior: TerminalShortcutLaunchBehavior = .currentTerminal
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.launchBehavior = launchBehavior
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        launchBehavior = try container.decodeIfPresent(
            TerminalShortcutLaunchBehavior.self,
            forKey: .launchBehavior
        ) ?? .currentTerminal
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(command, forKey: .command)
        try container.encode(launchBehavior, forKey: .launchBehavior)
    }
}
