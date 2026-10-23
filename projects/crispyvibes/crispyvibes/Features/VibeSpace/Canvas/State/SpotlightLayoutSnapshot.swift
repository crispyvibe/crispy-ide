import Foundation

/// A value-only identifier for a persistent item that can appear in Spotlight.
enum SpotlightPersistentItemID: Hashable, Sendable, Codable {
    case terminal(projectPath: String, tabID: UUID)
    case standaloneTerminal(surfaceID: UUID, tileID: UUID, tabID: UUID)
    case vibeCast
    case vibeLanes
    case acp(tileID: UUID, storeID: UUID)
    case file(tileID: UUID)
    case browser(tileID: UUID)

    private enum CodingKeys: String, CodingKey {
        case kind, projectPath, tabID, surfaceID, tileID, storeID
    }

    private enum Kind: String, Codable {
        case terminal, standaloneTerminal, vibeCast, vibeLanes, acp, file, browser
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .terminal:
            self = .terminal(
                projectPath: try container.decode(String.self, forKey: .projectPath),
                tabID: try container.decode(UUID.self, forKey: .tabID)
            )
        case .standaloneTerminal:
            self = .standaloneTerminal(
                surfaceID: try container.decode(UUID.self, forKey: .surfaceID),
                tileID: try container.decode(UUID.self, forKey: .tileID),
                tabID: try container.decode(UUID.self, forKey: .tabID)
            )
        case .vibeCast: self = .vibeCast
        case .vibeLanes: self = .vibeLanes
        case .acp:
            self = .acp(
                tileID: try container.decode(UUID.self, forKey: .tileID),
                storeID: try container.decode(UUID.self, forKey: .storeID)
            )
        case .file:
            self = .file(tileID: try container.decode(UUID.self, forKey: .tileID))
        case .browser:
            self = .browser(tileID: try container.decode(UUID.self, forKey: .tileID))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .terminal(projectPath, tabID):
            try container.encode(Kind.terminal, forKey: .kind)
            let persistedProjectPath = projectPath.hasPrefix("ssh://")
                ? projectPath
                : URL(fileURLWithPath: projectPath).standardizedFileURL.path
            try container.encode(persistedProjectPath, forKey: .projectPath)
            try container.encode(tabID, forKey: .tabID)
        case let .standaloneTerminal(surfaceID, tileID, tabID):
            try container.encode(Kind.standaloneTerminal, forKey: .kind)
            try container.encode(surfaceID, forKey: .surfaceID)
            try container.encode(tileID, forKey: .tileID)
            try container.encode(tabID, forKey: .tabID)
        case .vibeCast:
            try container.encode(Kind.vibeCast, forKey: .kind)
        case .vibeLanes:
            try container.encode(Kind.vibeLanes, forKey: .kind)
        case let .acp(tileID, storeID):
            try container.encode(Kind.acp, forKey: .kind)
            try container.encode(tileID, forKey: .tileID)
            try container.encode(storeID, forKey: .storeID)
        case let .file(tileID):
            try container.encode(Kind.file, forKey: .kind)
            try container.encode(tileID, forKey: .tileID)
        case let .browser(tileID):
            try container.encode(Kind.browser, forKey: .kind)
            try container.encode(tileID, forKey: .tileID)
        }
    }

    var safeToken: String {
        switch self {
        case let .terminal(projectPath, tabID):
            return "terminal:\(AppDiagnostics.pathToken(projectPath)):\(tabID.uuidString)"
        case let .standaloneTerminal(surfaceID, tileID, tabID):
            return "standalone:\(surfaceID.uuidString):\(tileID.uuidString):\(tabID.uuidString)"
        case .vibeCast: return "vibeCast"
        case .vibeLanes: return "vibeLanes"
        case let .acp(tileID, storeID): return "acp:\(tileID.uuidString):\(storeID.uuidString)"
        case let .file(tileID): return "file:\(tileID.uuidString)"
        case let .browser(tileID): return "browser:\(tileID.uuidString)"
        }
    }
}

/// Orientation used by a two-member Spotlight combo.
enum SpotlightComboOrientation: String, Codable, Sendable {
    case sideBySide
    case stacked

    mutating func toggle() {
        self = self == .sideBySide ? .stacked : .sideBySide
    }
}

/// One carousel position containing either one item or one two-member combo.
struct SpotlightPositionSnapshot: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var members: [SpotlightPersistentItemID]
    var orientation: SpotlightComboOrientation

    init(
        id: UUID = UUID(),
        members: [SpotlightPersistentItemID],
        orientation: SpotlightComboOrientation = .sideBySide
    ) {
        self.id = id
        self.members = members
        self.orientation = orientation
    }

    var isCombo: Bool { members.count == 2 }
}

/// Host-scoped, migration-safe Spotlight shelf order and combo snapshot.
struct SpotlightLayoutSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var positions: [SpotlightPositionSnapshot]

    private enum CodingKeys: String, CodingKey { case version, positions }

    init(version: Int = currentVersion, positions: [SpotlightPositionSnapshot] = []) {
        self.version = version
        self.positions = positions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        switch decodedVersion {
        case 0, Self.currentVersion:
            version = Self.currentVersion
            positions = try container.decodeIfPresent([SpotlightPositionSnapshot].self, forKey: .positions) ?? []
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported Spotlight layout snapshot version"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(positions, forKey: .positions)
    }

    func normalized(liveIDs: [SpotlightPersistentItemID]) -> SpotlightLayoutSnapshot {
        guard version == Self.currentVersion else {
            let uniqueLive = liveIDs.reduce(into: [SpotlightPersistentItemID]()) { result, id in
                if !result.contains(id) { result.append(id) }
            }
            return SpotlightLayoutSnapshot(
                positions: uniqueLive.map { SpotlightPositionSnapshot(members: [$0]) }
            )
        }
        let uniqueLive = liveIDs.reduce(into: [SpotlightPersistentItemID]()) { result, id in
            if !result.contains(id) { result.append(id) }
        }
        let liveSet = Set(uniqueLive)
        var seenMembers = Set<SpotlightPersistentItemID>()
        var seenPositionIDs = Set<UUID>()
        var result: [SpotlightPositionSnapshot] = []

        for position in positions {
            var retained: [SpotlightPersistentItemID] = []
            for member in position.members where retained.count < 2 {
                guard liveSet.contains(member), !seenMembers.contains(member) else { continue }
                seenMembers.insert(member)
                retained.append(member)
            }
            guard !retained.isEmpty else { continue }
            let positionID = seenPositionIDs.insert(position.id).inserted ? position.id : UUID()
            result.append(SpotlightPositionSnapshot(
                id: positionID,
                members: retained,
                orientation: retained.count == 2 ? position.orientation : .sideBySide
            ))
        }

        for id in uniqueLive where !seenMembers.contains(id) {
            result.append(SpotlightPositionSnapshot(members: [id]))
        }
        return SpotlightLayoutSnapshot(positions: result)
    }

    func position(containing member: SpotlightPersistentItemID) -> SpotlightPositionSnapshot? {
        positions.first { $0.members.contains(member) }
    }

    var flattenedMembers: [SpotlightPersistentItemID] {
        positions.flatMap(\.members)
    }
}

/// The three drop zones within a shelf tab.
enum SpotlightDropZone: String, Codable, Sendable {
    case before
    case club
    case after

    static func resolve(x: CGFloat, width: CGFloat) -> SpotlightDropZone {
        guard width > 0 else { return .club }
        let fraction = max(0, min(x / width, 1))
        if fraction < 0.25 { return .before }
        if fraction > 0.75 { return .after }
        return .club
    }
}

/// Identifies whether a drag moves one member or its entire carousel position.
enum SpotlightDragSubject: Codable, Equatable, Sendable {
    case position(UUID)
    case member(SpotlightPersistentItemID, positionID: UUID)

    private enum CodingKeys: String, CodingKey { case kind, positionID, member }
    private enum Kind: String, Codable { case position, member }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let positionID = try container.decode(UUID.self, forKey: .positionID)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .position: self = .position(positionID)
        case .member:
            self = .member(
                try container.decode(SpotlightPersistentItemID.self, forKey: .member),
                positionID: positionID
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .position(positionID):
            try container.encode(Kind.position, forKey: .kind)
            try container.encode(positionID, forKey: .positionID)
        case let .member(member, positionID):
            try container.encode(Kind.member, forKey: .kind)
            try container.encode(positionID, forKey: .positionID)
            try container.encode(member, forKey: .member)
        }
    }
}

/// Local drag payload guarded by host scope and shelf generation.
struct SpotlightDragPayload: Codable, Equatable, Sendable {
    var hostID: String
    var generation: UInt64
    var subject: SpotlightDragSubject
}

/// Pure reducer for moving, clubbing, and un-clubbing Spotlight positions.
enum SpotlightLayoutReducer {
    static func dropping(
        payload: SpotlightDragPayload,
        on targetPositionID: UUID,
        zone: SpotlightDropZone,
        snapshot: SpotlightLayoutSnapshot,
        hostID: String,
        generation: UInt64
    ) -> SpotlightLayoutSnapshot? {
        guard payload.hostID == hostID, payload.generation == generation else { return nil }
        guard let targetIndex = snapshot.positions.firstIndex(where: { $0.id == targetPositionID }) else { return nil }
        var positions = snapshot.positions

        switch payload.subject {
        case let .position(sourcePositionID):
            guard sourcePositionID != targetPositionID,
                  let sourceIndex = positions.firstIndex(where: { $0.id == sourcePositionID }) else { return nil }
            let moving = positions[sourceIndex]
            if zone == .club {
                guard moving.members.count == 1, positions[targetIndex].members.count == 1,
                      moving.members[0] != positions[targetIndex].members[0] else { return nil }
                positions.remove(at: sourceIndex)
                guard let adjustedTarget = positions.firstIndex(where: { $0.id == targetPositionID }) else { return nil }
                positions[adjustedTarget].members.append(moving.members[0])
                positions[adjustedTarget].orientation = .sideBySide
            } else {
                positions.remove(at: sourceIndex)
                guard let adjustedTarget = positions.firstIndex(where: { $0.id == targetPositionID }) else { return nil }
                positions.insert(moving, at: zone == .before ? adjustedTarget : adjustedTarget + 1)
            }

        case let .member(member, sourcePositionID):
            guard let sourceIndex = positions.firstIndex(where: { $0.id == sourcePositionID }),
                  positions[sourceIndex].members.contains(member) else { return nil }
            if sourcePositionID == targetPositionID { return nil }

            if zone == .club {
                guard positions[targetIndex].members.count == 1,
                      !positions[targetIndex].members.contains(member) else { return nil }
                remove(member: member, from: sourceIndex, positions: &positions)
                guard let adjustedTarget = positions.firstIndex(where: { $0.id == targetPositionID }) else { return nil }
                positions[adjustedTarget].members.append(member)
                positions[adjustedTarget].orientation = .sideBySide
            } else {
                remove(member: member, from: sourceIndex, positions: &positions)
                guard let adjustedTarget = positions.firstIndex(where: { $0.id == targetPositionID }) else { return nil }
                let single = SpotlightPositionSnapshot(members: [member])
                positions.insert(single, at: zone == .before ? adjustedTarget : adjustedTarget + 1)
            }
        }

        let result = SpotlightLayoutSnapshot(positions: positions)
        return result == snapshot ? nil : result
    }

    static func togglingOrientation(
        positionID: UUID,
        snapshot: SpotlightLayoutSnapshot
    ) -> SpotlightLayoutSnapshot? {
        guard let index = snapshot.positions.firstIndex(where: { $0.id == positionID }),
              snapshot.positions[index].isCombo else { return nil }
        var result = snapshot
        result.positions[index].orientation.toggle()
        return result
    }

    private static func remove(
        member: SpotlightPersistentItemID,
        from sourceIndex: Int,
        positions: inout [SpotlightPositionSnapshot]
    ) {
        positions[sourceIndex].members.removeAll { $0 == member }
        if positions[sourceIndex].members.isEmpty {
            positions.remove(at: sourceIndex)
        } else if positions[sourceIndex].members.count == 1 {
            positions[sourceIndex].orientation = .sideBySide
        }
    }
}

/// Reconciliation result used when live members disappear while Spotlight is open.
struct SpotlightReconciliationResult: Equatable {
    var snapshot: SpotlightLayoutSnapshot
    var replacementForCurrent: SpotlightPersistentItemID?
}

enum SpotlightLayoutReconciler {
    static func reconcile(
        snapshot: SpotlightLayoutSnapshot,
        liveIDs: [SpotlightPersistentItemID],
        currentID: SpotlightPersistentItemID?
    ) -> SpotlightReconciliationResult {
        let normalized = snapshot.normalized(liveIDs: liveIDs)
        guard let currentID, !liveIDs.contains(currentID) else {
            return SpotlightReconciliationResult(snapshot: normalized, replacementForCurrent: currentID)
        }
        if let priorIndex = snapshot.positions.firstIndex(where: { $0.members.contains(currentID) }) {
            let paired = snapshot.positions[priorIndex].members.first { liveIDs.contains($0) }
            if let paired {
                return SpotlightReconciliationResult(snapshot: normalized, replacementForCurrent: paired)
            }
            guard !normalized.positions.isEmpty else {
                return SpotlightReconciliationResult(snapshot: normalized, replacementForCurrent: nil)
            }
            for distance in 1...max(snapshot.positions.count, 1) {
                let candidateIndices = [priorIndex - distance, priorIndex + distance]
                for candidateIndex in candidateIndices where snapshot.positions.indices.contains(candidateIndex) {
                    if let survivor = snapshot.positions[candidateIndex].members.first(where: { liveIDs.contains($0) }) {
                        return SpotlightReconciliationResult(
                            snapshot: normalized,
                            replacementForCurrent: survivor
                        )
                    }
                }
            }
            return SpotlightReconciliationResult(snapshot: normalized, replacementForCurrent: nil)
        }
        return SpotlightReconciliationResult(snapshot: normalized, replacementForCurrent: nil)
    }
}
