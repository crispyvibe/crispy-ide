import Foundation

enum VibeLaneSkillSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case bundled
    case personal
    case linked

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .bundled: "shippingbox"
        case .personal: "person.crop.square"
        case .linked: "link"
        }
    }
}

enum VibeLaneSkillRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case work
    case review

    var id: String { rawValue }
}

enum VibeLaneSkillInteraction: String, Codable, CaseIterable, Identifiable, Sendable {
    case unattended
    case interactive

    var id: String { rawValue }
}

enum VibeLaneSkillResourceKind: String, Codable, CaseIterable, Sendable {
    case reference
    case script
    case asset
    case agentMetadata
    case other
}

struct VibeLaneSkillResource: Identifiable, Hashable, Sendable {
    let relativePath: String
    let kind: VibeLaneSkillResourceKind
    let fileURL: URL
    let byteCount: Int

    var id: String { relativePath }
}

enum VibeLaneSkillIssue: Hashable, Sendable {
    case emptyInstructions
    case missingCommand(String)
    case missingReference(String)
    case resourceScanLimit(Int)
}

enum VibeLaneSkillValidationState: String, CaseIterable, Sendable {
    case ready
    case attention
    case unavailable
}

struct VibeLaneSkillMetadata: Codable, Hashable, Sendable {
    var category: String
    var roles: [VibeLaneSkillRole]
    var interaction: VibeLaneSkillInteraction
    var requiredCommands: [String]

    init(
        category: String = "General",
        roles: [VibeLaneSkillRole] = VibeLaneSkillRole.allCases,
        interaction: VibeLaneSkillInteraction = .unattended,
        requiredCommands: [String] = []
    ) {
        self.category = category
        self.roles = roles
        self.interaction = interaction
        self.requiredCommands = requiredCommands
    }

    static let `default` = VibeLaneSkillMetadata()
}

struct VibeLaneSkillDraft: Hashable, Sendable {
    var name: String
    var detail: String
    var body: String
    var metadata: VibeLaneSkillMetadata
}

struct VibeLaneSkillDefinition: Identifiable, Hashable, Sendable {
    let reference: String
    let name: String
    let detail: String
    let body: String
    let source: VibeLaneSkillSource
    let rootURL: URL
    let fileURL: URL
    let metadata: VibeLaneSkillMetadata
    let resources: [VibeLaneSkillResource]
    let issues: [VibeLaneSkillIssue]

    var id: String { reference }
    var isEditable: Bool { source == .personal }
    var category: String { metadata.category }
    var roles: [VibeLaneSkillRole] { metadata.roles }
    var interaction: VibeLaneSkillInteraction { metadata.interaction }
    var requiredCommands: [String] { metadata.requiredCommands }

    var validationState: VibeLaneSkillValidationState {
        if issues.contains(where: {
            if case .missingCommand = $0 { return true }
            if case .missingReference = $0 { return true }
            return false
        }) {
            return .unavailable
        }
        return issues.isEmpty ? .ready : .attention
    }

    func supports(_ role: VibeLaneSkillRole) -> Bool {
        roles.contains(role)
    }

    /// The single definition of assignment eligibility (F059-R05): the skill must
    /// declare the role, be available, and — for Review — never pause for the
    /// user, because verification runs unattended.
    ///
    /// Lives on the model so every assignment path enforces it, not just the
    /// place where the installed-skill menu is drawn.
    func isAssignable(to role: VibeLaneSkillRole) -> Bool {
        supports(role)
            && validationState != .unavailable
            && !(role == .review && interaction == .interactive)
    }

    /// Why `isAssignable(to:)` refused, for user-facing feedback. nil when the
    /// skill is assignable.
    func assignmentRefusal(for role: VibeLaneSkillRole) -> VibeLaneSkillAssignmentRefusal? {
        if !supports(role) { return .roleNotSupported }
        if validationState == .unavailable { return .unavailable }
        if role == .review, interaction == .interactive { return .interactiveReview }
        return nil
    }
}

/// Why a skill cannot be assigned to a role. UI wording belongs in `AppStrings`.
enum VibeLaneSkillAssignmentRefusal: Equatable, Sendable {
    case roleNotSupported
    case unavailable
    case interactiveReview
}
