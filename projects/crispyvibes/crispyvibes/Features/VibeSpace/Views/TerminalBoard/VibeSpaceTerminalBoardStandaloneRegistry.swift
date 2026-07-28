import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class VibeSpaceTerminalBoardStandaloneRegistry {
    private let makeTerminalViewModel: @MainActor () -> TerminalViewModel

    private var viewModelsByVibeSpaceKey: [String: TerminalViewModel] = [:]

    init(makeTerminalViewModel: @escaping @MainActor () -> TerminalViewModel) {
        self.makeTerminalViewModel = makeTerminalViewModel
    }

    func viewModel(for vibespaceID: UUID?) -> TerminalViewModel {
        let key = vibespaceID?.uuidString ?? "__default__"
        if let existing = viewModelsByVibeSpaceKey[key] {
            return existing
        }

        let viewModel = makeTerminalViewModel()
        viewModel.updateShellResolutionContext(
            TerminalShellResolutionContext(appDefault: AppPreferences.storedTerminalShellPreference())
        )
        viewModelsByVibeSpaceKey[key] = viewModel
        return viewModel
    }

    func release(vibespaceID: UUID?) {
        let key = vibespaceID?.uuidString ?? "__default__"
        guard let viewModel = viewModelsByVibeSpaceKey.removeValue(forKey: key) else { return }
        viewModel.shutdown()
        assert(
            viewModelsByVibeSpaceKey[key] == nil,
            "ANOMALY: vibespace \(key) still registered after release"
        )
    }

    func shutdownAll() {
        let allViewModels = Array(viewModelsByVibeSpaceKey.values)
        viewModelsByVibeSpaceKey.removeAll()
        for viewModel in allViewModels {
            viewModel.shutdown()
        }
    }

    var registeredCount: Int { viewModelsByVibeSpaceKey.count }

    deinit {
        MainActor.assumeIsolated { shutdownAll() }
    }
}

@MainActor
struct VibeSpaceTerminalBoardWindowToolbarConfiguration {
    let stateChanges: AnyPublisher<Void, Never>?
    let addVibeCast: () -> Void
    let addVibeLanes: () -> Void
    let addAgent: (() -> Void)?
    let addBrowser: () -> Void
    let canAddVibeCast: () -> Bool
    let canAddVibeLanes: () -> Bool
    let canAddAgent: () -> Bool
    let canAddBrowser: () -> Bool
    /// Snapshot of the active vibespace's projects, used to populate the
    /// New Terminal popover hosted in the detached window's toolbar.
    let projects: [AnyProjectSession]
    /// Currently-focused project — drives the popover's "Temporary Terminal"
    /// shortcut row.
    let focusedProject: AnyProjectSession?
    /// Resolves a project's color tag for the popover's project-row icons.
    let colorForProject: (AnyProjectSession) -> Color?
    /// Invoked when the popover submits. Detached windows wire this to
    /// `boardStore.addTile(... surfaceID: detachedSurface)` so the new tile
    /// lands on the originating window's surface (not the primary one).
    /// Arguments: directoryURL, optional inferred owning-project root path,
    /// and the `preferTemporary` flag from the popover's Temporary Terminal
    /// shortcut row.
    let onCreateTerminal: (URL, String?, Bool) -> Void
    /// Whether the surface still has room for another tile.
    let canAddTerminal: () -> Bool
}

@MainActor
private final class VibeSpaceTerminalBoardWindowToolbarCoordinator: NSObject, NSToolbarDelegate, NSToolbarItemValidation {
    private static let toolbarIdentifier = NSToolbar.Identifier("com.crispyvibe.terminalBoard.detached.toolbar")
    private static let terminalIdentifier = NSToolbarItem.Identifier("com.crispyvibe.terminalBoard.detached.toolbar.terminal")
    private static let vibeCastIdentifier = NSToolbarItem.Identifier("com.crispyvibe.terminalBoard.detached.toolbar.vibecast")
    private static let vibeLanesIdentifier = NSToolbarItem.Identifier("com.crispyvibe.terminalBoard.detached.toolbar.vibe-lanes")
    private static let agentIdentifier = NSToolbarItem.Identifier("com.crispyvibe.terminalBoard.detached.toolbar.agent")
    private static let browserIdentifier = NSToolbarItem.Identifier("com.crispyvibe.terminalBoard.detached.toolbar.browser")

    private let configuration: VibeSpaceTerminalBoardWindowToolbarConfiguration
    private weak var toolbar: NSToolbar?
    private var stateChangesCancellable: AnyCancellable?

    init(configuration: VibeSpaceTerminalBoardWindowToolbarConfiguration) {
        self.configuration = configuration
        super.init()
        stateChangesCancellable = configuration.stateChanges?
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.toolbar?.validateVisibleItems()
            }
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.showsBaselineSeparator = false
        self.toolbar = toolbar
        return toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarItemIdentifiers
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarItemIdentifiers
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        []
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.terminalIdentifier:
            return makeHostedTerminalToolbarItem(identifier: itemIdentifier)
        case Self.vibeCastIdentifier:
            return toolbarItem(
                identifier: itemIdentifier,
                label: AppStrings.VibeCast.title,
                systemSymbolName: "antenna.radiowaves.left.and.right",
                action: #selector(addVibeCast(_:))
            )
        case Self.vibeLanesIdentifier:
            return toolbarItem(
                identifier: itemIdentifier,
                label: AppStrings.VibeLanes.title,
                systemSymbolName: VibeLaneVisualIdentity.symbolName,
                action: #selector(addVibeLanes(_:))
            )
        case Self.agentIdentifier:
            return toolbarItem(
                identifier: itemIdentifier,
                label: AppStrings.ACP.openAgent,
                systemSymbolName: "sparkles",
                action: #selector(addAgent(_:))
            )
        case Self.browserIdentifier:
            return toolbarItem(
                identifier: itemIdentifier,
                label: "Open Browser",
                systemSymbolName: "globe",
                action: #selector(addBrowser(_:))
            )
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.terminalIdentifier:
            return configuration.canAddTerminal()
        case Self.vibeCastIdentifier:
            return configuration.canAddVibeCast()
        case Self.vibeLanesIdentifier:
            return configuration.canAddVibeLanes()
        case Self.agentIdentifier:
            return configuration.addAgent != nil && configuration.canAddAgent()
        case Self.browserIdentifier:
            return configuration.canAddBrowser()
        default:
            return true
        }
    }

    /// Toolbar item order matches the main window's title-bar pill so the
    /// detached window feels consistent:
    /// Terminal / Agent / Browser / VibeCast / Vibe Lanes.
    private var toolbarItemIdentifiers: [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = [
            .flexibleSpace,
            Self.terminalIdentifier
        ]
        if configuration.addAgent != nil {
            identifiers.append(Self.agentIdentifier)
        }
        identifiers.append(Self.browserIdentifier)
        identifiers.append(Self.vibeCastIdentifier)
        identifiers.append(Self.vibeLanesIdentifier)
        return identifiers
    }

    private func toolbarItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        systemSymbolName: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: label)
        item.target = self
        item.action = action
        return item
    }

    /// Builds the SwiftUI `NewTerminalToolbarButton` hosted in an
    /// `NSHostingView` and wrapped as a view-based `NSToolbarItem`. The
    /// button posts no notifications — it calls `configuration.onCreateTerminal`
    /// directly so the new tile lands on the originating detached surface
    /// instead of the primary one. The hosting view re-injects the env
    /// values that NSToolbarItem hosting otherwise drops.
    private func makeHostedTerminalToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let projects = configuration.projects
        let focusedProject = configuration.focusedProject
        let colorForProject = configuration.colorForProject
        let onCreate = configuration.onCreateTerminal

        let button = NewTerminalToolbarButton(
            projects: projects,
            focusedProject: focusedProject,
            colorForProject: colorForProject,
            onCreate: onCreate
        )

        let hostingView = NSHostingView(rootView: button)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.frame = NSRect(x: 0, y: 0, width: 32, height: 28)

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = AppStrings.Terminal.newTerminal
        item.paletteLabel = AppStrings.Terminal.newTerminal
        item.toolTip = AppStrings.Terminal.newTerminal
        item.view = hostingView
        return item
    }

    @objc private func addVibeCast(_ sender: Any?) {
        guard configuration.canAddVibeCast() else {
            toolbar?.validateVisibleItems()
            return
        }
        configuration.addVibeCast()
        toolbar?.validateVisibleItems()
    }

    @objc private func addVibeLanes(_ sender: Any?) {
        guard configuration.canAddVibeLanes() else {
            toolbar?.validateVisibleItems()
            return
        }
        configuration.addVibeLanes()
        toolbar?.validateVisibleItems()
    }

    @objc private func addAgent(_ sender: Any?) {
        guard let addAgent = configuration.addAgent, configuration.canAddAgent() else {
            toolbar?.validateVisibleItems()
            return
        }
        addAgent()
        toolbar?.validateVisibleItems()
    }

    @objc private func addBrowser(_ sender: Any?) {
        guard configuration.canAddBrowser() else {
            toolbar?.validateVisibleItems()
            return
        }
        configuration.addBrowser()
        toolbar?.validateVisibleItems()
    }
}

@MainActor
final class VibeSpaceTerminalBoardDetachedWindowManager {
    private struct WindowRecord {
        let vibespaceID: UUID?
        let surfaceID: UUID
        let window: NSWindow
        let observers: [NSObjectProtocol]
        let eventMonitors: [Any]
        let onUserClose: (() -> Void)?
        let onPlacementChanged: ((VibeSpaceTerminalBoardWindowPlacement) -> Void)?
        let toolbarCoordinator: VibeSpaceTerminalBoardWindowToolbarCoordinator?
    }

    private var windowsByID: [UUID: WindowRecord] = [:]

    func openWindow<Content: View>(
        vibespaceID: UUID?,
        surfaceID: UUID,
        title: String,
        placement: VibeSpaceTerminalBoardWindowPlacement? = nil,
        toolbarConfiguration: VibeSpaceTerminalBoardWindowToolbarConfiguration? = nil,
        onUserClose: (() -> Void)? = nil,
        onPlacementChanged: ((VibeSpaceTerminalBoardWindowPlacement) -> Void)? = nil,
        onTitleChanged: ((String) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> UUID {
        let windowID = UUID()
        let hostingController = NSHostingController(
            rootView: content()
                .frame(minWidth: 780, minHeight: 520)
                .accessibilityIdentifier("vibespace.terminal-board.detached")
        )
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        let toolbarCoordinator = toolbarConfiguration.map {
            VibeSpaceTerminalBoardWindowToolbarCoordinator(configuration: $0)
        }
        let nsToolbar = toolbarCoordinator?.makeToolbar() ?? NSToolbar()
        nsToolbar.displayMode = .iconOnly
        nsToolbar.showsBaselineSeparator = false
        window.toolbar = nsToolbar
        window.toolbarStyle = .unifiedCompact
        if let placement {
            window.setFrame(
                NSRect(
                    x: placement.frameX,
                    y: placement.frameY,
                    width: placement.frameWidth,
                    height: placement.frameHeight
                ),
                display: false
            )
        } else {
            window.setContentSize(NSSize(width: 1120, height: 720))
        }
        window.minSize = NSSize(width: 780, height: 520)
        window.title = title

        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.teardownWindow(id: windowID)
            }
        }
        let moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                onPlacementChanged?(Self.placement(for: window))
            }
        }
        let resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                onPlacementChanged?(Self.placement(for: window))
            }
        }
        let titlebarContextMenuMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self, weak window] event in
            guard
                let self,
                let window,
                event.window === window
            else {
                return event
            }

            let handled = MainActor.assumeIsolated {
                guard Self.isTitlebarEvent(event, in: window) else {
                    return false
                }
                self.showTitlebarContextMenu(
                    for: window,
                    onTitleChanged: onTitleChanged
                )
                return true
            }
            if handled {
                return nil
            }
            return event
        }
        let eventMonitors = titlebarContextMenuMonitor.map { [$0] } ?? []

        windowsByID[windowID] = WindowRecord(
            vibespaceID: vibespaceID,
            surfaceID: surfaceID,
            window: window,
            observers: [closeObserver, moveObserver, resizeObserver],
            eventMonitors: eventMonitors,
            onUserClose: onUserClose,
            onPlacementChanged: onPlacementChanged,
            toolbarCoordinator: toolbarCoordinator
        )

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return windowID
    }

    func closeWindows(for vibespaceID: UUID?) {
        let ids = windowsByID.compactMap { id, record in
            record.vibespaceID == vibespaceID ? id : nil
        }
        ids.forEach { closeWindow(id: $0, notifyUserClose: false) }
    }

    func closeAll() {
        Array(windowsByID.keys).forEach { closeWindow(id: $0, notifyUserClose: false) }
    }

    func closeAfterTransfer(id: UUID?) {
        guard let id else { return }
        closeWindow(id: id, notifyUserClose: false)
    }

    func window(id: UUID?, contains screenPoint: CGPoint) -> Bool {
        guard let id, let record = windowsByID[id] else { return false }
        return record.window.frame.contains(NSPoint(x: screenPoint.x, y: screenPoint.y))
    }

    func surfaceID(
        vibespaceID: UUID?,
        atScreenPoint screenPoint: CGPoint,
        excluding windowIDToExclude: UUID? = nil
    ) -> UUID? {
        let point = NSPoint(x: screenPoint.x, y: screenPoint.y)
        for window in NSApp.orderedWindows {
            guard
                let target = windowsByID.first(where: { id, record in
                    id != windowIDToExclude &&
                        record.vibespaceID == vibespaceID &&
                        record.window === window &&
                        record.window.frame.contains(point)
                })
            else {
                continue
            }
            target.value.window.makeKeyAndOrderFront(nil)
            return target.value.surfaceID
        }
        return nil
    }

    func windowID(forSurfaceID surfaceID: UUID, vibespaceID: UUID?) -> UUID? {
        windowsByID.first { _, record in
            record.vibespaceID == vibespaceID && record.surfaceID == surfaceID
        }?.key
    }

    func orderedSurfaceIDs(for vibespaceID: UUID?) -> [UUID] {
        var orderedSurfaceIDs: [UUID] = []
        var seenSurfaceIDs: Set<UUID> = []

        for window in NSApp.orderedWindows {
            guard let record = windowsByID.values.first(where: {
                $0.vibespaceID == vibespaceID && $0.window === window
            }) else {
                continue
            }
            orderedSurfaceIDs.append(record.surfaceID)
            seenSurfaceIDs.insert(record.surfaceID)
        }

        for record in windowsByID.values where record.vibespaceID == vibespaceID && !seenSurfaceIDs.contains(record.surfaceID) {
            orderedSurfaceIDs.append(record.surfaceID)
        }

        return orderedSurfaceIDs
    }

    func focusSurface(_ surfaceID: UUID, vibespaceID: UUID?) {
        guard let record = windowsByID.values.first(where: {
            $0.vibespaceID == vibespaceID && $0.surfaceID == surfaceID
        }) else {
            return
        }
        record.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setTitle(_ title: String, forSurfaceID surfaceID: UUID, vibespaceID: UUID?) {
        guard let record = windowsByID.values.first(where: {
            $0.vibespaceID == vibespaceID && $0.surfaceID == surfaceID
        }) else {
            return
        }
        record.window.title = title
    }

    func containsSurface(_ surfaceID: UUID, vibespaceID: UUID?) -> Bool {
        windowID(forSurfaceID: surfaceID, vibespaceID: vibespaceID) != nil
    }

    func containsManagedWindow(_ window: NSWindow) -> Bool {
        windowsByID.values.contains { $0.window === window }
    }

    /// F048-R13/R16: resolve a managed `NSWindow` (typically `NSApp.keyWindow`)
    /// to its surfaceID + vibespaceID, or nil if the window is not a managed
    /// detached board window. Used by the bulk-move keyboard shortcuts to
    /// determine which surface initiated the action.
    func surfaceContext(forWindow window: NSWindow) -> (surfaceID: UUID, vibespaceID: UUID?)? {
        guard let record = windowsByID.values.first(where: { $0.window === window }) else {
            return nil
        }
        return (record.surfaceID, record.vibespaceID)
    }

    private func closeWindow(id: UUID, notifyUserClose: Bool) {
        guard let record = windowsByID.removeValue(forKey: id) else { return }
        record.onPlacementChanged?(Self.placement(for: record.window))
        for observer in record.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        for eventMonitor in record.eventMonitors {
            NSEvent.removeMonitor(eventMonitor)
        }
        if notifyUserClose {
            record.onUserClose?()
        }
        record.window.close()
    }

    private func teardownWindow(id: UUID) {
        guard let record = windowsByID.removeValue(forKey: id) else { return }
        record.onPlacementChanged?(Self.placement(for: record.window))
        for observer in record.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        for eventMonitor in record.eventMonitors {
            NSEvent.removeMonitor(eventMonitor)
        }
        record.onUserClose?()
    }

    private func showTitlebarContextMenu(
        for window: NSWindow,
        onTitleChanged: ((String) -> Void)?
    ) {
        let actionTarget = VibeSpaceTerminalBoardWindowMenuActionTarget { [weak window] in
            Task { @MainActor in
                guard let window else { return }
                self.presentRenamePrompt(for: window, onTitleChanged: onTitleChanged)
            }
        }
        let menu = NSMenu()
        let renameItem = NSMenuItem(
            title: AppStrings.Terminal.Window.renameWindow,
            action: #selector(VibeSpaceTerminalBoardWindowMenuActionTarget.performAction(_:)),
            keyEquivalent: ""
        )
        renameItem.target = actionTarget
        menu.addItem(renameItem)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        _ = actionTarget
    }

    private func presentRenamePrompt(
        for window: NSWindow,
        onTitleChanged: ((String) -> Void)?
    ) {
        let alert = NSAlert()
        alert.messageText = AppStrings.Terminal.Window.renameWindow
        alert.informativeText = AppStrings.Terminal.Window.renameWindowPrompt
        alert.addButton(withTitle: AppStrings.Common.rename)
        alert.addButton(withTitle: AppStrings.Common.cancel)

        let titleField = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        titleField.stringValue = window.title
        alert.accessoryView = titleField

        alert.beginSheetModal(for: window) { [weak window] response in
            Task { @MainActor in
                guard response == .alertFirstButtonReturn, let window else { return }
                let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return }
                window.title = title
                onTitleChanged?(title)
            }
        }
    }

    private static func isTitlebarEvent(_ event: NSEvent, in window: NSWindow) -> Bool {
        let location = event.locationInWindow
        guard location.x >= 0, location.x <= window.frame.width else { return false }

        if let contentView = window.contentView {
            let titlebarMinY = contentView.frame.maxY
            if titlebarMinY < window.frame.height, location.y >= titlebarMinY {
                return true
            }
        }

        return location.y >= max(0, window.frame.height - 44)
    }

    private static func placement(for window: NSWindow) -> VibeSpaceTerminalBoardWindowPlacement {
        let frame = window.frame
        let screenID = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")].map {
            String(describing: $0)
        }
        return VibeSpaceTerminalBoardWindowPlacement(
            frameX: frame.origin.x,
            frameY: frame.origin.y,
            frameWidth: frame.size.width,
            frameHeight: frame.size.height,
            screenID: screenID
        )
    }

    deinit {
        MainActor.assumeIsolated { closeAll() }
    }
}

private final class VibeSpaceTerminalBoardWindowMenuActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func performAction(_ sender: Any?) {
        action()
    }
}
