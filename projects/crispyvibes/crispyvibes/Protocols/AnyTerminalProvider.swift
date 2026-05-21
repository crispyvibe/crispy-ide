// AnyTerminalProvider.swift — SSH Remote Development
// Type-erased wrapper for TerminalProviding. Forwards objectWillChange for SwiftUI.

import Combine
import Foundation

@MainActor
final class AnyTerminalProvider: ObservableObject {
    private let _wrapped: any TerminalProviding
    private var cancellables = Set<AnyCancellable>()

    init<T: TerminalProviding>(_ provider: T) {
        self._wrapped = provider
        provider.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - State

    var tabs: [TerminalTab] {
        get { _wrapped.tabs }
        set { _wrapped.tabs = newValue }
    }
    var activeTabID: UUID? {
        get { _wrapped.activeTabID }
        set { _wrapped.activeTabID = newValue }
    }
    var activeTab: TerminalTab? { _wrapped.activeTab }
    var errorMessage: String? {
        get { _wrapped.errorMessage }
        set { _wrapped.errorMessage = newValue }
    }
    var workerStatus: PaneWorkerStatus { _wrapped.workerStatus }
    var availablePresets: [TerminalPresetDefinition] { _wrapped.availablePresets }
    var shortcutCommands: [TerminalShortcutDefinition] { _wrapped.shortcutCommands }
    var tabActivitySummary: TerminalTabActivitySummary { _wrapped.tabActivitySummary }

    // MARK: - Publishers

    var tabsPublisher: AnyPublisher<[TerminalTab], Never> { _wrapped.tabsPublisher }
    var activeTabIDPublisher: AnyPublisher<UUID?, Never> { _wrapped.activeTabIDPublisher }

    // MARK: - Tab Lifecycle

    func createTab(directoryURL: URL?, customName: String? = nil, origin: TerminalOrigin = .adHoc, tmuxSessionName: String? = nil, startImmediately: Bool = true) {
        _wrapped.createTab(directoryURL: directoryURL, customName: customName, origin: origin, tmuxSessionName: tmuxSessionName, startImmediately: startImmediately)
    }
    @discardableResult
    func createUserTab(defaultDirectory: URL) -> UUID? { _wrapped.createUserTab(defaultDirectory: defaultDirectory) }
    func closeTab(_ tab: TerminalTab) { _wrapped.closeTab(tab) }
    func selectTab(_ tab: TerminalTab) { _wrapped.selectTab(tab) }
    @discardableResult
    func moveTab(_ tabID: UUID, relativeTo targetTabID: UUID, placement: TerminalTabMovePlacement) -> Bool {
        _wrapped.moveTab(tabID, relativeTo: targetTabID, placement: placement)
    }
    func renameTab(_ tabID: UUID, to name: String) { _wrapped.renameTab(tabID, to: name) }
    func restartTab(_ tabID: UUID, activateTab: Bool = true) { _wrapped.restartTab(tabID, activateTab: activateTab) }

    // MARK: - Clipboard

    func copy(tabID: UUID) { _wrapped.copy(tabID: tabID) }
    func paste(tabID: UUID) { _wrapped.paste(tabID: tabID) }
    func copyActiveTab() { _wrapped.copyActiveTab() }
    func pasteActiveTab() { _wrapped.pasteActiveTab() }

    // MARK: - Session Access

    func session(for tabID: UUID) -> TerminalSession? { _wrapped.session(for: tabID) }
    func tabActivityStateOrInactive(for tabID: UUID) -> TerminalTabActivityState { _wrapped.tabActivityStateOrInactive(for: tabID) }
    func focusActiveTerminal() { _wrapped.focusActiveTerminal() }

    // MARK: - Tab Management

    func openOrSelectTab(for directoryURL: URL) { _wrapped.openOrSelectTab(for: directoryURL) }
    func ensureActiveTerminal(defaultDirectory: URL, transitionID: String? = nil, startIfCreated: Bool = true) {
        _wrapped.ensureActiveTerminal(defaultDirectory: defaultDirectory, transitionID: transitionID, startIfCreated: startIfCreated)
    }
    func ensureTerminalCount(_ desiredCount: Int, defaultDirectory: URL) {
        _wrapped.ensureTerminalCount(desiredCount, defaultDirectory: defaultDirectory)
    }
    func runStartupCommandOnTab(_ command: String, customName: String? = nil, tabIndex: Int, origin: TerminalOrigin? = nil, defaultDirectory: URL, activateTab: Bool = true) {
        _wrapped.runStartupCommandOnTab(command, customName: customName, tabIndex: tabIndex, origin: origin, defaultDirectory: defaultDirectory, activateTab: activateTab)
    }

    // MARK: - Shell & Presets

    func updateShellResolutionContext(_ context: TerminalShellResolutionContext) { _wrapped.updateShellResolutionContext(context) }
    func refreshAvailablePresets() { _wrapped.refreshAvailablePresets() }
    var shellResolutionProviderStore: TerminalShellResolutionProvider { _wrapped.shellResolutionProviderStore }
    func launchPreset(_ preset: TerminalPresetDefinition, mode: TerminalPresetLaunchMode, directoryURL: URL? = nil) {
        _wrapped.launchPreset(preset, mode: mode, directoryURL: directoryURL)
    }
    func runShortcut(_ shortcut: TerminalShortcutDefinition, defaultDirectory: URL) { _wrapped.runShortcut(shortcut, defaultDirectory: defaultDirectory) }
    @discardableResult
    func addShortcut(name: String, command: String, launchBehavior: TerminalShortcutLaunchBehavior = .currentTerminal) -> Bool { _wrapped.addShortcut(name: name, command: command, launchBehavior: launchBehavior) }
    func removeShortcut(id: UUID) { _wrapped.removeShortcut(id: id) }

    // MARK: - Restore & Teardown

    func restoreTabsFromEntries(
        _ entries: [TerminalSessionEntry],
        activeDirectory: URL?,
        activeIdentity: String?,
        defaultDirectory: URL
    ) {
        _wrapped.restoreTabsFromEntries(
            entries,
            activeDirectory: activeDirectory,
            activeIdentity: activeIdentity,
            defaultDirectory: defaultDirectory
        )
    }
    func clearError() { _wrapped.clearError() }
    func shutdown() { _wrapped.shutdown() }
}
