import AppKit
import SwiftUI
import XCTest

@testable import CrispyVibes

@MainActor
final class SpotlightPresentationTests: XCTestCase {
    private var windows: [NSWindow] = []
    private var container: AppContainer!

    override func setUp() {
        container = AppContainer.makeDefault()
    }

    override func tearDown() {
        windows.forEach {
            $0.orderOut(nil)
            $0.contentView = nil
        }
        windows.removeAll()
        container = nil
        super.tearDown()
    }

    func testShelfAndOverviewMountCompletePersistentMembersAndSearch() throws {
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        let first = SpotlightItem.file(tileID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/one.md"))
        let second = SpotlightItem.browser(tileID: UUID(), url: URL(string: "https://example.com/path")!)
        let items = [first, second]
        let snapshot = SpotlightLayoutSnapshot(positions: [
            SpotlightPositionSnapshot(members: [first.persistentID, second.persistentID])
        ])
        coordinator.setSpotlight(state(for: first), animated: false)

        let root = TerminalSpotlightOverlayHostView(
            coordinator: coordinator,
            items: items,
            layoutSnapshot: snapshot,
            hostID: "test-host",
            layoutGeneration: 1,
            projectColorTag: { _ in nil },
            onDismiss: {},
            onInstallScrollMonitor: {},
            onRemoveScrollMonitor: {},
            onSwitchSpotlight: { _ in },
            onSelectSpotlight: { _ in },
            onCommitLayout: { _ in },
            resolveCurrentLayout: { snapshot },
            onReconcile: {},
            stateForItem: state(for:),
            positionCardContent: { presentation in
                Text("members:\(presentation.members.count)")
                    .accessibilityIdentifier("spotlight.presentation.member-count")
            }
        )
        let hosting = mount(root)
        XCTAssertNotNil(hosting.window)
        let shelfScrollView = try XCTUnwrap(firstDescendant(of: NSScrollView.self, in: hosting))
        XCTAssertNotNil(shelfScrollView.documentView)
        XCTAssertEqual(snapshot.flattenedMembers, [first.persistentID, second.persistentID])
        XCTAssertFalse(first.persistentID.safeToken.contains("/tmp/one.md"))

        let initialTextFieldCount = descendants(of: NSTextField.self, in: hosting).count
        coordinator.presentOverview()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        hosting.layoutSubtreeIfNeeded()

        XCTAssertTrue(coordinator.isOverviewPresented)
        XCTAssertGreaterThan(descendants(of: NSTextField.self, in: hosting).count, initialTextFieldCount)
        XCTAssertTrue(coordinator.isOverviewPresented)
        coordinator.dismiss(animated: false)
    }

    func testShelfActivityAnimationUsesLiveStateWithoutChangingMountedGeometry() throws {
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        let item = SpotlightItem.file(tileID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/activity.md"))
        let activity = TerminalTabActivityState(id: UUID())
        let metadata = SpotlightItemMetadata(
            item: item,
            title: "Activity",
            secondary: "Project",
            group: "Project",
            iconName: "terminal",
            accentColor: .orange,
            activityState: activity
        )
        let position = SpotlightPositionSnapshot(members: [item.persistentID])
        let shelf = SpotlightTabShelf(
            coordinator: coordinator,
            catalog: SpotlightMetadataCatalog([metadata]),
            snapshot: SpotlightLayoutSnapshot(positions: [position]),
            hostID: "activity-host",
            generation: 1,
            currentID: item.persistentID,
            focusedID: item.persistentID,
            onSelect: { _ in },
            onCommit: { _ in },
            resolveCurrentLayout: { SpotlightLayoutSnapshot(positions: [position]) },
            onShowAll: {}
        )
        let hosting = mount(shelf)
        let scrollView = try XCTUnwrap(firstDescendant(of: NSScrollView.self, in: hosting))
        let documentView = try XCTUnwrap(scrollView.documentView)
        let shelfFrame = scrollView.frame
        let documentFrame = documentView.frame
        let fittingSize = hosting.fittingSize

        XCTAssertTrue(activity.update(isActive: true))
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        hosting.layoutSubtreeIfNeeded()
        let updatedScrollView = try XCTUnwrap(firstDescendant(of: NSScrollView.self, in: hosting))
        XCTAssertTrue(updatedScrollView === scrollView)
        XCTAssertTrue(updatedScrollView.documentView === documentView)
        XCTAssertEqual(updatedScrollView.frame, shelfFrame)
        XCTAssertEqual(documentView.frame, documentFrame)
        XCTAssertEqual(hosting.fittingSize, fittingSize)
        XCTAssertTrue(activity.isActive)
    }

    func testComboCardMountsOneStableNativeSplitAndFocusedSharedHeader() {
        let first = state(for: .file(tileID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/one.md")))
        let second = state(for: .browser(tileID: UUID(), url: URL(string: "https://example.com")!))
        let themeManager = CrispyVibesThemeManager(
            defaults: UserDefaults(suiteName: "spotlight-presentation-\(UUID())")!
        )
        let card = TerminalSpotlightCardView(
            spotlight: first,
            onDismiss: {},
            onPin: nil,
            pinAccessibilityLabel: nil,
            shortcutDefinitions: [],
            onShortcutSelected: nil,
            onManageShortcutsRequested: nil,
            onSendSignal: nil,
            onRenamePersistentTab: { _, _, _ in },
            comboMembers: [first, second],
            comboOrientation: .sideBySide,
            onFocusMember: { _ in },
            onToggleComboOrientation: {},
            spotlightContent: { state, _ in Text(state.title) },
            inputBarContent: { _, _, _ in EmptyView() }
        )
        let hosting = mount(card.environmentObject(themeManager))

        let split = firstDescendant(of: TrackingSplitView.self, in: hosting)
        XCTAssertNotNil(split)
        XCTAssertEqual(split?.arrangedSubviews.count, 2)
        XCTAssertEqual(split?.accessibilityIdentifier(), "spotlight.combo.split")
    }

    func testComboFocusAndOrientationUpdateWithoutReplacingSplitOrHostingRoots() throws {
        let first = state(for: .browser(tileID: UUID(), url: URL(string: "https://one.example")!))
        let second = state(for: .browser(tileID: UUID(), url: URL(string: "https://two.example")!))
        let model = SpotlightComboMountModel(first: first, second: second)
        let themeManager = CrispyVibesThemeManager(
            defaults: UserDefaults(suiteName: "spotlight-combo-stability-\(UUID())")!
        )
        let hosting = mount(SpotlightComboMountHarness(model: model).environmentObject(themeManager))
        let split = try XCTUnwrap(firstDescendant(of: TrackingSplitView.self, in: hosting))
        let roots = split.arrangedSubviews
        XCTAssertTrue(split.isVertical)

        model.focused = second
        model.orientation = .stacked
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        hosting.layoutSubtreeIfNeeded()

        let updatedSplit = try XCTUnwrap(firstDescendant(of: TrackingSplitView.self, in: hosting))
        XCTAssertTrue(updatedSplit === split)
        XCTAssertEqual(updatedSplit.arrangedSubviews.count, 2)
        XCTAssertTrue(updatedSplit.arrangedSubviews[0] === roots[0])
        XCTAssertTrue(updatedSplit.arrangedSubviews[1] === roots[1])
        XCTAssertFalse(updatedSplit.isVertical)
        XCTAssertEqual(model.focused.navigationIdentity, second.navigationIdentity)
    }

    func testTerminalComboCompanionSelectionHasOneOwnerAndKeepsNativeRootsStable() throws {
        let viewModel = container.makeTerminalViewModel()
        defer { viewModel.shutdown() }
        let root = URL(fileURLWithPath: "/tmp/spotlight-terminal-combo")
        viewModel.createTab(directoryURL: root, startImmediately: false)
        viewModel.createTab(directoryURL: root, startImmediately: false)
        let tabs = viewModel.tabs
        XCTAssertEqual(tabs.count, 2)
        let surfaceID = UUID()
        let first = TerminalSpotlightState(
            id: UUID(),
            source: .persistent(terminalViewModel: viewModel, tabID: tabs[0].id),
            title: "First Terminal",
            accentColor: nil,
            workingDirectoryURL: root,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            isTemporary: false,
            owningProjectRootURL: root,
            surfaceID: surfaceID
        )
        let second = TerminalSpotlightState(
            id: UUID(),
            source: .persistent(terminalViewModel: viewModel, tabID: tabs[1].id),
            title: "Second Terminal",
            accentColor: nil,
            workingDirectoryURL: root,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            isTemporary: false,
            owningProjectRootURL: root,
            surfaceID: surfaceID
        )
        let model = SpotlightTerminalComboInteractionModel(first: first, second: second)
        let themeManager = CrispyVibesThemeManager(
            defaults: UserDefaults(suiteName: "spotlight-terminal-interaction-\(UUID())")!
        )
        let hosting = mount(
            SpotlightTerminalComboInteractionHarness(model: model)
                .environmentObject(themeManager)
        )
        let split = try XCTUnwrap(firstDescendant(of: TrackingSplitView.self, in: hosting))
        let nativeRoots = split.arrangedSubviews
        let companionButton = try XCTUnwrap(
            descendants(of: NSButton.self, in: hosting).first {
                $0.identifier?.rawValue == "terminal-combo-probe-\(second.id.uuidString)"
            }
        )

        companionButton.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(model.transitionRequests, 1)
        XCTAssertEqual(model.focusRequests, 1)
        XCTAssertEqual(model.focusedActivations, 0)
        XCTAssertEqual(model.focused.id, second.id)
        XCTAssertEqual(model.focused.surfaceID, surfaceID)
        XCTAssertEqual(first.id, model.first.id)
        XCTAssertEqual(second.id, model.second.id)
        let updatedSplit = try XCTUnwrap(firstDescendant(of: TrackingSplitView.self, in: hosting))
        XCTAssertTrue(updatedSplit === split)
        XCTAssertTrue(updatedSplit.arrangedSubviews[0] === nativeRoots[0])
        XCTAssertTrue(updatedSplit.arrangedSubviews[1] === nativeRoots[1])

        let focusedButton = try XCTUnwrap(
            descendants(of: NSButton.self, in: hosting).first {
                $0.identifier?.rawValue == "terminal-combo-probe-\(second.id.uuidString)"
            }
        )
        focusedButton.performClick(nil)
        XCTAssertEqual(model.transitionRequests, 1)
        XCTAssertEqual(model.focusRequests, 1)
        XCTAssertEqual(model.focusedActivations, 1)
        XCTAssertEqual(model.focused.id, second.id)
        XCTAssertEqual(model.focused.surfaceID, surfaceID)
    }

    private func state(for item: SpotlightItem) -> TerminalSpotlightState {
        switch item {
        case let .file(tileID, url):
            let group = container.makeEditorGroupStore(bufferStore: DocumentBufferStore())
            return TerminalSpotlightState(
                id: UUID(), source: .file(tileID: tileID, fileURL: url, group: group),
                title: url.lastPathComponent, accentColor: nil,
                workingDirectoryURL: url.deletingLastPathComponent(),
                onSplitTerminalRequested: nil, onTemporaryTerminalRequested: nil,
                isTemporary: false, owningProjectRootURL: nil
            )
        case let .browser(tileID, url):
            return TerminalSpotlightState(
                id: UUID(), source: .browser(tileID: tileID, url: url),
                title: url.host ?? "Browser", accentColor: nil,
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                onSplitTerminalRequested: nil, onTemporaryTerminalRequested: nil,
                isTemporary: false, owningProjectRootURL: nil
            )
        case .terminal, .standaloneTerminal, .vibeCast, .vibeLanes, .acp:
            preconditionFailure("Unused test item")
        }
    }

    private func mount<V: View>(_ root: V) -> NSHostingView<V> {
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 760)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        windows.append(window)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func firstDescendant<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = firstDescendant(of: type, in: subview) { return match }
        }
        return nil
    }

    private func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
        var result: [T] = []
        if let match = view as? T { result.append(match) }
        for subview in view.subviews {
            result.append(contentsOf: descendants(of: type, in: subview))
        }
        return result
    }

}


@MainActor
private final class SpotlightTerminalComboInteractionModel: ObservableObject {
    let first: TerminalSpotlightState
    let second: TerminalSpotlightState
    @Published var focused: TerminalSpotlightState
    private(set) var transitionRequests = 0
    private(set) var focusRequests = 0
    private(set) var focusedActivations = 0

    init(first: TerminalSpotlightState, second: TerminalSpotlightState) {
        self.first = first
        self.second = second
        focused = first
    }

    func requestFocus(_ identity: SpotlightNavigationIdentity) {
        transitionRequests += 1
        guard let target = [first, second].first(where: { $0.navigationIdentity == identity }) else { return }
        focused = target
        focusRequests += 1
    }

    func activateFocused(_ member: TerminalSpotlightState) {
        guard member.id == focused.id else { return }
        focusedActivations += 1
    }
}

@MainActor
private struct SpotlightTerminalComboInteractionHarness: View {
    @ObservedObject var model: SpotlightTerminalComboInteractionModel

    var body: some View {
        TerminalSpotlightCardView(
            spotlight: model.focused,
            onDismiss: {},
            onPin: nil,
            pinAccessibilityLabel: nil,
            shortcutDefinitions: [],
            onShortcutSelected: nil,
            onManageShortcutsRequested: nil,
            onSendSignal: nil,
            onRenamePersistentTab: { _, _, _ in },
            comboMembers: [model.first, model.second],
            comboOrientation: .sideBySide,
            onFocusMember: model.requestFocus,
            onToggleComboOrientation: {},
            spotlightContent: { member, interaction in
                SpotlightTerminalComboInteractionProbe(
                    member: member,
                    interaction: interaction,
                    onFocusedActivation: { model.activateFocused(member) }
                )
            },
            inputBarContent: { _, _, _ in EmptyView() }
        )
    }
}

@MainActor
private struct SpotlightTerminalComboInteractionProbe: NSViewRepresentable {
    let member: TerminalSpotlightState
    let interaction: SpotlightMemberInteractionContext
    let onFocusedActivation: () -> Void

    @MainActor
    final class Coordinator: NSObject {
        var interaction: SpotlightMemberInteractionContext?
        var onFocusedActivation: (() -> Void)?

        @objc func selectMember() {
            interaction?.handleTerminalSelection {
                onFocusedActivation?()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: member.title, target: context.coordinator, action: #selector(Coordinator.selectMember))
        button.identifier = NSUserInterfaceItemIdentifier("terminal-combo-probe-\(member.id.uuidString)")
        updateCoordinator(context.coordinator)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title = member.title
        updateCoordinator(context.coordinator)
    }

    private func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.interaction = interaction
        coordinator.onFocusedActivation = onFocusedActivation
    }
}

@MainActor
private final class SpotlightComboMountModel: ObservableObject {
    let first: TerminalSpotlightState
    let second: TerminalSpotlightState
    @Published var focused: TerminalSpotlightState
    @Published var orientation: SpotlightComboOrientation = .sideBySide

    init(first: TerminalSpotlightState, second: TerminalSpotlightState) {
        self.first = first
        self.second = second
        focused = first
    }
}

@MainActor
private struct SpotlightComboMountHarness: View {
    @ObservedObject var model: SpotlightComboMountModel

    var body: some View {
        TerminalSpotlightCardView(
            spotlight: model.focused,
            onDismiss: {},
            onPin: nil,
            pinAccessibilityLabel: nil,
            shortcutDefinitions: [],
            onShortcutSelected: nil,
            onManageShortcutsRequested: nil,
            onSendSignal: nil,
            onRenamePersistentTab: { _, _, _ in },
            comboMembers: [model.first, model.second],
            comboOrientation: model.orientation,
            onFocusMember: { _ in },
            onToggleComboOrientation: {},
            spotlightContent: { state, _ in Text(state.title) },
            inputBarContent: { _, _, _ in EmptyView() }
        )
    }
}
