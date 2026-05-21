import Combine
import SwiftUI

let stackedRailItemSpacing: CGFloat = 8
let stackedRailOuterPadding: CGFloat = 12

func stackedCardHeight(for count: Int, availableHeight: CGFloat, isHorizontal: Bool) -> CGFloat {
    if isHorizontal {
        return max(availableHeight - stackedRailOuterPadding, 120)
    }
    guard count > 0 else { return 150 }
    let totalSpacing = CGFloat(max(count - 1, 0)) * stackedRailItemSpacing
    let usableHeight = max(availableHeight - stackedRailOuterPadding - totalSpacing, 1)
    let rawHeight = usableHeight / CGFloat(count)
    return max(rawHeight, 120)
}

func stackedCardWidth(for count: Int, availableWidth: CGFloat) -> CGFloat {
    guard count > 0 else { return 260 }
    let totalSpacing = CGFloat(max(count - 1, 0)) * stackedRailItemSpacing
    let usableWidth = max(availableWidth - stackedRailOuterPadding - totalSpacing, 1)
    let rawWidth = usableWidth / CGFloat(count)
    return max(rawWidth, 220)
}

@MainActor
final class StackedRailTerminalStore: ObservableObject {
    @Published private(set) var tabsByProjectPath: [String: [TerminalTab]] = [:]
    @Published private(set) var rankingVersion: UInt = 0

    private var subscriptionsByProjectPath: [String: AnyCancellable] = [:]
    private var activeTabSubscriptionsByProjectPath: [String: AnyCancellable] = [:]
    private var activitySubscriptionsByProjectPath: [String: [UUID: AnyCancellable]] = [:]
    private var observedTerminalViewModelIDsByProjectPath: [String: ObjectIdentifier] = [:]
    private var activeTabIDByProjectPath: [String: UUID] = [:]
    private var lastSelectedTabIDByProjectPath: [String: UUID] = [:]
    private var lastActivatedTabIDByProjectPath: [String: UUID] = [:]

    deinit {
        subscriptionsByProjectPath.values.forEach { $0.cancel() }
        activeTabSubscriptionsByProjectPath.values.forEach { $0.cancel() }
        activitySubscriptionsByProjectPath.values.forEach { subscriptions in
            subscriptions.values.forEach { $0.cancel() }
        }
    }

    func syncProjects(_ projects: [AnyProjectSession]) {
        let activeProjectPaths = Set(projects.map { $0.rootURL.standardizedFileURL.path })

        for stalePath in subscriptionsByProjectPath.keys.filter({ !activeProjectPaths.contains($0) }) {
            subscriptionsByProjectPath[stalePath]?.cancel()
            subscriptionsByProjectPath.removeValue(forKey: stalePath)
            activeTabSubscriptionsByProjectPath[stalePath]?.cancel()
            activeTabSubscriptionsByProjectPath.removeValue(forKey: stalePath)
            activitySubscriptionsByProjectPath[stalePath]?.values.forEach { $0.cancel() }
            activitySubscriptionsByProjectPath.removeValue(forKey: stalePath)
            observedTerminalViewModelIDsByProjectPath.removeValue(forKey: stalePath)
            tabsByProjectPath.removeValue(forKey: stalePath)
            activeTabIDByProjectPath.removeValue(forKey: stalePath)
            lastSelectedTabIDByProjectPath.removeValue(forKey: stalePath)
            lastActivatedTabIDByProjectPath.removeValue(forKey: stalePath)
        }

        for project in projects {
            let projectPath = project.rootURL.standardizedFileURL.path
            let terminalProvider = project.terminal
            setTabs(terminalProvider.tabs, for: projectPath)
            syncActivitySubscriptions(
                for: projectPath,
                terminalProvider: terminalProvider,
                tabs: terminalProvider.tabs
            )
            setActiveTabID(terminalProvider.activeTabID, for: projectPath)

            let terminalProviderID = ObjectIdentifier(terminalProvider)
            guard observedTerminalViewModelIDsByProjectPath[projectPath] != terminalProviderID else {
                continue
            }

            subscriptionsByProjectPath[projectPath]?.cancel()
            activeTabSubscriptionsByProjectPath[projectPath]?.cancel()
            activitySubscriptionsByProjectPath[projectPath]?.values.forEach { $0.cancel() }
            activitySubscriptionsByProjectPath[projectPath] = [:]
            observedTerminalViewModelIDsByProjectPath[projectPath] = terminalProviderID
            subscriptionsByProjectPath[projectPath] = terminalProvider.tabsPublisher
                .receive(on: RunLoop.main)
                .sink { [weak self, terminalProvider] tabs in
                    self?.setTabs(tabs, for: projectPath)
                    self?.syncActivitySubscriptions(
                        for: projectPath,
                        terminalProvider: terminalProvider,
                        tabs: tabs
                    )
                }
            activeTabSubscriptionsByProjectPath[projectPath] = terminalProvider.activeTabIDPublisher
                .receive(on: RunLoop.main)
                .sink { [weak self] activeTabID in
                    self?.setActiveTabID(activeTabID, for: projectPath)
                }
        }
    }

    func tabs(for projectPath: String) -> [TerminalTab] {
        tabsByProjectPath[projectPath] ?? []
    }

    func orderedTabs(
        for projectPath: String,
        tabs: [TerminalTab],
        terminalProvider: AnyTerminalProvider
    ) -> [TerminalTab] {
        let activeTabID = activeTabIDByProjectPath[projectPath]
        let lastSelectedTabID = lastSelectedTabIDByProjectPath[projectPath]
        let lastActivatedTabID = lastActivatedTabIDByProjectPath[projectPath]
        let indexedTabs = Array(tabs.enumerated())

        return indexedTabs.sorted { lhs, rhs in
            let lhsIsActive = terminalProvider.tabActivityStateOrInactive(for: lhs.element.id).isActive
            let rhsIsActive = terminalProvider.tabActivityStateOrInactive(for: rhs.element.id).isActive
            if lhsIsActive != rhsIsActive {
                return lhsIsActive && !rhsIsActive
            }

            if lhsIsActive, rhsIsActive {
                if lhs.element.id == lastActivatedTabID, rhs.element.id != lastActivatedTabID {
                    return true
                }
                if rhs.element.id == lastActivatedTabID, lhs.element.id != lastActivatedTabID {
                    return false
                }
            } else {
                if lhs.element.id == lastSelectedTabID, rhs.element.id != lastSelectedTabID {
                    return true
                }
                if rhs.element.id == lastSelectedTabID, lhs.element.id != lastSelectedTabID {
                    return false
                }
            }

            if lhs.element.id == activeTabID, rhs.element.id != activeTabID {
                return true
            }
            if rhs.element.id == activeTabID, lhs.element.id != activeTabID {
                return false
            }

            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    private func setTabs(_ tabs: [TerminalTab], for projectPath: String) {
        let validIDs = Set(tabs.map(\.id))
        if let activeTabID = activeTabIDByProjectPath[projectPath], !validIDs.contains(activeTabID) {
            activeTabIDByProjectPath.removeValue(forKey: projectPath)
        }
        if let lastSelectedTabID = lastSelectedTabIDByProjectPath[projectPath], !validIDs.contains(lastSelectedTabID) {
            lastSelectedTabIDByProjectPath.removeValue(forKey: projectPath)
        }
        if let lastActivatedTabID = lastActivatedTabIDByProjectPath[projectPath], !validIDs.contains(lastActivatedTabID) {
            lastActivatedTabIDByProjectPath.removeValue(forKey: projectPath)
        }

        guard tabsByProjectPath[projectPath] != tabs else { return }
        tabsByProjectPath[projectPath] = tabs
    }

    private func setActiveTabID(_ activeTabID: UUID?, for projectPath: String) {
        if let activeTabID {
            activeTabIDByProjectPath[projectPath] = activeTabID
            lastSelectedTabIDByProjectPath[projectPath] = activeTabID
        } else {
            activeTabIDByProjectPath.removeValue(forKey: projectPath)
        }
        touchRankingVersion()
    }

    private func syncActivitySubscriptions(
        for projectPath: String,
        terminalProvider: AnyTerminalProvider,
        tabs: [TerminalTab]
    ) {
        let validIDs = Set(tabs.map(\.id))
        let existingIDs = activitySubscriptionsByProjectPath[projectPath].map { Set($0.keys) } ?? []
        let staleIDs = existingIDs.subtracting(validIDs)
        for staleID in staleIDs {
            activitySubscriptionsByProjectPath[projectPath]?[staleID]?.cancel()
            activitySubscriptionsByProjectPath[projectPath]?.removeValue(forKey: staleID)
        }

        for tab in tabs {
            guard activitySubscriptionsByProjectPath[projectPath]?[tab.id] == nil else { continue }
            let activityState = terminalProvider.tabActivityStateOrInactive(for: tab.id)
            activitySubscriptionsByProjectPath[projectPath, default: [:]][tab.id] = activityState.$isActive
                .receive(on: RunLoop.main)
                .sink { [weak self] isActive in
                    guard let self else { return }
                    if isActive {
                        self.lastActivatedTabIDByProjectPath[projectPath] = tab.id
                    }
                    self.touchRankingVersion()
                }
        }

        let currentActiveTabs = tabs.filter { terminalProvider.tabActivityStateOrInactive(for: $0.id).isActive }
        if let lastActivatedTabID = lastActivatedTabIDByProjectPath[projectPath], validIDs.contains(lastActivatedTabID) {
            return
        }
        if let activeTabID = activeTabIDByProjectPath[projectPath], currentActiveTabs.contains(where: { $0.id == activeTabID }) {
            lastActivatedTabIDByProjectPath[projectPath] = activeTabID
        } else if let firstActiveTabID = currentActiveTabs.first?.id {
            lastActivatedTabIDByProjectPath[projectPath] = firstActiveTabID
        }
    }

    private func touchRankingVersion() {
        rankingVersion &+= 1
    }
}

struct StackedRailObservedVibeSpace: Equatable {
    let vibespaceID: UUID?
    let projectPaths: [String]
}

struct StackedRailTerminalEntry: Identifiable {
    let projectPath: String
    let terminalTab: TerminalTab

    var id: UUID {
        terminalTab.id
    }
}

struct StackedRailProjectGroup: Identifiable {
    let projectPath: String
    let project: AnyProjectSession
    let orderedVisibleEntries: [StackedRailTerminalEntry]

    var id: String {
        projectPath
    }

    var primaryEntry: StackedRailTerminalEntry? {
        orderedVisibleEntries.first
    }

    var additionalEntries: [StackedRailTerminalEntry] {
        Array(orderedVisibleEntries.dropFirst())
    }
}

struct StackedRailExpansionOverlayPresentation: Identifiable {
    let group: StackedRailProjectGroup
    let railPosition: ProjectRailPosition
    let anchorFrame: CGRect
    let preferredHeight: CGFloat
    let preferredWidth: CGFloat?
    let accentColor: Color
    let shortcutIndex: Int?
    let projectTitle: String
    let onCard: StackedRailCardRenderer
    let onFocusEntry: (StackedRailTerminalEntry) -> Void

    var id: String {
        group.projectPath
    }
}

@MainActor
final class StackedRailExpansionOverlayCoordinator: ObservableObject {
    @Published private(set) var presentation: StackedRailExpansionOverlayPresentation?
    @Published private(set) var overlayHoveredProjectPath: String?

    private var dismissTask: Task<Void, Never>?

    func show(_ presentation: StackedRailExpansionOverlayPresentation) {
        cancelDismissTask()
        self.presentation = presentation
    }

    func updateAnchorFrame(_ anchorFrame: CGRect, for projectPath: String) {
        guard var presentation, presentation.group.projectPath == projectPath else { return }
        presentation = StackedRailExpansionOverlayPresentation(
            group: presentation.group,
            railPosition: presentation.railPosition,
            anchorFrame: anchorFrame,
            preferredHeight: presentation.preferredHeight,
            preferredWidth: presentation.preferredWidth,
            accentColor: presentation.accentColor,
            shortcutIndex: presentation.shortcutIndex,
            projectTitle: presentation.projectTitle,
            onCard: presentation.onCard,
            onFocusEntry: presentation.onFocusEntry
        )
        self.presentation = presentation
    }

    func setOverlayHover(projectPath: String, isHovering: Bool) {
        if isHovering {
            cancelDismissTask()
            overlayHoveredProjectPath = projectPath
        } else if overlayHoveredProjectPath == projectPath {
            overlayHoveredProjectPath = nil
            scheduleDismiss(projectPath: projectPath)
        }
    }

    func scheduleDismiss(projectPath: String, isKeyboardFocused: Bool = false) {
        guard presentation?.group.projectPath == projectPath else { return }
        guard !isKeyboardFocused else { return }

        cancelDismissTask()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(55))
            guard !Task.isCancelled else { return }
            guard overlayHoveredProjectPath != projectPath else { return }
            guard presentation?.group.projectPath == projectPath else { return }
            presentation = nil
        }
    }

    func dismiss(projectPath: String? = nil) {
        cancelDismissTask()
        if let projectPath {
            guard presentation?.group.projectPath == projectPath else { return }
            if overlayHoveredProjectPath == projectPath {
                overlayHoveredProjectPath = nil
            }
        } else {
            overlayHoveredProjectPath = nil
        }
        presentation = nil
    }

    private func cancelDismissTask() {
        dismissTask?.cancel()
        dismissTask = nil
    }
}

@MainActor
struct StackedRailPresentation {
    let projectsByPath: [String: AnyProjectSession]
    let visibleGroups: [StackedRailProjectGroup]
    let hiddenEntries: [StackedRailTerminalEntry]

    init(
        projects: [AnyProjectSession],
        stackedRailStore: StackedRailTerminalStore,
        hiddenTerminalIDsByProjectPath: [String: Set<UUID>]
    ) {
        let projectsByPath = Dictionary(
            uniqueKeysWithValues: projects.map { project in
                (project.rootURL.standardizedFileURL.path, project)
            }
        )
        var visibleGroups: [StackedRailProjectGroup] = []
        var hiddenEntries: [StackedRailTerminalEntry] = []

        for project in projects {
            let projectPath = project.rootURL.standardizedFileURL.path
            let hiddenIDs = hiddenTerminalIDsByProjectPath[projectPath] ?? []
            let visibleTabs = stackedRailStore.orderedTabs(
                for: projectPath,
                tabs: stackedRailStore.tabs(for: projectPath).filter { !hiddenIDs.contains($0.id) },
                terminalProvider: project.terminal
            )
            let visibleEntries = visibleTabs.map { terminalTab in
                StackedRailTerminalEntry(projectPath: projectPath, terminalTab: terminalTab)
            }

            if !visibleEntries.isEmpty {
                visibleGroups.append(
                    StackedRailProjectGroup(
                        projectPath: projectPath,
                        project: project,
                        orderedVisibleEntries: visibleEntries
                    )
                )
            }

            for terminalTab in stackedRailStore.tabs(for: projectPath) where hiddenIDs.contains(terminalTab.id) {
                let entry = StackedRailTerminalEntry(projectPath: projectPath, terminalTab: terminalTab)
                hiddenEntries.append(entry)
            }
        }

        self.projectsByPath = projectsByPath
        self.visibleGroups = visibleGroups
        self.hiddenEntries = hiddenEntries
    }

    func project(for entry: StackedRailTerminalEntry) -> AnyProjectSession? {
        projectsByPath[entry.projectPath]
    }
}
