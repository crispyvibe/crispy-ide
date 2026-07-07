import Foundation

// F059 — Vibe Lanes definition schema (the reusable process template).
// Mirrors specs/features/ai-agents/vibe-lanes/schema-design.md §1.
//
// A checkpoint is a bounded Work -> Verify loop with a carry-forward contract.
//
// A lane is inert data; only the execution engine, given a lane + a task, runs anything.

/// Current contract version of the lane definition schema. Additive changes do
/// not bump this; breaking changes do (and ship a migration).
enum VibeLaneSchema {
    static let version = 1
}

// MARK: - Verification

/// How we know a checkpoint's OUTCOME is done: a single plain-text definition
/// checked against the outcome. Authored in the lane, never hardcoded. By
/// default an independent reviewer agent judges it (running whatever read-only
/// checks it needs); with `humanReview` the USER takes the reviewer's seat and
/// the task pauses as Needs you for an approve / request-changes verdict.
struct VibeLaneVerificationDefinition: Codable, Hashable, Sendable {
    /// "Done when…" — the checkpoint passes only if the outcome meets this.
    var definition: String
    /// true = a person verifies this checkpoint instead of the reviewer agent.
    var humanReview: Bool

    init(_ definition: String = "", humanReview: Bool = false) {
        self.definition = definition
        self.humanReview = humanReview
    }

    var isEmpty: Bool { definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    enum CodingKeys: String, CodingKey {
        case definition, humanReview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        definition = try container.decode(String.self, forKey: .definition)
        humanReview = try container.decodeIfPresent(Bool.self, forKey: .humanReview) ?? false
    }
}

// MARK: - Work + Bounds

/// What the agent does at a checkpoint.
struct VibeLaneWorkDefinition: Codable, Hashable, Sendable {
    var goal: String
    var instructions: String
    var skills: [String]

    init(goal: String, instructions: String = "", skills: [String] = []) {
        self.goal = goal
        self.instructions = instructions
        self.skills = skills
    }
}

enum VibeLaneBoundBehavior: String, Codable, Sendable {
    case stop
    case escalate
}

/// Stop conditions the engine enforces for one checkpoint.
struct VibeLaneBounds: Codable, Hashable, Sendable {
    var maxAttempts: Int
    var timeoutSeconds: Int
    var onExhausted: VibeLaneBoundBehavior

    init(maxAttempts: Int = 10, timeoutSeconds: Int = 1800, onExhausted: VibeLaneBoundBehavior = .stop) {
        self.maxAttempts = maxAttempts
        self.timeoutSeconds = timeoutSeconds
        self.onExhausted = onExhausted
    }

    static let `default` = VibeLaneBounds()

    enum CodingKeys: String, CodingKey {
        case maxAttempts, timeoutSeconds, onExhausted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxAttempts = try container.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? 10
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 1800
        onExhausted = try container.decodeIfPresent(VibeLaneBoundBehavior.self, forKey: .onExhausted) ?? .stop
    }
}

struct VibeLaneInputRequirement: Codable, Hashable, Identifiable, Sendable {
    var key: String
    var askUser: Bool
    var prompt: String?

    var id: String { key }

    init(key: String, askUser: Bool = false, prompt: String? = nil) {
        self.key = key
        self.askUser = askUser
        self.prompt = prompt
    }
}

struct VibeLaneOutputDeclaration: Codable, Hashable, Identifiable, Sendable {
    var key: String
    var detail: String?

    var id: String { key }

    init(key: String, detail: String? = nil) {
        self.key = key
        self.detail = detail
    }
}

extension VibeLaneOutputDeclaration {
    enum CodingKeys: String, CodingKey {
        case key
        case detail = "description"
        case legacyDetail = "detail"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
            ?? container.decodeIfPresent(String.self, forKey: .legacyDetail)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encodeIfPresent(detail, forKey: .detail)
    }
}

// MARK: - Checkpoint

/// One stage of a lane. Identified by a stable `key`, never by position, so
/// reordering / inserting never breaks references or running tasks.
struct VibeLaneCheckpoint: Codable, Hashable, Identifiable, Sendable {
    var key: String
    var order: Int
    var work: VibeLaneWorkDefinition
    var verify: VibeLaneVerificationDefinition
    var bounds: VibeLaneBounds
    /// Carry-forward input keys this step needs before it can run.
    var requires: [VibeLaneInputRequirement]?
    /// Carry-forward output keys this step must emit on pass.
    var produces: [VibeLaneOutputDeclaration]?

    var id: String { key }

    /// Non-optional views of the declared contract.
    var requiredInputs: [String] { inputRequirements.map(\.key) }
    var inputRequirements: [VibeLaneInputRequirement] { requires ?? [] }
    var askUserInputs: [VibeLaneInputRequirement] { inputRequirements.filter(\.askUser) }
    var producedOutputs: [String] { outputDeclarations.map(\.key) }
    var outputDeclarations: [VibeLaneOutputDeclaration] { produces ?? [] }

    // Read-only conveniences for the UI.
    var goal: String { work.goal }
    var skills: [String] { work.skills }
    var instructions: String { work.instructions }

    var displayTitle: String {
        key
            .split(separator: "-")
            .map { Self.displayWord(for: String($0)) }
            .joined(separator: " ")
    }

    private static func displayWord(for rawValue: String) -> String {
        let acronymWords: Set<String> = ["api", "ci", "id", "pr", "ui", "url"]
        if acronymWords.contains(rawValue.lowercased()) {
            return rawValue.uppercased()
        }
        return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    init(
        key: String,
        order: Int,
        work: VibeLaneWorkDefinition,
        verify: VibeLaneVerificationDefinition,
        bounds: VibeLaneBounds = .default,
        requires: [VibeLaneInputRequirement]? = nil,
        produces: [VibeLaneOutputDeclaration]? = nil
    ) {
        self.key = key
        self.order = order
        self.work = work
        self.verify = verify
        self.bounds = bounds
        self.requires = requires
        self.produces = produces
    }

    /// Convenience initializer used by the catalog and tests.
    init(
        key: String,
        order: Int,
        goal: String,
        instructions: String = "",
        skills: [String] = [],
        verify: VibeLaneVerificationDefinition,
        bounds: VibeLaneBounds = .default,
        requires: [String]? = nil,
        produces: [String]? = nil
    ) {
        self.init(
            key: key,
            order: order,
            work: VibeLaneWorkDefinition(goal: goal, instructions: instructions, skills: skills),
            verify: verify,
            bounds: bounds,
            requires: requires?.map { VibeLaneInputRequirement(key: $0) },
            produces: produces?.map { VibeLaneOutputDeclaration(key: $0) }
        )
    }
}

extension VibeLaneCheckpoint {
    enum CodingKeys: String, CodingKey {
        case key, order, work, verify, bounds, requires, produces
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        order = try container.decode(Int.self, forKey: .order)
        work = try container.decode(VibeLaneWorkDefinition.self, forKey: .work)
        verify = try container.decode(VibeLaneVerificationDefinition.self, forKey: .verify)
        bounds = try container.decodeIfPresent(VibeLaneBounds.self, forKey: .bounds) ?? .default
        if let structured = try? container.decodeIfPresent([VibeLaneInputRequirement].self, forKey: .requires) {
            requires = structured
        } else {
            let legacy = try container.decodeIfPresent([String].self, forKey: .requires)
            requires = legacy?.map { VibeLaneInputRequirement(key: $0) }
        }
        if let structured = try? container.decodeIfPresent([VibeLaneOutputDeclaration].self, forKey: .produces) {
            produces = structured
        } else {
            let legacy = try container.decodeIfPresent([String].self, forKey: .produces)
            produces = legacy?.map { VibeLaneOutputDeclaration(key: $0) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(order, forKey: .order)
        try container.encode(work, forKey: .work)
        try container.encode(verify, forKey: .verify)
        try container.encode(bounds, forKey: .bounds)
        try container.encodeIfPresent(requires, forKey: .requires)
        try container.encodeIfPresent(produces, forKey: .produces)
    }
}

// MARK: - Lane

/// A reusable process template: an ordered pipeline of checkpoints. Authored,
/// versioned, and reused across tasks.
struct VibeLaneDefinition: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var schemaVersion: Int
    /// Content revision; increments on every save. A task pins the version it ran against.
    var version: Int
    var name: String
    var detail: String?
    var steerLimit: Int
    var checkpoints: [VibeLaneCheckpoint]
    /// Set when this lane's content was seeded from the shipped starter catalog
    /// (the fingerprint of that shipped content). Cleared on the first user edit.
    /// Pristine starter lanes auto-refresh when the app ships improved content;
    /// user-owned lanes (nil) are never touched.
    var seededFingerprint: String?

    var orderedCheckpoints: [VibeLaneCheckpoint] {
        checkpoints.sorted { $0.order < $1.order }
    }

    var routeSummary: String {
        orderedCheckpoints.map(\.displayTitle).joined(separator: " -> ")
    }

    func checkpoint(forKey key: String) -> VibeLaneCheckpoint? {
        checkpoints.first { $0.key == key }
    }

    /// The next checkpoint after the one with `key`, in order, or nil at the end.
    func checkpoint(after key: String) -> VibeLaneCheckpoint? {
        let ordered = orderedCheckpoints
        guard let idx = ordered.firstIndex(where: { $0.key == key }), idx + 1 < ordered.count else {
            return nil
        }
        return ordered[idx + 1]
    }

    var firstCheckpoint: VibeLaneCheckpoint? { orderedCheckpoints.first }

    init(
        id: UUID = UUID(),
        schemaVersion: Int = VibeLaneSchema.version,
        version: Int = 1,
        name: String,
        detail: String? = nil,
        steerLimit: Int = 1,
        checkpoints: [VibeLaneCheckpoint],
        seededFingerprint: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.version = version
        self.name = name
        self.detail = detail
        self.steerLimit = steerLimit
        self.checkpoints = checkpoints
        self.seededFingerprint = seededFingerprint
    }
}

extension VibeLaneDefinition {
    enum CodingKeys: String, CodingKey {
        case id, schemaVersion, version, name, steerLimit, checkpoints, seededFingerprint
        case detail = "description"
        case legacyDetail = "detail"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? VibeLaneSchema.version
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        name = try container.decode(String.self, forKey: .name)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
            ?? container.decodeIfPresent(String.self, forKey: .legacyDetail)
        steerLimit = try container.decodeIfPresent(Int.self, forKey: .steerLimit) ?? 1
        checkpoints = try container.decode([VibeLaneCheckpoint].self, forKey: .checkpoints)
        seededFingerprint = try container.decodeIfPresent(String.self, forKey: .seededFingerprint)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(version, forKey: .version)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encode(steerLimit, forKey: .steerLimit)
        try container.encode(checkpoints, forKey: .checkpoints)
        try container.encodeIfPresent(seededFingerprint, forKey: .seededFingerprint)
    }
}
