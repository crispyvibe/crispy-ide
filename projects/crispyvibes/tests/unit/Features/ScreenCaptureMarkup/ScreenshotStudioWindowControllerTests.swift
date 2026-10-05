import AppKit
import XCTest
@testable import CrispyVibes

@MainActor
final class ScreenshotStudioWindowControllerTests: XCTestCase {
    func test_presentOrFocusUsesOnePanelOnCapturedDisplayAndNativeCloseCleansUp() throws {
        let fixture = try ScreenshotStudioFixture()
        let activation = Activation()
        let focus = Focus()
        let controller = ScreenshotStudioWindowController(
            registry: ScreenCaptureSurfaceRegistry(),
            announcer: fixture.editor.services.announcer,
            applicationActivator: activation,
            windowFocuser: focus
        )
        fixture.viewModel.installNewCapture(fixture.capture())

        controller.presentOrFocus(viewModel: fixture.viewModel)
        let panel = try XCTUnwrap(controller.panel)
        controller.presentOrFocus(viewModel: fixture.viewModel)

        XCTAssertTrue(controller.panel === panel)
        XCTAssertEqual(activation.count, 2)
        XCTAssertEqual(focus.keyed.count, 2)
        XCTAssertLessThanOrEqual(panel.frame.width, fixture.visibleFrame.width * 0.8 + 0.5)
        XCTAssertLessThanOrEqual(panel.frame.height, fixture.visibleFrame.height * 0.8 + 0.5)
        XCTAssertTrue(panel.collectionBehavior.contains(.moveToActiveSpace))
        panel.close()
        awaitStudioTurns()
        XCTAssertNil(controller.panel)
        XCTAssertNil(controller.viewModel)
    }

    func test_studioCoordinatorInstallsPresentsThenStartsEagerDelivery() async throws {
        let fixture = try ScreenshotStudioFixture()
        let controller = ScreenshotStudioWindowController(
            registry: ScreenCaptureSurfaceRegistry(),
            announcer: fixture.editor.services.announcer,
            applicationActivator: Activation(),
            windowFocuser: Focus()
        )
        let coordinator = ScreenshotStudioCoordinator(
            windowController: controller,
            historyStore: ScreenCaptureHistoryStore(repository: fixture.repository),
            viewModelFactory: { _ in fixture.viewModel }
        )
        let capture = fixture.capture()

        coordinator.present(capture)

        XCTAssertEqual(controller.viewModel?.selectedItemID, capture.id)
        XCTAssertNotNil(controller.panel)
        await waitForStudioCondition { fixture.clipboard.values.count == 1 }
        await waitForStudioCondition { await fixture.repository.addCount == 1 }
        controller.dismiss()
    }
}

extension ScreenshotStudioWindowControllerTests {
    func test_copyAndDismissProductionPixelsClosesPanelOnlyAfterClipboardAndHistoryPublication() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let baseRepository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: ScreenCaptureThumbnailService()
        )
        let repository = ScreenCaptureHistoryPostCommitGateRepository(base: baseRepository)
        await repository.arm(.loadEntries)
        let pasteboard = NSPasteboard(name: .init("F062.CopyAndDismiss.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("pre-populated", forType: .string)
        let rasterServices = RasterImageEditorServices.makeDefault()
        let delivery = ScreenCaptureDeliveryCoordinator(
            exporter: rasterServices.exporter,
            encoder: ScreenCaptureOutputService(encoder: RasterImageEncoder()),
            clipboard: AppKitScreenCaptureClipboard(pasteboard: pasteboard),
            repository: repository
        )
        let editor = RasterImageEditorViewModel(services: rasterServices)
        let placement = ScreenCapturePlacementContext(
            displayID: 1,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 900)
        )
        let viewModel = ScreenshotStudioViewModel(
            rasterViewModel: editor,
            repository: repository,
            delivery: delivery,
            placement: placement
        )
        let image = RasterImageTestFixtures.quadrantImage(width: 64, height: 64)
        let capture = CapturedScreenImage(
            cgImage: image,
            canvasSize: CGSize(width: 64, height: 64),
            exportScale: 1,
            nativePixelSize: CGSize(width: 64, height: 64),
            colorSpaceName: nil,
            placement: placement
        )
        let item = ScreenshotStudioItem(id: UUID(), capture: capture, source: .capture)
        let session = RasterImageEditSession.inMemory(image, canvasSize: capture.canvasSize)
        viewModel.install(item)
        viewModel.didChangeRevision(itemID: item.id, session: session, revision: 0, isDirty: false)
        XCTAssertTrue(session.commit(.stroke(.init(
            points: [CGPoint(x: 8, y: 32), CGPoint(x: 56, y: 32)],
            color: RasterColor(red: 1, green: 0, blue: 0),
            lineWidth: 10
        ))))
        let controller = ScreenshotStudioWindowController(
            registry: ScreenCaptureSurfaceRegistry(),
            announcer: rasterServices.announcer,
            applicationActivator: Activation(),
            windowFocuser: Focus()
        )
        controller.presentOrFocus(viewModel: viewModel)

        viewModel.copyAndDismiss()
        await repository.waitUntilBlocked()

        XCTAssertNotNil(controller.panel, "The panel stays open after clipboard and disk commit until guarded publication finishes")
        XCTAssertNil(pasteboard.string(forType: .string))
        let clipboardPNG = try XCTUnwrap(pasteboard.data(forType: .png))
        let clipboardTIFF = try XCTUnwrap(pasteboard.data(forType: .tiff))
        XCTAssertNotNil(NSImage(data: clipboardTIFF))
        let committedIDsBeforePublication = try await baseRepository.loadEntries().map(\.id)
        XCTAssertEqual(committedIDsBeforePublication, [item.id])

        await repository.release()
        await waitForStudioCondition { controller.panel == nil }

        let clipboardImage = try XCTUnwrap(NSBitmapImageRep(data: clipboardPNG)?.cgImage)
        let historyImage = try await baseRepository.flattenedSource(for: item.id).cgImage
        let expectedRed = (r: UInt8(255), g: UInt8(0), b: UInt8(0))
        XCTAssertTrue(RasterImageTestFixtures.matches(
            RasterImageTestFixtures.pixel(clipboardImage, x: 32, y: 32),
            expectedRed,
            tolerance: 35
        ))
        XCTAssertTrue(RasterImageTestFixtures.matches(
            RasterImageTestFixtures.pixel(historyImage, x: 32, y: 32),
            expectedRed,
            tolerance: 35
        ))
        XCTAssertNil(controller.viewModel)
    }

    func test_initialCommittedAddRaceFallsBackToUpdateAndCopyAndDismissClosesWithoutDuplicate() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let baseRepository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: ScreenCaptureThumbnailService()
        )
        let repository = ScreenCaptureCommittedAddGateRepository(base: baseRepository)
        let png = try ScreenCaptureHistoryTestFixture.png(width: 8, height: 8)
        let clipboard = RecordingClipboard()
        let delivery = ScreenCaptureDeliveryCoordinator(
            exporter: ImmediateRasterExporter(),
            encoder: FixedScreenCaptureOutput(png: png),
            clipboard: clipboard,
            repository: repository
        )
        let fixture = try ScreenshotStudioFixture()
        let viewModel = ScreenshotStudioViewModel(
            rasterViewModel: fixture.editor,
            repository: repository,
            delivery: delivery,
            placement: .init(displayID: 1, visibleFrame: fixture.visibleFrame)
        )
        let item = fixture.item()
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        viewModel.install(item)
        viewModel.didChangeRevision(itemID: item.id, session: session, revision: 0, isDirty: false)
        var closeCount = 0
        viewModel.onClose = { closeCount += 1 }

        viewModel.deliverCurrentCapture()
        await repository.waitUntilAddCommittedAndBlocked()
        viewModel.copyAndDismiss()
        await repository.releaseAdd()
        await waitForStudioCondition { closeCount == 1 }

        let addAttemptCount = await repository.addAttemptCount
        let updateAttemptCount = await repository.updateAttemptCount
        let committedIDs = try await baseRepository.loadEntries().map(\.id)
        XCTAssertEqual(addAttemptCount, 2)
        XCTAssertEqual(updateAttemptCount, 1)
        XCTAssertEqual(committedIDs, [item.id])
        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(clipboard.values.count, 2)
        viewModel.shutdown()
    }
}


extension ScreenshotStudioWindowControllerTests {
    func test_recoveryPanelActivatesApplicationBeforeKeyingOnlyRecoveryPanel() throws {
        let events = RecoveryFocusEvents()
        let controller = ScreenCaptureRecoveryPanelController(
            registry: ScreenCaptureSurfaceRegistry(),
            authorizer: RecoveryAuthorizer(),
            applicationActivator: RecoveryActivation(events: events),
            windowFocuser: RecoveryFocus(events: events),
            viewModelFactory: { title, message, commands in
                ScreenCaptureRecoveryViewModel(title: title, message: message, commands: commands)
            }
        )

        controller.presentError(.captureFailed) { _ in }
        let panel = try XCTUnwrap(controller.panel)

        XCTAssertEqual(events.values, ["activate", "key", "front"])
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(events.windows.allSatisfy { $0 === panel })
        controller.dismiss()
        XCTAssertNil(controller.panel)
    }
}

@MainActor
private final class RecoveryFocusEvents {
    var values: [String] = []
    var windows: [NSWindow] = []
}

@MainActor
private final class RecoveryActivation: ScreenCaptureApplicationActivating {
    private let events: RecoveryFocusEvents
    init(events: RecoveryFocusEvents) { self.events = events }
    func activateApplication() { events.values.append("activate") }
}

@MainActor
private final class RecoveryFocus: ScreenCaptureWindowFocusing {
    private let events: RecoveryFocusEvents
    init(events: RecoveryFocusEvents) { self.events = events }
    func makeKeyAndOrderFront(_ window: NSWindow) {
        events.values.append("key")
        events.windows.append(window)
    }
    func orderFrontRegardless(_ window: NSWindow) {
        events.values.append("front")
        events.windows.append(window)
    }
    func makeFirstResponder(_ responder: NSResponder, in window: NSWindow) -> Bool { true }
}

@MainActor
private final class RecoveryAuthorizer: ScreenCaptureAuthorizing {
    var cachedAuthorizationState: ScreenCaptureAuthorizationState { .deniedOrRestricted }
    func authorizationStatus() -> ScreenCaptureAuthorizationState { .deniedOrRestricted }
    func requestAuthorization() -> ScreenCaptureAuthorizationState { .deniedOrRestricted }
    func openScreenRecordingSettings() {}
}
