import Foundation
import SwiftUI

private struct AppRailSizeState: Codable, Equatable {
    var leftWidth: Double
    var rightWidth: Double
    var topHeight: Double
    var bottomHeight: Double

    static let `default` = AppRailSizeState(
        leftWidth: AppFirstRunExperience.Layout.defaultLeftRailWidth,
        rightWidth: AppFirstRunExperience.Layout.defaultRightRailWidth,
        topHeight: AppFirstRunExperience.Layout.defaultTopRailHeight,
        bottomHeight: AppFirstRunExperience.Layout.defaultBottomRailHeight
    )

    func normalized() -> AppRailSizeState {
        AppRailSizeState(
            leftWidth: Double(max(CGFloat(leftWidth), 150)),
            rightWidth: Double(max(CGFloat(rightWidth), 150)),
            topHeight: Double(clamped(CGFloat(topHeight), min: 150, max: 420)),
            bottomHeight: Double(clamped(CGFloat(bottomHeight), min: 150, max: 420))
        )
    }
}

struct VibeSpaceSpotlightTerminalOrderEntry: Codable, Equatable, Hashable {
    var projectPath: String
    var tabID: UUID

    init(projectPath: String, tabID: UUID) {
        self.projectPath = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        self.tabID = tabID
    }
}

extension Array where Element == VibeSpaceSpotlightTerminalOrderEntry {
    func normalized() -> [VibeSpaceSpotlightTerminalOrderEntry] {
        var seen = Set<VibeSpaceSpotlightTerminalOrderEntry>()
        var result: [VibeSpaceSpotlightTerminalOrderEntry] = []
        for entry in self where !entry.projectPath.isEmpty {
            let normalized = VibeSpaceSpotlightTerminalOrderEntry(
                projectPath: entry.projectPath,
                tabID: entry.tabID
            )
            guard seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }
        return result
    }
}

private struct VibeSpaceRailLayoutState: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case railSizes
        case canvasModeRawValue
        case terminalOnlyLayoutOrientationRawValue
        case detailedTerminalPaneHeight
        case detailedTerminalPaneCollapsed
        case terminalBoardLayout
        case terminalBoardState
        case vibespaceSpotlightTerminalOrder
    }

    var railSizes: AppRailSizeState
    var canvasModeRawValue: String
    var terminalOnlyLayoutOrientationRawValue: String
    var detailedTerminalPaneHeight: Double
    var detailedTerminalPaneCollapsed: Bool
    var terminalBoardLayout: VibeSpaceTerminalBoardLayout
    var terminalBoardState: VibeSpaceTerminalBoardState
    var vibespaceSpotlightTerminalOrder: [VibeSpaceSpotlightTerminalOrderEntry]

    init(
        railSizes: AppRailSizeState = .default,
        canvasMode: VibeSpaceCanvasMode = AppFirstRunExperience.Layout.defaultCanvasMode,
        terminalOnlyLayoutOrientation: VibeSpaceTerminalOnlyLayoutOrientation =
            AppFirstRunExperience.Layout.defaultTerminalOnlyLayoutOrientation,
        detailedTerminalPaneHeight: Double = AppFirstRunExperience.Layout.defaultDetailedTerminalPaneHeight,
        detailedTerminalPaneCollapsed: Bool = false,
        terminalBoardLayout: VibeSpaceTerminalBoardLayout = .empty,
        terminalBoardState: VibeSpaceTerminalBoardState? = nil,
        vibespaceSpotlightTerminalOrder: [VibeSpaceSpotlightTerminalOrderEntry] = []
    ) {
        self.railSizes = railSizes
        self.canvasModeRawValue = canvasMode.rawValue
        self.terminalOnlyLayoutOrientationRawValue = terminalOnlyLayoutOrientation.rawValue
        self.detailedTerminalPaneHeight = detailedTerminalPaneHeight
        self.detailedTerminalPaneCollapsed = detailedTerminalPaneCollapsed
        self.terminalBoardLayout = terminalBoardLayout
        self.terminalBoardState = terminalBoardState ?? .fromLegacyLayout(terminalBoardLayout)
        self.vibespaceSpotlightTerminalOrder = vibespaceSpotlightTerminalOrder.normalized()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        railSizes = try container.decodeIfPresent(AppRailSizeState.self, forKey: .railSizes) ?? .default
        canvasModeRawValue = try container.decodeIfPresent(String.self, forKey: .canvasModeRawValue)
            ?? AppFirstRunExperience.Layout.defaultCanvasMode.rawValue
        terminalOnlyLayoutOrientationRawValue = try container.decodeIfPresent(
            String.self,
            forKey: .terminalOnlyLayoutOrientationRawValue
        ) ?? AppFirstRunExperience.Layout.defaultTerminalOnlyLayoutOrientation.rawValue
        detailedTerminalPaneHeight = try container.decodeIfPresent(
            Double.self,
            forKey: .detailedTerminalPaneHeight
        ) ?? AppFirstRunExperience.Layout.defaultDetailedTerminalPaneHeight
        detailedTerminalPaneCollapsed = try container.decodeIfPresent(
            Bool.self,
            forKey: .detailedTerminalPaneCollapsed
        ) ?? false
        terminalBoardLayout = try container.decodeIfPresent(VibeSpaceTerminalBoardLayout.self, forKey: .terminalBoardLayout) ?? .empty
        terminalBoardState = try container.decodeIfPresent(
            VibeSpaceTerminalBoardState.self,
            forKey: .terminalBoardState
        ) ?? .fromLegacyLayout(terminalBoardLayout)
        vibespaceSpotlightTerminalOrder = try container.decodeIfPresent(
            [VibeSpaceSpotlightTerminalOrderEntry].self,
            forKey: .vibespaceSpotlightTerminalOrder
        )?.normalized() ?? []
    }

    var canvasMode: VibeSpaceCanvasMode {
        VibeSpaceCanvasMode(rawValue: canvasModeRawValue) ?? AppFirstRunExperience.Layout.defaultCanvasMode
    }

    var terminalOnlyLayoutOrientation: VibeSpaceTerminalOnlyLayoutOrientation {
        VibeSpaceTerminalOnlyLayoutOrientation(rawValue: terminalOnlyLayoutOrientationRawValue)
            ?? AppFirstRunExperience.Layout.defaultTerminalOnlyLayoutOrientation
    }

    func normalized() -> VibeSpaceRailLayoutState {
        VibeSpaceRailLayoutState(
            railSizes: railSizes.normalized(),
            canvasMode: canvasMode,
            terminalOnlyLayoutOrientation: terminalOnlyLayoutOrientation,
            detailedTerminalPaneHeight: max(detailedTerminalPaneHeight, 160),
            detailedTerminalPaneCollapsed: detailedTerminalPaneCollapsed,
            terminalBoardLayout: terminalBoardState.normalized().primaryLayout,
            terminalBoardState: terminalBoardState.normalized(),
            vibespaceSpotlightTerminalOrder: vibespaceSpotlightTerminalOrder.normalized()
        )
    }
}

@MainActor
final class LayoutPersistenceService: ObservableObject {
    static let shared = LayoutPersistenceService()

    @Published private var vibespaceLayoutsByID: [String: VibeSpaceRailLayoutState] = [:]
    @Published private var projectLayoutsByPath: [String: ProjectPaneLayoutState] = [:]
    @Published private(set) var vibespaceSidebarWidth: CGFloat

    private let persistenceStore: AppPersistenceDataStore
    private let projectPaneLayoutsFileURL: URL
    private var vibespacePersistenceStore: VibeSpacePersistenceStore?

    convenience init(fileManager: FileManager = .default, stateFileURL: URL? = nil) {
        let persistenceStore: AppPersistenceDataStore
        if let stateFileURL {
            persistenceStore = AppPersistenceDataStore(
                fileManager: fileManager,
                appDirectoryURL: stateFileURL.deletingLastPathComponent()
            )
        } else {
            persistenceStore = AppPersistenceDataStore(fileManager: fileManager)
        }
        self.init(persistenceStore: persistenceStore)
    }

    init(persistenceStore: AppPersistenceDataStore) {
        self.persistenceStore = persistenceStore
        self.projectPaneLayoutsFileURL = persistenceStore.appFileURL(relativePath: "project-pane-layouts.json")
        // Load sidebar width from app-state.json
        let store = VibeSpacePersistenceStore(store: self.persistenceStore)
        let appState = store.loadAppState()
        self.vibespaceSidebarWidth = max(
            CGFloat(appState.sidebarWidth ?? AppFirstRunExperience.Layout.defaultVibeSpaceSidebarWidth),
            180
        )
        self.projectLayoutsByPath = persistenceStore.load([String: ProjectPaneLayoutState].self, from: projectPaneLayoutsFileURL) ?? [:]
    }

    func resetToFirstRunState() {
        // Remove the persisted per-vibespace layout files too — otherwise the
        // lazy-load in `layoutForVibeSpace` would re-read them after the reset.
        if let wps = vibespacePersistenceStore {
            for key in vibespaceLayoutsByID.keys {
                if let uuid = UUID(uuidString: key) {
                    persistenceStore.removeFile(at: wps.vibespaceLayoutURL(for: uuid))
                }
            }
        }
        vibespaceLayoutsByID = [:]
        projectLayoutsByPath = [:]
        vibespaceSidebarWidth = CGFloat(AppFirstRunExperience.Layout.defaultVibeSpaceSidebarWidth)
        persistenceStore.removeFile(at: projectPaneLayoutsFileURL)
    }

    func setVibeSpacePersistenceStore(_ store: VibeSpacePersistenceStore) {
        self.vibespacePersistenceStore = store
    }

    func canvasMode(for vibespaceID: UUID?) -> VibeSpaceCanvasMode {
        let key = vibespaceKey(for: vibespaceID)
        return layoutForVibeSpace(key).canvasMode
    }

    func setCanvasMode(_ mode: VibeSpaceCanvasMode, for vibespaceID: UUID?) {
        let key = vibespaceKey(for: vibespaceID)
        var layout = layoutForVibeSpace(key)
        guard layout.canvasMode != mode else { return }
        layout.canvasModeRawValue = mode.rawValue
        vibespaceLayoutsByID[key] = layout.normalized()
        persistVibeSpaceLayout(key: key)
    }

    func terminalOnlyLayoutOrientation(for vibespaceID: UUID?) -> VibeSpaceTerminalOnlyLayoutOrientation {
        let key = vibespaceKey(for: vibespaceID)
        return layoutForVibeSpace(key).terminalOnlyLayoutOrientation
    }

    func setTerminalOnlyLayoutOrientation(
        _ orientation: VibeSpaceTerminalOnlyLayoutOrientation,
        for vibespaceID: UUID?
    ) {
        let key = vibespaceKey(for: vibespaceID)
        var layout = layoutForVibeSpace(key)
        guard layout.terminalOnlyLayoutOrientation != orientation else { return }
        layout.terminalOnlyLayoutOrientationRawValue = orientation.rawValue
        vibespaceLayoutsByID[key] = layout.normalized()
        persistVibeSpaceLayout(key: key)
    }

    func detailedTerminalPaneHeight(for vibespaceID: UUID?) -> CGFloat {
        let key = vibespaceKey(for: vibespaceID)
        return max(CGFloat(layoutForVibeSpace(key).detailedTerminalPaneHeight), 160)
    }

    func setDetailedTerminalPaneHeight(_ height: CGFloat, for vibespaceID: UUID?) {
        let key = vibespaceKey(for: vibespaceID)
        var layout = layoutForVibeSpace(key)
        let clampedHeight = Double(max(height, 160))
        guard abs(layout.detailedTerminalPaneHeight - clampedHeight) > 0.5 else { return }
        layout.detailedTerminalPaneHeight = clampedHeight
        vibespaceLayoutsByID[key] = layout.normalized()
        persistVibeSpaceLayout(key: key)
    }

    func isDetailedTerminalPaneCollapsed(for vibespaceID: UUID?) -> Bool {
        let key = vibespaceKey(for: vibespaceID)
        return layoutForVibeSpace(key).detailedTerminalPaneCollapsed
    }

    func setDetailedTerminalPaneCollapsed(_ isCollapsed: Bool, for vibespaceID: UUID?) {
        let key = vibespaceKey(for: vibespaceID)
        var layout = layoutForVibeSpace(key)
        guard layout.detailedTerminalPaneCollapsed != isCollapsed else { return }
        layout.detailedTerminalPaneCollapsed = isCollapsed
        vibespaceLayoutsByID[key] = layout.normalized()
        persistVibeSpaceLayout(key: key)
    }

    func terminalBoardLayout(for vibespaceID: UUID?) -> VibeSpaceTerminalBoardLayout {
        terminalBoardState(for: vibespaceID).primaryLayout
    }

    func terminalBoardState(for vibespaceID: UUID?) -> VibeSpaceTerminalBoardState {
        if let vibespaceID {
            loadVibeSpaceLayoutIfNeeded(for: vibespaceID)
        }
        let key = vibespaceKey(for: vibespaceID)
        return layoutForVibeSpace(key).terminalBoardState.normalized()
    }

    /// Persist the full terminal board state for a vibespace.
    ///
    /// Dedupes via equality; otherwise stores the provided state verbatim (modulo
    /// defensive normalization of non-board fields like rail sizes). Callers are
    /// responsible for normalizing the board state and capturing any external state
    /// (browser snapshots, etc.) before invoking this.
    func setTerminalBoardState(
        _ terminalBoardState: VibeSpaceTerminalBoardState,
        for vibespaceID: UUID?
    ) {
        let key = vibespaceKey(for: vibespaceID)
        var layout = layoutForVibeSpace(key)
        guard layout.terminalBoardState != terminalBoardState else { return }
        layout.terminalBoardState = terminalBoardState
        layout.terminalBoardLayout = terminalBoardState.primaryLayout
        vibespaceLayoutsByID[key] = layout.normalized()
        persistVibeSpaceLayout(key: key)
    }

    func vibespaceSpotlightTerminalOrder(
        liveIdentities: [VibeSpaceSpotlightTerminalOrderEntry],
        for vibespaceID: UUID?
    ) -> [VibeSpaceSpotlightTerminalOrderEntry] {
        if let vibespaceID {
            loadVibeSpaceLayoutIfNeeded(for: vibespaceID)
        }
        let liveOrder = liveIdentities.normalized()
        let liveSet = Set(liveOrder)
        let persisted = layoutForVibeSpace(vibespaceKey(for: vibespaceID)).vibespaceSpotlightTerminalOrder
        var ordered = persisted.filter { liveSet.contains($0) }.normalized()
        let orderedSet = Set(ordered)
        ordered.append(contentsOf: liveOrder.filter { !orderedSet.contains($0) })
        return ordered
    }

    func setVibeSpaceSpotlightTerminalOrder(
        _ order: [VibeSpaceSpotlightTerminalOrderEntry],
        for vibespaceID: UUID?
    ) {
        if let vibespaceID {
            loadVibeSpaceLayoutIfNeeded(for: vibespaceID)
        }
        let key = vibespaceKey(for: vibespaceID)
        var layout = layoutForVibeSpace(key)
        let normalizedOrder = order.normalized()
        guard layout.vibespaceSpotlightTerminalOrder != normalizedOrder else { return }
        layout.vibespaceSpotlightTerminalOrder = normalizedOrder
        vibespaceLayoutsByID[key] = layout.normalized()
        persistVibeSpaceLayout(key: key)
    }

    @discardableResult
    func moveVibeSpaceSpotlightTerminal(
        _ draggedIdentity: VibeSpaceSpotlightTerminalOrderEntry,
        relativeTo targetIdentity: VibeSpaceSpotlightTerminalOrderEntry,
        placement: TerminalTabMovePlacement,
        liveIdentities: [VibeSpaceSpotlightTerminalOrderEntry],
        for vibespaceID: UUID?
    ) -> Bool {
        guard draggedIdentity != targetIdentity else { return false }
        var order = vibespaceSpotlightTerminalOrder(liveIdentities: liveIdentities, for: vibespaceID)
        guard order.contains(draggedIdentity), order.contains(targetIdentity) else { return false }
        order.removeAll { $0 == draggedIdentity }
        guard let targetIndex = order.firstIndex(of: targetIdentity) else { return false }
        let insertIndex = placement == .before ? targetIndex : targetIndex + 1
        order.insert(draggedIdentity, at: min(insertIndex, order.count))
        setVibeSpaceSpotlightTerminalOrder(order, for: vibespaceID)
        return true
    }

    func railSize(for position: ProjectRailPosition, vibespaceID: UUID?) -> CGFloat {
        let key = vibespaceKey(for: vibespaceID)
        let sizes = layoutForVibeSpace(key).railSizes
        switch position {
        case .left:
            return max(CGFloat(sizes.leftWidth), 150)
        case .right:
            return max(CGFloat(sizes.rightWidth), 150)
        case .top:
            return clamped(CGFloat(sizes.topHeight), min: 150, max: 420)
        case .bottom:
            return clamped(CGFloat(sizes.bottomHeight), min: 150, max: 420)
        }
    }

    func setRailSize(_ size: CGFloat, for position: ProjectRailPosition, vibespaceID: UUID?) {
        let key = vibespaceKey(for: vibespaceID)
        var layout = layoutForVibeSpace(key)
        var didChange = false

        switch position {
        case .left:
            let clampedSize = Double(max(size, 150))
            if abs(layout.railSizes.leftWidth - clampedSize) > 0.5 {
                layout.railSizes.leftWidth = clampedSize
                didChange = true
            }
        case .right:
            let clampedSize = Double(max(size, 150))
            if abs(layout.railSizes.rightWidth - clampedSize) > 0.5 {
                layout.railSizes.rightWidth = clampedSize
                didChange = true
            }
        case .top:
            let clampedSize = Double(clamped(size, min: 150, max: 420))
            if abs(layout.railSizes.topHeight - clampedSize) > 0.5 {
                layout.railSizes.topHeight = clampedSize
                didChange = true
            }
        case .bottom:
            let clampedSize = Double(clamped(size, min: 150, max: 420))
            if abs(layout.railSizes.bottomHeight - clampedSize) > 0.5 {
                layout.railSizes.bottomHeight = clampedSize
                didChange = true
            }
        }

        guard didChange else { return }
        vibespaceLayoutsByID[key] = layout.normalized()
        persistVibeSpaceLayout(key: key)
    }

    func setVibeSpaceSidebarWidth(_ width: CGFloat) {
        let clamped = max(width, 180)
        guard abs(vibespaceSidebarWidth - clamped) > 0.5 else { return }
        vibespaceSidebarWidth = clamped
        persistSidebarWidth()
    }

    func paneLayout(for projectRootURL: URL) -> ProjectPaneLayoutState {
        let pathKey = normalizedProjectPath(projectRootURL)
        return projectLayoutsByPath[pathKey]?.normalized() ?? .default
    }

    func setPaneLayout(_ layout: ProjectPaneLayoutState, for projectRootURL: URL) {
        let pathKey = normalizedProjectPath(projectRootURL)
        let normalizedLayout = layout.normalized()
        if let existing = projectLayoutsByPath[pathKey], existing == normalizedLayout {
            return
        }
        projectLayoutsByPath[pathKey] = normalizedLayout
        persistProjectPaneLayouts()
    }

    /// Load layout from per-vibespace file if not already in memory.
    func loadVibeSpaceLayoutIfNeeded(for vibespaceID: UUID) {
        let key = vibespaceID.uuidString
        guard vibespaceLayoutsByID[key] == nil else { return }
        guard let wps = vibespacePersistenceStore else { return }
        let url = wps.vibespaceLayoutURL(for: vibespaceID)
        if let layout = persistenceStore.load(VibeSpaceRailLayoutState.self, from: url) {
            vibespaceLayoutsByID[key] = layout.normalized()
        }
    }

    private func layoutForVibeSpace(_ key: String) -> VibeSpaceRailLayoutState {
        // Load the persisted layout before returning. Every getter/setter funnels
        // through here, so this guarantees a setter (setCanvasMode/setRailSize/…)
        // mutates the real layout rather than an empty default that would then be
        // persisted over the saved board (wiping tiles/positions).
        if vibespaceLayoutsByID[key] == nil, let uuid = UUID(uuidString: key) {
            loadVibeSpaceLayoutIfNeeded(for: uuid)
        }
        return vibespaceLayoutsByID[key] ?? VibeSpaceRailLayoutState()
    }

    private func vibespaceKey(for vibespaceID: UUID?) -> String {
        vibespaceID?.uuidString ?? "__global__"
    }

    private func normalizedProjectPath(_ projectRootURL: URL) -> String {
        projectRootURL.standardizedFileURL.path
    }

    private func persistVibeSpaceLayout(key: String) {
        guard let wps = vibespacePersistenceStore,
              let uuid = UUID(uuidString: key),
              let layout = vibespaceLayoutsByID[key] else { return }
        let url = wps.vibespaceLayoutURL(for: uuid)
        persistenceStore.save(layout, to: url)
    }

    private func persistAllVibeSpaceLayouts() {
        guard let wps = vibespacePersistenceStore else { return }
        for (key, layout) in vibespaceLayoutsByID {
            guard let uuid = UUID(uuidString: key) else { continue }
            let url = wps.vibespaceLayoutURL(for: uuid)
            persistenceStore.save(layout, to: url)
        }
    }

    private func persistSidebarWidth() {
        let store = VibeSpacePersistenceStore(store: persistenceStore)
        var appState = store.loadAppState()
        appState.sidebarWidth = Double(vibespaceSidebarWidth)
        store.saveAppState(appState)
    }

    private func persistProjectPaneLayouts() {
        persistenceStore.save(projectLayoutsByPath, to: projectPaneLayoutsFileURL)
    }

    // MARK: - Editor Session State

    func saveEditorSessionState(_ state: EditorSessionState, for vibespaceID: UUID) {
        guard let wps = vibespacePersistenceStore else { return }
        let url = wps.vibespaceDirectoryURL(for: vibespaceID)
            .appendingPathComponent("editor-session.json")
        persistenceStore.save(state, to: url)
    }

    func loadEditorSessionState(for vibespaceID: UUID) -> EditorSessionState? {
        guard let wps = vibespacePersistenceStore else { return nil }
        let url = wps.vibespaceDirectoryURL(for: vibespaceID)
            .appendingPathComponent("editor-session.json")
        return persistenceStore.load(EditorSessionState.self, from: url)
    }
}
