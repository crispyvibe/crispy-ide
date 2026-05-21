import Foundation

struct VibeSpaceTerminalStartupProfile: Codable, Equatable {
    var presetID: String?
    var command: String

    static let empty = VibeSpaceTerminalStartupProfile(
        presetID: nil,
        command: ""
    )

    var hasInstruction: Bool {
        presetID != nil || !command.isEmpty
    }

    func normalized() -> VibeSpaceTerminalStartupProfile {
        let trimmedPreset = presetID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedPreset = (trimmedPreset?.isEmpty == false) ? trimmedPreset : nil
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPreset = normalizedCommand.isEmpty ? normalizedPreset : nil

        return VibeSpaceTerminalStartupProfile(
            presetID: resolvedPreset,
            command: normalizedCommand
        )
    }
}

struct VibeSpaceStartupSettings: Codable, Equatable {
    var startupTerminalCount: Int
    var startupProfiles: [VibeSpaceTerminalStartupProfile]
    var focusTerminalOnProjectSwitch: Bool

    static let minimumTerminalCount = 1
    static let maximumTerminalCount = 8
    static let noPresetSelectionToken = "none"

    init(
        startupTerminalCount: Int,
        startupProfiles: [VibeSpaceTerminalStartupProfile],
        focusTerminalOnProjectSwitch: Bool
    ) {
        self.startupTerminalCount = startupTerminalCount
        self.startupProfiles = startupProfiles
        self.focusTerminalOnProjectSwitch = focusTerminalOnProjectSwitch
    }

    static let `default` = VibeSpaceStartupSettings(
        startupTerminalCount: AppFirstRunExperience.VibeSpace.defaultStartupTerminalCount,
        startupProfiles: AppFirstRunExperience.VibeSpace.defaultStartupProfiles,
        focusTerminalOnProjectSwitch: AppFirstRunExperience.VibeSpace.defaultFocusTerminalOnProjectSwitch
    )

    func normalized() -> VibeSpaceStartupSettings {
        let clampedCount = Swift.max(
            Self.minimumTerminalCount,
            Swift.min(startupTerminalCount, Self.maximumTerminalCount)
        )
        var normalizedProfiles = startupProfiles
            .map { $0.normalized() }
            .prefix(Self.maximumTerminalCount)
            .map { $0 }
        while normalizedProfiles.count < clampedCount {
            normalizedProfiles.append(.empty)
        }

        return VibeSpaceStartupSettings(
            startupTerminalCount: clampedCount,
            startupProfiles: normalizedProfiles,
            focusTerminalOnProjectSwitch: focusTerminalOnProjectSwitch
        )
    }

    func profile(at terminalIndex: Int) -> VibeSpaceTerminalStartupProfile {
        let normalized = normalized()
        guard terminalIndex >= 0 else { return .empty }
        guard terminalIndex < normalized.startupProfiles.count else { return .empty }
        return normalized.startupProfiles[terminalIndex]
    }

    var activeProfiles: [VibeSpaceTerminalStartupProfile] {
        let normalized = normalized()
        guard !normalized.startupProfiles.isEmpty else { return [] }
        return Array(normalized.startupProfiles.prefix(normalized.startupTerminalCount))
    }

    mutating func setProfile(_ profile: VibeSpaceTerminalStartupProfile, at terminalIndex: Int) {
        guard terminalIndex >= 0, terminalIndex < Self.maximumTerminalCount else { return }
        while startupProfiles.count <= terminalIndex {
            startupProfiles.append(.empty)
        }
        startupProfiles[terminalIndex] = profile.normalized()
    }

    private enum CodingKeys: String, CodingKey {
        case startupTerminalCount
        case startupProfiles
        case focusTerminalOnProjectSwitch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let count = try container.decodeIfPresent(Int.self, forKey: .startupTerminalCount) ?? Self.default.startupTerminalCount
        let focusOnSwitch = try container.decodeIfPresent(Bool.self, forKey: .focusTerminalOnProjectSwitch) ?? Self.default.focusTerminalOnProjectSwitch

        let decodedProfiles = try container.decodeIfPresent(
            [VibeSpaceTerminalStartupProfile].self,
            forKey: .startupProfiles
        ) ?? [.empty]

        self = VibeSpaceStartupSettings(
            startupTerminalCount: count,
            startupProfiles: decodedProfiles,
            focusTerminalOnProjectSwitch: focusOnSwitch
        ).normalized()
    }

    func encode(to encoder: Encoder) throws {
        let normalized = normalized()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(normalized.startupTerminalCount, forKey: .startupTerminalCount)
        try container.encode(normalized.startupProfiles, forKey: .startupProfiles)
        try container.encode(normalized.focusTerminalOnProjectSwitch, forKey: .focusTerminalOnProjectSwitch)
    }
}

struct VibeSpaceProjectStartupOverride: Codable, Equatable {
    var startupTerminalCount: Int
    var startupProfiles: [VibeSpaceTerminalStartupProfile]

    static let minimumTerminalCount = VibeSpaceStartupSettings.minimumTerminalCount
    static let maximumTerminalCount = VibeSpaceStartupSettings.maximumTerminalCount
    static let empty = VibeSpaceProjectStartupOverride(
        startupTerminalCount: 1,
        startupProfiles: [.empty]
    )

    init(
        startupTerminalCount: Int,
        startupProfiles: [VibeSpaceTerminalStartupProfile]
    ) {
        self.startupTerminalCount = startupTerminalCount
        self.startupProfiles = startupProfiles
    }

    init(
        startupPresetID: String?,
        startupCommand: String
    ) {
        self.init(
            startupTerminalCount: 1,
            startupProfiles: [
                VibeSpaceTerminalStartupProfile(
                    presetID: startupPresetID,
                    command: startupCommand
                )
            ]
        )
    }

    var startupPresetID: String? {
        normalized().profile(at: 0).presetID
    }

    var startupCommand: String {
        normalized().profile(at: 0).command
    }

    var hasAnyInstruction: Bool {
        activeProfiles.contains(where: \.hasInstruction)
    }

    func normalized() -> VibeSpaceProjectStartupOverride {
        let clampedCount = Swift.max(
            Self.minimumTerminalCount,
            Swift.min(startupTerminalCount, Self.maximumTerminalCount)
        )
        var normalizedProfiles = startupProfiles
            .map { $0.normalized() }
            .prefix(Self.maximumTerminalCount)
            .map { $0 }
        while normalizedProfiles.count < clampedCount {
            normalizedProfiles.append(.empty)
        }

        return VibeSpaceProjectStartupOverride(
            startupTerminalCount: clampedCount,
            startupProfiles: normalizedProfiles
        )
    }

    func profile(at terminalIndex: Int) -> VibeSpaceTerminalStartupProfile {
        let normalized = normalized()
        guard terminalIndex >= 0 else { return .empty }
        guard terminalIndex < normalized.startupProfiles.count else { return .empty }
        return normalized.startupProfiles[terminalIndex]
    }

    var activeProfiles: [VibeSpaceTerminalStartupProfile] {
        let normalized = normalized()
        guard !normalized.startupProfiles.isEmpty else { return [] }
        return Array(normalized.startupProfiles.prefix(normalized.startupTerminalCount))
    }

    mutating func setProfile(_ profile: VibeSpaceTerminalStartupProfile, at terminalIndex: Int) {
        guard terminalIndex >= 0, terminalIndex < Self.maximumTerminalCount else { return }
        while startupProfiles.count <= terminalIndex {
            startupProfiles.append(.empty)
        }
        startupProfiles[terminalIndex] = profile.normalized()
    }

    private enum CodingKeys: String, CodingKey {
        case startupTerminalCount
        case startupProfiles
        case startupPresetID
        case startupCommand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.startupProfiles) || container.contains(.startupTerminalCount) {
            let count = try container.decodeIfPresent(Int.self, forKey: .startupTerminalCount) ?? Self.empty.startupTerminalCount
            let profiles = try container.decodeIfPresent(
                [VibeSpaceTerminalStartupProfile].self,
                forKey: .startupProfiles
            ) ?? [.empty]
            self = VibeSpaceProjectStartupOverride(
                startupTerminalCount: count,
                startupProfiles: profiles
            ).normalized()
            return
        }

        let presetID = try container.decodeIfPresent(String.self, forKey: .startupPresetID)
        let command = try container.decodeIfPresent(String.self, forKey: .startupCommand) ?? ""
        self = VibeSpaceProjectStartupOverride(
            startupPresetID: presetID,
            startupCommand: command
        ).normalized()
    }

    func encode(to encoder: Encoder) throws {
        let normalized = normalized()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(normalized.startupTerminalCount, forKey: .startupTerminalCount)
        try container.encode(normalized.startupProfiles, forKey: .startupProfiles)
    }
}
