import CryptoKit
import Foundation

struct VibeRevisionKey: Hashable, Sendable {
    let vibeID: UUID
    let version: Int
}

/// Converts legacy embedded checkpoints into central Vibes and hydrates pinned
/// references into the runtime checkpoint shape consumed by the engine.
enum VibeLaneReferenceResolver {
    struct State {
        var lanes: [VibeLaneDefinition]
        var vibes: [VibeDefinition]
        var revisions: [VibeDefinition]
        var changed: Bool
    }

    static func resolve(
        lanes: [VibeLaneDefinition],
        vibes: [VibeDefinition],
        revisions: [VibeDefinition] = []
    ) -> State {
        var currentByID = Dictionary(uniqueKeysWithValues: vibes.map { ($0.id, $0) })
        var revisionByKey = Dictionary(
            uniqueKeysWithValues: revisions.map {
                (VibeRevisionKey(vibeID: $0.id, version: $0.version), $0)
            }
        )
        var changed = false

        let resolvedLanes = lanes.map { lane -> VibeLaneDefinition in
            var resolvedLane = lane
            let category = VibeLaneCatalog.vibeCategory(forLaneID: lane.id)
            resolvedLane.checkpoints = lane.checkpoints.enumerated().map { index, checkpoint in
                var resolved = checkpoint
                if let vibeID = checkpoint.vibeID,
                   let vibeVersion = checkpoint.vibeVersion {
                    let key = VibeRevisionKey(vibeID: vibeID, version: vibeVersion)
                    if let vibe = exactVibe(
                        id: vibeID,
                        version: vibeVersion,
                        currentByID: currentByID,
                        revisionByKey: revisionByKey
                    ) {
                        return vibe.applying(to: checkpoint)
                    }

                    guard checkpoint.hasCompleteExpectationDefinition else {
                        // No stored Vibe and nothing to recover from: the pinned
                        // revision is gone. Mark it so `isRunnable` refuses the
                        // lane rather than treating it as an unfinished draft.
                        resolved.unresolvedVibeReference = true
                        return resolved
                    }
                    let recovered = VibeDefinition(
                        id: vibeID,
                        version: vibeVersion,
                        category: category,
                        checkpoint: checkpoint
                    )
                    if currentByID[vibeID] == nil {
                        currentByID[vibeID] = recovered
                    } else {
                        revisionByKey[key] = recovered
                    }
                    changed = true
                    return recovered.applying(to: checkpoint)
                }

                let vibeID = migratedID(lane: lane, checkpoint: checkpoint, index: index)
                let vibe = currentByID[vibeID] ?? VibeDefinition(
                    id: vibeID,
                    category: category,
                    checkpoint: checkpoint
                )
                currentByID[vibeID] = vibe
                resolved = vibe.applying(to: checkpoint)
                changed = true
                return resolved
            }
            return resolvedLane
        }

        return State(
            lanes: resolvedLanes,
            vibes: Array(currentByID.values),
            revisions: Array(revisionByKey.values),
            changed: changed
        )
    }

    static func exactVibe(
        id: UUID,
        version: Int,
        current: [VibeDefinition],
        revisions: [VibeDefinition]
    ) -> VibeDefinition? {
        exactVibe(
            id: id,
            version: version,
            currentByID: Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) }),
            revisionByKey: Dictionary(
                uniqueKeysWithValues: revisions.map {
                    (VibeRevisionKey(vibeID: $0.id, version: $0.version), $0)
                }
            )
        )
    }

    private static func exactVibe(
        id: UUID,
        version: Int,
        currentByID: [UUID: VibeDefinition],
        revisionByKey: [VibeRevisionKey: VibeDefinition]
    ) -> VibeDefinition? {
        if let current = currentByID[id], current.version == version {
            return current
        }
        return revisionByKey[VibeRevisionKey(vibeID: id, version: version)]
    }

    static func migratedID(
        lane: VibeLaneDefinition,
        checkpoint: VibeLaneCheckpoint,
        index: Int
    ) -> UUID {
        let payload = [
            lane.id.uuidString,
            checkpoint.key,
            String(index),
            checkpoint.displayTitle,
            checkpoint.work.goal,
            checkpoint.work.instructions,
            checkpoint.work.skills.joined(separator: "\u{1e}"),
            checkpoint.verify.definition,
            checkpoint.verify.reviewSkills.joined(separator: "\u{1e}"),
            String(checkpoint.verify.humanReview),
            String(checkpoint.bounds.maxAttempts),
            String(checkpoint.bounds.timeoutSeconds),
            checkpoint.bounds.onExhausted.rawValue,
            checkpoint.engine.agentID ?? "",
            checkpoint.engine.modelID ?? "",
            checkpoint.engine.modeID ?? "",
            checkpoint.engine.reasoningLevel?.rawValue ?? "",
        ].joined(separator: "\u{1f}")
        let digest = Array(SHA256.hash(data: Data(payload.utf8)))
        let uuid: uuid_t = (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        )
        return UUID(uuid: uuid)
    }
}

/// Reference-only representation used by lane authoring persistence. Runtime
/// snapshots continue using `VibeLaneDefinition` so tasks and loops remain
/// immutable even if a central Vibe later changes.
struct StoredVibeLaneDefinition: Codable {
    struct Step: Codable {
        var key: String
        var order: Int
        var vibeID: UUID
        var vibeVersion: Int
        var requires: [VibeLaneInputRequirement]?
        var produces: [VibeLaneOutputDeclaration]?

        init?(_ checkpoint: VibeLaneCheckpoint) {
            guard let vibeID = checkpoint.vibeID,
                  let vibeVersion = checkpoint.vibeVersion else {
                return nil
            }
            self.key = checkpoint.key
            self.order = checkpoint.order
            self.vibeID = vibeID
            self.vibeVersion = vibeVersion
            self.requires = checkpoint.requires
            self.produces = checkpoint.produces
        }

        func resolved(
            current: [VibeDefinition],
            revisions: [VibeDefinition]
        ) -> VibeLaneCheckpoint {
            let shell = VibeLaneCheckpoint(
                key: key,
                order: order,
                vibeID: vibeID,
                vibeVersion: vibeVersion,
                goal: "",
                verify: VibeLaneVerificationDefinition(""),
                requires: requires?.map(\.key),
                produces: produces?.map(\.key)
            )
            guard let vibe = VibeLaneReferenceResolver.exactVibe(
                id: vibeID,
                version: vibeVersion,
                current: current,
                revisions: revisions
            ) else {
                // Fail closed: mark the step so `isRunnable` rejects the lane
                // instead of letting an empty goal/verification look like an
                // ordinary unfinished draft that could still be executed.
                var unresolved = shell
                unresolved.requires = requires
                unresolved.produces = produces
                unresolved.unresolvedVibeReference = true
                return unresolved
            }
            var resolved = vibe.applying(to: shell)
            resolved.requires = requires
            resolved.produces = produces
            return resolved
        }
    }

    var id: UUID
    var schemaVersion: Int
    var version: Int
    var name: String
    var detail: String?
    var steerLimit: Int
    var steps: [Step]
    var seededFingerprint: String?

    init?(_ lane: VibeLaneDefinition) {
        let steps = lane.checkpoints.compactMap(Step.init)
        guard steps.count == lane.checkpoints.count else { return nil }
        id = lane.id
        schemaVersion = lane.schemaVersion
        version = lane.version
        name = lane.name
        detail = lane.detail
        steerLimit = lane.steerLimit
        self.steps = steps
        seededFingerprint = lane.seededFingerprint
    }

    func resolved(
        current: [VibeDefinition],
        revisions: [VibeDefinition]
    ) -> VibeLaneDefinition {
        VibeLaneDefinition(
            id: id,
            schemaVersion: schemaVersion,
            version: version,
            name: name,
            detail: detail,
            steerLimit: steerLimit,
            checkpoints: steps.map { $0.resolved(current: current, revisions: revisions) },
            seededFingerprint: seededFingerprint
        )
    }
}
