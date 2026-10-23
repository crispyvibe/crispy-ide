import AppKit
import Combine
import SwiftUI
import WebKit
import XCTest

@testable import CrispyVibes

private actor SynchronizationFileContentProvider: FileContentProviding {
    private let contentByPath: [String: Data]

    init(contentByPath: [String: Data]) {
        self.contentByPath = contentByPath
    }

    func readFile(at path: String) async throws -> Data {
        guard let data = contentByPath[path] else { throw CocoaError(.fileReadNoSuchFile) }
        return data
    }

    func writeFile(at path: String, contents: Data) async throws {}
}

@MainActor
final class ContentViewerGroupReconciliationTests: XCTestCase {
    private final class CountBox {
        var value = 0
    }

    private var container: AppContainer!
    private var group: EditorGroupStore!
    private var root: URL!
    private var firstURL: URL!
    private var secondURL: URL!
    private var firstProvider: SynchronizationFileContentProvider!
    private var secondProvider: SynchronizationFileContentProvider!

    override func setUpWithError() throws {
        container = AppContainer.makeDefault()
        group = container.makeEditorGroupStore(bufferStore: DocumentBufferStore())
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("crispy-content-sync-\(UUID().uuidString)", isDirectory: true)
        firstURL = root.appendingPathComponent("project-a/A.md")
        secondURL = root.appendingPathComponent("project-b/B.md")
        try FileManager.default.createDirectory(
            at: firstURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("# A".utf8).write(to: firstURL)
        try Data("# B".utf8).write(to: secondURL)
        firstProvider = SynchronizationFileContentProvider(
            contentByPath: [firstURL.path: Data("# A".utf8)]
        )
        secondProvider = SynchronizationFileContentProvider(
            contentByPath: [secondURL.path: Data("# B".utf8)]
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        secondProvider = nil
        firstProvider = nil
        group = nil
        container = nil
    }

    func testFilteredHiddenActiveActivatesFirstVisibleExactlyOnceAndSynchronizesMarkdown() async throws {
        let ids = await openBothFiles()
        let notificationCount = CountBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .contentViewerTabActivated,
            object: nil,
            queue: .main
        ) { _ in notificationCount.value += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        group.reconcileActiveSelection(visibleTabIDs: [ids.first])
        group.reconcileActiveSelection(visibleTabIDs: [ids.first])

        XCTAssertEqual(group.activeTabID, ids.first)
        XCTAssertEqual(group.markdownViewModel.currentDocumentID, ids.firstReference.documentIdentity)
        XCTAssertTrue(group.activeFileContentProvider as AnyObject === firstProvider)
        XCTAssertTrue(group.markdownViewModel.fileContentProvider as AnyObject === firstProvider)
        XCTAssertEqual(notificationCount.value, 1)
    }

    func testNoVisibleTabsPreservesHiddenActiveSelectionAndProvider() async throws {
        let ids = await openBothFiles()
        let notificationCount = CountBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .contentViewerTabActivated,
            object: nil,
            queue: .main
        ) { _ in notificationCount.value += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        group.reconcileActiveSelection(visibleTabIDs: [])

        XCTAssertEqual(group.activeTabID, ids.second)
        XCTAssertEqual(group.markdownViewModel.currentDocumentID, ids.secondReference.documentIdentity)
        XCTAssertTrue(group.activeFileContentProvider as AnyObject === secondProvider)
        XCTAssertEqual(notificationCount.value, 0)
    }

    func testSameVisibleActiveSelectionDoesNotEmitNotificationLoop() async throws {
        let ids = await openBothFiles()
        let notificationCount = CountBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .contentViewerTabActivated,
            object: nil,
            queue: .main
        ) { _ in notificationCount.value += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        for _ in 0..<3 {
            group.reconcileActiveSelection(visibleTabIDs: [ids.first, ids.second])
        }

        XCTAssertEqual(group.activeTabID, ids.second)
        XCTAssertEqual(notificationCount.value, 0)
    }

    func testUserCanReassertSameTabProviderAndProjectFocusNotification() async throws {
        let ids = await openBothFiles()
        group.markdownViewModel.fileContentProvider = firstProvider
        let notificationCount = CountBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .contentViewerTabActivated,
            object: nil,
            queue: .main
        ) { notification in
            guard let tab = notification.userInfo?[AppCommandUserInfoKey.tab] as? ContentViewerTab,
                  tab.id == ids.second else { return }
            notificationCount.value += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        group.activateTab(ids.second)

        XCTAssertEqual(group.activeTabID, ids.second)
        XCTAssertTrue(group.markdownViewModel.fileContentProvider as AnyObject === secondProvider)
        XCTAssertEqual(group.markdownViewModel.currentDocumentID, ids.secondReference.documentIdentity)
        XCTAssertEqual(notificationCount.value, 1)
    }

    func testClosingActiveTabUsesOneLifecycleActivationAndSynchronizesFallbackProjectProvider() async throws {
        let ids = await openBothFiles()
        group.activateTab(ids.first)
        let notificationCount = CountBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .contentViewerTabActivated,
            object: nil,
            queue: .main
        ) { notification in
            guard let tab = notification.userInfo?[AppCommandUserInfoKey.tab] as? ContentViewerTab,
                  tab.id == ids.second else { return }
            notificationCount.value += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let commitsBefore = AppDiagnostics.eventStore.snapshot().filter {
            $0.event == "content_tab_selection_commit"
        }.count

        group.closeTab(ids.first)

        let commitsAfter = AppDiagnostics.eventStore.snapshot().filter {
            $0.event == "content_tab_selection_commit"
        }.count
        XCTAssertEqual(group.activeTabID, ids.second)
        XCTAssertEqual(group.activeFileDocumentReference, ids.secondReference)
        XCTAssertEqual(group.markdownViewModel.currentDocumentID, ids.secondReference.documentIdentity)
        XCTAssertTrue(group.activeFileContentProvider as AnyObject === secondProvider)
        XCTAssertTrue(group.markdownViewModel.fileContentProvider as AnyObject === secondProvider)
        XCTAssertEqual(notificationCount.value, 1)
        XCTAssertEqual(commitsAfter - commitsBefore, 1)
    }

    private func openBothFiles() async -> (
        first: String,
        second: String,
        firstReference: FileDocumentReference,
        secondReference: FileDocumentReference
    ) {
        let firstReference = FileDocumentReference(
            url: firstURL,
            projectIdentifier: firstURL.deletingLastPathComponent().path
        )
        let secondReference = FileDocumentReference(
            url: secondURL,
            projectIdentifier: secondURL.deletingLastPathComponent().path
        )
        group.openFileInTab(
            at: firstURL,
            documentReference: firstReference,
            fileContentProvider: firstProvider
        )
        _ = await waitForCondition(timeout: 4) {
            self.group.markdownViewModel.currentDocumentID == firstReference.documentIdentity
                && self.group.markdownViewModel.rawContent == "# A"
        }
        group.openFileInTab(
            at: secondURL,
            documentReference: secondReference,
            fileContentProvider: secondProvider
        )
        _ = await waitForCondition(timeout: 4) {
            self.group.markdownViewModel.currentDocumentID == secondReference.documentIdentity
                && self.group.markdownViewModel.rawContent == "# B"
        }
        return (
            ContentViewerTab.file(reference: firstReference).id,
            ContentViewerTab.file(reference: secondReference).id,
            firstReference,
            secondReference
        )
    }
}

@MainActor
final class ContentViewerMountedSynchronizationTests: XCTestCase {
    private final class CountBox {
        var value = 0
    }

    private var container: AppContainer!
    private var group: EditorGroupStore!
    private var windows: [NSWindow] = []

    override func setUp() {
        container = AppContainer.makeDefault()
        group = container.makeEditorGroupStore(bufferStore: DocumentBufferStore())
    }

    override func tearDown() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        group = nil
        container = nil
        super.tearDown()
    }

    func testDirectObserverRoutesOneActivationOnNextLayoutTurn() throws {
        group.openTab(.vibeCast)
        group.openTab(.vibeLanes)
        group.activateTab(ContentViewerTab.vibeCast.id)
        let notificationCount = CountBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .contentViewerTabActivated,
            object: nil,
            queue: .main
        ) { _ in notificationCount.value += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        var objectChangeCount = 0
        let cancellable = group.objectWillChange.sink { objectChangeCount += 1 }
        defer { cancellable.cancel() }

        let root = SinglePaneContentViewerObserverScope(
            group: group,
            viewerScope: .allProjects,
            focusedProjectRootPath: nil
        ) { _, _, activeTab in
            ContentRouteProbe(identifier: "content-observer-probe", value: activeTab?.id ?? "none")
        }
        let hosting = mount(root)
        objectChangeCount = 0

        group.activateTab(ContentViewerTab.vibeLanes.id)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        hosting.layoutSubtreeIfNeeded()

        let probe = try XCTUnwrap(descendant(
            in: hosting,
            identifier: "content-observer-probe"
        ) as? ContentRouteProbeView)
        XCTAssertEqual(probe.renderedValue, ContentViewerTab.vibeLanes.id)
        XCTAssertEqual(group.activeTabID, ContentViewerTab.vibeLanes.id)
        XCTAssertEqual(notificationCount.value, 1)
        XCTAssertEqual(objectChangeCount, 1)
    }

    func testMountedSplitPaneObserverRoutesBWithOneActivationAfterOneTurn() throws {
        group.openTab(.vibeCast)
        group.openTab(.vibeLanes)
        group.activateTab(ContentViewerTab.vibeCast.id)
        let notificationCount = CountBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .contentViewerTabActivated,
            object: nil,
            queue: .main
        ) { _ in notificationCount.value += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        let root = SplitPaneContentViewerObserverScope(
            group: group,
            viewerScope: .allProjects,
            focusedProjectRootPath: nil
        ) { activeTab in
            ContentRouteProbe(
                identifier: "split-content-observer-probe",
                value: activeTab?.id ?? "none"
            )
        }
        let hosting = mount(root)

        group.activateTab(ContentViewerTab.vibeLanes.id)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        hosting.layoutSubtreeIfNeeded()

        let probe = try XCTUnwrap(descendant(
            in: hosting,
            identifier: "split-content-observer-probe"
        ) as? ContentRouteProbeView)
        XCTAssertEqual(probe.renderedValue, ContentViewerTab.vibeLanes.id)
        XCTAssertEqual(group.activeTabID, ContentViewerTab.vibeLanes.id)
        XCTAssertEqual(notificationCount.value, 1)
    }

    func testKeyedRouteRecreatesTargetScopedStateForSameKindSwitch() throws {
        let selection = RoutedSelection(tabID: "browser-A")
        let recorder = RoutedCreationRecorder()
        let root = RoutedSelectionRoot(selection: selection, recorder: recorder)
        let hosting = mount(root)

        var probe = try XCTUnwrap(descendant(
            in: hosting,
            identifier: "keyed-route-probe"
        ) as? ContentRouteProbeView)
        XCTAssertEqual(probe.renderedValue, "browser-A")
        XCTAssertEqual(probe.accessibilityValue() as? String, "browser-A")
        XCTAssertEqual(recorder.createdIdentities, ["browser-A"])

        selection.tabID = "browser-B"
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        hosting.layoutSubtreeIfNeeded()

        probe = try XCTUnwrap(descendant(
            in: hosting,
            identifier: "keyed-route-probe"
        ) as? ContentRouteProbeView)
        XCTAssertEqual(probe.renderedValue, "browser-B")
        XCTAssertEqual(probe.accessibilityValue() as? String, "browser-B")
        XCTAssertEqual(recorder.createdIdentities.last, "browser-B")
        XCTAssertTrue(recorder.createdIdentities.contains("browser-A"))

        selection.tabID = "browser-A"
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        hosting.layoutSubtreeIfNeeded()

        probe = try XCTUnwrap(descendant(
            in: hosting,
            identifier: "keyed-route-probe"
        ) as? ContentRouteProbeView)
        XCTAssertEqual(probe.renderedValue, "browser-A")
        XCTAssertEqual(probe.accessibilityValue() as? String, "browser-A")
        XCTAssertEqual(recorder.createdIdentities.last, "browser-A")
    }

    func testBrowserContainerSwitchesActualWKWebViewAttachmentFromAToB() {
        let a = BrowserPanelViewModel()
        let b = BrowserPanelViewModel()
        let container = BrowserContainerView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let window = NSWindow(
            contentRect: container.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        windows.append(window)

        container.attach(
            a,
            allowsOwnershipParticipation: true,
            ownershipPriority: 220,
            onInteraction: nil
        )
        container.layoutSubtreeIfNeeded()
        XCTAssertTrue(a.webView.superview === container)

        container.attach(
            b,
            allowsOwnershipParticipation: true,
            ownershipPriority: 220,
            onInteraction: nil
        )
        container.layoutSubtreeIfNeeded()

        XCTAssertNil(a.webView.superview)
        XCTAssertTrue(b.webView.superview === container)
        XCTAssertEqual(container.subviews.filter { $0 is WKWebView }.count, 1)
    }

    private func mount<V: View>(_ root: V) -> NSHostingView<V> {
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        windows.append(window)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        return hosting
    }

    private func descendant(in view: NSView, identifier: String) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for subview in view.subviews {
            if let match = descendant(in: subview, identifier: identifier) { return match }
        }
        return nil
    }
}

private struct ContentRouteProbe: NSViewRepresentable {
    let identifier: String
    let value: String

    func makeNSView(context: Context) -> ContentRouteProbeView {
        ContentRouteProbeView(identifier: identifier)
    }

    func updateNSView(_ nsView: ContentRouteProbeView, context: Context) {
        nsView.renderedValue = value
        nsView.setAccessibilityValue(value)
    }
}

private final class ContentRouteProbeView: NSView {
    var renderedValue = ""

    init(identifier: String) {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier(identifier)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class RoutedSelection: ObservableObject {
    @Published var tabID: String

    init(tabID: String) {
        self.tabID = tabID
    }
}

@MainActor
private final class RoutedCreationRecorder {
    var createdIdentities: [String] = []
}

@MainActor
private final class RoutedProbeState: ObservableObject {
    let identity: String

    init(identity: String, recorder: RoutedCreationRecorder) {
        self.identity = identity
        recorder.createdIdentities.append(identity)
    }
}

@MainActor
private struct RoutedIdentityProbe: View {
    @StateObject private var state: RoutedProbeState

    init(identity: String, recorder: RoutedCreationRecorder) {
        _state = StateObject(wrappedValue: RoutedProbeState(identity: identity, recorder: recorder))
    }

    var body: some View {
        ContentRouteProbe(identifier: "keyed-route-probe", value: state.identity)
    }
}

@MainActor
private struct RoutedSelectionRoot: View {
    @ObservedObject var selection: RoutedSelection
    let recorder: RoutedCreationRecorder

    var body: some View {
        ContentTabRoutedContentScope(tabID: selection.tabID, paneID: nil) {
            RoutedIdentityProbe(identity: selection.tabID, recorder: recorder)
        }
    }
}
