import CoreGraphics
import XCTest
@testable import CrispyVibes

/// F062 selection behavior without real displays, TCC, or sleeps.
@MainActor
final class CaptureSelectionViewModelTests: XCTestCase {
    private actor Magnifier: ScreenCaptureMagnifierSampling {
        func sample(_ request: ScreenCaptureMagnifierRequest) async -> CGImage? { nil }
    }

    private actor ManualScheduler: ScreenCaptureScheduling {
        private var continuations: [CheckedContinuation<Void, Error>] = []

        func sleep(for duration: Duration) async throws {
            try await withCheckedThrowingContinuation { continuations.append($0) }
        }

        func advance() {
            guard !continuations.isEmpty else { return }
            continuations.removeFirst().resume()
        }

        var pendingSleepCount: Int { continuations.count }
    }

    private actor ControlledMagnifier: ScreenCaptureMagnifierSampling {
        private var requests: [ScreenCaptureMagnifierRequest] = []
        private var continuations: [CheckedContinuation<CGImage?, Never>] = []

        func sample(_ request: ScreenCaptureMagnifierRequest) async -> CGImage? {
            requests.append(request)
            return await withCheckedContinuation { continuations.append($0) }
        }

        var requestCount: Int { requests.count }

        func request(at index: Int) -> ScreenCaptureMagnifierRequest? {
            requests.indices.contains(index) ? requests[index] : nil
        }

        func completeNext(with image: CGImage?) {
            guard !continuations.isEmpty else { return }
            continuations.removeFirst().resume(returning: image)
        }
    }

    func test_rememberedWindowModeStillExposesImmediateModeChanges() {
        var announcements: [String] = []
        let viewModel = makeViewModel(initialMode: .window) { announcements.append($0) }
        XCTAssertEqual(viewModel.mode, .window)
        viewModel.selectMode(.display)
        viewModel.selectMode(.region)
        XCTAssertEqual(viewModel.mode, .region)
        XCTAssertEqual(announcements.count, 2)
    }

    func test_regionCommitsOnReleaseWithNativeRetinaDimensions() throws {
        let viewModel = makeViewModel(initialMode: .region)
        var committed: CaptureSelectionDescriptor?
        viewModel.onCommit = { committed = $0 }
        viewModel.beginRegion(on: 7, swiftUIPoint: CGPoint(x: 10, y: 10))
        viewModel.finishRegion(on: 7, swiftUIPoint: CGPoint(x: 110, y: 60))
        guard case .region(let displayID, let pixels) = try XCTUnwrap(committed?.target) else {
            return XCTFail("Expected region")
        }
        XCTAssertEqual(displayID, 7)
        XCTAssertEqual(pixels.size, CGSize(width: 200, height: 100))
        XCTAssertEqual(viewModel.nativePixelSize, CGSize(width: 200, height: 100))
    }

    func test_crossBoundaryDragClampsAndAnnouncesBeforeRelease() {
        var announcements: [String] = []
        let viewModel = makeViewModel(initialMode: .region) { announcements.append($0) }
        viewModel.beginRegion(on: 7, swiftUIPoint: CGPoint(x: 100, y: 100))
        viewModel.updateRegion(on: 7, swiftUIPoint: CGPoint(x: 900, y: -20))
        XCTAssertTrue(viewModel.boundaryResistanceVisible)
        XCTAssertEqual(viewModel.regionLocalRect?.maxX, 800)
        XCTAssertEqual(viewModel.regionLocalRect?.maxY, 600)
        XCTAssertTrue(announcements.contains(AppStrings.ScreenCapture.regionLimitedToDisplay))
    }

    func test_F062_S05_windowClickCommitsCompleteWindowWithoutSecondConfirmation() {
        let viewModel = makeViewModel(initialMode: .window)
        var commits: [CaptureSelectionDescriptor] = []
        viewModel.onCommit = { commits.append($0) }
        viewModel.selectWindow(9)
        viewModel.commitCurrentTarget()
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.first?.target, .window(windowID: 9, placementDisplayID: 7))
    }

    func test_F062_S06_displayClickCommitsSelectedNativeDisplay() {
        let viewModel = makeViewModel(initialMode: .display)
        var committed: CaptureSelectionDescriptor?
        viewModel.onCommit = { committed = $0 }
        viewModel.selectDisplay(7)
        viewModel.commitCurrentTarget()
        XCTAssertEqual(committed?.target, .display(displayID: 7))
        XCTAssertEqual(viewModel.catalog.displays.first?.nativePixelSize, CGSize(width: 1_600, height: 1_200))
    }

    func test_keyboardAndVoiceOverCommitAndCancel() {
        var announcements: [String] = []
        let viewModel = makeViewModel(initialMode: .window) { announcements.append($0) }
        var committed: CaptureSelectionDescriptor?
        var cancelled = false
        viewModel.onCommit = { committed = $0 }
        viewModel.onCancel = { cancelled = true }
        viewModel.traverseTarget(forward: true)
        viewModel.commitCurrentTarget()
        viewModel.cancel()
        XCTAssertEqual(committed?.target, .window(windowID: 9, placementDisplayID: 7))
        XCTAssertTrue(cancelled)
        XCTAssertTrue(announcements.contains { $0.contains("Window") })
    }

    func test_delayAndPointerUpdateSelectionOptions() {
        let viewModel = makeViewModel(initialMode: .display)
        viewModel.selectDelay(.threeSeconds)
        viewModel.setIncludesPointer(true)
        XCTAssertEqual(viewModel.options, CaptureOptions(delay: .threeSeconds, includesPointer: true))
        viewModel.shutdown()
    }

    func test_countdownUsesInjectedClockAndAnnouncesEverySecond() async throws {
        let scheduler = ManualScheduler()
        var announcements: [String] = []
        let delay = ScreenCaptureDelayViewModel(scheduler: scheduler) { announcements.append($0) }
        let task = Task { try await delay.wait(for: .threeSeconds) }
        await waitForCountdown(3, in: delay)
        await scheduler.advance()
        await waitForCountdown(2, in: delay)
        await scheduler.advance()
        await waitForCountdown(1, in: delay)
        await scheduler.advance()
        try await task.value
        XCTAssertNil(delay.countdown)
        XCTAssertEqual(announcements, [3, 2, 1].map(AppStrings.ScreenCapture.countdown))
    }

    func test_magnifierLatestWinsPublishesTrailingRequestAtBoundedCadence() async throws {
        let sampler = ControlledMagnifier()
        let scheduler = ManualScheduler()
        let viewModel = makeViewModel(initialMode: .region, magnifierSampler: sampler, scheduler: scheduler)
        defer { viewModel.shutdown() }

        viewModel.hover(on: 7, swiftUIPoint: CGPoint(x: 100, y: 100))
        await waitUntil { await sampler.requestCount == 1 }
        viewModel.hover(on: 7, swiftUIPoint: CGPoint(x: 200, y: 100))
        viewModel.hover(on: 7, swiftUIPoint: CGPoint(x: 300, y: 100))

        let imageA = try makeImage(red: 10)
        let imageC = try makeImage(red: 30)
        await sampler.completeNext(with: imageA)
        await waitUntil { await scheduler.pendingSleepCount == 1 }
        XCTAssertNil(viewModel.magnifierImage, "A must be suppressed when a newer request is pending")
        await scheduler.advance()
        await waitUntil { await sampler.requestCount == 2 }

        let trailingRequest = await sampler.request(at: 1)
        let trailing = try XCTUnwrap(trailingRequest)
        XCTAssertEqual(trailing.sourceRect, CGRect(x: 295, y: 95, width: 10, height: 10))
        await sampler.completeNext(with: imageC)
        await waitUntil { viewModel.magnifierImage === imageC }
        XCTAssertTrue(viewModel.magnifierImage === imageC)
        let requestCount = await sampler.requestCount
        XCTAssertEqual(requestCount, 2, "B must be coalesced and sampling must remain bounded")
    }

    func test_modeChangeAndShutdownBlockLateMagnifierPublication() async throws {
        let modeSampler = ControlledMagnifier()
        let modeViewModel = makeViewModel(initialMode: .region, magnifierSampler: modeSampler)
        modeViewModel.hover(on: 7, swiftUIPoint: CGPoint(x: 100, y: 100))
        await waitUntil { await modeSampler.requestCount == 1 }
        modeViewModel.selectMode(.window)
        await modeSampler.completeNext(with: try makeImage(red: 40))
        await settle()
        XCTAssertNil(modeViewModel.magnifierImage)
        modeViewModel.shutdown()

        let shutdownSampler = ControlledMagnifier()
        let shutdownViewModel = makeViewModel(initialMode: .region, magnifierSampler: shutdownSampler)
        shutdownViewModel.hover(on: 7, swiftUIPoint: CGPoint(x: 100, y: 100))
        await waitUntil { await shutdownSampler.requestCount == 1 }
        shutdownViewModel.shutdown()
        await shutdownSampler.completeNext(with: try makeImage(red: 50))
        await settle()
        XCTAssertNil(shutdownViewModel.magnifierImage)
    }

    func test_magnifierSamplesPointerNeighborhoodIndependentOfSelectedRegionSize() async throws {
        let sampler = ControlledMagnifier()
        let scheduler = ManualScheduler()
        let viewModel = makeViewModel(initialMode: .region, magnifierSampler: sampler, scheduler: scheduler)
        defer { viewModel.shutdown() }

        viewModel.beginRegion(on: 7, swiftUIPoint: CGPoint(x: 10, y: 10))
        await waitUntil { await sampler.requestCount == 1 }
        viewModel.updateRegion(on: 7, swiftUIPoint: CGPoint(x: 700, y: 500))
        await sampler.completeNext(with: nil)
        await waitUntil { await scheduler.pendingSleepCount == 1 }
        await scheduler.advance()
        await waitUntil { await sampler.requestCount == 2 }

        let sampledRequest = await sampler.request(at: 1)
        let request = try XCTUnwrap(sampledRequest)
        XCTAssertEqual(viewModel.nativePixelSize, CGSize(width: 1_380, height: 980))
        XCTAssertEqual(request.outputSize, CGSize(width: 20, height: 20))
        XCTAssertEqual(request.sourceRect.size, CGSize(width: 10, height: 10))
        XCTAssertNotEqual(request.sourceRect.size, viewModel.regionLocalRect?.size)
        await sampler.completeNext(with: nil)
    }

    func test_zeroDelayIsVisibleAndCancellationPreventsLateCompletion() async {
        let scheduler = ManualScheduler()
        var announcements: [String] = []
        let delay = ScreenCaptureDelayViewModel(scheduler: scheduler) { announcements.append($0) }
        let task = Task { try await delay.wait(for: .none, showNoneFor: .milliseconds(350)) }
        await waitForCountdown(0, in: delay)
        task.cancel()
        await scheduler.advance()
        var didCancel = false
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            didCancel = true
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(didCancel)
        XCTAssertEqual(announcements, [AppStrings.ScreenCapture.delayChanged(0)])
    }

    private func waitForCountdown(_ value: Int, in viewModel: ScreenCaptureDelayViewModel) async {
        for _ in 0..<100 where viewModel.countdown != value { await Task.yield() }
        XCTAssertEqual(viewModel.countdown, value)
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not met")
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func makeImage(red: UInt8) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: CGFloat(red) / 255, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return try XCTUnwrap(context.makeImage())
    }

    private func makeViewModel(
        initialMode: CaptureMode,
        magnifierSampler: any ScreenCaptureMagnifierSampling = Magnifier(),
        scheduler: any ScreenCaptureScheduling = ContinuousScreenCaptureScheduler(),
        announce: @escaping (String) -> Void = { _ in }
    ) -> CaptureSelectionViewModel {
        let display = ScreenCaptureDisplayDescriptor(
            id: 7,
            appKitFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            captureKitFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            visibleAppKitFrame: CGRect(x: 0, y: 0, width: 800, height: 560),
            backingScale: 2,
            nativePixelSize: CGSize(width: 1_600, height: 1_200)
        )
        let window = ScreenCaptureWindowDescriptor(
            id: 9,
            frame: CGRect(x: 20, y: 20, width: 200, height: 100),
            windowLayer: 0,
            isOnScreen: true,
            placementDisplayID: 7
        )
        return CaptureSelectionViewModel(
            catalog: ScreenCaptureCatalog(generation: 4, displays: [display], windows: [window]),
            initialMode: initialMode,
            options: .default,
            magnifierSampler: magnifierSampler,
            excludedWindowIDs: { [] },
            scheduler: scheduler,
            announce: announce
        )
    }
}
