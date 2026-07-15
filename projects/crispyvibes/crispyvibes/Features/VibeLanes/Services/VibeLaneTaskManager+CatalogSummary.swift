import Foundation

// F060 — a compact, prompt-friendly view of the lane catalog for consumers
// outside Vibe Lanes (the todo pipeline bridge). Exposes only what dispatch
// mapping and triage prompts need; never full lane definitions.

/// One lane's dispatch-relevant surface: identity, description, and the first
/// checkpoint's required input keys (with their ask-user flag).
struct VibeLaneCatalogEntry: Equatable, Sendable {
    let laneID: UUID
    let name: String
    let detail: String?
    /// Required input keys of the first checkpoint: key → askUser.
    let firstCheckpointRequires: [String: Bool]
}

extension VibeLaneTaskManager {
    /// Summaries for every authored lane, sorted by name. Empty lanes (no
    /// checkpoints) are excluded — they cannot run a task.
    func catalogSummary() -> [VibeLaneCatalogEntry] {
        lanes.compactMap { lane in
            guard let first = lane.firstCheckpoint else { return nil }
            return VibeLaneCatalogEntry(
                laneID: lane.id,
                name: lane.name,
                detail: lane.detail,
                firstCheckpointRequires: Dictionary(
                    first.inputRequirements.map { ($0.key, $0.askUser) },
                    uniquingKeysWith: { lhs, rhs in lhs || rhs }
                )
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Resolve a lane by UUID string or unique case-insensitive name match.
    /// Returns `.ambiguous` with candidates when a name matches several lanes.
    enum LaneResolution: Equatable {
        case resolved(UUID)
        case ambiguous([String])
        case notFound
    }

    func resolveLaneReference(_ reference: String) -> LaneResolution {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: trimmed), lane(withID: id) != nil {
            return .resolved(id)
        }
        let matches = lanes.filter {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
        switch matches.count {
        case 0: return .notFound
        case 1: return .resolved(matches[0].id)
        default: return .ambiguous(matches.map(\.name))
        }
    }
}
