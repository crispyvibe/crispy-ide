import SwiftUI

extension VibeLaneEditorView {
    var selectedCheckpointBinding: Binding<VibeLaneCheckpoint>? {
        guard draft.checkpoints.indices.contains(selectedIndex) else { return nil }
        return Binding(
            get: { draft.checkpoints[selectedIndex] },
            set: { draft.checkpoints[selectedIndex] = $0 }
        )
    }

    var detailBinding: Binding<String> {
        Binding(
            get: { draft.detail ?? "" },
            set: { draft.detail = $0.isEmpty ? nil : $0 }
        )
    }

    func latestVibe(for checkpoint: VibeLaneCheckpoint) -> VibeDefinition? {
        guard let vibeID = checkpoint.vibeID else { return nil }
        return vibes.first { $0.id == vibeID }
    }

    func addVibe(_ vibe: VibeDefinition) {
        let existing = Set(draft.checkpoints.map(\.key))
        let base = VibeLaneTaskManager.normalizedKey(vibe.name)
        var key = base.isEmpty ? "step-\(draft.checkpoints.count + 1)" : base
        var suffix = 2
        while existing.contains(key) {
            key = "\(base)-\(suffix)"
            suffix += 1
        }
        draft.checkpoints.append(
            vibe.checkpoint(key: key, order: draft.checkpoints.count)
        )
        selectedIndex = draft.checkpoints.count - 1
    }

    func useLatestVibe(_ vibe: VibeDefinition) {
        guard draft.checkpoints.indices.contains(selectedIndex) else { return }
        draft.checkpoints[selectedIndex] = vibe.applying(
            to: draft.checkpoints[selectedIndex]
        )
    }

    func removeCheckpoint() {
        guard draft.checkpoints.indices.contains(selectedIndex) else { return }
        let removedKey = draft.checkpoints[selectedIndex].key
        draft.checkpoints.remove(at: selectedIndex)
        draft.loopGroups = draft.loopGroups.compactMap { group in
            var updated = group
            updated.members.removeAll { $0 == removedKey }
            return updated.members.count >= 2 ? updated : nil
        }
        refreshCheckpointOrder()
        selectedIndex = min(selectedIndex, max(0, draft.checkpoints.count - 1))
    }

    func canMoveCheckpoint(offset: Int) -> Bool {
        let newIndex = selectedIndex + offset
        guard draft.checkpoints.indices.contains(selectedIndex),
              draft.checkpoints.indices.contains(newIndex) else { return false }
        return draft.loopGroup(containing: draft.checkpoints[selectedIndex].key) == nil
            && draft.loopGroup(containing: draft.checkpoints[newIndex].key) == nil
    }

    func moveCheckpoint(offset: Int) {
        let newIndex = selectedIndex + offset
        guard draft.checkpoints.indices.contains(selectedIndex),
              draft.checkpoints.indices.contains(newIndex),
              draft.loopGroup(containing: draft.checkpoints[selectedIndex].key) == nil,
              draft.loopGroup(containing: draft.checkpoints[newIndex].key) == nil else {
            return
        }
        draft.checkpoints.swapAt(selectedIndex, newIndex)
        selectedIndex = newIndex
        refreshCheckpointOrder()
    }

    func checkpointHasErrors(at index: Int) -> Bool {
        draft.validationIssues.contains {
            !$0.isRepairedOnEditorSave && $0.checkpointIndex == index
        }
    }

    private func refreshCheckpointOrder() {
        for index in draft.checkpoints.indices {
            draft.checkpoints[index].order = index
        }
    }
}

