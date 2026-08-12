import Foundation

struct VibeCategory: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let systemImage: String

    static let engineering = VibeCategory(
        id: "engineering",
        name: "Engineering",
        systemImage: "hammer"
    )
    static let incidentResponse = VibeCategory(
        id: "incidentResponse",
        name: "Incident Response",
        systemImage: "bolt.trianglebadge.exclamationmark"
    )
    static let release = VibeCategory(
        id: "release",
        name: "Release",
        systemImage: "shippingbox"
    )
    static let productLaunch = VibeCategory(
        id: "productLaunch",
        name: "Product Launch",
        systemImage: "megaphone"
    )
    static let researchAndDecisions = VibeCategory(
        id: "researchAndDecisions",
        name: "Research & Decisions",
        systemImage: "doc.text.magnifyingglass"
    )
    static let general = VibeCategory(
        id: "general",
        name: "General",
        systemImage: "square.grid.2x2"
    )

    static let allCases: [VibeCategory] = [
        .engineering,
        .incidentResponse,
        .release,
        .productLaunch,
        .researchAndDecisions,
        .general,
    ]

    static func custom(name: String, systemImage: String) -> VibeCategory {
        VibeCategory(
            id: "custom:\(UUID().uuidString.lowercased())",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            systemImage: systemImage
        )
    }

    static func resolved(id: String, name: String?, systemImage: String?) -> VibeCategory {
        if let builtIn = allCases.first(where: { $0.id == id }) {
            return builtIn
        }
        let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = resolvedName?.isEmpty == false ? resolvedName ?? id : id
        let icon = systemImage?.isEmpty == false ? systemImage ?? "tag" : "tag"
        return VibeCategory(
            id: id,
            name: displayName,
            systemImage: icon
        )
    }

    static func available(
        in vibes: [VibeDefinition],
        including category: VibeCategory? = nil
    ) -> [VibeCategory] {
        var categories = Dictionary(uniqueKeysWithValues: allCases.map { ($0.id, $0) })
        for vibe in vibes {
            categories[vibe.category.id] = resolved(
                id: vibe.category.id,
                name: vibe.category.name,
                systemImage: vibe.category.systemImage
            )
        }
        if let category {
            categories[category.id] = category
        }
        return categories.values.sorted(by: sort)
    }

    static func sort(_ lhs: VibeCategory, _ rhs: VibeCategory) -> Bool {
        let lhsIndex = allCases.firstIndex(where: { $0.id == lhs.id })
        let rhsIndex = allCases.firstIndex(where: { $0.id == rhs.id })
        switch (lhsIndex, rhsIndex) {
        case let (.some(lhsIndex), .some(rhsIndex)):
            return lhsIndex < rhsIndex
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func == (lhs: VibeCategory, rhs: VibeCategory) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// A reusable, versioned outcome contract. Vibes are authored independently
/// and referenced by lane steps; they do not own ordering or handoff data.
struct VibeDefinition: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var version: Int
    var name: String
    var detail: String?
    var category: VibeCategory
    var work: VibeLaneWorkDefinition
    var verify: VibeLaneVerificationDefinition
    var bounds: VibeLaneBounds
    var engine: VibeLaneEngineConfiguration

    init(
        id: UUID = UUID(),
        version: Int = 1,
        name: String,
        detail: String? = nil,
        category: VibeCategory = .general,
        work: VibeLaneWorkDefinition,
        verify: VibeLaneVerificationDefinition,
        bounds: VibeLaneBounds = .default,
        engine: VibeLaneEngineConfiguration = .default
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.detail = detail
        self.category = category
        self.work = work
        self.verify = verify
        self.bounds = bounds
        self.engine = engine
    }

    init(
        id: UUID = UUID(),
        version: Int = 1,
        name: String,
        detail: String? = nil,
        category: VibeCategory = .general,
        goal: String,
        instructions: String = "",
        skills: [String] = [],
        verify: VibeLaneVerificationDefinition,
        bounds: VibeLaneBounds = .default,
        engine: VibeLaneEngineConfiguration = .default
    ) {
        self.init(
            id: id,
            version: version,
            name: name,
            detail: detail,
            category: category,
            work: VibeLaneWorkDefinition(
                goal: goal,
                instructions: instructions,
                skills: skills
            ),
            verify: verify,
            bounds: bounds,
            engine: engine
        )
    }

    init(
        id: UUID,
        version: Int = 1,
        category: VibeCategory = .general,
        checkpoint: VibeLaneCheckpoint
    ) {
        self.init(
            id: id,
            version: version,
            name: checkpoint.displayTitle,
            category: category,
            work: checkpoint.work,
            verify: checkpoint.verify,
            bounds: checkpoint.bounds,
            engine: checkpoint.engine
        )
    }

    var isReady: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !work.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !verify.isEmpty
            && bounds.maxAttempts > 0
            && bounds.timeoutSeconds > 0
    }

    func applying(to checkpoint: VibeLaneCheckpoint) -> VibeLaneCheckpoint {
        var resolved = checkpoint
        resolved.vibeID = id
        resolved.vibeVersion = version
        resolved.title = name
        resolved.work = work
        resolved.verify = verify
        resolved.bounds = bounds
        resolved.engine = engine
        return resolved
    }

    func checkpoint(
        key: String,
        order: Int,
        requires: [VibeLaneInputRequirement]? = nil,
        produces: [VibeLaneOutputDeclaration]? = nil
    ) -> VibeLaneCheckpoint {
        VibeLaneCheckpoint(
            key: key,
            order: order,
            vibeID: id,
            vibeVersion: version,
            title: name,
            engine: engine,
            work: work,
            verify: verify,
            bounds: bounds,
            requires: requires,
            produces: produces
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case version
        case name
        case detail
        case category
        case categoryName
        case categoryIcon
        case work
        case verify
        case bounds
        case engine
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        version = try values.decode(Int.self, forKey: .version)
        name = try values.decode(String.self, forKey: .name)
        detail = try values.decodeIfPresent(String.self, forKey: .detail)
        let categoryID = try values.decodeIfPresent(String.self, forKey: .category)
            ?? VibeCategory.general.id
        category = VibeCategory.resolved(
            id: categoryID,
            name: try values.decodeIfPresent(String.self, forKey: .categoryName),
            systemImage: try values.decodeIfPresent(String.self, forKey: .categoryIcon)
        )
        work = try values.decode(VibeLaneWorkDefinition.self, forKey: .work)
        verify = try values.decode(VibeLaneVerificationDefinition.self, forKey: .verify)
        bounds = try values.decode(VibeLaneBounds.self, forKey: .bounds)
        engine = try values.decode(VibeLaneEngineConfiguration.self, forKey: .engine)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(version, forKey: .version)
        try values.encode(name, forKey: .name)
        try values.encodeIfPresent(detail, forKey: .detail)
        try values.encode(category.id, forKey: .category)
        if !VibeCategory.allCases.contains(category) {
            try values.encode(category.name, forKey: .categoryName)
            try values.encode(category.systemImage, forKey: .categoryIcon)
        }
        try values.encode(work, forKey: .work)
        try values.encode(verify, forKey: .verify)
        try values.encode(bounds, forKey: .bounds)
        try values.encode(engine, forKey: .engine)
    }
}
