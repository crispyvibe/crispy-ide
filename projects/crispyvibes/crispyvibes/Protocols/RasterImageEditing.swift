import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Decodes raster files into upright pixels.
protocol RasterImageDecoding: Sendable {
    /// Decodes a display image whose longest edge is at most `maxPixelSize` (or full resolution
    /// for small sources) plus source facts.
    func decode(contentsOf url: URL, maxPixelSize: Int) -> RasterImageDecodeResult?
    /// Decodes every source pixel, upright, for export.
    func fullResolutionImage(contentsOf url: URL) -> CGImage?
}

/// Replays edit operations over a base bitmap.
protocol RasterImageRendering: Sendable {
    /// Replays geometric and overlay operations; `.adjust` operations are ignored here.
    func render(base: CGImage, baseCanvasSize: CGSize, operations: [ImageEditOperation]) -> CGImage?
    /// Applies color adjustments to a base bitmap.
    func applyAdjustments(_ adjustments: RasterImageAdjustments, to image: CGImage) -> CGImage?
}

extension RasterImageRendering {
    /// Adjusts `base` with the operations' effective adjustments, then replays them.
    func renderAdjusted(base: CGImage, baseCanvasSize: CGSize, operations: [ImageEditOperation]) -> CGImage? {
        let adjustments = operations.effectiveAdjustments
        let adjustedBase = adjustments.isIdentity ? base : applyAdjustments(adjustments, to: base)
        return adjustedBase.flatMap { render(base: $0, baseCanvasSize: baseCanvasSize, operations: operations) }
    }
}

/// Encodes a bitmap for a destination file type.
protocol RasterImageEncoding: Sendable {
    /// `options` selects an explicit format/quality; `nil` derives the format from the extension.
    func encodedData(for image: CGImage, destinationURL: URL, options: RasterImageExportOptions?) throws -> Data
}

/// Runs cancellable full-resolution render/encode work off the main thread.
protocol RasterImageExporting: Sendable {
    /// Starts `job`; `completion` runs on the main actor unless the work was cancelled.
    @discardableResult
    func export(
        _ job: RasterImageExportJob,
        completion: @escaping @MainActor (Result<RasterImageExportResult, Error>) -> Void
    ) -> RasterImageWorkHandle
}

/// Asks the user where to export. Called on the main thread; `completion` receives `nil` on cancel.
protocol RasterImageExportDestinationPicking {
    func pickDestination(suggestedName: String, contentType: UTType, completion: @escaping (URL?) -> Void)
}

/// Samples a color from anywhere on screen (eyedropper). Called on the main thread;
/// `completion` receives `nil` when the user cancels.
protocol RasterImageColorSampling {
    func sampleColor(completion: @escaping (RasterColor?) -> Void)
}

/// Posts VoiceOver announcements for editor status changes. Called on the main thread.
protocol RasterImageAccessibilityAnnouncing {
    func announce(_ message: String)
}

/// Places images or text on the system clipboard. Called on the main thread.
protocol RasterImagePasteboardWriting {
    func write(_ image: CGImage, size: CGSize) -> Bool
    func writeText(_ text: String) -> Bool
}

/// On-device image analysis. Work runs off the main thread; completions run on the main actor.
protocol RasterImageAnalyzing: Sendable {
    /// Recognizes text lines (reading order) in `image`. Cancelling the handle stops the request;
    /// a cancelled request never calls `completion`.
    @discardableResult
    func recognizeText(in image: CGImage, completion: @escaping @MainActor (Result<[RecognizedTextLine], Error>) -> Void) -> RasterImageWorkHandle
    /// Produces a same-size grayscale mask of the foreground subject(s) in `image`.
    @discardableResult
    func foregroundMask(for image: CGImage, completion: @escaping @MainActor (Result<RasterImageMask, Error>) -> Void) -> RasterImageWorkHandle
}
