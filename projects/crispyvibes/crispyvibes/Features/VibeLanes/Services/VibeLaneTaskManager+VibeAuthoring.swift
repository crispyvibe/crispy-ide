import Foundation

extension VibeLaneTaskManager {
    @discardableResult
    func createVibe(name: String = AppStrings.VibeLanes.newVibe) async -> VibeDefinition? {
        await createVibe(VibeDefinition(
            name: name,
            goal: "",
            verify: VibeLaneVerificationDefinition("")
        ))
    }

    /// Persist a complete new Vibe in one manager-owned mutation.
    @discardableResult
    func createVibe(_ proposed: VibeDefinition) async -> VibeDefinition? {
        guard vibe(withID: proposed.id) == nil else { return nil }
        var vibe = proposed
        vibe.version = 1
        vibe.name = vibe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        vibe.detail = vibe.detail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        do {
            try await store.persistCurrentVibe(vibe)
        } catch {
            recordPersistenceResult(error)
            return nil
        }
        publishCurrentVibe(vibe)
        recordPersistenceResult(nil)
        return vibe
    }

    @discardableResult
    func updateVibe(_ vibe: VibeDefinition) async -> VibeDefinition? {
        let current = self.vibe(withID: vibe.id) ?? vibe
        var updated = vibe
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.detail = updated.detail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        updated.version = current.version + 1
        do {
            try await store.persistCurrentVibe(updated)
        } catch {
            recordPersistenceResult(error)
            return nil
        }
        vibeRevisions[VibeRevisionKey(
            vibeID: current.id,
            version: current.version
        )] = current
        publishCurrentVibe(updated)
        recordPersistenceResult(nil)
        return updated
    }

    @discardableResult
    func deleteVibe(id: UUID) async -> Bool {
        guard vibeUsageCount(id: id) == 0 else { return false }
        do {
            try await store.removeCurrentVibe(id: id)
        } catch {
            recordPersistenceResult(error)
            return false
        }
        removePublishedVibe(id: id)
        recordPersistenceResult(nil)
        return true
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
