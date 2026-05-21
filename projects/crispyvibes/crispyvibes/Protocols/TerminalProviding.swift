// TerminalProviding.swift — SSH Remote Development

import Combine
import Foundation

/// Abstraction over terminal tab management.
/// Local: backed by TerminalViewModel (existing). Remote: same TerminalViewModel
/// configured with processLaunchOverride for SSH PTY sessions.
/// Views consume this protocol via AnyTerminalProvider type-erased wrapper.
@MainActor
protocol TerminalProviding: ObservableObject {

    // MARK: - State

    var tabs: [TerminalTab] { get set }
    var activeTabID: UUID? { get set }
    var activeTab: TerminalTab? { get }
    var errorMessage: String? { get set }
    var workerStatus: PaneWorkerStatus { get }
    var availablePresets: [TerminalPresetDefinition] { get }
    var shortcutCommands: [TerminalShortcutDefinition] { get }
    var tabActivitySummary: TerminalTabActivitySummary { get }

    // MARK: - Publishers

    var tabsPublisher: AnyPublisher<[TerminalTab], Never> { get }
    var activeTabIDPublisher: AnyPublisher<UUID?, Never> { get }

    // MARK: - Tab Lifecycle

    func createTab(
        directoryURL: URL?,
        customName: String?,
        origin: TerminalOrigin,
        tmuxSessionName: String?,
        startImmediately: Bool
    )
    @discardableResult
    func createUserTab(defaultDirectory: URL) -> UUID?
    func closeTab(_ tab: TerminalTab)
    func selectTab(_ tab: TerminalTab)
    @discardableResult
    func moveTab(_ tabID: UUID, relativeTo targetTabID: UUID, placement: TerminalTabMovePlacement) -> Bool
    func renameTab(_ tabID: UUID, to name: String)
    func restartTab(_ tabID: UUID, activateTab: Bool)

    // MARK: - Clipboard

    func copy(tabID: UUID)
    func paste(tabID: UUID)
    func copyActiveTab()
    func pasteActiveTab()

    // MARK: - Session Access

    func session(for tabID: UUID) -> TerminalSession?
    func tabActivityStateOrInactive(for tabID: UUID) -> TerminalTabActivityState
    func focusActiveTerminal()

    // MARK: - Tab Management

    func openOrSelectTab(for directoryURL: URL)
    func ensureActiveTerminal(defaultDirectory: URL, transitionID: String?, startIfCreated: Bool)
    func ensureTerminalCount(_ desiredCount: Int, defaultDirectory: URL)
    func runStartupCommandOnTab(
        _ command: String,
        customName: String?,
        tabIndex: Int,
        origin: TerminalOrigin?,
        defaultDirectory: URL,
        activateTab: Bool
    )

    // MARK: - Shell & Presets

    func updateShellResolutionContext(_ context: TerminalShellResolutionContext)
    func refreshAvailablePresets()
    var shellResolutionProviderStore: TerminalShellResolutionProvider { get }
    func launchPreset(_ preset: TerminalPresetDefinition, mode: TerminalPresetLaunchMode, directoryURL: URL?)
    func runShortcut(_ shortcut: TerminalShortcutDefinition, defaultDirectory: URL)
    @discardableResult
    func addShortcut(name: String, command: String, launchBehavior: TerminalShortcutLaunchBehavior) -> Bool
    func removeShortcut(id: UUID)

    // MARK: - Restore & Teardown

    func restoreTabsFromEntries(
        _ entries: [TerminalSessionEntry],
        activeDirectory: URL?,
        activeIdentity: String?,
        defaultDirectory: URL
    )
    func clearError()
    func shutdown()
}
