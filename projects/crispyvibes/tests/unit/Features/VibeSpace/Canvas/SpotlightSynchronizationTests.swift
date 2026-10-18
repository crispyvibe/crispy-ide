import AppKit
import SwiftUI
import WebKit
import XCTest

@testable import CrispyVibes

@MainActor
final class SpotlightNavigationResolverTests: XCTestCase {
    private var container: AppContainer!
    private var projects: [AnyProjectSession] = []
    private var roots: [URL] = []

    override func setUpWithError() throws {
        container = AppContainer.makeDefault()
        for name in ["project-a", "project-b"] {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("crispy-spotlight-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            roots.append(root)
            projects.append(container.makeProjectSession(rootURL: root, vibespaceID: nil))
        }
    }

    override func tearDownWithError() throws {
        projects.forEach { $0.shutdown() }
        projects.removeAll()
        for root in roots {
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }
        roots.removeAll()
        container = nil
    }

    func testRelativeSelectionWrapsInBothDirections() throws {
        let file = SpotlightItem.file(tileID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/a.md"))
        let browser = SpotlightItem.browser(tileID: UUID(), url: URL(string: "https://example.com")!)
        let items: [SpotlightItem] = [file, browser, .vibeCast]

        let forward = try XCTUnwrap(SpotlightNavigationResolver.relativeSelection(
            offset: 1,
            currentIdentity: SpotlightNavigationIdentity.vibeCast,
            items: items
        ))
        let backward = try XCTUnwrap(SpotlightNavigationResolver.relativeSelection(
            offset: -1,
            currentIdentity: file.navigationIdentity,
            items: items
        ))

        XCTAssertEqual(forward.targetIdentity, file.navigationIdentity)
        XCTAssertEqual(forward.direction, 1)
        XCTAssertEqual(backward.targetIdentity, SpotlightNavigationIdentity.vibeCast)
        XCTAssertEqual(backward.direction, -1)
    }

    func testTargetSelectionUsesStableIdentityInsteadOfRenderedIndex() throws {
        let file = SpotlightItem.file(tileID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/a.md"))
        let target = SpotlightItem.browser(tileID: UUID(), url: URL(string: "https://example.com/target")!)
        let staleIndexReplacement = SpotlightItem.browser(tileID: UUID(), url: URL(string: "https://example.com/stale")!)
        let reordered: [SpotlightItem] = [staleIndexReplacement, .vibeCast, target, file]

        let selection = try XCTUnwrap(SpotlightNavigationResolver.selection(
            targetIdentity: target.navigationIdentity,
            currentIdentity: file.navigationIdentity,
            items: reordered
        ))

        XCTAssertEqual(selection.targetIdentity, target.navigationIdentity)
        XCTAssertEqual(selection.item.navigationIdentity, target.navigationIdentity)
    }

    func testDuplicateTerminalTabIDsRemainProjectScoped() throws {
        let sharedTabID = UUID()
        let tabA = TerminalTab(id: sharedTabID, workingDirectory: roots[0])
        let tabB = TerminalTab(id: sharedTabID, workingDirectory: roots[1])
        let itemA = SpotlightItem.terminal(project: projects[0], tab: tabA)
        let itemB = SpotlightItem.terminal(project: projects[1], tab: tabB)

        XCTAssertNotEqual(itemA.navigationIdentity, itemB.navigationIdentity)
        let selection = try XCTUnwrap(SpotlightNavigationResolver.selection(
            targetIdentity: itemB.navigationIdentity,
            currentIdentity: itemA.navigationIdentity,
            items: [itemA, itemB]
        ))
        XCTAssertEqual(selection.targetIdentity, itemB.navigationIdentity)

        let token = itemA.navigationIdentity.diagnosticToken
        XCTAssertTrue(token.contains(AppDiagnostics.pathToken(roots[0].standardizedFileURL.path)))
        XCTAssertFalse(token.contains(roots[0].standardizedFileURL.path))
    }

    func testFileAndBrowserTileIdentityUsesTileID() {
        let fileID = UUID()
        let browserID = UUID()
        let file = SpotlightItem.file(tileID: fileID, fileURL: URL(fileURLWithPath: "/tmp/a.md"))
        let browser = SpotlightItem.browser(tileID: browserID, url: URL(string: "https://example.com")!)

        XCTAssertEqual(file.navigationIdentity, .file(tileID: fileID))
        XCTAssertEqual(browser.navigationIdentity, .browser(tileID: browserID))
    }

    func testMissingOrCurrentTargetsAreNoOps() {
        let file = SpotlightItem.file(tileID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/a.md"))
        let items = [file]

        XCTAssertNil(SpotlightNavigationResolver.relativeSelection(
            offset: 1,
            currentIdentity: .vibeCast,
            items: items
        ))
        XCTAssertNil(SpotlightNavigationResolver.selection(
            targetIdentity: .browser(tileID: UUID()),
            currentIdentity: file.navigationIdentity,
            items: items
        ))
        XCTAssertNil(SpotlightNavigationResolver.selection(
            targetIdentity: file.navigationIdentity,
            currentIdentity: file.navigationIdentity,
            items: items
        ))
    }

    func testPersistentStateUsesNormalizedProjectScopeAndNilScopesNeverAlias() {
        let tabID = UUID()
        let viewModel = container.makeTerminalViewModel()
        let normalized = persistentState(
            id: UUID(),
            viewModel: viewModel,
            tabID: tabID,
            root: roots[0].appendingPathComponent("..", isDirectory: true).appendingPathComponent("project-a")
        )
        let item = SpotlightItem.terminal(
            project: projects[0],
            tab: TerminalTab(id: tabID, workingDirectory: roots[0])
        )
        let unscopedA = persistentState(id: UUID(), viewModel: viewModel, tabID: tabID, root: nil)
        let unscopedB = persistentState(id: UUID(), viewModel: viewModel, tabID: tabID, root: nil)

        XCTAssertEqual(normalized.navigationIdentity, item.navigationIdentity)
        XCTAssertNotEqual(unscopedA.navigationIdentity, unscopedB.navigationIdentity)
        XCTAssertNotEqual(unscopedA.navigationIdentity, item.navigationIdentity)
    }

    func testUnscopedPersistentCurrentItemDoesNotInventProjectMatchOrEnableNavigation() throws {
        let sharedTabID = UUID()
        let viewModel = container.makeTerminalViewModel()
        let unscoped = persistentState(
            id: UUID(),
            viewModel: viewModel,
            tabID: sharedTabID,
            root: nil
        )
        let projectItem = SpotlightItem.terminal(
            project: projects[0],
            tab: TerminalTab(id: sharedTabID, workingDirectory: roots[0])
        )
        let items: [SpotlightItem] = [projectItem, .vibeCast]

        XCTAssertFalse(SpotlightNavigationResolver.hasNavigableCurrentItem(
            currentIdentity: unscoped.navigationIdentity,
            items: items
        ))
        XCTAssertFalse(SpotlightNavigationResolver.carouselNavigationEnabled(
            for: unscoped,
            items: items
        ))
        XCTAssertNil(SpotlightNavigationResolver.relativeSelection(
            offset: 1,
            currentIdentity: try XCTUnwrap(unscoped.navigationIdentity),
            items: items
        ))
    }

    private func persistentState(
        id: UUID,
        viewModel: TerminalViewModel,
        tabID: UUID,
        root: URL?
    ) -> TerminalSpotlightState {
        TerminalSpotlightState(
            id: id,
            source: .persistent(terminalViewModel: viewModel, tabID: tabID),
            title: "Terminal",
            accentColor: nil,
            workingDirectoryURL: roots[0],
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            isTemporary: false,
            owningProjectRootURL: root
        )
    }
}

@MainActor
final class TerminalSpotlightCoordinatorSynchronizationTests: XCTestCase {
    private var coordinator: TerminalSpotlightCoordinator!

    override func setUp() {
        coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
    }

    override func tearDown() {
        coordinator.dismiss(animated: false)
        coordinator = nil
    }

    func testBeginPublishesDirectionAndEntryOffsetBeforeTargetThenCommitsNextTurn() throws {
        let a = makeState(source: .vibeCast, title: "A")
        let b = makeState(source: .vibeLanes, title: "B")
        coordinator.setSpotlight(a, animated: false)
        drainMainTurn()
        let selection = SpotlightNavigationSelection(
            item: .vibeLanes,
            sourceIdentity: .vibeCast,
            targetIdentity: .vibeLanes,
            direction: 1
        )

        let transaction = coordinator.beginCarouselSwitch(selection)

        XCTAssertEqual(coordinator.swipeDirection, .trailing)
        XCTAssertEqual(coordinator.swipeOffset, 200)
        XCTAssertEqual(coordinator.spotlight?.id, a.id)
        XCTAssertEqual(coordinator.activeSwitchGeneration, transaction.generation)

        var focused: [UUID] = []
        XCTAssertTrue(coordinator.setSpotlight(
            b,
            animated: false,
            switchTransaction: transaction,
            onFocusSpotlight: { focused.append($0.id) }
        ))
        XCTAssertEqual(coordinator.spotlight?.id, b.id)
        XCTAssertTrue(focused.isEmpty)

        drainMainTurn()
        XCTAssertEqual(focused, [b.id])
        XCTAssertEqual(coordinator.swipeOffset, 0)
        XCTAssertEqual(coordinator.activeSwitchGeneration, transaction.generation)

        drainCarouselCompletion()
        XCTAssertNil(coordinator.activeSwitchGeneration)
        XCTAssertEqual(coordinator.swipeDirection, .none)
        XCTAssertEqual(coordinator.swipeOffset, 0)
    }

    func testRapidAToBToCSuppressesStaleCompletionAndFocus() {
        let surfaceID = UUID()
        let rootB = URL(fileURLWithPath: "/tmp/spotlight-project-b")
        let rootC = URL(fileURLWithPath: "/tmp/spotlight-project-c")
        let a = makeState(source: .vibeCast, title: "A", surfaceID: surfaceID)
        let bID = UUID()
        let cID = UUID()
        let b = makeState(
            source: .browser(tileID: bID, url: URL(string: "https://b.example")!),
            title: "B",
            root: rootB,
            surfaceID: surfaceID
        )
        let c = makeState(
            source: .browser(tileID: cID, url: URL(string: "https://c.example")!),
            title: "C",
            root: rootC,
            surfaceID: surfaceID
        )
        coordinator.setSpotlight(a, animated: false)
        drainMainTurn()
        var focused: [UUID] = []

        let ab = coordinator.beginCarouselSwitch(SpotlightNavigationSelection(
            item: .browser(tileID: bID, url: URL(string: "https://b.example")!),
            sourceIdentity: .vibeCast,
            targetIdentity: .browser(tileID: bID),
            direction: 1
        ))
        XCTAssertTrue(coordinator.setSpotlight(
            b,
            animated: false,
            switchTransaction: ab,
            onFocusSpotlight: { focused.append($0.id) }
        ))
        let bc = coordinator.beginCarouselSwitch(SpotlightNavigationSelection(
            item: .browser(tileID: cID, url: URL(string: "https://c.example")!),
            sourceIdentity: .browser(tileID: bID),
            targetIdentity: .browser(tileID: cID),
            direction: 1
        ))
        XCTAssertTrue(coordinator.setSpotlight(
            c,
            animated: false,
            switchTransaction: bc,
            onFocusSpotlight: { focused.append($0.id) }
        ))

        drainMainTurn()
        drainCarouselCompletion()

        XCTAssertEqual(focused, [c.id])
        XCTAssertEqual(coordinator.spotlight?.id, c.id)
        XCTAssertEqual(coordinator.spotlight?.surfaceID, surfaceID)
        XCTAssertEqual(coordinator.spotlight?.owningProjectRootURL, rootC.standardizedFileURL)
        XCTAssertNil(coordinator.activeSwitchGeneration)
        XCTAssertEqual(coordinator.swipeOffset, 0)
    }

    func testDirectPresentationCancelsSwitchCompletionAndQueuedFocus() {
        let a = makeState(source: .vibeCast, title: "A")
        let b = makeState(source: .vibeLanes, title: "B")
        let cID = UUID()
        let c = makeState(
            source: .browser(tileID: cID, url: URL(string: "https://c.example")!),
            title: "C",
            surfaceID: UUID()
        )
        coordinator.setSpotlight(a, animated: false)
        drainMainTurn()
        var focused: [UUID] = []
        let transaction = coordinator.beginCarouselSwitch(SpotlightNavigationSelection(
            item: .vibeLanes,
            sourceIdentity: .vibeCast,
            targetIdentity: .vibeLanes,
            direction: -1
        ))
        XCTAssertEqual(coordinator.swipeDirection, .leading)
        XCTAssertEqual(coordinator.swipeOffset, -200)
        XCTAssertTrue(coordinator.setSpotlight(
            b,
            animated: false,
            switchTransaction: transaction,
            onFocusSpotlight: { focused.append($0.id) }
        ))

        XCTAssertTrue(coordinator.setSpotlight(
            c,
            animated: false,
            onFocusSpotlight: { focused.append($0.id) }
        ))
        XCTAssertNil(coordinator.activeSwitchGeneration)
        XCTAssertEqual(coordinator.swipeDirection, .none)
        XCTAssertEqual(coordinator.swipeOffset, 0)

        drainMainTurn()
        drainCarouselCompletion()
        XCTAssertEqual(focused, [c.id])
        XCTAssertEqual(coordinator.spotlight?.id, c.id)
    }

    func testDismissResetsGenerationDirectionAndOffset() {
        let a = makeState(source: .vibeCast, title: "A")
        coordinator.setSpotlight(a, animated: false)
        drainMainTurn()
        _ = coordinator.beginCarouselSwitch(SpotlightNavigationSelection(
            item: .vibeLanes,
            sourceIdentity: .vibeCast,
            targetIdentity: .vibeLanes,
            direction: 1
        ))

        coordinator.dismiss(animated: false)

        XCTAssertNil(coordinator.spotlight)
        XCTAssertNil(coordinator.activeSwitchGeneration)
        XCTAssertEqual(coordinator.swipeDirection, .none)
        XCTAssertEqual(coordinator.swipeOffset, 0)
        XCTAssertEqual(coordinator.tabPageOffset, 0)
    }

    private func makeState(
        source: TerminalSpotlightState.Source,
        title: String,
        root: URL? = nil,
        surfaceID: UUID? = nil
    ) -> TerminalSpotlightState {
        TerminalSpotlightState(
            id: UUID(),
            source: source,
            title: title,
            accentColor: nil,
            workingDirectoryURL: root ?? URL(fileURLWithPath: "/tmp"),
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            isTemporary: false,
            owningProjectRootURL: root,
            surfaceID: surfaceID
        )
    }

    private func drainMainTurn() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    }

    private func drainCarouselCompletion() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
    }
}

@MainActor
final class SpotlightMountedCardSynchronizationTests: XCTestCase {
    private final class LifecycleCounter {
        var installs = 0
        var removals = 0
    }

    private var window: NSWindow?

    override func tearDown() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        super.tearDown()
    }

    func testOneTargetSwitchUpdatesMountedCardWithoutRemountingOverlayLifecycle() throws {
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        let ids = (0..<6).map { _ in UUID() }
        let items = ids.enumerated().map { index, id in
            SpotlightItem.browser(tileID: id, url: URL(string: "https://\(index).example")!)
        }
        let a = makeBrowserState(tileID: ids[0], title: "sentinel-A")
        let b = makeBrowserState(tileID: ids[4], title: "sentinel-B")
        coordinator.setSpotlight(a, animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        let lifecycle = LifecycleCounter()
        let root = TerminalSpotlightOverlayHostView(
            coordinator: coordinator,
            items: items,
            projectColorTag: { _ in nil },
            onDismiss: {},
            onInstallScrollMonitor: { lifecycle.installs += 1 },
            onRemoveScrollMonitor: { lifecycle.removals += 1 },
            onSwitchSpotlight: { _ in },
            onSelectSpotlight: { _ in },
            onReorderTerminalTab: { _, _, _ in false },
            cardContent: { SpotlightCardProbe(state: $0) }
        )
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1100, height: 760)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        self.window = window
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(lifecycle.installs, 1)

        let transaction = coordinator.beginCarouselSwitch(SpotlightNavigationSelection(
            item: items[4],
            sourceIdentity: items[0].navigationIdentity,
            targetIdentity: items[4].navigationIdentity,
            direction: 1
        ))
        XCTAssertTrue(coordinator.setSpotlight(b, animated: false, switchTransaction: transaction))
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        hostingView.layoutSubtreeIfNeeded()

        let probe = try XCTUnwrap(descendant(in: hostingView, identifier: SpotlightCardProbeView.identifier) as? SpotlightCardProbeView)
        XCTAssertEqual(probe.renderedSentinel, "sentinel-B")
        XCTAssertEqual(probe.accessibilityValue() as? String, items[4].navigationIdentity.diagnosticToken)
        XCTAssertEqual(coordinator.spotlight?.navigationIdentity, items[4].navigationIdentity)
        XCTAssertEqual(lifecycle.installs, 1)
        XCTAssertEqual(lifecycle.removals, 0)
    }

    func testMissingCurrentIdentityHidesMountedNavigationAndDoesNotInstallMonitor() throws {
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        let liveA = UUID()
        let liveB = UUID()
        let missing = UUID()
        let items = [
            SpotlightItem.browser(tileID: liveA, url: URL(string: "https://a.example")!),
            SpotlightItem.browser(tileID: liveB, url: URL(string: "https://b.example")!),
        ]
        coordinator.setSpotlight(makeBrowserState(tileID: missing, title: "missing"), animated: false)
        let lifecycle = LifecycleCounter()
        let root = TerminalSpotlightOverlayHostView(
            coordinator: coordinator,
            items: items,
            projectColorTag: { _ in nil },
            onDismiss: {},
            onInstallScrollMonitor: { lifecycle.installs += 1 },
            onRemoveScrollMonitor: { lifecycle.removals += 1 },
            onSwitchSpotlight: { _ in XCTFail("Dead carousel must not navigate") },
            onSelectSpotlight: { _ in XCTFail("Hidden strip must not select") },
            onReorderTerminalTab: { _, _, _ in false },
            cardContent: { SpotlightCardProbe(state: $0) }
        )
        let hosting = mount(root)

        XCTAssertEqual(lifecycle.installs, 0)
        XCTAssertNil(descendant(in: hosting, identifier: "spotlight.navigation.previous"))
        XCTAssertNil(descendant(in: hosting, identifier: "spotlight.navigation.next"))
        XCTAssertNil(descendant(in: hosting, identifier: "spotlight.navigation.tab-strip"))
    }

    func testMountedRealBrowserHostsSwitchForwardAndReverseWithoutStaleAttachment() throws {
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        let aID = UUID()
        let bID = UUID()
        let itemA = SpotlightItem.browser(tileID: aID, url: URL(string: "https://a.example")!)
        let itemB = SpotlightItem.browser(tileID: bID, url: URL(string: "https://b.example")!)
        let stateA = makeBrowserState(tileID: aID, title: "browser-A")
        let stateB = makeBrowserState(tileID: bID, title: "browser-B")
        let viewModelA = BrowserPanelViewModel()
        let viewModelB = BrowserPanelViewModel()
        coordinator.setSpotlight(stateA, animated: false)
        let root = TerminalSpotlightOverlayHostView(
            coordinator: coordinator,
            items: [itemA, itemB],
            projectColorTag: { _ in nil },
            onDismiss: {},
            onInstallScrollMonitor: {},
            onRemoveScrollMonitor: {},
            onSwitchSpotlight: { _ in },
            onSelectSpotlight: { _ in },
            onReorderTerminalTab: { _, _, _ in false },
            cardContent: { spotlight in
                let viewModel: BrowserPanelViewModel
                if case let .browser(tileID, _) = spotlight.source, tileID == bID {
                    viewModel = viewModelB
                } else {
                    viewModel = viewModelA
                }
                return BrowserContentView(viewModel: viewModel)
            }
        )
        let hosting = mount(root)
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(coordinator.spotlight?.navigationIdentity, itemA.navigationIdentity)
        XCTAssertNotNil(viewModelA.webView.superview)
        XCTAssertNil(viewModelB.webView.superview)

        let forward = coordinator.beginCarouselSwitch(SpotlightNavigationSelection(
            item: itemB,
            sourceIdentity: itemA.navigationIdentity,
            targetIdentity: itemB.navigationIdentity,
            direction: 1
        ))
        XCTAssertTrue(coordinator.setSpotlight(stateB, animated: false, switchTransaction: forward))
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(coordinator.spotlight?.navigationIdentity, itemB.navigationIdentity)
        XCTAssertNil(viewModelA.webView.superview)
        XCTAssertNotNil(viewModelB.webView.superview)

        let reverse = coordinator.beginCarouselSwitch(SpotlightNavigationSelection(
            item: itemA,
            sourceIdentity: itemB.navigationIdentity,
            targetIdentity: itemA.navigationIdentity,
            direction: -1
        ))
        XCTAssertTrue(coordinator.setSpotlight(stateA, animated: false, switchTransaction: reverse))
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(coordinator.spotlight?.navigationIdentity, itemA.navigationIdentity)
        XCTAssertNotNil(viewModelA.webView.superview)
        XCTAssertNil(viewModelB.webView.superview)
    }

    func testMountedShelfKeepsStableRootWhileSelectionChangesByIdentity() throws {
        let coordinator = TerminalSpotlightCoordinator(diagnosticsSnapshot: TerminalDiagnosticsSnapshot())
        let firstID = UUID()
        let secondID = UUID()
        let first = SpotlightItem.browser(tileID: firstID, url: URL(string: "https://first.example")!)
        let second = SpotlightItem.browser(tileID: secondID, url: URL(string: "https://second.example")!)
        let firstState = makeBrowserState(tileID: firstID, title: "first")
        let secondState = makeBrowserState(tileID: secondID, title: "second")
        coordinator.setSpotlight(firstState, animated: false)
        let root = TerminalSpotlightOverlayHostView(
            coordinator: coordinator,
            items: [first, second],
            projectColorTag: { _ in nil },
            onDismiss: {},
            onInstallScrollMonitor: {},
            onRemoveScrollMonitor: {},
            onSwitchSpotlight: { _ in },
            onSelectSpotlight: { _ in },
            onReorderTerminalTab: { _, _, _ in false },
            cardContent: { SpotlightCardProbe(state: $0) }
        )
        let hosting = mount(root)
        let shelf = try XCTUnwrap(firstDescendant(of: NSScrollView.self, in: hosting))
        let originalFrame = shelf.frame
        let transaction = coordinator.beginCarouselSwitch(SpotlightNavigationSelection(
            item: second,
            sourceIdentity: first.navigationIdentity,
            targetIdentity: second.navigationIdentity,
            direction: 1
        ))
        XCTAssertTrue(coordinator.setSpotlight(secondState, animated: false, switchTransaction: transaction))
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        hosting.layoutSubtreeIfNeeded()

        let updatedShelf = try XCTUnwrap(firstDescendant(of: NSScrollView.self, in: hosting))
        XCTAssertTrue(updatedShelf === shelf)
        XCTAssertEqual(updatedShelf.frame, originalFrame)
        XCTAssertEqual(coordinator.spotlight?.navigationIdentity, second.navigationIdentity)
    }

    private func mount<V: View>(_ root: V) -> NSHostingView<V> {
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1100, height: 760)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        self.window = window
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }

    private func makeBrowserState(tileID: UUID, title: String) -> TerminalSpotlightState {
        TerminalSpotlightState(
            id: UUID(),
            source: .browser(tileID: tileID, url: URL(string: "https://example.com")!),
            title: title,
            accentColor: nil,
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            isTemporary: false,
            owningProjectRootURL: nil
        )
    }

    private func firstDescendant<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = firstDescendant(of: type, in: subview) { return match }
        }
        return nil
    }

    private func descendant(in view: NSView, identifier: String) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for subview in view.subviews {
            if let match = descendant(in: subview, identifier: identifier) { return match }
        }
        return nil
    }

    private func sourceFileURL(named name: String) -> URL? {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let source = candidate.appendingPathComponent(
                "crispyvibes/Features/VibeSpace/Canvas/Views/\(name)"
            )
            if FileManager.default.fileExists(atPath: source.path) { return source }
            candidate.deleteLastPathComponent()
        }
        return nil
    }
}

private struct SpotlightCardProbe: NSViewRepresentable {
    let state: TerminalSpotlightState

    func makeNSView(context: Context) -> SpotlightCardProbeView {
        SpotlightCardProbeView()
    }

    func updateNSView(_ nsView: SpotlightCardProbeView, context: Context) {
        nsView.renderedSentinel = state.title
        nsView.setAccessibilityValue(state.navigationIdentity?.diagnosticToken)
    }
}

private final class SpotlightCardProbeView: NSView {
    static let identifier = "spotlight-card-probe"
    var renderedSentinel = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier(Self.identifier)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
