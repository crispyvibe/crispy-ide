import AppKit
import QuartzCore
import XCTest
@testable import CrispyVibes

@MainActor
final class GhosttyTerminalViewInputTests: XCTestCase {
    private func makeWindowAndRoot() -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = root
        return (window, root)
    }

    private func makeSessionAndEngine() -> (TerminalSession, GhosttyTerminalEngine) {
        let services = TerminalServices()
        let engine = GhosttyTerminalEngine(terminalServices: services)
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: services,
            engineFactory: { _ in engine }
        )
        return (session, engine)
    }

    func testDoCommandInsertNewlineDoesNotQueueEnter() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())

        engine.terminalView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertTrue(
            engine.pendingTextForTesting.isEmpty,
            "doCommand should not inject Return directly; keyDown owns terminal key dispatch."
        )
    }

    func testInsertTextOutsideKeyDownSendsCommittedTextOnce() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        var committedText: [String] = []
        engine.terminalView.committedTextSinkForTesting = { committedText.append($0) }

        engine.terminalView.insertText("touch security key", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(committedText, ["touch security key"])
    }

    func testInsertTextDuringKeyDownAccumulatesInsteadOfSendingImmediately() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        var committedText: [String] = []
        engine.terminalView.committedTextSinkForTesting = { committedText.append($0) }
        engine.terminalView.keyTextAccumulator = []

        engine.terminalView.insertText("secret", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(engine.terminalView.keyTextAccumulator, ["secret"])
        XCTAssertTrue(
            committedText.isEmpty,
            "Committed text should accumulate during keyDown instead of sending immediately."
        )
    }

    func testViewTracksScreenChangeObservationWithWindowLifecycle() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = root

        root.addSubview(engine.terminalView)
        root.layoutSubtreeIfNeeded()

        XCTAssertTrue(engine.terminalView.observedWindowForScreenChanges === window)
        XCTAssertNotNil(engine.terminalView.screenChangeObserver)

        engine.terminalView.removeFromSuperview()

        XCTAssertNil(engine.terminalView.observedWindowForScreenChanges)
        XCTAssertNil(engine.terminalView.screenChangeObserver)
    }

    func testWindowScreenChangeNotificationTriggersViewHandler() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = root
        root.addSubview(engine.terminalView)
        root.layoutSubtreeIfNeeded()

        var handledCount = 0
        engine.terminalView.onWindowScreenChangeHandledForTesting = {
            handledCount += 1
        }

        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))

        XCTAssertEqual(handledCount, 1)
    }

    func testHandleWindowDidChangeScreenDefersBackingRefreshUntilNextRunLoop() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = root
        root.addSubview(engine.terminalView)
        root.layoutSubtreeIfNeeded()

        var handledCount = 0
        engine.terminalView.onWindowScreenChangeHandledForTesting = {
            handledCount += 1
        }

        engine.terminalView.handleWindowDidChangeScreen()

        XCTAssertEqual(handledCount, 0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.01))

        XCTAssertEqual(handledCount, 1)
    }

    func testSyncBackingLayerMetricsUpdatesMetalLayerState() throws {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        let (window, root) = makeWindowAndRoot()
        root.addSubview(engine.terminalView)
        root.layoutSubtreeIfNeeded()

        engine.terminalView.syncBackingLayerMetrics(
            pixelWidth: 640,
            pixelHeight: 480,
            backingScale: 1.0
        )

        let metalLayer = try XCTUnwrap(engine.terminalView.layer as? CAMetalLayer)
        XCTAssertEqual(metalLayer.drawableSize, CGSize(width: 640, height: 480))
        XCTAssertEqual(metalLayer.contentsScale, window.backingScaleFactor)
    }

    func testViewWindowLifecycleRequestsPollingSync() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        let (_, root) = makeWindowAndRoot()
        var syncCount = 0
        engine.onOutputPollingSyncRequestedForTesting = {
            syncCount += 1
        }

        root.addSubview(engine.terminalView)
        root.layoutSubtreeIfNeeded()

        XCTAssertGreaterThanOrEqual(syncCount, 1)

        syncCount = 0
        engine.terminalView.removeFromSuperview()

        XCTAssertGreaterThanOrEqual(syncCount, 1)
    }

    func testHostReattachRequestsPollingSyncForExistingGhosttySurfaceState() {
        let (session, engine) = makeSessionAndEngine()
        defer { session.terminate() }

        let (_, root) = makeWindowAndRoot()
        let container = TerminalContainerView(
            ownershipCoordinator: session.terminalServices.hostOwnershipCoordinator,
            frame: root.bounds
        )
        root.addSubview(container)
        root.layoutSubtreeIfNeeded()

        var syncCount = 0
        engine.onOutputPollingSyncRequestedForTesting = {
            syncCount += 1
        }

        container.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .regular,
            isActive: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(syncCount, 0)

        syncCount = 0

        container.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .regular,
            isActive: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(syncCount, 0)
    }

    func testCommandClickActivatesGhosttyLinkTargetRouting() throws {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        engine.currentDirectoryPath = FileManager.default.temporaryDirectory.path
        engine.terminalView.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        engine.terminalView.visibleContentsProviderForTesting = {
            "open https://example.com/docs here"
        }
        engine.terminalView.dimensionsProviderForTesting = { (cols: 40, rows: 2) }

        var openedURL: URL?
        let observer = NotificationCenter.default.addObserver(
            forName: .ghosttyOpenLinkTargetRequested,
            object: nil,
            queue: .main
        ) { notification in
            openedURL = notification.userInfo?[AppCommandUserInfoKey.url] as? URL
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        let point = CGPoint(x: 115, y: 75)
        XCTAssertTrue(
            engine.terminalView.beginInteractiveTargetClick(at: point, modifierFlags: [.command])
        )
        let target = try XCTUnwrap(
            engine.terminalView.activatedInteractiveTargetOnMouseUp(
                at: point,
                modifierFlags: [.command]
            )
        )

        engine.terminalView.activateInteractiveTarget(target)

        XCTAssertEqual(openedURL, URL(string: "https://example.com/docs"))
    }

    func testCommandClickActivatesCompleteWrappedGhosttyLinkAcrossLogicalLine() throws {
        let urlString = "https://media.example.tv/watch/documentaries/science-and-nature/"
            + "exploring-the-deepest-regions-of-the-pacific-ocean?episode=7&season=3"
            + "&quality=ultra-high-definition"
        let columns = 48
        let wrappedRows = Int(ceil(Double(urlString.count) / Double(columns)))
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        engine.currentDirectoryPath = FileManager.default.temporaryDirectory.path
        engine.terminalView.frame = NSRect(
            x: 0,
            y: 0,
            width: CGFloat(columns * 10),
            height: CGFloat(wrappedRows * 20)
        )
        engine.terminalView.visibleContentsProviderForTesting = { urlString }
        engine.terminalView.dimensionsProviderForTesting = { (cols: columns, rows: wrappedRows) }

        var openedURL: URL?
        let observer = NotificationCenter.default.addObserver(
            forName: .ghosttyOpenLinkTargetRequested,
            object: nil,
            queue: .main
        ) { notification in
            openedURL = notification.userInfo?[AppCommandUserInfoKey.url] as? URL
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let point = CGPoint(
            x: 35,
            y: engine.terminalView.bounds.height - 10
        )
        XCTAssertTrue(
            engine.terminalView.beginInteractiveTargetClick(at: point, modifierFlags: [.command])
        )
        XCTAssertEqual(engine.terminalView.interactiveHoverOverlay.highlightRects.count, wrappedRows)
        let target = try XCTUnwrap(
            engine.terminalView.activatedInteractiveTargetOnMouseUp(
                at: point,
                modifierFlags: [.command]
            )
        )

        engine.terminalView.activateInteractiveTarget(target)


        XCTAssertEqual(target, .link(urlString))
        XCTAssertEqual(openedURL, URL(string: urlString))
    }

    func testCommandClickActivatesCompleteIndentedTUIWrappedGhosttyLink() throws {
        let urlString = "https://api.example.net/v1/organizations/engineering-"
            + "department/projects/customer-analytics/reports/quarte"
            + "rly-performance-summary"
        let visibleText = [
            "  https://api.example.net/v1/organizations/engineering-",
            "  department/projects/customer-analytics/reports/quarte",
            "  rly-performance-summary"
        ].joined(separator: "\n")
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        engine.currentDirectoryPath = FileManager.default.temporaryDirectory.path
        engine.terminalView.frame = NSRect(x: 0, y: 0, width: 550, height: 60)
        engine.terminalView.visibleContentsProviderForTesting = { visibleText }
        engine.terminalView.dimensionsProviderForTesting = { (cols: 55, rows: 3) }

        var openedURL: URL?
        let observer = NotificationCenter.default.addObserver(
            forName: .ghosttyOpenLinkTargetRequested,
            object: nil,
            queue: .main
        ) { notification in
            openedURL = notification.userInfo?[AppCommandUserInfoKey.url] as? URL
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let point = CGPoint(x: 50, y: 50)
        XCTAssertTrue(
            engine.terminalView.beginInteractiveTargetClick(at: point, modifierFlags: [.command])
        )
        XCTAssertEqual(engine.terminalView.interactiveHoverOverlay.highlightRects.count, 3)
        let target = try XCTUnwrap(
            engine.terminalView.activatedInteractiveTargetOnMouseUp(
                at: point,
                modifierFlags: [.command]
            )
        )

        engine.terminalView.activateInteractiveTarget(target)

        XCTAssertEqual(target, .link(urlString))
        XCTAssertEqual(openedURL, URL(string: urlString))
    }

    func testCommandClickRefreshesStaleWidthCacheBeforeOpeningWrappedGhosttyLink() throws {
        let urlString = "https://media.example.tv/watch/documentaries/science-and-nature/"
            + "exploring-the-deepest-regions-of-the-pacific-ocean?episode=7&season=3"
            + "&quality=ultra-high-definition"
        let currentColumns = 53
        let staleColumns = 60
        let characters = Array(urlString)
        let physicalText: (Int) -> String = { columns in
            stride(from: 0, to: characters.count, by: columns).map { start in
                String(characters[start..<min(start + columns, characters.count)])
            }.joined(separator: "\n")
        }
        let currentText = physicalText(currentColumns)
        let currentRows = currentText.split(separator: "\n").count
        let staleText = physicalText(staleColumns)
        let staleRows = staleText.split(separator: "\n").count

        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        engine.currentDirectoryPath = FileManager.default.temporaryDirectory.path
        engine.lastVisibleContents = staleText
        engine.lastVisibleContentsDimensions = (cols: staleColumns, rows: staleRows)
        engine.terminalView.frame = NSRect(
            x: 0,
            y: 0,
            width: CGFloat(currentColumns * 10),
            height: CGFloat(currentRows * 20)
        )
        var liveReadCount = 0
        engine.terminalView.visibleContentsProviderForTesting = {
            liveReadCount += 1
            return currentText
        }
        engine.terminalView.dimensionsProviderForTesting = {
            (cols: currentColumns, rows: currentRows)
        }

        var openedURL: URL?
        let observer = NotificationCenter.default.addObserver(
            forName: .ghosttyOpenLinkTargetRequested,
            object: nil,
            queue: .main
        ) { notification in
            openedURL = notification.userInfo?[AppCommandUserInfoKey.url] as? URL
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let point = CGPoint(x: 35, y: engine.terminalView.bounds.height - 10)
        XCTAssertTrue(
            engine.terminalView.beginInteractiveTargetClick(at: point, modifierFlags: [.command])
        )
        XCTAssertEqual(engine.terminalView.interactiveHoverOverlay.highlightRects.count, currentRows)
        let target = try XCTUnwrap(
            engine.terminalView.activatedInteractiveTargetOnMouseUp(
                at: point,
                modifierFlags: [.command]
            )
        )

        engine.terminalView.activateInteractiveTarget(target)

        XCTAssertEqual(target, .link(urlString))
        XCTAssertEqual(openedURL, URL(string: urlString))
        XCTAssertEqual(liveReadCount, 1, "A dimension mismatch should trigger exactly one live read.")
        XCTAssertEqual(engine.lastVisibleContents, currentText)
        XCTAssertEqual(engine.lastVisibleContentsDimensions?.cols, currentColumns)
        XCTAssertEqual(engine.lastVisibleContentsDimensions?.rows, currentRows)
    }

    func testCommandClickActivatesGhosttyFileTargetRouting() throws {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = rootDirectory.appendingPathComponent("src", isDirectory: true)
        let fileURL = sourceDirectory.appendingPathComponent("example.txt", isDirectory: false)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try Data("sample".utf8).write(to: fileURL)

        engine.currentDirectoryPath = rootDirectory.path
        engine.terminalView.frame = NSRect(x: 0, y: 0, width: 420, height: 100)
        engine.terminalView.visibleContentsProviderForTesting = {
            "src/example.txt:12:3"
        }
        engine.terminalView.dimensionsProviderForTesting = { (cols: 21, rows: 1) }

        var openedURL: URL?
        var openedLine: Int?
        var openedColumn: Int?
        let observer = NotificationCenter.default.addObserver(
            forName: .ghosttyOpenFileSystemTargetRequested,
            object: nil,
            queue: .main
        ) { notification in
            openedURL = notification.userInfo?[AppCommandUserInfoKey.url] as? URL
            openedLine = notification.userInfo?[AppCommandUserInfoKey.line] as? Int
            openedColumn = notification.userInfo?[AppCommandUserInfoKey.column] as? Int
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        let point = CGPoint(x: 110, y: 50)
        XCTAssertTrue(
            engine.terminalView.beginInteractiveTargetClick(at: point, modifierFlags: [.command])
        )
        let target = try XCTUnwrap(
            engine.terminalView.activatedInteractiveTargetOnMouseUp(
                at: point,
                modifierFlags: [.command]
            )
        )

        engine.terminalView.activateInteractiveTarget(target)

        XCTAssertEqual(openedURL, fileURL.standardizedFileURL)
        XCTAssertEqual(openedLine, 12)
        XCTAssertEqual(openedColumn, 3)
    }

    func testPlainClickDoesNotStartInteractiveGhosttyActivation() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        engine.terminalView.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        engine.terminalView.visibleContentsProviderForTesting = {
            "https://example.com/docs"
        }
        engine.terminalView.dimensionsProviderForTesting = { (cols: 24, rows: 1) }

        let point = CGPoint(x: 120, y: 50)
        XCTAssertFalse(
            engine.terminalView.beginInteractiveTargetClick(at: point, modifierFlags: [])
        )
    }

    func testPlainClickStartsGhosttyInteractiveContextMenuTracking() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        engine.terminalView.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        engine.terminalView.visibleContentsProviderForTesting = {
            "https://example.com/docs"
        }
        engine.terminalView.dimensionsProviderForTesting = { (cols: 24, rows: 1) }

        let point = CGPoint(x: 120, y: 50)

        XCTAssertTrue(
            engine.terminalView.beginInteractiveTargetContextMenuClick(at: point, modifierFlags: [])
        )
        XCTAssertEqual(engine.terminalView.pendingContextMenuMouseDownPoint, point)
    }

    func testPlainClickShowsGhosttyInteractiveContextMenuForLinkTarget() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        engine.terminalView.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        engine.terminalView.visibleContentsProviderForTesting = {
            "https://example.com/docs"
        }
        engine.terminalView.dimensionsProviderForTesting = { (cols: 24, rows: 1) }

        let point = CGPoint(x: 120, y: 50)
        var presentedTarget: TerminalInteractiveTarget?
        var presentedPoint: CGPoint?
        engine.terminalView.interactiveTargetMenuPresenterForTesting = { target, location in
            presentedTarget = target
            presentedPoint = location
        }

        XCTAssertTrue(
            engine.terminalView.beginInteractiveTargetContextMenuClick(at: point, modifierFlags: [])
        )
        let target = engine.terminalView.interactiveTargetForContextMenuOnMouseUp(
            at: point,
            modifierFlags: []
        )
        if let target {
            engine.terminalView.showInteractiveTargetContextMenu(for: target, at: point)
        }

        XCTAssertEqual(target, .link("https://example.com/docs"))
        XCTAssertEqual(presentedTarget, .link("https://example.com/docs"))
        XCTAssertEqual(presentedPoint, point)
    }

    func testPlainHoverHighlightsGhosttyInteractiveTargetWithoutChangingCursorMode() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        engine.terminalView.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        engine.terminalView.visibleContentsProviderForTesting = {
            "https://example.com/docs"
        }
        engine.terminalView.dimensionsProviderForTesting = { (cols: 24, rows: 1) }

        let point = CGPoint(x: 120, y: 50)
        engine.terminalView.updateHoveredInteractiveTarget(at: point, modifierFlags: [])

        XCTAssertEqual(
            engine.terminalView.hoveredInteractiveTarget,
            .link("https://example.com/docs")
        )
        XCTAssertEqual(engine.terminalView.interactiveHoverOverlay.highlightRects.count, 1)
        XCTAssertFalse(engine.terminalView.isPointingHandCursorActive)
    }
}
