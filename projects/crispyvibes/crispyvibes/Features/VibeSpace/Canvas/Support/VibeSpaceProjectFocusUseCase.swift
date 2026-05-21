import Foundation

@MainActor
struct VibeSpaceProjectFocusUseCase {
    enum ShortcutFocusCommand {
        case focusProject(AnyProjectSession)
        case cycleTerminal(project: AnyProjectSession, tabID: UUID)
        case noOp
    }

    enum AdjacentTerminalCommand {
        case focusProject(AnyProjectSession)
        case selectTab(project: AnyProjectSession, tabID: UUID)
    }

    private let projectRoutingUseCase = VibeSpaceProjectRoutingUseCase()

    func shortcutProjectIndex(from notification: Notification) -> Int? {
        if let value = notification.userInfo?[AppCommandUserInfoKey.index] as? Int {
            return value
        }
        if let text = notification.userInfo?[AppCommandUserInfoKey.index] as? String,
           let value = Int(text) {
            return value
        }
        return nil
    }

    func shortcutFocusCommand(index: Int, in vibespace: VibeSpaceState) -> ShortcutFocusCommand {
        guard index > 0,
              let project = projectRoutingUseCase.projectForShortcut(index: index, in: vibespace) else {
            return .noOp
        }

        let result = ProjectTerminalCycler.resolve(
            isAlreadyFocused: vibespace.focusedProjectID == project.id,
            tabIDs: project.terminal.tabs.map(\.id),
            activeTabID: project.terminal.activeTabID
        )

        switch result {
        case .focusProject:
            return .focusProject(project)
        case let .cycleTerminal(nextTabID):
            return .cycleTerminal(project: project, tabID: nextTabID)
        case .noOp:
            return .noOp
        }
    }

    func adjacentProject(
        offset: Int,
        focusedProjectID: UUID?,
        projects: [AnyProjectSession]
    ) -> AnyProjectSession? {
        guard offset != 0, !projects.isEmpty else { return nil }

        let currentIndex = focusedProjectID.flatMap { focusedID in
            projects.firstIndex(where: { $0.id == focusedID })
        } ?? 0
        let wrappedIndex = projectRoutingUseCase.wrappedIndex(
            afterShifting: currentIndex,
            by: offset,
            count: projects.count
        )
        return projects[wrappedIndex]
    }

    func adjacentTerminalCommand(
        offset: Int,
        focusedProject: AnyProjectSession?,
        projects: [AnyProjectSession]
    ) -> AdjacentTerminalCommand? {
        guard offset != 0, !projects.isEmpty else { return nil }
        guard let project = focusedProject ?? projects.first else { return nil }

        let tabs = project.terminal.tabs
        guard !tabs.isEmpty else {
            return .focusProject(project)
        }

        let currentIndex = project.terminal.activeTabID
            .flatMap { activeTabID in tabs.firstIndex(where: { $0.id == activeTabID }) } ?? 0
        let wrappedIndex = projectRoutingUseCase.wrappedIndex(
            afterShifting: currentIndex,
            by: offset,
            count: tabs.count
        )
        return .selectTab(project: project, tabID: tabs[wrappedIndex].id)
    }
}
