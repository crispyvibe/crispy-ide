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
/// checked against the outcome. Authored in the Vibe, never hardcoded. By
/// default an independent reviewer agent judges it using any referenced review
/// skills; with `humanReview` the USER takes the reviewer's seat and the task
/// pauses as Needs you for an approve / request-changes verdict.
struct VibeLaneVerificationDefinition: Codable, Hashable, Sendable {
    /// "Done when…" — the checkpoint passes only if the outcome meets this.
    var definition: String
    /// Skill folders / SKILL.md files available only to the reviewer agent.
    var reviewSkills: [String]
    /// true = a person verifies this checkpoint instead of the reviewer agent.
    var humanReview: Bool

    init(
        _ definition: String = "",
        reviewSkills: [String] = [],
        humanReview: Bool = false
    ) {
        self.definition = definition
        self.reviewSkills = reviewSkills
        self.humanReview = humanReview
    }

    var isEmpty: Bool { definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    enum CodingKeys: String, CodingKey {
        case definition, reviewSkills, humanReview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        definition = try container.decode(String.self, forKey: .definition)
        reviewSkills = try container.decodeIfPresent([String].self, forKey: .reviewSkills) ?? []
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

// MARK: - Loop Groups

/// A side-effect-free condition evaluated against verified lane values after the
/// final member of a loop-group visit passes.
indirect enum VibeLaneVariableCondition: Codable, Hashable, Sendable {
    case equals(variable: String, value: String)
    case notEquals(variable: String, value: String)
    case isSet(variable: String)
    case all([VibeLaneVariableCondition])
    case any([VibeLaneVariableCondition])
    case not(VibeLaneVariableCondition)

    var referencedVariables: Set<String> {
        switch self {
        case .equals(let variable, _), .notEquals(let variable, _), .isSet(let variable):
            return [variable]
        case .all(let conditions), .any(let conditions):
            return conditions.reduce(into: Set<String>()) { $0.formUnion($1.referencedVariables) }
        case .not(let condition):
            return condition.referencedVariables
        }
    }

    func evaluate(values: [String: String]) -> Bool {
        switch self {
        case .equals(let variable, let expected):
            return values[variable]?.trimmingCharacters(in: .whitespacesAndNewlines) == expected
        case .notEquals(let variable, let expected):
            guard let value = values[variable]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return value != expected
        case .isSet(let variable):
            return values[variable]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .all(let conditions):
            return !conditions.isEmpty && conditions.allSatisfy { $0.evaluate(values: values) }
        case .any(let conditions):
            return conditions.contains { $0.evaluate(values: values) }
        case .not(let condition):
            return !condition.evaluate(values: values)
        }
    }
}

extension VibeLaneVariableCondition {
    private enum Kind: String, Codable {
        case equals, notEquals, isSet, all, any, not
    }

    private enum CodingKeys: String, CodingKey {
        case kind, variable, value, conditions, condition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .equals:
            self = .equals(
                variable: try container.decode(String.self, forKey: .variable),
                value: try container.decode(String.self, forKey: .value)
            )
        case .notEquals:
            self = .notEquals(
                variable: try container.decode(String.self, forKey: .variable),
                value: try container.decode(String.self, forKey: .value)
            )
        case .isSet:
            self = .isSet(variable: try container.decode(String.self, forKey: .variable))
        case .all:
            self = .all(try container.decode([Self].self, forKey: .conditions))
        case .any:
            self = .any(try container.decode([Self].self, forKey: .conditions))
        case .not:
            self = .not(try container.decode(Self.self, forKey: .condition))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .equals(let variable, let value):
            try container.encode(Kind.equals, forKey: .kind)
            try container.encode(variable, forKey: .variable)
            try container.encode(value, forKey: .value)
        case .notEquals(let variable, let value):
            try container.encode(Kind.notEquals, forKey: .kind)
            try container.encode(variable, forKey: .variable)
            try container.encode(value, forKey: .value)
        case .isSet(let variable):
            try container.encode(Kind.isSet, forKey: .kind)
            try container.encode(variable, forKey: .variable)
        case .all(let conditions):
            try container.encode(Kind.all, forKey: .kind)
            try container.encode(conditions, forKey: .conditions)
        case .any(let conditions):
            try container.encode(Kind.any, forKey: .kind)
            try container.encode(conditions, forKey: .conditions)
        case .not(let condition):
            try container.encode(Kind.not, forKey: .kind)
            try container.encode(condition, forKey: .condition)
        }
    }
}

enum VibeLaneLoopExhaustedBehavior: String, Codable, Hashable, Sendable {
    case stop
    case escalate
    case advance
}

/// A contiguous, bounded set of ordinary checkpoints that repeats as one unit.
struct VibeLaneLoopGroup: Codable, Hashable, Identifiable, Sendable {
    var key: String
    var members: [String]
    var maxIterations: Int
    var exitWhen: VibeLaneVariableCondition
    var onExhausted: VibeLaneLoopExhaustedBehavior

    var id: String { key }

    init(
        key: String,
        members: [String],
        maxIterations: Int = 3,
        exitWhen: VibeLaneVariableCondition,
        onExhausted: VibeLaneLoopExhaustedBehavior = .stop
    ) {
        self.key = key
        self.members = members
        self.maxIterations = maxIterations
        self.exitWhen = exitWhen
        self.onExhausted = onExhausted
    }
}

// MARK: - Checkpoint

/// One stage of a lane. Identified by a stable `key`, never by position, so
/// reordering / inserting never breaks references or running tasks.
struct VibeLaneCheckpoint: Codable, Hashable, Identifiable, Sendable {
    var key: String
    var order: Int
    /// Canonical Vibe pinned by this lane step. nil only for legacy embedded
    /// checkpoints before store migration.
    var vibeID: UUID?
    var vibeVersion: Int?
    /// Human-facing step name. Existing definitions fall back to a title
    /// derived from `key`, which remains the stable execution identity.
    var title: String?
    /// Authored execution settings for this step. Unset agent/model/reasoning
    /// knobs inherit ACP app defaults when an attempt starts. Trust is always
    /// full for Vibe Lane execution.
    var engine: VibeLaneEngineConfiguration
    var work: VibeLaneWorkDefinition
    var verify: VibeLaneVerificationDefinition
    var bounds: VibeLaneBounds
    /// Carry-forward input keys this step needs before it can run.
    var requires: [VibeLaneInputRequirement]?
    /// Carry-forward output keys this step must emit on pass.
    var produces: [VibeLaneOutputDeclaration]?
    /// Set by reference hydration when the pinned `(vibeID, vibeVersion)` could
    /// not be found, so the work/verification content is missing rather than
    /// merely unfinished. Transient: deliberately absent from `CodingKeys` so it
    /// is never persisted — it is recomputed every time a lane is hydrated.
    var unresolvedVibeReference: Bool = false

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
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        return key
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
        vibeID: UUID? = nil,
        vibeVersion: Int? = nil,
        title: String? = nil,
        engine: VibeLaneEngineConfiguration = .default,
        work: VibeLaneWorkDefinition,
        verify: VibeLaneVerificationDefinition,
        bounds: VibeLaneBounds = .default,
        requires: [VibeLaneInputRequirement]? = nil,
        produces: [VibeLaneOutputDeclaration]? = nil
    ) {
        self.key = key
        self.order = order
        self.vibeID = vibeID
        self.vibeVersion = vibeVersion
        self.title = title
        self.engine = engine
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
        vibeID: UUID? = nil,
        vibeVersion: Int? = nil,
        title: String? = nil,
        engine: VibeLaneEngineConfiguration = .default,
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
            vibeID: vibeID,
            vibeVersion: vibeVersion,
            title: title,
            engine: engine,
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
        case key, order, vibeID, vibeVersion, title, engine, work, verify, bounds, requires, produces
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        order = try container.decode(Int.self, forKey: .order)
        vibeID = try container.decodeIfPresent(UUID.self, forKey: .vibeID)
        vibeVersion = try container.decodeIfPresent(Int.self, forKey: .vibeVersion)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        engine = try container.decodeIfPresent(VibeLaneEngineConfiguration.self, forKey: .engine) ?? .default
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
        try container.encodeIfPresent(vibeID, forKey: .vibeID)
        try container.encodeIfPresent(vibeVersion, forKey: .vibeVersion)
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            try container.encode(title, forKey: .title)
        }
        if !engine.isDefault {
            try container.encode(engine, forKey: .engine)
        }
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
    /// Authored, non-overlapping checkpoint groups that may repeat as bounded units.
    var loopGroups: [VibeLaneLoopGroup]
    /// Set when this lane's content was seeded from the shipped starter catalog
    /// (the fingerprint of that shipped content). Cleared on the first user edit.
    /// Pristine starter lanes auto-refresh when the app ships improved content;
    /// user-owned lanes (nil) are never touched.
    var seededFingerprint: String?

    var orderedCheckpoints: [VibeLaneCheckpoint] {
        checkpoints.sorted { $0.order < $1.order }
    }

    /// Human-readable route. Loop-group members are wrapped in brackets with the
    /// authored iteration bound so a repeating span never reads as linear.
    var routeSummary: String {
        var parts: [String] = []
        var index = 0
        let ordered = orderedCheckpoints
        while index < ordered.count {
            let checkpoint = ordered[index]
            guard let group = loopGroup(containing: checkpoint.key),
                  group.members.first == checkpoint.key else {
                parts.append(checkpoint.displayTitle)
                index += 1
                continue
            }
            let titles = group.members.compactMap { self.checkpoint(forKey: $0)?.displayTitle }
            parts.append("[\(titles.joined(separator: " <-> ")) x\(group.maxIterations)]")
            index += group.members.count
        }
        return parts.joined(separator: " -> ")
    }

    func checkpoint(forKey key: String) -> VibeLaneCheckpoint? {
        checkpoints.first { $0.key == key }
    }

    func loopGroup(forKey key: String) -> VibeLaneLoopGroup? {
        loopGroups.first { $0.key == key }
    }

    func loopGroup(containing checkpointKey: String) -> VibeLaneLoopGroup? {
        loopGroups.first { $0.members.contains(checkpointKey) }
    }

    func memberPosition(of checkpointKey: String, in group: VibeLaneLoopGroup) -> Int? {
        group.members.firstIndex(of: checkpointKey)
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
        loopGroups: [VibeLaneLoopGroup] = [],
        seededFingerprint: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.version = version
        self.name = name
        self.detail = detail
        self.steerLimit = steerLimit
        self.checkpoints = checkpoints
        self.loopGroups = loopGroups
        self.seededFingerprint = seededFingerprint
    }
}

extension VibeLaneDefinition {
    enum CodingKeys: String, CodingKey {
        case id, schemaVersion, version, name, steerLimit, checkpoints, loopGroups, seededFingerprint
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
        loopGroups = try container.decodeIfPresent([VibeLaneLoopGroup].self, forKey: .loopGroups) ?? []
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
        if !loopGroups.isEmpty {
            try container.encode(loopGroups, forKey: .loopGroups)
        }
        try container.encodeIfPresent(seededFingerprint, forKey: .seededFingerprint)
    }
}
