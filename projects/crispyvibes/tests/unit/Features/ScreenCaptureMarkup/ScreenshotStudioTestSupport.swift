import AppKit
import XCTest
@testable import CrispyVibes

@MainActor
final class ScreenshotStudioFixture {
    let visibleFrame = CGRect(x: 400, y: 200, width: 1_200, height: 900)
    let repository: ControlledRepository
    let clipboard: RecordingClipboard
    let exporter: RasterExporterRecording
    let delivery: ScreenCaptureDeliveryCoordinator
    let editor: RasterImageEditorViewModel
    let viewModel: ScreenshotStudioViewModel
    let image: CGImage

    init(
        repository: ControlledRepository? = nil,
        output: (any ScreenCaptureOutputEncoding)? = nil,
        clipboard: RecordingClipboard? = nil,
        scheduler: any ScreenCaptureScheduling = ContinuousScreenCaptureScheduler(),
        exporter: RasterExporterRecording? = nil
    ) throws {
        self.repository = try repository ?? ControlledRepository()
        self.clipboard = clipboard ?? RecordingClipboard()
        self.exporter = exporter ?? ImmediateRasterExporter()
        image = try Self.makeImage()
        delivery = ScreenCaptureDeliveryCoordinator(
            exporter: self.exporter,
            encoder: output ?? ImmediateOutput(),
            clipboard: self.clipboard,
            repository: self.repository,
            scheduler: scheduler
        )
        editor = RasterImageEditorViewModel(services: .makeDefault())
        viewModel = ScreenshotStudioViewModel(
            rasterViewModel: editor,
            repository: self.repository,
            delivery: delivery,
            placement: .init(displayID: 7, visibleFrame: visibleFrame)
        )
    }

    func item(id: UUID = UUID(), source: ScreenshotStudioItem.Source = .capture) -> ScreenshotStudioItem {
        .init(id: id, capture: capturedImage(), source: source)
    }

    func capture(id: UUID = UUID()) -> AcquiredScreenCapture {
        AcquiredScreenCapture(id: id, image: capturedImage())
    }

    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }

    func capturedImage() -> CapturedScreenImage {
        .init(
            cgImage: image,
            canvasSize: imageSize,
            exportScale: 1,
            nativePixelSize: imageSize,
            colorSpaceName: nil,
            placement: .init(displayID: 7, visibleFrame: visibleFrame)
        )
    }

    static func makeImage() throws -> CGImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try XCTUnwrap(context.makeImage())
    }
}

protocol RasterExporterRecording: RasterImageExporting {
    @MainActor var count: Int { get }
    @MainActor var revisions: [Int] { get }
}

final class ImmediateRasterExporter: RasterExporterRecording, @unchecked Sendable {
    @MainActor private(set) var count = 0
    @MainActor private(set) var revisions: [Int] = []

    func export(
        _ job: RasterImageExportJob,
        completion: @escaping @MainActor (Result<RasterImageExportResult, Error>) -> Void
    ) -> RasterImageWorkHandle {
        let handle = RasterImageWorkHandle()
        MainActor.assumeIsolated {
            count += 1
            revisions.append(job.revision)
            let image: CGImage
            switch job.source {
            case .memory(let source): image = source
            case .file: return
            }
            completion(.success(.init(image: image, data: nil, revision: job.revision)))
        }
        return handle
    }
}

final class ControlledRasterExporter: RasterExporterRecording, @unchecked Sendable {
    struct Pending {
        let job: RasterImageExportJob
        let completion: @MainActor (Result<RasterImageExportResult, Error>) -> Void
    }
    @MainActor private(set) var pending: [Pending] = []
    @MainActor var count: Int { pending.count }
    @MainActor var revisions: [Int] { pending.map(\.job.revision) }

    func export(
        _ job: RasterImageExportJob,
        completion: @escaping @MainActor (Result<RasterImageExportResult, Error>) -> Void
    ) -> RasterImageWorkHandle {
        MainActor.assumeIsolated { pending.append(.init(job: job, completion: completion)) }
        return RasterImageWorkHandle()
    }

    @MainActor
    func complete(index: Int) {
        let value = pending[index]
        guard case .memory(let image) = value.job.source else { return }
        value.completion(.success(.init(image: image, data: nil, revision: value.job.revision)))
    }
}

actor ImmediateOutput: ScreenCaptureOutputEncoding {
    func encode(_ image: CapturedScreenImage) async throws -> EncodedScreenCapture {
        .init(png: Data([1]), tiff: Data([2]))
    }
}

actor SuspendedOutput: ScreenCaptureOutputEncoding {
    func encode(_ image: CapturedScreenImage) async throws -> EncodedScreenCapture {
        try await Task.sleep(for: .seconds(30))
        return .init(png: Data([1]), tiff: Data([2]))
    }
}

@MainActor
final class RecordingClipboard: ScreenCaptureClipboardDelivering {
    private(set) var values: [EncodedScreenCapture] = []
    var failures: Int
    init(failures: Int = 0) { self.failures = failures }
    func writeCompleteRepresentations(_ representations: EncodedScreenCapture) throws {
        if failures > 0 {
            failures -= 1
            throw ScreenCaptureError.clipboardFailed
        }
        values.append(representations)
    }
}

actor ManualScheduler: ScreenCaptureScheduling {
    var continuations: [CheckedContinuation<Void, Never>] = []
    var waiterCount: Int { continuations.count }
    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        await withCheckedContinuation { continuations.append($0) }
        try Task.checkCancellation()
    }
    func releaseAll() {
        let values = continuations
        continuations.removeAll()
        values.forEach { $0.resume() }
    }
}

actor ControlledRepository: ScreenCaptureHistoryRepository {
    var entries: [ScreenCaptureHistoryEntry] = []
    var images: [UUID: ScreenCaptureHistoryImage] = [:]
    var sourceFailures: Set<UUID> = []
    var addFailures = 0
    var updateFailures = 0
    var sourceContinuations: [UUID: CheckedContinuation<ScreenCaptureHistoryImage, Error>] = [:]
    var suspendedSources: Set<UUID> = []
    private(set) var addCount = 0
    private(set) var updateCount = 0
    private(set) var deleteCount = 0
    private(set) var clearCount = 0
    let image: ScreenCaptureHistoryImage

    init() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        image = ScreenCaptureHistoryImage(cgImage: try XCTUnwrap(context.makeImage()))
    }

    func seed(ids: [UUID]) {
        entries = ids.enumerated().map { index, id in makeEntry(id: id, offset: index) }
        ids.forEach { images[$0] = image }
    }

    func failNextAdd() { addFailures += 1 }
    func failNextUpdate() { updateFailures += 1 }

    func suspendSource(id: UUID) { suspendedSources.insert(id) }
    func failSource(id: UUID) { sourceFailures.insert(id) }
    func isSourcePending(id: UUID) -> Bool { sourceContinuations[id] != nil }
    func resumeSource(id: UUID) {
        sourceContinuations.removeValue(forKey: id)?.resume(returning: image)
        suspendedSources.remove(id)
    }

    func loadEntries() async throws -> [ScreenCaptureHistoryEntry] { entries }
    func add(id: UUID, content: ScreenCaptureHistoryContent) async throws -> ScreenCaptureHistoryEntry {
        addCount += 1
        if addFailures > 0 {
            addFailures -= 1
            throw ScreenCaptureHistoryError.fileOperationFailed
        }
        let entry = makeEntry(id: id, offset: -addCount)
        entries.removeAll { $0.id == id }
        entries.insert(entry, at: 0)
        images[id] = image
        return entry
    }
    func update(id: UUID, content: ScreenCaptureHistoryContent) async throws -> ScreenCaptureHistoryEntry {
        updateCount += 1
        if updateFailures > 0 {
            updateFailures -= 1
            throw ScreenCaptureHistoryError.fileOperationFailed
        }
        guard let prior = entries.first(where: { $0.id == id }) else { throw ScreenCaptureHistoryError.itemNotFound }
        let entry = ScreenCaptureHistoryEntry(
            schemaVersion: prior.schemaVersion,
            id: id,
            createdAt: prior.createdAt,
            updatedAt: Date(),
            currentVersionID: UUID(),
            flattenedFileIdentifier: "flattened.png",
            thumbnailFileIdentifier: "thumbnail.png",
            canvasWidth: content.canvasWidth,
            canvasHeight: content.canvasHeight,
            exportScale: content.exportScale,
            pixelWidth: 8,
            pixelHeight: 8
        )
        entries.removeAll { $0.id == id }
        entries.insert(entry, at: 0)
        return entry
    }
    func thumbnail(for id: UUID) async throws -> ScreenCaptureHistoryImage {
        guard let image = images[id] else { throw ScreenCaptureHistoryError.itemNotFound }
        return image
    }
    func flattenedSource(for id: UUID) async throws -> ScreenCaptureHistoryImage {
        if sourceFailures.contains(id) { throw ScreenCaptureHistoryError.decodingFailed }
        if suspendedSources.contains(id) {
            return try await withCheckedThrowingContinuation { sourceContinuations[id] = $0 }
        }
        guard let image = images[id] else { throw ScreenCaptureHistoryError.itemNotFound }
        return image
    }
    func delete(id: UUID) async throws {
        deleteCount += 1
        entries.removeAll { $0.id == id }
        images[id] = nil
    }
    func clear() async throws {
        clearCount += 1
        entries.removeAll()
        images.removeAll()
    }

    func makeEntry(id: UUID, offset: Int) -> ScreenCaptureHistoryEntry {
        let date = Date().addingTimeInterval(TimeInterval(-offset))
        return .init(
            schemaVersion: 1,
            id: id,
            createdAt: date,
            updatedAt: date,
            currentVersionID: UUID(),
            flattenedFileIdentifier: "flattened.png",
            thumbnailFileIdentifier: "thumbnail.png",
            canvasWidth: 8,
            canvasHeight: 8,
            exportScale: 1,
            pixelWidth: 8,
            pixelHeight: 8
        )
    }
}

@MainActor
final class Activation: ScreenCaptureApplicationActivating {
    private(set) var count = 0
    func activateApplication() { count += 1 }
}

@MainActor
final class Focus: ScreenCaptureWindowFocusing {
    private(set) var keyed: [NSWindow] = []
    func makeKeyAndOrderFront(_ window: NSWindow) { keyed.append(window) }
    func orderFrontRegardless(_ window: NSWindow) {}
    func makeFirstResponder(_ responder: NSResponder, in window: NSWindow) -> Bool { true }
}

@MainActor
func waitForStudioCondition(_ condition: @escaping () async -> Bool) async {
    for _ in 0..<1_000 {
        if await condition() { return }
        await Task.yield()
    }
    XCTFail("Condition did not become true")
}

@MainActor
func awaitStudioTurns(_ count: Int = 20) {
    for _ in 0..<count { RunLoop.current.run(until: Date()) }
}


actor BlockingOutput: ScreenCaptureOutputEncoding {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func encode(_ image: CapturedScreenImage) async throws -> EncodedScreenCapture {
        started = true
        await withCheckedContinuation { continuation = $0 }
        return .init(png: Data([1]), tiff: Data([2]))
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

struct FailingScheduler: ScreenCaptureScheduling {
    func sleep(for duration: Duration) async throws {
        throw ScreenCaptureError.captureFailed
    }
}

/// Blocks the first add after its downstream disk commit but before delivery can register it.
actor ScreenCaptureCommittedAddGateRepository: ScreenCaptureHistoryRepository {
    private let base: any ScreenCaptureHistoryRepository
    private var shouldBlockAdd = true
    private var isAddBlocked = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var addAttemptCount = 0
    private(set) var updateAttemptCount = 0

    init(base: any ScreenCaptureHistoryRepository) {
        self.base = base
    }

    func waitUntilAddCommittedAndBlocked() async {
        while !isAddBlocked { await Task.yield() }
    }

    func releaseAdd() {
        continuation?.resume()
        continuation = nil
        isAddBlocked = false
    }

    func loadEntries() async throws -> [ScreenCaptureHistoryEntry] {
        try await base.loadEntries()
    }

    func add(id: UUID, content: ScreenCaptureHistoryContent) async throws -> ScreenCaptureHistoryEntry {
        addAttemptCount += 1
        let entry = try await base.add(id: id, content: content)
        if shouldBlockAdd {
            shouldBlockAdd = false
            isAddBlocked = true
            await withCheckedContinuation { continuation = $0 }
        }
        return entry
    }

    func update(id: UUID, content: ScreenCaptureHistoryContent) async throws -> ScreenCaptureHistoryEntry {
        updateAttemptCount += 1
        return try await base.update(id: id, content: content)
    }

    func thumbnail(for id: UUID) async throws -> ScreenCaptureHistoryImage {
        try await base.thumbnail(for: id)
    }

    func flattenedSource(for id: UUID) async throws -> ScreenCaptureHistoryImage {
        try await base.flattenedSource(for: id)
    }

    func delete(id: UUID) async throws {
        try await base.delete(id: id)
    }

    func clear() async throws {
        try await base.clear()
    }
}
