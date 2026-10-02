import CoreGraphics
import Foundation
import os

/// Renders display composites off the main thread, latest request wins.
///
/// Used when the live canvas can't draw vectors directly over the flattened bitmap: pixel-effect
/// markup (blur/pixelate) or a live/compare adjustment override.
final class RasterImageLiveCompositor: @unchecked Sendable {
    /// Identifies the inputs a composite was rendered from.
    struct Key: Equatable {
        let revision: Int
        let adjustments: RasterImageAdjustments?
        let sessionID: ObjectIdentifier
    }

    private let queue = DispatchQueue(label: "com.crispyvibe.raster-image.live-composite", qos: .userInteractive)
    private let latestRequest = OSAllocatedUnfairLock(initialState: 0)

    /// Renders `job` and delivers the image on the main actor unless a newer request superseded it.
    func render(
        _ job: RasterImageExportJob,
        renderer: any RasterImageRendering,
        completion: @escaping @MainActor (CGImage?) -> Void
    ) {
        let request = latestRequest.withLock { value -> Int in
            value += 1
            return value
        }
        queue.async { [latestRequest] in
            guard latestRequest.withLock({ $0 }) == request else { return }
            let image: CGImage?
            if case .memory(let base) = job.source {
                image = renderer.renderAdjusted(base: base, baseCanvasSize: job.baseCanvasSize, operations: job.operations)
            } else {
                image = nil
            }
            DispatchQueue.main.async {
                guard latestRequest.withLock({ $0 }) == request else { return }
                MainActor.assumeIsolated { completion(image) }
            }
        }
    }

    /// Drops any in-flight result.
    func cancel() {
        latestRequest.withLock { $0 += 1 }
    }
}
