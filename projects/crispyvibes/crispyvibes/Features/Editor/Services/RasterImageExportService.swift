import CoreGraphics
import Foundation
import os

/// Immutable description of one full-resolution render (and optional encode).
struct RasterImageExportJob: @unchecked Sendable {
    let source: RasterImageSource
    let baseCanvasSize: CGSize
    let operations: [ImageEditOperation]
    /// Document revision the job was created from.
    let revision: Int
    /// Encode for this destination; `nil` renders only (Copy).
    let destinationURL: URL?
    /// Explicit format/quality (Export As); `nil` derives the format from the extension.
    var options: RasterImageExportOptions?
}

/// Output of an export job.
struct RasterImageExportResult: @unchecked Sendable {
    let image: CGImage
    let data: Data?
    let revision: Int
}

/// Thread-safe cancellation token for background raster work.
final class RasterImageWorkHandle: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (cancelled: false, onCancel: [() -> Void]()))

    var isCancelled: Bool { state.withLock { $0.cancelled } }

    func cancel() {
        let handlers = state.withLock { value -> [() -> Void] in
            guard !value.cancelled else { return [] }
            value.cancelled = true
            defer { value.onCancel.removeAll() }
            return value.onCancel
        }
        handlers.forEach { $0() }
    }

    /// Runs `handler` on cancellation (immediately if already cancelled).
    func onCancel(_ handler: @escaping () -> Void) {
        let runNow = state.withLock { value -> Bool in
            if value.cancelled { return true }
            value.onCancel.append(handler)
            return false
        }
        if runNow { handler() }
    }
}

/// Default exporter: decodes full resolution, replays operations, and encodes on a serial queue.
struct RasterImageExportService: RasterImageExporting {
    let decoder: any RasterImageDecoding
    let renderer: any RasterImageRendering
    let encoder: any RasterImageEncoding
    let queue: DispatchQueue

    init(
        decoder: any RasterImageDecoding,
        renderer: any RasterImageRendering,
        encoder: any RasterImageEncoding,
        queue: DispatchQueue = DispatchQueue(label: "com.crispyvibe.raster-image.export", qos: .userInitiated)
    ) {
        self.decoder = decoder
        self.renderer = renderer
        self.encoder = encoder
        self.queue = queue
    }

    @discardableResult
    func export(
        _ job: RasterImageExportJob,
        completion: @escaping @MainActor (Result<RasterImageExportResult, Error>) -> Void
    ) -> RasterImageWorkHandle {
        let handle = RasterImageWorkHandle()
        let decoder = decoder
        let renderer = renderer
        let encoder = encoder
        queue.async {
            let result = Self.run(job, handle: handle, decoder: decoder, renderer: renderer, encoder: encoder)
            DispatchQueue.main.async {
                guard !handle.isCancelled else { return }
                MainActor.assumeIsolated { completion(result) }
            }
        }
        return handle
    }

    /// Synchronous pipeline; exposed for the standalone canvas and tests.
    static func run(
        _ job: RasterImageExportJob,
        handle: RasterImageWorkHandle?,
        decoder: any RasterImageDecoding,
        renderer: any RasterImageRendering,
        encoder: any RasterImageEncoding
    ) -> Result<RasterImageExportResult, Error> {
        autoreleasepool {
            let base: CGImage?
            switch job.source {
            case .memory(let image): base = image
            case .file(let url): base = decoder.fullResolutionImage(contentsOf: url)
            }
            guard let base else { return .failure(RasterImageSaveError.decodeFailure) }
            if handle?.isCancelled == true { return .failure(CancellationError()) }

            guard let rendered = renderer.renderAdjusted(base: base, baseCanvasSize: job.baseCanvasSize, operations: job.operations) else {
                return .failure(RasterImageSaveError.encodingFailure)
            }
            if handle?.isCancelled == true { return .failure(CancellationError()) }

            guard let destinationURL = job.destinationURL else {
                return .success(RasterImageExportResult(image: rendered, data: nil, revision: job.revision))
            }
            do {
                let data = try encoder.encodedData(for: rendered, destinationURL: destinationURL, options: job.options)
                return .success(RasterImageExportResult(image: rendered, data: data, revision: job.revision))
            } catch {
                return .failure(error)
            }
        }
    }
}

/// Encodes through `RasterImagePersistence` (orientation 1, format from the extension).
struct RasterImageEncoder: RasterImageEncoding {
    func encodedData(for image: CGImage, destinationURL: URL, options: RasterImageExportOptions?) throws -> Data {
        guard let options else {
            return try RasterImagePersistence.encodedData(for: image, destinationURL: destinationURL)
        }
        return try RasterImagePersistence.encodedData(for: image, type: options.format.contentType, quality: options.quality)
    }
}
