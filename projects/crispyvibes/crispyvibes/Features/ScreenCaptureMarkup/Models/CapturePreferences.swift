import Foundation

/// A still-image capture interaction offered by F062.
enum CaptureMode: String, CaseIterable, Codable, Sendable {
    case region
    case window
    case display
}

/// Delay applied after the user commits a target and before acquisition begins.
enum CaptureDelay: Int, CaseIterable, Codable, Sendable {
    case none = 0
    case threeSeconds = 3
    case fiveSeconds = 5
    case tenSeconds = 10

    /// Duration represented by this delay.
    var duration: Duration { .seconds(rawValue) }
}

/// Acquisition options shared by the capture command.
struct CaptureOptions: Codable, Equatable, Sendable {
    var delay: CaptureDelay
    var includesPointer: Bool

    /// First-use options: no delay and no pointer.
    static let `default` = CaptureOptions(delay: .none, includesPointer: false)
}

/// Persistable F062 preferences. Schema v3 stores only mode, delay, and pointer state.
struct ScreenCapturePreferences: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case mode
        case delay
        case includesPointer
        case options
    }

    private enum LegacyOptionsKeys: String, CodingKey {
        case delay
        case includesPointer
    }

    private(set) var schemaVersion: Int
    var mode: CaptureMode
    var options: CaptureOptions

    init(
        mode: CaptureMode,
        options: CaptureOptions,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.options = options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? container.decode(CaptureMode.self, forKey: .mode)) ?? .region

        let legacy = try? container.nestedContainer(
            keyedBy: LegacyOptionsKeys.self,
            forKey: .options
        )
        let delay = (try? container.decode(CaptureDelay.self, forKey: .delay))
            ?? (try? legacy?.decode(CaptureDelay.self, forKey: .delay))
            ?? .none
        let includesPointer = (try? container.decode(Bool.self, forKey: .includesPointer))
            ?? (try? legacy?.decode(Bool.self, forKey: .includesPointer))
            ?? false
        options = CaptureOptions(delay: delay, includesPointer: includesPointer)
        schemaVersion = Self.currentSchemaVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(mode, forKey: .mode)
        try container.encode(options.delay, forKey: .delay)
        try container.encode(options.includesPointer, forKey: .includesPointer)
    }

    /// First-use preferences specified by F062.
    static let `default` = ScreenCapturePreferences(mode: .region, options: .default)
}
