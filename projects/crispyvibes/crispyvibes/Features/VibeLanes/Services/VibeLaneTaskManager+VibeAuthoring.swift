import Foundation

extension VibeLaneTaskManager {
    @discardableResult
    func createVibe(name: String = AppStrings.VibeLanes.newVibe) async -> VibeDefinition? {
        let vibe = VibeDefinition(
            name: name,
            goal: "",
            verify: VibeLaneVerificationDefinition("")
        )
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
