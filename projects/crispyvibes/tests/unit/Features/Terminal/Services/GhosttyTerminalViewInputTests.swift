import AppKit
import QuartzCore
import XCTest
@testable import CrispyVibes

@MainActor
final class GhosttyTerminalViewInputTests: XCTestCase {
    private var mountedWindows: [NSWindow] = []

    override func tearDown() {
        for window in mountedWindows {
            window.orderOut(nil)
            window.contentView = nil
        }
        mountedWindows.removeAll()
        super.tearDown()
    }

    private func makeWindowAndRoot(
        size: CGSize = CGSize(width: 320, height: 200)
    ) -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = root
        mountedWindows.append(window)
        return (window, root)
    }

    private func makeScrollEvent(
        in window: NSWindow,
        at windowPoint: CGPoint,
        deltaX: Int32,
        deltaY: Int32,
        modifierFlags: CGEventFlags = []
    ) throws -> NSEvent {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cgEvent = try XCTUnwrap(
            CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 2,
                wheel1: deltaY,
                wheel2: deltaX,
                wheel3: 0
            )
        )
        cgEvent.location = window.convertPoint(toScreen: windowPoint)
        cgEvent.flags = modifierFlags
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
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

    func testOpticalTransformPreservesZoomAnchorAndRoundTripsPoints() {
        var transform = TerminalOpticalTransform()
        let contentSize = CGSize(width: 320, height: 200)
        let anchor = CGPoint(x: 240, y: 50)
        let terminalAnchorBeforeZoom = transform.terminalPoint(fromViewport: anchor)

        transform.setScale(
            2,
            anchoredAt: anchor,
            contentSize: contentSize,
            viewportSize: contentSize
        )

        let terminalAnchorAfterZoom = transform.terminalPoint(fromViewport: anchor)
        XCTAssertEqual(terminalAnchorAfterZoom.x, terminalAnchorBeforeZoom.x, accuracy: 0.001)
        XCTAssertEqual(terminalAnchorAfterZoom.y, terminalAnchorBeforeZoom.y, accuracy: 0.001)

        let terminalPoint = CGPoint(x: 180, y: 80)
        let roundTripped = transform.terminalPoint(
            fromViewport: transform.viewportPoint(fromTerminal: terminalPoint)
        )
        XCTAssertEqual(roundTripped.x, terminalPoint.x, accuracy: 0.001)
        XCTAssertEqual(roundTripped.y, terminalPoint.y, accuracy: 0.001)
    }

    /// F001-S59
    func testOpticalTransformClampsAboveNormalPanAndCentersShrink() {
        let size = CGSize(width: 320, height: 200)
        var transform = TerminalOpticalTransform(scale: 2, visibleOrigin: .zero)

        transform.pan(by: CGPoint(x: -10_000, y: 10_000), contentSize: size, viewportSize: size)
        XCTAssertEqual(transform.visibleOrigin.x, 160, accuracy: 0.001)
        XCTAssertEqual(transform.visibleOrigin.y, 100, accuracy: 0.001)

        transform.setScale(0.5, anchoredAt: .zero, contentSize: size, viewportSize: size)
        XCTAssertEqual(transform.scale, 0.5, accuracy: 0.001)
        XCTAssertEqual(transform.visibleOrigin.x, -160, accuracy: 0.001)
        XCTAssertEqual(transform.visibleOrigin.y, -100, accuracy: 0.001)

        transform.pan(by: CGPoint(x: 10_000, y: -10_000), contentSize: size, viewportSize: size)
        XCTAssertEqual(transform.visibleOrigin.x, -160, accuracy: 0.001)
        XCTAssertEqual(transform.visibleOrigin.y, -100, accuracy: 0.001)
    }

    /// F001-S59, F001-S60
    func testTerminalPointTracksDocumentCoordinatesUnderCompositorZoomAndPan() throws {
        let (session, engine) = makeSessionAndEngine()
        defer { session.terminate() }

        let (window, root) = makeWindowAndRoot()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let container = TerminalContainerView(
            ownershipCoordinator: session.terminalServices.hostOwnershipCoordinator,
            frame: root.bounds,
            allowsGhosttySurfaceRestorationForTesting: false
        )
        root.addSubview(container)
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

        let backingRect = engine.terminalView.convertToBacking(engine.terminalView.bounds)
        engine.terminalView.lastSyncedSurfaceGeometry = GhosttyTerminalView.SurfaceGeometry(
            pixelWidth: UInt32(max(backingRect.width, 1)),
            pixelHeight: UInt32(max(backingRect.height, 1)),
            backingScale: Double(window.backingScaleFactor)
        )
        let terminalFrame = engine.terminalView.frame
        let surfaceGeometry = try XCTUnwrap(engine.terminalView.lastSyncedSurfaceGeometry)
        let gridDimensions = engine.currentDimensions()
        var characterCoordinateInvalidationCount = 0
        engine.terminalView.characterCoordinatesInvalidationSinkForTesting = {
            characterCoordinateInvalidationCount += 1
        }
        container.configureOpticalViewportForTesting(
            magnification: 2,
            centeredAt: CGPoint(x: 152, y: 100),
            panDelta: CGPoint(x: 20, y: 20)
        )

        let expectedPoint = CGPoint(x: 100, y: 75)
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: container.opticalWindowPointForTesting(terminalPoint: expectedPoint),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        )

        let actualPoint = engine.terminalView.terminalPoint(for: event)
        XCTAssertEqual(actualPoint.x, expectedPoint.x, accuracy: 0.001)
        XCTAssertEqual(actualPoint.y, expectedPoint.y, accuracy: 0.001)
        XCTAssertEqual(container.opticalMagnificationForTesting, 2, accuracy: 0.001)
        XCTAssertGreaterThan(characterCoordinateInvalidationCount, 0)
        XCTAssertEqual(engine.terminalView.frame, terminalFrame)
        XCTAssertEqual(engine.terminalView.lastSyncedSurfaceGeometry, surfaceGeometry)
        XCTAssertEqual(engine.currentDimensions().cols, gridDimensions.cols)
        XCTAssertEqual(engine.currentDimensions().rows, gridDimensions.rows)

        let presentationPoint = engine.terminalView.presentationPoint(for: expectedPoint)
        let presentationWindowPoint = engine.terminalView.convert(presentationPoint, to: nil)
        let expectedWindowPoint = container.opticalWindowPointForTesting(terminalPoint: expectedPoint)
        XCTAssertEqual(presentationWindowPoint.x, expectedWindowPoint.x, accuracy: 0.001)
        XCTAssertEqual(presentationWindowPoint.y, expectedWindowPoint.y, accuracy: 0.001)

        let terminalRect = CGRect(x: expectedPoint.x, y: expectedPoint.y, width: 12, height: 8)
        let presentationRect = engine.terminalView.presentationRect(for: terminalRect)
        XCTAssertEqual(presentationRect.origin.x, presentationPoint.x, accuracy: 0.001)
        XCTAssertEqual(presentationRect.origin.y, presentationPoint.y, accuracy: 0.001)
        XCTAssertEqual(presentationRect.width, 24, accuracy: 0.001)
        XCTAssertEqual(presentationRect.height, 16, accuracy: 0.001)

        let rightEdgeTerminalPoint = CGPoint(x: 217.5, y: 110)
        let rightEdgeWindowPoint = container.opticalWindowPointForTesting(
            terminalPoint: rightEdgeTerminalPoint
        )
        XCTAssertTrue(root.hitTest(rightEdgeWindowPoint) === engine.terminalView)
    }

    /// F001-S59, F001-S60, F001-S61
    func testHostAppliesCenteredShrinkWithoutChangingTerminalGeometryOrMarginHitTesting() throws {
        let (session, engine) = makeSessionAndEngine()
        defer { session.terminate() }

        let (window, root) = makeWindowAndRoot()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let container = TerminalContainerView(
            ownershipCoordinator: session.terminalServices.hostOwnershipCoordinator,
            frame: root.bounds,
            allowsGhosttySurfaceRestorationForTesting: false
        )
        root.addSubview(container)
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

        let backingRect = engine.terminalView.convertToBacking(engine.terminalView.bounds)
        engine.terminalView.lastSyncedSurfaceGeometry = GhosttyTerminalView.SurfaceGeometry(
            pixelWidth: UInt32(max(backingRect.width, 1)),
            pixelHeight: UInt32(max(backingRect.height, 1)),
            backingScale: Double(window.backingScaleFactor)
        )
        let terminalFrame = engine.terminalView.frame
        let surfaceGeometry = try XCTUnwrap(engine.terminalView.lastSyncedSurfaceGeometry)
        let gridDimensions = engine.currentDimensions()
        container.applyMagnificationGestureEventForTesting(.began)
        container.applyMagnificationGestureEventForTesting(.changed(-10))

        XCTAssertEqual(session.displayMagnification, 0.5, accuracy: 0.001)
        XCTAssertEqual(container.opticalMagnificationForTesting, 0.5, accuracy: 0.001)
        XCTAssertEqual(container.opticalVisibleOriginForTesting.x, -152, accuracy: 0.001)
        XCTAssertEqual(container.opticalVisibleOriginForTesting.y, -100, accuracy: 0.001)
        XCTAssertEqual(engine.terminalView.frame, terminalFrame)
        XCTAssertEqual(engine.terminalView.lastSyncedSurfaceGeometry, surfaceGeometry)
        XCTAssertEqual(engine.currentDimensions().cols, gridDimensions.cols)
        XCTAssertEqual(engine.currentDimensions().rows, gridDimensions.rows)

        let blankMarginPoint = container.opticalWindowPointForTesting(
            terminalPoint: CGPoint(x: -50, y: 100)
        )
        XCTAssertFalse(root.hitTest(blankMarginPoint) === engine.terminalView)

        let expectedTerminalPoint = CGPoint(x: 100, y: 75)
        let displayedPoint = container.opticalWindowPointForTesting(terminalPoint: expectedTerminalPoint)
        XCTAssertTrue(root.hitTest(displayedPoint) === engine.terminalView)
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved,
                location: displayedPoint,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )
        let mappedPoint = engine.terminalView.terminalPoint(for: event)
        XCTAssertEqual(mappedPoint.x, expectedTerminalPoint.x, accuracy: 0.001)
        XCTAssertEqual(mappedPoint.y, expectedTerminalPoint.y, accuracy: 0.001)

        let presentationRect = engine.terminalView.presentationRect(
            for: CGRect(x: 100, y: 75, width: 20, height: 10)
        )
        XCTAssertEqual(presentationRect.width, 10, accuracy: 0.001)
        XCTAssertEqual(presentationRect.height, 5, accuracy: 0.001)
    }

    /// F001-S59, F003-S17
    func testCenteredShrinkConsumesVerticalAndHorizontalScrollInBlankMarginsOnly() throws {
        let (session, engine) = makeSessionAndEngine()
        defer { session.terminate() }

        let (window, root) = makeWindowAndRoot()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let container = TerminalContainerView(
            ownershipCoordinator: session.terminalServices.hostOwnershipCoordinator,
            frame: root.bounds,
            allowsGhosttySurfaceRestorationForTesting: false
        )
        root.addSubview(container)
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
        container.configureOpticalViewportForTesting(
            magnification: 0.5,
            centeredAt: CGPoint(x: 152, y: 100),
            panDelta: .zero
        )

        var forwardedScrolls: [(x: CGFloat, y: CGFloat)] = []
        engine.terminalView.scrollWheelSinkForTesting = {
            forwardedScrolls.append((x: $0.scrollingDeltaX, y: $0.scrollingDeltaY))
        }
        let blankMarginPoint = container.opticalWindowPointForTesting(
            terminalPoint: CGPoint(x: -50, y: 100)
        )
        let displayedContentPoint = container.opticalWindowPointForTesting(
            terminalPoint: CGPoint(x: 100, y: 75)
        )

        container.deliverOpticalScrollWheelForTesting(
            try makeScrollEvent(in: window, at: blankMarginPoint, deltaX: 0, deltaY: 18),
            atWindowPoint: blankMarginPoint
        )
        container.deliverOpticalScrollWheelForTesting(
            try makeScrollEvent(in: window, at: blankMarginPoint, deltaX: 14, deltaY: 0),
            atWindowPoint: blankMarginPoint
        )
        XCTAssertTrue(forwardedScrolls.isEmpty)

        container.deliverOpticalScrollWheelForTesting(
            try makeScrollEvent(in: window, at: displayedContentPoint, deltaX: 0, deltaY: 18),
            atWindowPoint: displayedContentPoint
        )
        container.deliverOpticalScrollWheelForTesting(
            try makeScrollEvent(in: window, at: displayedContentPoint, deltaX: 14, deltaY: 0),
            atWindowPoint: displayedContentPoint
        )
        XCTAssertEqual(forwardedScrolls.count, 2)
        if forwardedScrolls.count == 2 {
            XCTAssertNotEqual(forwardedScrolls[0].y, 0)
            XCTAssertNotEqual(forwardedScrolls[1].x, 0)
        }
    }

    /// F001-S59, F003-S17
    func testViewportPanUsesStrictAboveNormalBoundaryAndOptionPassesThrough() throws {
        let (session, engine) = makeSessionAndEngine()
        defer { session.terminate() }

        let (window, root) = makeWindowAndRoot()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let container = TerminalContainerView(
            ownershipCoordinator: session.terminalServices.hostOwnershipCoordinator,
            frame: root.bounds,
            allowsGhosttySurfaceRestorationForTesting: false
        )
        root.addSubview(container)
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
        let displayedPoint = container.opticalWindowPointForTesting(
            terminalPoint: CGPoint(x: 100, y: 75)
        )
        var forwardedCount = 0
        engine.terminalView.scrollWheelSinkForTesting = { _ in forwardedCount += 1 }

        container.configureOpticalViewportForTesting(
            magnification: 1,
            centeredAt: CGPoint(x: 152, y: 100),
            panDelta: .zero
        )
        let normalOrigin = container.opticalVisibleOriginForTesting
        container.deliverOpticalScrollWheelForTesting(
            try makeScrollEvent(in: window, at: displayedPoint, deltaX: 12, deltaY: 16),
            atWindowPoint: displayedPoint
        )
        XCTAssertEqual(forwardedCount, 1)
        XCTAssertEqual(container.opticalVisibleOriginForTesting, normalOrigin)

        container.configureOpticalViewportForTesting(
            magnification: 0.9,
            centeredAt: CGPoint(x: 152, y: 100),
            panDelta: .zero
        )
        let shrinkOrigin = container.opticalVisibleOriginForTesting
        container.deliverOpticalScrollWheelForTesting(
            try makeScrollEvent(in: window, at: displayedPoint, deltaX: 12, deltaY: 16),
            atWindowPoint: displayedPoint
        )
        XCTAssertEqual(forwardedCount, 2)
        XCTAssertEqual(container.opticalVisibleOriginForTesting, shrinkOrigin)

        container.configureOpticalViewportForTesting(
            magnification: 1.0001,
            centeredAt: CGPoint(x: 152, y: 100),
            panDelta: .zero
        )
        let aboveNormalOrigin = container.opticalVisibleOriginForTesting
        container.deliverOpticalScrollWheelForTesting(
            try makeScrollEvent(in: window, at: displayedPoint, deltaX: -12, deltaY: 16),
            atWindowPoint: displayedPoint
        )
        XCTAssertEqual(forwardedCount, 2)
        XCTAssertNotEqual(container.opticalVisibleOriginForTesting, aboveNormalOrigin)

        let pannedOrigin = container.opticalVisibleOriginForTesting
        container.deliverOpticalScrollWheelForTesting(
            try makeScrollEvent(
                in: window,
                at: displayedPoint,
                deltaX: 12,
                deltaY: 16,
                modifierFlags: .maskAlternate
            ),
            atWindowPoint: displayedPoint
        )
        XCTAssertEqual(forwardedCount, 3)
        XCTAssertEqual(container.opticalVisibleOriginForTesting, pannedOrigin)
    }

    /// F001-S60
    func testHigherPriorityMountedHostBalancesPressBeforeReparenting() throws {
        let services = TerminalServices()
        let engine = GhosttyTerminalEngine(terminalServices: services)
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: services,
            engineFactory: { _ in engine }
        )
        defer { session.terminate() }

        let (window, root) = makeWindowAndRoot(size: CGSize(width: 640, height: 200))
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let oldHost = TerminalContainerView(
            ownershipCoordinator: services.hostOwnershipCoordinator,
            frame: NSRect(x: 0, y: 0, width: 320, height: 200),
            allowsGhosttySurfaceRestorationForTesting: false
        )
        let newHost = TerminalContainerView(
            ownershipCoordinator: services.hostOwnershipCoordinator,
            frame: NSRect(x: 320, y: 0, width: 320, height: 200),
            allowsGhosttySurfaceRestorationForTesting: false
        )
        root.addSubview(oldHost)
        root.addSubview(newHost)
        oldHost.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .compact,
            isActive: false,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(oldHost.hostsTerminalView(session.hostedView))

        var forwardedPrimaryButtonStates: [Bool] = []
        engine.terminalView.primaryMouseButtonSinkForTesting = {
            forwardedPrimaryButtonStates.append($0)
        }
        let mouseDown = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: oldHost.opticalWindowPointForTesting(terminalPoint: CGPoint(x: 20, y: 20)),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        )
        engine.terminalView.mouseDown(with: mouseDown)
        XCTAssertEqual(forwardedPrimaryButtonStates, [true])

        var newHostDoubleClickCount = 0
        newHost.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .regular,
            isActive: true,
            onDoubleClick: { newHostDoubleClickCount += 1 },
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(forwardedPrimaryButtonStates, [true, false])
        XCTAssertFalse(engine.terminalView.isPrimaryMousePressForwarded)
        XCTAssertTrue(newHost.hostsTerminalView(session.hostedView))
        XCTAssertFalse(oldHost.hostsTerminalView(session.hostedView))
        XCTAssertFalse(oldHost.hasOpticalDocumentReferenceForTesting)
        XCTAssertNotNil(engine.terminalView.opticalViewportPointerMapper)
        XCTAssertNotNil(engine.terminalView.opticalViewportPointMapper)
        XCTAssertNotNil(engine.terminalView.opticalViewportRectMapper)
        engine.terminalView.onDoubleClick?()
        XCTAssertEqual(newHostDoubleClickCount, 1)
    }

    func testMountedSameSessionHandoffResetsPanAndReacquiresFromCanonicalTransform() {
        let services = TerminalServices()
        let engine = GhosttyTerminalEngine(terminalServices: services)
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: services,
            engineFactory: { _ in engine },
            displayMagnification: 2
        )
        defer { session.terminate() }

        let (window, root) = makeWindowAndRoot(size: CGSize(width: 640, height: 200))
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let hostA = TerminalContainerView(
            ownershipCoordinator: services.hostOwnershipCoordinator,
            frame: NSRect(x: 0, y: 0, width: 320, height: 200),
            allowsGhosttySurfaceRestorationForTesting: false
        )
        let hostB = TerminalContainerView(
            ownershipCoordinator: services.hostOwnershipCoordinator,
            frame: NSRect(x: 320, y: 0, width: 320, height: 200),
            allowsGhosttySurfaceRestorationForTesting: false
        )
        root.addSubview(hostA)
        root.addSubview(hostB)
        hostA.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .compact,
            isActive: false,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()

        XCTAssertTrue(hostA.hostsTerminalView(session.hostedView))
        XCTAssertNil(engine.terminalView.surface)
        XCTAssertEqual(hostA.opticalMagnificationForTesting, 2, accuracy: 0.001)
        let initialScaledOrigin = hostA.opticalVisibleOriginForTesting
        hostA.configureOpticalViewportForTesting(
            magnification: 2,
            centeredAt: CGPoint(x: 152, y: 100),
            panDelta: CGPoint(x: 40, y: -30)
        )
        hostA.applyMagnificationGestureEventForTesting(.began)
        let stalePannedOrigin = hostA.opticalVisibleOriginForTesting
        XCTAssertNotEqual(stalePannedOrigin, initialScaledOrigin)
        XCTAssertFalse(hostA.isMagnificationGestureStateResetForTesting)

        hostB.attach(
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

        XCTAssertEqual(session.displayMagnification, 2, accuracy: 0.001)
        XCTAssertFalse(hostA.hostsTerminalView(session.hostedView))
        XCTAssertFalse(hostA.hasOpticalDocumentReferenceForTesting)
        XCTAssertEqual(hostA.opticalMagnificationForTesting, 1, accuracy: 0.001)
        XCTAssertEqual(hostA.opticalVisibleOriginForTesting, .zero)
        XCTAssertTrue(hostA.isMagnificationGestureStateResetForTesting)
        XCTAssertTrue(hostB.hostsTerminalView(session.hostedView))
        XCTAssertEqual(hostB.opticalMagnificationForTesting, 2, accuracy: 0.001)
        XCTAssertEqual(hostB.opticalVisibleOriginForTesting.x, 76, accuracy: 0.001)
        XCTAssertEqual(hostB.opticalVisibleOriginForTesting.y, 50, accuracy: 0.001)
        let centeredHandoffOrigin = hostB.opticalVisibleOriginForTesting
        XCTAssertNotEqual(centeredHandoffOrigin, stalePannedOrigin)
        XCTAssertNotNil(engine.terminalView.opticalViewportPointerMapper)
        XCTAssertNotNil(engine.terminalView.opticalViewportPointMapper)
        XCTAssertNotNil(engine.terminalView.opticalViewportRectMapper)

        hostB.applyMagnificationGestureEventForTesting(.began)
        XCTAssertFalse(hostB.isMagnificationGestureStateResetForTesting)
        hostB.removeFromSuperview()
        root.layoutSubtreeIfNeeded()
        XCTAssertEqual(session.displayMagnification, 2, accuracy: 0.001)
        XCTAssertEqual(hostB.opticalMagnificationForTesting, 1, accuracy: 0.001)
        XCTAssertEqual(hostB.opticalVisibleOriginForTesting, .zero)
        XCTAssertTrue(hostB.isMagnificationGestureStateResetForTesting)

        let reacquisitionDeadline = Date().addingTimeInterval(1)
        while !hostA.hostsTerminalView(session.hostedView), Date() < reacquisitionDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            root.layoutSubtreeIfNeeded()
        }

        XCTAssertTrue(hostA.hostsTerminalView(session.hostedView))
        XCTAssertEqual(session.displayMagnification, 2, accuracy: 0.001)
        XCTAssertEqual(hostA.opticalMagnificationForTesting, 2, accuracy: 0.001)
        XCTAssertEqual(hostA.opticalVisibleOriginForTesting.x, centeredHandoffOrigin.x, accuracy: 0.001)
        XCTAssertEqual(hostA.opticalVisibleOriginForTesting.y, centeredHandoffOrigin.y, accuracy: 0.001)
        XCTAssertNotEqual(hostA.opticalVisibleOriginForTesting, stalePannedOrigin)
    }

    /// F001-S59, F001-S61
    func testSubnormalScaleRestoresAcrossGhosttyHostHandoff() {
        let services = TerminalServices()
        let engine = GhosttyTerminalEngine(terminalServices: services)
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: services,
            engineFactory: { _ in engine },
            displayMagnification: 0.9
        )
        defer { session.terminate() }

        let (window, root) = makeWindowAndRoot(size: CGSize(width: 640, height: 200))
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let primaryHost = TerminalContainerView(
            ownershipCoordinator: services.hostOwnershipCoordinator,
            frame: NSRect(x: 0, y: 0, width: 320, height: 200),
            allowsGhosttySurfaceRestorationForTesting: false
        )
        let secondaryHost = TerminalContainerView(
            ownershipCoordinator: services.hostOwnershipCoordinator,
            frame: NSRect(x: 320, y: 0, width: 320, height: 200),
            allowsGhosttySurfaceRestorationForTesting: false
        )
        root.addSubview(primaryHost)
        root.addSubview(secondaryHost)

        primaryHost.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .compact,
            isActive: false,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(primaryHost.hostsTerminalView(session.hostedView))
        XCTAssertEqual(primaryHost.opticalMagnificationForTesting, 0.9, accuracy: 0.001)
        let terminalFrame = engine.terminalView.frame

        secondaryHost.attach(
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

        XCTAssertTrue(secondaryHost.hostsTerminalView(session.hostedView))
        XCTAssertEqual(secondaryHost.opticalMagnificationForTesting, 0.9, accuracy: 0.001)
        XCTAssertEqual(engine.terminalView.frame, terminalFrame)

        secondaryHost.removeFromSuperview()
    }

    /// F001-S59, F001-S61
    func testHostSessionReplacementRestoresSubnormalScaleAndResetsPartialGesture() {
        let services = TerminalServices()
        let firstEngine = GhosttyTerminalEngine(terminalServices: services)
        let secondEngine = GhosttyTerminalEngine(terminalServices: services)
        let firstSession = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: services,
            engineFactory: { _ in firstEngine }
        )
        let secondSession = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: services,
            engineFactory: { _ in secondEngine },
            displayMagnification: 0.7
        )
        defer {
            firstSession.terminate()
            secondSession.terminate()
        }

        let (window, root) = makeWindowAndRoot()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let container = TerminalContainerView(
            ownershipCoordinator: services.hostOwnershipCoordinator,
            frame: root.bounds,
            allowsGhosttySurfaceRestorationForTesting: false
        )
        root.addSubview(container)
        container.attach(
            firstSession.hostedView,
            session: firstSession,
            sessionID: firstSession.id,
            displayDensity: .regular,
            isActive: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()
        container.applyMagnificationGestureEventForTesting(.began)
        container.applyMagnificationGestureEventForTesting(.changed(-0.04))

        container.attach(
            secondSession.hostedView,
            session: secondSession,
            sessionID: secondSession.id,
            displayDensity: .regular,
            isActive: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(container.opticalMagnificationForTesting, 0.7, accuracy: 0.001)
        container.applyMagnificationGestureEventForTesting(.changed(-0.04))
        XCTAssertEqual(secondSession.displayMagnification, 0.7, accuracy: 0.001)
        container.applyMagnificationGestureEventForTesting(.changed(-0.04))
        XCTAssertEqual(secondSession.displayMagnification, 0.6, accuracy: 0.001)
        XCTAssertTrue(container.hostsTerminalView(secondSession.hostedView))
    }

    func testHostSessionChangeResetsCompositorTransformBeforeRestoringMagnification() {
        let services = TerminalServices()
        let firstEngine = GhosttyTerminalEngine(terminalServices: services)
        let secondEngine = GhosttyTerminalEngine(terminalServices: services)
        let firstSession = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: services,
            engineFactory: { _ in firstEngine }
        )
        let secondSession = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: services,
            engineFactory: { _ in secondEngine },
            displayMagnification: 2
        )
        defer {
            firstSession.terminate()
            secondSession.terminate()
        }

        let (_, root) = makeWindowAndRoot()
        let container = TerminalContainerView(
            ownershipCoordinator: services.hostOwnershipCoordinator,
            frame: root.bounds
        )
        root.addSubview(container)
        container.attach(
            firstSession.hostedView,
            session: firstSession,
            sessionID: firstSession.id,
            displayDensity: .regular,
            isActive: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()
        container.configureOpticalViewportForTesting(
            magnification: 2,
            centeredAt: CGPoint(x: 152, y: 100),
            panDelta: CGPoint(x: 40, y: 20)
        )

        container.attach(
            secondSession.hostedView,
            session: secondSession,
            sessionID: secondSession.id,
            displayDensity: .regular,
            isActive: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(container.opticalMagnificationForTesting, 2, accuracy: 0.001)
        XCTAssertEqual(container.opticalVisibleOriginForTesting.x, 76, accuracy: 0.001)
        XCTAssertEqual(container.opticalVisibleOriginForTesting.y, 50, accuracy: 0.001)
        XCTAssertTrue(container.hostsTerminalView(secondSession.hostedView))
    }

    /// F003-S16
    func testHostDoubleClickInvokesCallbackWithoutForwardingSecondGhosttyClick() throws {
        let (session, engine) = makeSessionAndEngine()
        defer { session.terminate() }

        let (window, root) = makeWindowAndRoot()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let container = TerminalContainerView(
            ownershipCoordinator: session.terminalServices.hostOwnershipCoordinator,
            frame: root.bounds
        )
        root.addSubview(container)
        var doubleClickCount = 0
        container.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .regular,
            isActive: true,
            onDoubleClick: { doubleClickCount += 1 },
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()

        var forwardedPrimaryButtonStates: [Bool] = []
        engine.terminalView.primaryMouseButtonSinkForTesting = {
            forwardedPrimaryButtonStates.append($0)
        }
        container.configureOpticalViewportForTesting(
            magnification: 2,
            centeredAt: CGPoint(x: 152, y: 100),
            panDelta: CGPoint(x: 20, y: 20)
        )
        let location = container.opticalWindowPointForTesting(terminalPoint: CGPoint(x: 100, y: 75))
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type,
                    location: location,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 2,
                    pressure: 0
                )
            )
        }

        engine.terminalView.mouseDown(with: try event(.leftMouseDown))

        XCTAssertEqual(doubleClickCount, 1)
        XCTAssertTrue(engine.terminalView.suppressesNextPrimaryMouseUp)
        XCTAssertTrue(forwardedPrimaryButtonStates.isEmpty)

        engine.terminalView.mouseUp(with: try event(.leftMouseUp))

        XCTAssertFalse(engine.terminalView.suppressesNextPrimaryMouseUp)
        XCTAssertFalse(engine.terminalView.isPrimaryMousePressForwarded)
        XCTAssertTrue(forwardedPrimaryButtonStates.isEmpty)
    }

    /// F003-S16
    func testDoubleClickWithoutCallbackRetainsGhosttyMouseSequence() throws {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        var forwardedPrimaryButtonStates: [Bool] = []
        engine.terminalView.primaryMouseButtonSinkForTesting = {
            forwardedPrimaryButtonStates.append($0)
        }
        engine.terminalView.opticalViewportPointerMapper = { _ in CGPoint(x: 40, y: 40) }
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 2,
                pressure: 0
            )
        )
        let mouseUp = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 2,
                pressure: 0
            )
        )

        engine.terminalView.mouseDown(with: event)
        engine.terminalView.mouseUp(with: mouseUp)

        XCTAssertEqual(forwardedPrimaryButtonStates, [true, false])
    }

    /// F001-S60
    func testHostDetachReleasesForwardedPrimaryMousePress() throws {
        let (session, engine) = makeSessionAndEngine()
        defer { session.terminate() }

        let (window, root) = makeWindowAndRoot()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let container = TerminalContainerView(
            ownershipCoordinator: session.terminalServices.hostOwnershipCoordinator,
            frame: root.bounds
        )
        root.addSubview(container)
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

        var forwardedPrimaryButtonStates: [Bool] = []
        engine.terminalView.primaryMouseButtonSinkForTesting = {
            forwardedPrimaryButtonStates.append($0)
        }
        let mouseDown = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: container.opticalWindowPointForTesting(terminalPoint: CGPoint(x: 20, y: 20)),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        )

        engine.terminalView.mouseDown(with: mouseDown)
        XCTAssertEqual(forwardedPrimaryButtonStates, [true])

        container.removeFromSuperview()

        XCTAssertFalse(engine.terminalView.isPrimaryMousePressForwarded)
        XCTAssertEqual(forwardedPrimaryButtonStates, [true, false])
    }

    /// F001-S60
    func testWindowFocusLossReleasesForwardedPrimaryMousePress() throws {
        let (session, engine) = makeSessionAndEngine()
        defer { session.terminate() }

        let (window, root) = makeWindowAndRoot()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let container = TerminalContainerView(
            ownershipCoordinator: session.terminalServices.hostOwnershipCoordinator,
            frame: root.bounds
        )
        root.addSubview(container)
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

        var forwardedPrimaryButtonStates: [Bool] = []
        engine.terminalView.primaryMouseButtonSinkForTesting = {
            forwardedPrimaryButtonStates.append($0)
        }
        let point = CGPoint(x: 20, y: 20)
        let mouseDown = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: container.opticalWindowPointForTesting(terminalPoint: point),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        )

        engine.terminalView.mouseDown(with: mouseDown)
        XCTAssertTrue(engine.terminalView.isPrimaryMousePressForwarded)
        XCTAssertEqual(forwardedPrimaryButtonStates, [true])

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)

        XCTAssertFalse(engine.terminalView.isPrimaryMousePressForwarded)
        XCTAssertEqual(forwardedPrimaryButtonStates, [true, false])
    }

    /// F001-S60
    func testDraggingInteractiveTargetTransitionsToBalancedGhosttySelection() throws {
        let (session, engine) = makeSessionAndEngine()
        defer { session.terminate() }

        let (window, root) = makeWindowAndRoot()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let container = TerminalContainerView(
            ownershipCoordinator: session.terminalServices.hostOwnershipCoordinator,
            frame: root.bounds
        )
        root.addSubview(container)
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

        engine.currentDirectoryPath = FileManager.default.temporaryDirectory.path
        var forwardedPrimaryButtonStates: [Bool] = []
        engine.terminalView.primaryMouseButtonSinkForTesting = {
            forwardedPrimaryButtonStates.append($0)
        }
        engine.terminalView.visibleContentsProviderForTesting = {
            "open https://example.com/docs here"
        }
        engine.terminalView.dimensionsProviderForTesting = { (cols: 40, rows: 2) }

        let start = CGPoint(
            x: engine.terminalView.bounds.width * 10.5 / 40,
            y: engine.terminalView.bounds.height * 0.75
        )
        let end = CGPoint(x: start.x + 20, y: start.y)
        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type,
                    location: container.opticalWindowPointForTesting(terminalPoint: point),
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 0
                )
            )
        }

        engine.terminalView.mouseDown(with: try event(.leftMouseDown, at: start))
        XCTAssertNotNil(engine.terminalView.pendingContextMenuMouseDownPoint)
        XCTAssertFalse(engine.terminalView.isPrimaryMousePressForwarded)

        engine.terminalView.mouseDragged(with: try event(.leftMouseDragged, at: end))
        XCTAssertNil(engine.terminalView.pendingContextMenuMouseDownPoint)
        XCTAssertTrue(engine.terminalView.isPrimaryMousePressForwarded)
        XCTAssertEqual(forwardedPrimaryButtonStates, [true])

        engine.terminalView.mouseUp(with: try event(.leftMouseUp, at: end))
        XCTAssertFalse(engine.terminalView.isPrimaryMousePressForwarded)
        XCTAssertEqual(forwardedPrimaryButtonStates, [true, false])
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
