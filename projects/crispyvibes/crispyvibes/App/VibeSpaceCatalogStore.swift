import Foundation

struct VibeSpaceCatalogRemovalResult {
    let removedVibeSpaceID: UUID
    let fallbackVibeSpaceID: UUID?
}

@MainActor
final class VibeSpaceCatalogStore: ObservableObject {
    @Published private(set) var vibespaces: [VibeSpaceState] = []
    private let terminalBoardStandaloneRegistry: VibeSpaceTerminalBoardStandaloneRegistry
    private let terminalBoardDetachedWindowManager: VibeSpaceTerminalBoardDetachedWindowManager

    init(
        terminalBoardStandaloneRegistry: VibeSpaceTerminalBoardStandaloneRegistry,
        terminalBoardDetachedWindowManager: VibeSpaceTerminalBoardDetachedWindowManager
    ) {
        self.terminalBoardStandaloneRegistry = terminalBoardStandaloneRegistry
        self.terminalBoardDetachedWindowManager = terminalBoardDetachedWindowManager
    }

    var count: Int {
        vibespaces.count
    }

    var hasAnyVibeSpace: Bool {
        !vibespaces.isEmpty
    }

    var firstVibeSpaceID: UUID? {
        vibespaces.first?.id
    }

    var openVibeSpaceIDs: Set<UUID> {
        Set(vibespaces.map(\.id))
    }

    func vibespaceNamesLowercased() -> Set<String> {
        Set(vibespaces.map { $0.name.lowercased() })
    }

    func activeVibeSpaceIndex(for activeVibeSpaceID: UUID?) -> Int? {
        if let activeVibeSpaceID,
           let index = vibespaces.firstIndex(where: { $0.id == activeVibeSpaceID }) {
            return index
        }
        return vibespaces.isEmpty ? nil : 0
    }

    func vibespaceState(at index: Int?) -> VibeSpaceState? {
        guard let index, vibespaces.indices.contains(index) else { return nil }
        return vibespaces[index]
    }

    func activeVibeSpaceValue<T>(
        for activeVibeSpaceID: UUID?,
        _ transform: (VibeSpaceState, UUID) -> T?
    ) -> T? {
        guard let vibespaceIndex = activeVibeSpaceIndex(for: activeVibeSpaceID) else { return nil }
        let vibespace = vibespaces[vibespaceIndex]
        return transform(vibespace, vibespace.id)
    }

    func vibespaceValue<T>(for vibespaceID: UUID, _ transform: (VibeSpaceState) -> T?) -> T? {
        guard let vibespaceIndex = vibespaces.firstIndex(where: { $0.id == vibespaceID }) else { return nil }
        return transform(vibespaces[vibespaceIndex])
    }

    func mutateActiveVibeSpace(
        for activeVibeSpaceID: UUID?,
        _ update: (inout VibeSpaceState, UUID) -> Void
    ) {
        guard let vibespaceIndex = activeVibeSpaceIndex(for: activeVibeSpaceID) else { return }
        let vibespaceID = vibespaces[vibespaceIndex].id
        update(&vibespaces[vibespaceIndex], vibespaceID)
    }

    func mutateVibeSpace(id vibespaceID: UUID, _ update: (inout VibeSpaceState) -> Void) {
        guard let vibespaceIndex = vibespaces.firstIndex(where: { $0.id == vibespaceID }) else { return }
        update(&vibespaces[vibespaceIndex])
    }

    func allProjects() -> [(vibespaceID: UUID, project: AnyProjectSession)] {
        vibespaces.flatMap { vibespace in
            vibespace.projects.map { project in
                (vibespaceID: vibespace.id, project: project)
            }
        }
    }

    func replaceDisplayedVibeSpace(with vibespace: VibeSpaceState) {
        shutdownDisplayedVibeSpaces()
        vibespaces = [vibespace]
    }

    func clearDisplayedVibeSpaces() {
        shutdownDisplayedVibeSpaces()
        vibespaces = []
    }

    func removeDisplayedVibeSpace(at index: Int) -> VibeSpaceCatalogRemovalResult {
        let removedVibeSpace = vibespaces.remove(at: index)
        terminalBoardDetachedWindowManager.closeWindows(for: removedVibeSpace.id)
        removedVibeSpace.shutdownProjects()
        terminalBoardStandaloneRegistry.release(vibespaceID: removedVibeSpace.id)
        return VibeSpaceCatalogRemovalResult(
            removedVibeSpaceID: removedVibeSpace.id,
            fallbackVibeSpaceID: vibespaces.first?.id
        )
    }

    func resetDisplayedVibeSpaces() {
        vibespaces = []
    }

    func shutdownDisplayedVibeSpaces() {
        for vibespace in vibespaces {
            terminalBoardDetachedWindowManager.closeWindows(for: vibespace.id)
            vibespace.shutdownProjects()
            terminalBoardStandaloneRegistry.release(vibespaceID: vibespace.id)
        }
    }
}
