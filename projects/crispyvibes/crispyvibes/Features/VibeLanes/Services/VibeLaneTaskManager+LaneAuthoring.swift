import Foundation

// F059 — VibeLaneTaskManager lane authoring (F059-R01): create / update / delete
// reusable lanes, and retain the exact revision a running task pinned so lane
// edits never mutate an in-flight or finished task (R07/S07). Split from the core
// type per coding-guidelines ("types over 200 LOC: split impl into extensions").
// Lane mutation is published through core helpers so the
// `@Published private(set) lanes` setter stays local to the core type.

extension VibeLaneTaskManager {

    /// Create an empty recipe. Vibes are added from the central library in the
    /// lane designer.
    @discardableResult
    func createLane(
        name: String = AppStrings.VibeLanes.newLane
    ) async -> VibeLaneDefinition? {
        let lane = VibeLaneDefinition(
            name: name,
            detail: nil,
            checkpoints: []
        )
        do {
            try await store.persistCurrentLane(lane)
        } catch {
            recordPersistenceResult(error)
            return nil
        }
        publishCurrentLane(lane)
        recordPersistenceResult(nil)
        return lane
    }

    /// Persist edits to a lane (bumps its content version; running tasks keep
    /// the version they pinned). Normalizes checkpoint keys so the engine and
    /// the UI never see empty or duplicate keys. Saving marks the lane
    /// user-owned: starter auto-refresh will never touch it again.
    ///
    /// Compare-and-swap on the content version: the incoming draft must be based
    /// on the revision that is currently published. The new version is derived
    /// from the store's value, never from the caller's — otherwise two saves
    /// from the same base both write v2 and the second silently overwrites the
    /// first, breaking the immutable `(laneID, version)` contract that tasks and
    /// loop snapshots pin against.
    @discardableResult
    func updateLane(_ lane: VibeLaneDefinition) async -> VibeLaneDefinition? {
        let current = lanes.first { $0.id == lane.id }
        if let current, lane.version != current.version {
            logger.warning(
                "updateLane: stale draft for \(lane.id.uuidString, privacy: .public) (draft v\(lane.version) vs current v\(current.version))"
            )
            recordPersistenceMessage(AppStrings.VibeLanes.laneRevisionConflict)
            return nil
        }
        var updated = lane
        let originalCheckpoints = updated.checkpoints
        updated.checkpoints = Self.normalizedCheckpoints(originalCheckpoints)
        var keyRemap: [String: String] = [:]
        for (original, normalized) in zip(originalCheckpoints, updated.checkpoints) {
            keyRemap[original.key, default: normalized.key] = normalized.key
        }
        updated.loopGroups = updated.loopGroups.map { group in
            var normalized = group
            normalized.key = Self.normalizedKey(group.key)
            normalized.members = group.members.map { keyRemap[$0] ?? $0 }
            return normalized
        }
        updated.version = (current?.version ?? lane.version) + 1
        updated.seededFingerprint = nil
        do {
            try await store.persistCurrentLane(updated)
        } catch {
            recordPersistenceResult(error)
            return nil
        }
        if let current {
            laneRevisions[VibeLaneRevisionKey(
                laneID: current.id,
                version: current.version
            )] = current
        }
        publishCurrentLane(updated)
        recordPersistenceResult(nil)
        return updated
    }

    /// Bring back deleted starter lanes and refresh pristine ones to the latest
    /// shipped content. User-edited copies are never overwritten.
    func restoreStarterLanes() async {
        do {
            apply(try await store.restoreStarterLanesPersisted())
            recordPersistenceResult(nil)
        } catch {
            recordPersistenceResult(error)
        }
    }

    func deleteLane(id: UUID) async {
        guard let current = lanes.first(where: { $0.id == id }) else { return }
        let isStarter = VibeLaneCatalog.starterLanes.contains { $0.id == id }
        do {
            try await store.removeCurrentLane(id: id, tombstone: isStarter)
        } catch {
            recordPersistenceResult(error)
            return
        }
        laneRevisions[VibeLaneRevisionKey(
            laneID: current.id,
            version: current.version
        )] = current
        removePublishedLane(id: id)
        recordPersistenceResult(nil)
    }

    /// Guarantee unique, non-empty checkpoint keys and contiguous order.
    static func normalizedCheckpoints(_ checkpoints: [VibeLaneCheckpoint]) -> [VibeLaneCheckpoint] {
        guard !checkpoints.isEmpty else { return [] }
        var seen = Set<String>()
        return checkpoints.enumerated().map { index, checkpoint in
            var c = checkpoint
            c.order = index
            let title = c.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            c.title = title?.isEmpty == false ? title : nil
            var key = normalizedKey(c.key)
            if key.isEmpty || seen.contains(key) {
                key = "step-\(index + 1)-\(UUID().uuidString.prefix(4))"
            }
            seen.insert(key)
            c.key = key
            return c
        }
    }

    static func normalizedKey(_ rawValue: String) -> String {
        let lowercased = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var scalars: [Character] = []
        var lastWasDash = false
        for character in lowercased {
            if character.isLetter || character.isNumber {
                scalars.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                scalars.append("-")
                lastWasDash = true
            }
        }
        return String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
