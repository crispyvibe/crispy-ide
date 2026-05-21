import SwiftUI

@MainActor
final class VibeSpaceSidebarSessionsViewModel: ObservableObject {
    @Published private(set) var vibespaceGroups: [VibeSpaceSidebarTmuxVibeSpaceGroup] = []
    @Published private(set) var hasLoadedSnapshot = false
    @Published private(set) var isRefreshIndicatorVisible = false
    @Published var expandedVibeSpaceIDs: Set<UUID> = []
    @Published var expandedSectionIDs: Set<String> = []

    private var activeVibeSpaceID: UUID?
    private var vibespaces: [VibeSpaceState] = []
    private var refreshTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var refreshIndicatorTask: Task<Void, Never>?
    private let sessionBrowser = VibeSpaceSidebarSessionBrowser()

    func start(activeVibeSpaceID: UUID?, vibespaces: [VibeSpaceState]) {
        self.activeVibeSpaceID = activeVibeSpaceID
        self.vibespaces = vibespaces
        refresh(showIndicator: true)
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self else { return }
                self.refresh(showIndicator: false)
            }
        }
    }

    func update(activeVibeSpaceID: UUID?, vibespaces: [VibeSpaceState]) {
        self.activeVibeSpaceID = activeVibeSpaceID
        self.vibespaces = vibespaces
        refresh(showIndicator: false)
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshIndicatorTask?.cancel()
        refreshIndicatorTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        expandedVibeSpaceIDs = []
        expandedSectionIDs = []
        hasLoadedSnapshot = false
        isRefreshIndicatorVisible = false
    }

    func refresh() {
        refresh(showIndicator: true)
    }

    private func refresh(showIndicator: Bool) {
        refreshTask?.cancel()
        refreshIndicatorTask?.cancel()
        let snapshot = vibespaces
        let activeVibeSpaceID = activeVibeSpaceID
        isRefreshIndicatorVisible = false

        if showIndicator {
            refreshIndicatorTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.refreshTask != nil else { return }
                self.isRefreshIndicatorVisible = true
            }
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.loadVibeSpaceGroups(for: snapshot, activeVibeSpaceID: activeVibeSpaceID)
        }
    }

    private func loadVibeSpaceGroups(
        for vibespaces: [VibeSpaceState],
        activeVibeSpaceID: UUID?
    ) async {
        defer {
            refreshIndicatorTask?.cancel()
            refreshIndicatorTask = nil
            isRefreshIndicatorVisible = false
        }

        let nextGroups = await sessionBrowser.buildVibeSpaceGroups(
            for: vibespaces,
            activeVibeSpaceID: activeVibeSpaceID
        )

        if !Task.isCancelled {
            vibespaceGroups = nextGroups
            syncExpandedVibeSpaces(with: nextGroups)
            syncExpandedSections(with: nextGroups)
            hasLoadedSnapshot = true
        }
    }

    private func syncExpandedVibeSpaces(with groups: [VibeSpaceSidebarTmuxVibeSpaceGroup]) {
        let validIDs = Set(groups.map(\.id))
        expandedVibeSpaceIDs.formIntersection(validIDs)
        if expandedVibeSpaceIDs.isEmpty,
           let currentVibeSpace = groups.first(where: \.isCurrentVibeSpace) {
            expandedVibeSpaceIDs = [currentVibeSpace.id]
        }
    }

    private func syncExpandedSections(with groups: [VibeSpaceSidebarTmuxVibeSpaceGroup]) {
        let validIDs = Set(groups.flatMap { $0.sections.map(\.id) })
        expandedSectionIDs.formIntersection(validIDs)
        if expandedSectionIDs.isEmpty,
           let currentVibeSpace = groups.first(where: \.isCurrentVibeSpace) {
            expandedSectionIDs = Set(currentVibeSpace.sections.map(\.id))
        }
    }
}
