import AppKit
import SwiftUI
import XCTest

@testable import CrispyVibes

@MainActor
final class NativeSplitViewTests: XCTestCase {
    private final class SizeBox {
        var value: CGFloat

        init(_ value: CGFloat) {
            self.value = value
        }
    }

    private typealias TestSplitView = NativeSplitView<Text, Text>
    private typealias TestCoordinator = TestSplitView.Coordinator
    private var testWindows: [NSWindow] = []

    override func tearDown() {
        for window in testWindows {
            window.orderOut(nil)
            window.contentView = nil
        }
        testWindows.removeAll()
        super.tearDown()
    }

    func testBeginAndNormalMouseUpFinishExactlyOnce() {
        let fixture = makeFixture()

        fixture.coordinator.beginDividerDrag(installMonitoring: false)
        XCTAssertTrue(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.dragBeginCount, 1)

        fixture.coordinator.handleMouseUp(
            mouseEvent(.leftMouseUp, location: NSPoint(x: 220, y: 50)))

        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.dragFinishCount, 1)
        XCTAssertEqual(fixture.coordinator.dragCancellationCount, 0)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .mouseUp)
        XCTAssertEqual(fixture.size.value, 220, accuracy: 0.5)
    }

    func testCancellationAndDuplicateCancellationAreIdempotent() {
        let fixture = makeFixture()
        fixture.coordinator.beginDividerDrag(installMonitoring: false)

        fixture.coordinator.finishDividerDrag(reason: .appResignedActive)
        fixture.coordinator.finishDividerDrag(reason: .windowClosed)

        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.dragFinishCount, 1)
        XCTAssertEqual(fixture.coordinator.dragCancellationCount, 1)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .appResignedActive)
        assertResourcesRemoved(fixture.coordinator)
    }

    func testLocalDraggedAndMouseUpEventsAreConsumed() {
        let fixture = makeFixture()
        fixture.coordinator.beginDividerDrag(installMonitoring: false)

        let dragged = mouseEvent(.leftMouseDragged, location: NSPoint(x: 205, y: 50))
        XCTAssertNil(fixture.coordinator.handleLocalEvent(dragged))
        XCTAssertEqual(fixture.size.value, 205, accuracy: 0.5)

        let up = mouseEvent(.leftMouseUp, location: NSPoint(x: 215, y: 50))
        XCTAssertNil(fixture.coordinator.handleLocalEvent(up))
        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .mouseUp)
        XCTAssertEqual(fixture.size.value, 215, accuracy: 0.5)
    }

    func testGlobalMouseUpCompletesNormallyAndAppliesFinalPosition() {
        let fixture = makeFixture()
        fixture.coordinator.beginDividerDrag(installMonitoring: false)

        fixture.coordinator.handleGlobalMouseUp(
            mouseEvent(.leftMouseUp, location: NSPoint(x: 230, y: 50))
        )

        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .globalMouseUp)
        XCTAssertEqual(fixture.coordinator.dragCancellationCount, 0)
        XCTAssertEqual(fixture.size.value, 230, accuracy: 0.5)
    }

    func testStaleGlobalMouseUpCannotFinishReplacementDrag() {
        let fixture = makeFixture()
        let firstGeneration = fixture.coordinator.beginDividerDrag(installMonitoring: false)
        let secondGeneration = fixture.coordinator.beginDividerDrag(installMonitoring: false)
        let applyCountBeforeQueuedReplacementFinish = fixture.coordinator.dividerPositionApplyCount
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))

        XCTAssertTrue(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(
            fixture.coordinator.dividerPositionApplyCount,
            applyCountBeforeQueuedReplacementFinish
        )
        fixture.coordinator.handleGlobalMouseUp(
            mouseEvent(.leftMouseUp, location: NSPoint(x: 230, y: 50)),
            generation: firstGeneration
        )

        XCTAssertTrue(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.activeDragGeneration, secondGeneration)
        XCTAssertEqual(fixture.coordinator.dragFinishCount, 1)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .replacement)
        XCTAssertEqual(fixture.size.value, 150, accuracy: 0.5)

        fixture.coordinator.handleGlobalMouseUp(generation: secondGeneration)
        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.dragFinishCount, 2)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .globalMouseUp)
    }

    func testStaleLocalAndObserverCallbacksCannotAffectReplacementDrag() {
        let fixture = makeFixture()
        let firstGeneration = fixture.coordinator.beginDividerDrag(installMonitoring: false)
        let secondGeneration = fixture.coordinator.beginDividerDrag(installMonitoring: false)
        let staleDrag = mouseEvent(.leftMouseDragged, location: NSPoint(x: 240, y: 50))

        XCTAssertTrue(
            fixture.coordinator.handleLocalEvent(
                staleDrag,
                generation: firstGeneration
            ) === staleDrag
        )
        fixture.coordinator.finishDividerDrag(
            reason: .appResignedActive,
            generation: firstGeneration
        )

        XCTAssertTrue(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.activeDragGeneration, secondGeneration)
        XCTAssertEqual(fixture.coordinator.dragFinishCount, 1)
        XCTAssertEqual(fixture.size.value, 150, accuracy: 0.5)

        fixture.coordinator.finishDividerDrag(
            reason: .appResignedActive,
            generation: secondGeneration
        )
        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.dragFinishCount, 2)
    }

    func testAppDeactivationNotificationCancelsDrag() {
        let fixture = makeFixture()
        fixture.coordinator.beginDividerDrag(installMonitoring: false)

        NotificationCenter.default.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )

        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .appResignedActive)
    }

    func testWindowLifecycleNotificationsCancelDrag() {
        let cases: [(Notification.Name, DividerDragFinishReason)] = [
            (NSWindow.didResignKeyNotification, .windowResignedKey),
            (NSWindow.didMiniaturizeNotification, .windowMiniaturized),
            (NSWindow.willCloseNotification, .windowClosed),
        ]

        for (notification, expectedReason) in cases {
            let fixture = makeWindowFixture()
            fixture.coordinator.beginDividerDrag(installMonitoring: false)
            NotificationCenter.default.post(name: notification, object: fixture.window)

            XCTAssertFalse(
                fixture.coordinator.isDividerDragActive, "Failed for \(notification.rawValue)")
            XCTAssertEqual(fixture.coordinator.lastFinishReason, expectedReason)
            fixture.coordinator.shutdown(reason: .dismantled)
        }
    }

    func testWindowOrderOutCancelsDrag() {
        let fixture = makeWindowFixture()
        fixture.window.orderFront(nil)
        fixture.coordinator.beginDividerDrag(installMonitoring: false)

        fixture.window.orderOut(nil)
        NotificationCenter.default.post(
            name: NSWindow.didChangeOcclusionStateNotification,
            object: fixture.window
        )

        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .windowOrderedOut)
    }

    func testViewRemovalCancelsDrag() {
        let fixture = makeWindowFixture()
        fixture.coordinator.beginDividerDrag(installMonitoring: false)

        fixture.splitView.removeFromSuperview()

        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .viewRemoved)
    }

    func testButtonStateWatchdogCancelsAfterGrace() {
        let fixture = makeFixture()
        var time: TimeInterval = 10
        fixture.coordinator.currentTime = { time }
        fixture.coordinator.initiatingButtonIsPressed = { false }
        fixture.coordinator.beginDividerDrag(installMonitoring: false)

        time += TestCoordinator.watchdogGraceDuration + 0.01
        fixture.coordinator.evaluateWatchdog()

        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .initiatingButtonReleased)
    }

    func testMaximumDurationWatchdogCancelsEvenWhenButtonRemainsPressed() {
        let fixture = makeFixture()
        var time: TimeInterval = 20
        fixture.coordinator.currentTime = { time }
        fixture.coordinator.initiatingButtonIsPressed = { true }
        fixture.coordinator.beginDividerDrag(installMonitoring: false)

        time += TestCoordinator.maximumDragDuration
        fixture.coordinator.evaluateWatchdog()

        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .maximumDuration)
        XCTAssertLessThanOrEqual(TestCoordinator.maximumDragDuration, 30)
    }

    func testVerticalDividerPersistsPrimaryConstraintsAndMinimumSecondary() {
        let fixture = makeFixture(minPrimary: 100, maxPrimary: 350, minSecondary: 120)
        fixture.coordinator.beginDividerDrag(installMonitoring: false)

        fixture.coordinator.handleMouseDragged(
            mouseEvent(.leftMouseDragged, location: NSPoint(x: 20, y: 50))
        )
        XCTAssertEqual(fixture.size.value, 100, accuracy: 0.5)

        fixture.coordinator.handleMouseDragged(
            mouseEvent(.leftMouseDragged, location: NSPoint(x: 390, y: 50))
        )
        XCTAssertEqual(fixture.size.value, 278, accuracy: 0.5)
        fixture.coordinator.finishDividerDrag(reason: .mouseUp)
    }

    func testPrimaryAtEndAndHorizontalOrientationPersistCorrectSize() {
        let endFixture = makeFixture(primaryAtEnd: true, minPrimary: 80, maxPrimary: 250)
        endFixture.coordinator.beginDividerDrag(installMonitoring: false)
        endFixture.coordinator.handleMouseDragged(
            mouseEvent(.leftMouseDragged, location: NSPoint(x: 100, y: 50))
        )
        XCTAssertEqual(endFixture.size.value, 250, accuracy: 0.5)
        endFixture.coordinator.finishDividerDrag(reason: .mouseUp)

        let horizontalFixture = makeFixture(
            isVertical: false,
            minPrimary: 90,
            maxPrimary: 220,
            minSecondary: 60
        )
        horizontalFixture.coordinator.beginDividerDrag(installMonitoring: false)
        horizontalFixture.coordinator.handleMouseDragged(
            mouseEvent(.leftMouseDragged, location: NSPoint(x: 30, y: 75))
        )
        XCTAssertEqual(horizontalFixture.size.value, 90, accuracy: 0.5)
        horizontalFixture.coordinator.finishDividerDrag(reason: .mouseUp)
    }

    func testZeroGeometryDoesNotRetryUntilFrameBecomesUsable() {
        let fixture = makeFixture(frame: .zero)

        fixture.coordinator.applyDividerPositionIfNeeded(force: true)
        let scheduleCountAtZero = fixture.coordinator.deferredApplyScheduleCount
        let applyCountAtZero = fixture.coordinator.dividerPositionApplyCount
        for _ in 0..<3 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(fixture.coordinator.deferredApplyScheduleCount, scheduleCountAtZero)
        XCTAssertEqual(fixture.coordinator.dividerPositionApplyCount, applyCountAtZero)
        XCTAssertEqual(scheduleCountAtZero, 0)
        XCTAssertEqual(applyCountAtZero, 0)

        fixture.splitView.setFrameSize(NSSize(width: 400, height: 300))
        XCTAssertEqual(fixture.coordinator.geometryChangeRequestCount, 1)
        XCTAssertEqual(fixture.coordinator.deferredApplyScheduleCount, 1)
        XCTAssertEqual(fixture.coordinator.dividerPositionApplyCount, 0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        XCTAssertEqual(fixture.coordinator.dividerPositionApplyCount, 1)
        XCTAssertEqual(fixture.splitView.subviews[0].frame.width, 150, accuracy: 0.5)

        for _ in 0..<3 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(fixture.coordinator.deferredApplyScheduleCount, 1)
        XCTAssertEqual(fixture.coordinator.dividerPositionApplyCount, 1)
    }

    func testPrimaryAtEndChangeCancelsDragOnceAndAppliesNewSemantics() {
        let fixture = makeFixture()
        fixture.coordinator.beginDividerDrag(installMonitoring: false)
        fixture.coordinator.updateHostedContent(
            primary: Text("pending"), secondary: Text("pending-secondary"))
        let updatesBeforeChange = fixture.coordinator.hostedContentUpdateCount

        fixture.coordinator.updateParent(
            makeParent(size: fixture.size, primaryAtEnd: true)
        )
        fixture.coordinator.updateHostedContent(
            primary: Text("new-primary"),
            secondary: Text("new-secondary")
        )

        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.dragFinishCount, 1)
        XCTAssertEqual(fixture.coordinator.dragCancellationCount, 1)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .configurationChanged)
        XCTAssertEqual(fixture.coordinator.hostedContentUpdateCount, updatesBeforeChange)

        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        XCTAssertEqual(fixture.splitView.subviews[0].frame.width, 248, accuracy: 0.5)
        XCTAssertEqual(fixture.coordinator.hostedContentUpdateCount, updatesBeforeChange + 1)
        XCTAssertEqual(fixture.coordinator.hostedContentFlushCount, 1)
    }

    func testConstraintChangeCancelsDragOnceAndAppliesNewConstraint() {
        let fixture = makeFixture()
        fixture.coordinator.beginDividerDrag(installMonitoring: false)
        let updatedParent = makeParent(
            size: fixture.size,
            minPrimary: 180,
            maxPrimary: 320,
            minSecondary: 90
        )

        fixture.coordinator.updateParent(updatedParent)
        fixture.coordinator.updateParent(updatedParent)

        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        XCTAssertEqual(fixture.coordinator.dragFinishCount, 1)
        XCTAssertEqual(fixture.coordinator.dragCancellationCount, 1)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .configurationChanged)

        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        XCTAssertEqual(fixture.splitView.subviews[0].frame.width, 180, accuracy: 0.5)
    }

    func testNonDividerMouseDownIsForwardedWhileDividerHitIsConsumed() {
        let fixture = makeFixture()
        let nonDivider = mouseEvent(.leftMouseDown, location: NSPoint(x: 20, y: 50))
        fixture.splitView.mouseDown(with: nonDivider)
        XCTAssertEqual(fixture.splitView.nonDividerMouseDownForwardCount, 1)
        XCTAssertEqual(fixture.splitView.dividerMouseDownCount, 0)

        let divider = mouseEvent(.leftMouseDown, location: NSPoint(x: 150, y: 50))
        fixture.splitView.mouseDown(with: divider)
        XCTAssertEqual(fixture.splitView.dividerMouseDownCount, 1)
        XCTAssertTrue(fixture.coordinator.isDividerDragActive)
        fixture.coordinator.finishDividerDrag(reason: .dismantled)
    }

    func testInitialHostedContentPopulatesBothStableRootsSynchronouslyOnce() {
        let fixture = makeFixture()
        let firstHost = fixture.coordinator.firstHost
        let secondHost = fixture.coordinator.secondHost

        XCTAssertEqual(fixture.coordinator.hostedContentUpdateCount, 0)
        XCTAssertEqual(fixture.coordinator.firstContentHolder.updateCount, 0)
        XCTAssertEqual(fixture.coordinator.secondContentHolder.updateCount, 0)

        fixture.coordinator.populateInitialHostedContent(
            primary: Text("initial-primary"),
            secondary: Text("initial-secondary")
        )

        XCTAssertEqual(fixture.coordinator.hostedContentUpdateCount, 1)
        XCTAssertEqual(fixture.coordinator.firstContentHolder.updateCount, 1)
        XCTAssertEqual(fixture.coordinator.secondContentHolder.updateCount, 1)
        XCTAssertTrue(firstHost === fixture.coordinator.firstHost)
        XCTAssertTrue(secondHost === fixture.coordinator.secondHost)
        XCTAssertEqual(fixture.coordinator.firstRootAssignmentCount, 1)
        XCTAssertEqual(fixture.coordinator.secondRootAssignmentCount, 1)

        fixture.coordinator.populateInitialHostedContent(
            primary: Text("ignored-primary"),
            secondary: Text("ignored-secondary")
        )
        XCTAssertEqual(fixture.coordinator.hostedContentUpdateCount, 1)
    }

    func testHostedContentUpdatesAreSuppressedAndCoalescedDuringDrag() {
        let fixture = makeFixture()
        fixture.coordinator.updateHostedContent(
            primary: Text("initial"), secondary: Text("secondary"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        let updatesBeforeDrag = fixture.coordinator.hostedContentUpdateCount
        fixture.coordinator.beginDividerDrag(installMonitoring: false)

        fixture.coordinator.updateHostedContent(
            primary: Text("one"), secondary: Text("one-secondary"))
        fixture.coordinator.updateHostedContent(
            primary: Text("two"), secondary: Text("two-secondary"))

        XCTAssertEqual(fixture.coordinator.hostedContentSuppressedCount, 2)
        XCTAssertEqual(fixture.coordinator.hostedContentSuppressionIndicationCount, 1)
        XCTAssertEqual(fixture.coordinator.hostedContentUpdateCount, updatesBeforeDrag)
        fixture.coordinator.finishDividerDrag(reason: .appResignedActive)
        XCTAssertEqual(fixture.coordinator.hostedContentFlushCount, 0)
        XCTAssertEqual(fixture.coordinator.hostedContentUpdateCount, updatesBeforeDrag)
        XCTAssertEqual(fixture.coordinator.firstContentHolder.updateCount, updatesBeforeDrag)
        XCTAssertEqual(fixture.coordinator.secondContentHolder.updateCount, updatesBeforeDrag)

        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        XCTAssertEqual(fixture.coordinator.hostedContentFlushCount, 1)
        XCTAssertEqual(fixture.coordinator.hostedContentFlushIndicationCount, 1)
        XCTAssertEqual(fixture.coordinator.hostedContentUpdateCount, updatesBeforeDrag + 1)
        XCTAssertEqual(fixture.coordinator.firstContentHolder.updateCount, updatesBeforeDrag + 1)
        XCTAssertEqual(fixture.coordinator.secondContentHolder.updateCount, updatesBeforeDrag + 1)
    }

    func testHostingRootsStayStableAndUnchangedDividerColorDoesNotInvalidate() {
        let fixture = makeFixture()
        let firstHost = fixture.coordinator.firstHost
        let secondHost = fixture.coordinator.secondHost
        let color = NSColor.systemBlue

        XCTAssertTrue(fixture.splitView.updateDividerColorIfNeeded(color))
        let appearanceUpdates = fixture.splitView.dividerAppearanceUpdateCount
        XCTAssertFalse(fixture.splitView.updateDividerColorIfNeeded(color))
        XCTAssertEqual(fixture.splitView.dividerAppearanceUpdateCount, appearanceUpdates)

        fixture.coordinator.updateHostedContent(primary: Text("one"), secondary: Text("two"))
        fixture.coordinator.updateHostedContent(primary: Text("three"), secondary: Text("four"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        XCTAssertTrue(firstHost === fixture.coordinator.firstHost)
        XCTAssertTrue(secondHost === fixture.coordinator.secondHost)
        XCTAssertEqual(fixture.coordinator.firstRootAssignmentCount, 1)
        XCTAssertEqual(fixture.coordinator.secondRootAssignmentCount, 1)
        XCTAssertEqual(fixture.coordinator.firstContentHolder.updateCount, 1)
        XCTAssertEqual(fixture.coordinator.secondContentHolder.updateCount, 1)
    }

    func testRepeatedInterruptedDragsLeaveNoResourcesOrState() {
        let fixture = makeFixture()

        for _ in 0..<20 {
            fixture.coordinator.beginDividerDrag(installMonitoring: true)
            XCTAssertTrue(fixture.coordinator.isDividerDragActive)
            fixture.coordinator.finishDividerDrag(reason: .appResignedActive)
            assertResourcesRemoved(fixture.coordinator)
        }

        XCTAssertEqual(fixture.coordinator.dragBeginCount, 20)
        XCTAssertEqual(fixture.coordinator.dragFinishCount, 20)
        XCTAssertEqual(fixture.coordinator.dragCancellationCount, 20)
    }

    func testDismantleCancelsDragDiscardsPendingContentAndDetachesSplitView() {
        let fixture = makeFixture()
        fixture.coordinator.updateHostedContent(
            primary: Text("initial"), secondary: Text("initial-secondary"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        let updatesBeforeDrag = fixture.coordinator.hostedContentUpdateCount
        fixture.coordinator.beginDividerDrag(installMonitoring: true)
        fixture.coordinator.updateHostedContent(
            primary: Text("pending"), secondary: Text("pending-secondary"))

        TestSplitView.dismantleNSView(fixture.splitView, coordinator: fixture.coordinator)

        XCTAssertEqual(fixture.coordinator.hostedContentUpdateCount, updatesBeforeDrag)
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        XCTAssertEqual(fixture.coordinator.hostedContentUpdateCount, updatesBeforeDrag)
        XCTAssertEqual(fixture.coordinator.hostedContentFlushCount, 0)
        assertResourcesRemoved(fixture.coordinator)
        XCTAssertEqual(fixture.coordinator.lastFinishReason, .dismantled)
        XCTAssertNil(fixture.splitView.delegate)
        XCTAssertNil(fixture.splitView.onDividerMouseDown)
        XCTAssertNil(fixture.splitView.onDividerMouseDragged)
        XCTAssertNil(fixture.splitView.onDividerMouseUp)
        XCTAssertNil(fixture.splitView.onViewRemoved)
        XCTAssertNil(fixture.splitView.onGeometryChanged)
        XCTAssertNil(fixture.splitView.isCustomDividerDragActive)
    }

    func testDiagnosticSeverityReservesErrorForWatchdogInvariantRecovery() {
        let expectedLifecycleReasons: [DividerDragFinishReason] = [
            .mouseUp, .globalMouseUp, .replacement, .appResignedActive,
            .windowResignedKey, .windowMiniaturized, .windowClosed,
            .windowOrderedOut, .viewRemoved, .configurationChanged,
            .dismantled, .deinitialized,
        ]
        XCTAssertTrue(expectedLifecycleReasons.allSatisfy { !$0.isErrorDiagnostic })
        XCTAssertTrue(DividerDragFinishReason.initiatingButtonReleased.isErrorDiagnostic)
        XCTAssertTrue(DividerDragFinishReason.maximumDuration.isErrorDiagnostic)
    }

    func testMountedRepresentableSynchronouslyPopulatesStableHostsAndKeepsRootsOnUpdate() throws {
        let model = MountedNativeSplitModel()
        let root = MountedNativeSplitRoot(model: model)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 500, height: 320)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        testWindows.append(window)
        hosting.layoutSubtreeIfNeeded()

        let splitView = try XCTUnwrap(firstDescendant(of: TrackingSplitView.self, in: hosting))
        let hosts = splitView.subviews.compactMap {
            $0 as? OverflowHostingView<SplitHostedContentRoot>
        }
        XCTAssertEqual(hosts.count, 2)
        let firstHost = try XCTUnwrap(hosts.first)
        let secondHost = try XCTUnwrap(hosts.last)
        let firstHolder = firstHost.rootView.holder
        let secondHolder = secondHost.rootView.holder
        XCTAssertFalse(firstHolder === secondHolder)
        XCTAssertEqual(firstHolder.updateCount, 1)
        XCTAssertEqual(secondHolder.updateCount, 1)

        model.primary = "primary-B"
        model.secondary = "secondary-B"
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        hosting.layoutSubtreeIfNeeded()

        let updatedSplitView = try XCTUnwrap(firstDescendant(of: TrackingSplitView.self, in: hosting))
        let updatedHosts = updatedSplitView.subviews.compactMap {
            $0 as? OverflowHostingView<SplitHostedContentRoot>
        }
        XCTAssertTrue(updatedSplitView === splitView)
        XCTAssertEqual(updatedHosts.count, 2)
        XCTAssertTrue(updatedHosts[0] === firstHost)
        XCTAssertTrue(updatedHosts[1] === secondHost)
        XCTAssertTrue(updatedHosts[0].rootView.holder === firstHolder)
        XCTAssertTrue(updatedHosts[1].rootView.holder === secondHolder)
        XCTAssertGreaterThanOrEqual(firstHolder.updateCount, 2)
        XCTAssertGreaterThanOrEqual(secondHolder.updateCount, 2)
        XCTAssertNotNil(descendant(in: firstHost, identifier: "native-split-sentinel.primary-B"))
        XCTAssertNotNil(descendant(in: secondHost, identifier: "native-split-sentinel.secondary-B"))
    }

    func testUIRegressionIsLocalOnlyAndTeardownExcludesInstalledProductionApp() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let regression = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "tests/ui/App/ChromeAndSettingsUITests.swift"
            ),
            encoding: .utf8
        )
        let support = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "tests/ui/Support/UITestSupport.swift"
            ),
            encoding: .utf8
        )
        let localGuard = try XCTUnwrap(
            regression.range(of: "guard UITestAppTarget.current == .local else")
        )
        let fixtureCreation = try XCTUnwrap(
            regression.range(of: "let fixture = try makeFixture(projectCount: 1)")
        )
        let launch = try XCTUnwrap(regression.range(of: "app.launch()"))

        XCTAssertLessThan(localGuard.lowerBound, fixtureCreation.lowerBound)
        XCTAssertLessThan(localGuard.lowerBound, launch.lowerBound)
        XCTAssertTrue(
            regression.contains(
                "testAppTerminationMatchingRejectsEveryMainProfileAndAllowsLocalOnly"
            )
        )
        XCTAssertTrue(
            support.contains(
                "static let installedProductionExecutablePath = \"/Applications/Crispy.app/Contents/MacOS/Crispy\""
            )
        )
        XCTAssertTrue(support.contains("guard self == .local else { return false }"))
        XCTAssertTrue(support.contains("target.shouldTerminate("))
    }

    func testRealWindowDividerMouseDownReturnsPromptlyAndDeactivationClearsState() {
        let fixture = makeWindowFixture()
        fixture.window.orderFront(nil)
        fixture.splitView.layoutSubtreeIfNeeded()
        fixture.splitView.setPosition(150, ofDividerAt: 0)
        let event = mouseEvent(
            .leftMouseDown,
            location: NSPoint(x: 150, y: 80),
            windowNumber: fixture.window.windowNumber
        )

        let start = ProcessInfo.processInfo.systemUptime
        fixture.splitView.mouseDown(with: event)
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        XCTAssertLessThan(elapsed, 0.1)
        XCTAssertTrue(fixture.coordinator.isDividerDragActive)
        NotificationCenter.default.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )
        XCTAssertFalse(fixture.coordinator.isDividerDragActive)
        assertResourcesRemoved(fixture.coordinator)
    }

    private func makeFixture(
        isVertical: Bool = true,
        primaryAtEnd: Bool = false,
        minPrimary: CGFloat = 100,
        maxPrimary: CGFloat = 300,
        minSecondary: CGFloat = 80,
        frame: NSRect = NSRect(x: 0, y: 0, width: 400, height: 300)
    ) -> (splitView: TrackingSplitView, coordinator: TestCoordinator, size: SizeBox) {
        let size = SizeBox(150)
        let parent = makeParent(
            size: size,
            isVertical: isVertical,
            primaryAtEnd: primaryAtEnd,
            minPrimary: minPrimary,
            maxPrimary: maxPrimary,
            minSecondary: minSecondary
        )
        let coordinator = TestCoordinator(parent: parent)
        let splitView = TrackingSplitView(frame: frame)
        splitView.isVertical = isVertical
        splitView.delegate = coordinator
        splitView.addArrangedSubview(coordinator.firstHost)
        splitView.addArrangedSubview(coordinator.secondHost)
        coordinator.attach(splitView)
        wire(splitView, to: coordinator)
        splitView.adjustSubviews()
        if (isVertical ? frame.width : frame.height) > splitView.dividerThickness {
            splitView.setPosition(150, ofDividerAt: 0)
            splitView.adjustSubviews()
        }
        return (splitView, coordinator, size)
    }

    private func makeParent(
        size: SizeBox,
        isVertical: Bool = true,
        primaryAtEnd: Bool = false,
        minPrimary: CGFloat = 100,
        maxPrimary: CGFloat = 300,
        minSecondary: CGFloat = 80
    ) -> TestSplitView {
        TestSplitView(
            isVerticalSplit: isVertical,
            primaryAtEnd: primaryAtEnd,
            primarySize: Binding(
                get: { size.value },
                set: { size.value = $0 }
            ),
            minPrimary: minPrimary,
            maxPrimary: maxPrimary,
            minSecondary: minSecondary,
            primary: { Text("primary") },
            secondary: { Text("secondary") }
        )
    }

    private func makeWindowFixture() -> (
        window: NSWindow,
        splitView: TrackingSplitView,
        coordinator: TestCoordinator,
        size: SizeBox
    ) {
        let fixture = makeFixture()
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = fixture.splitView
        testWindows.append(window)
        fixture.splitView.frame = window.contentView?.bounds ?? .zero
        fixture.splitView.autoresizingMask = [.width, .height]
        fixture.splitView.layoutSubtreeIfNeeded()
        return (window, fixture.splitView, fixture.coordinator, fixture.size)
    }

    private func wire(_ splitView: TrackingSplitView, to coordinator: TestCoordinator) {
        splitView.onDividerMouseDown = { [weak coordinator] event in
            coordinator?.beginDividerDrag(with: event)
        }
        splitView.onDividerMouseDragged = { [weak coordinator] event in
            coordinator?.handleMouseDragged(event)
        }
        splitView.onDividerMouseUp = { [weak coordinator] event in
            coordinator?.handleMouseUp(event)
        }
        splitView.onViewRemoved = { [weak coordinator] in
            coordinator?.finishDividerDrag(reason: .viewRemoved)
        }
        splitView.onGeometryChanged = { [weak coordinator] in
            coordinator?.requestApplyAfterGeometryChange()
        }
        splitView.isCustomDividerDragActive = { [weak coordinator] in
            coordinator?.isDividerDragActive == true
        }
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

    private func mouseEvent(
        _ type: NSEvent.EventType,
        location: NSPoint,
        windowNumber: Int = 0
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        )!
    }

    private func assertResourcesRemoved(
        _ coordinator: TestCoordinator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(coordinator.localEventMonitor, file: file, line: line)
        XCTAssertNil(coordinator.globalEventMonitor, file: file, line: line)
        XCTAssertTrue(coordinator.dragObservers.isEmpty, file: file, line: line)
        XCTAssertNil(coordinator.watchdogTimer, file: file, line: line)
        XCTAssertFalse(coordinator.isDividerDragActive, file: file, line: line)
    }
}


@MainActor
private final class MountedNativeSplitModel: ObservableObject {
    @Published var primary = "primary-A"
    @Published var secondary = "secondary-A"
    var primarySize: CGFloat = 180
}

@MainActor
private struct MountedNativeSplitRoot: View {
    @ObservedObject var model: MountedNativeSplitModel

    var body: some View {
        NativeSplitView(
            isVerticalSplit: true,
            primaryAtEnd: false,
            primarySize: Binding(
                get: { model.primarySize },
                set: { model.primarySize = $0 }
            ),
            minPrimary: 100,
            maxPrimary: 300,
            minSecondary: 100,
            primary: { NativeSplitSentinel(identity: model.primary) },
            secondary: { NativeSplitSentinel(identity: model.secondary) }
        )
    }
}

@MainActor
private struct NativeSplitSentinel: NSViewRepresentable {
    let identity: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.setAccessibilityIdentifier("native-split-sentinel.\(identity)")
    }
}
