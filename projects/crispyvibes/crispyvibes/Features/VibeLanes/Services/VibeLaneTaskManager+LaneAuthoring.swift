import Foundation

// F059 — VibeLaneTaskManager lane authoring (F059-R01): create / update / delete
// reusable lanes, and retain the exact revision a running task pinned so lane
// edits never mutate an in-flight or finished task (R07/S07). Split from the core
// type per coding-guidelines ("types over 200 LOC: split impl into extensions").
// Lane mutation is published via the core `reloadLanes()` so the
// `@Published private(set) lanes` setter stays local to the core file.

extension VibeLaneTaskManager {

    /// Create a new lane with one starter checkpoint, persist it, and return it.
    @discardableResult
    func createLane(name: String = AppStrings.VibeLanes.newLane) -> VibeLaneDefinition {
        let lane = VibeLaneDefinition(
            name: name,
            detail: nil,
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "step-1", order: 0,
                    goal: "",
                    verify: VibeLaneVerificationDefinition("")
                )
            ]
        )
        store.saveLane(lane)
        reloadLanes()
        return lane
    }

    /// Persist edits to a lane (bumps its content version; running tasks keep
    /// the version they pinned). Normalizes checkpoint keys so the engine and
    /// the UI never see empty or duplicate keys. Saving marks the lane
    /// user-owned: starter auto-refresh will never touch it again.
    @discardableResult
    func updateLane(_ lane: VibeLaneDefinition) -> VibeLaneDefinition {
        // Retain the outgoing revision if any task still pins it, so its run keeps
        // resolving the exact lane it started against (R07/S07).
        archiveIfPinned(laneID: lane.id)
        var updated = lane
        updated.checkpoints = Self.normalizedCheckpoints(updated.checkpoints)
        updated.version += 1
        updated.seededFingerprint = nil
        store.saveLane(updated)
        reloadLanes()
        return updated
    }

    /// Bring back deleted starter lanes and refresh pristine ones to the latest
    /// shipped content. User-edited copies are never overwritten.
    func restoreStarterLanes() {
        store.restoreStarterLanes()
        reloadLanes()
    }

    func deleteLane(id: UUID) {
        // Retain the current revision if a task still pins it, so a deleted lane's
        // in-flight/finished tasks keep resolving their process.
        archiveIfPinned(laneID: id)
        store.deleteLane(id: id)
        reloadLanes()
    }

    /// Guarantee unique, non-empty checkpoint keys and contiguous order.
    static func normalizedCheckpoints(_ checkpoints: [VibeLaneCheckpoint]) -> [VibeLaneCheckpoint] {
        guard !checkpoints.isEmpty else {
            return [
                VibeLaneCheckpoint(
                    key: "step-1",
                    order: 0,
                    goal: "",
                    verify: VibeLaneVerificationDefinition("")
                )
            ]
        }
        var seen = Set<String>()
        return checkpoints.enumerated().map { index, checkpoint in
            var c = checkpoint
            c.order = index
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

    /// Archive the currently-registered revision of `laneID` if any task pins it.
    private func archiveIfPinned(laneID: UUID) {
        guard let current = lanes.first(where: { $0.id == laneID }),
              tasks.contains(where: { $0.laneID == laneID && $0.laneVersion == current.version }) else {
            return
        }
        store.archiveLaneRevision(current)
    }
}
