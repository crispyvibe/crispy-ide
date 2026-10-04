import Foundation

/// Metadata-free canonical and bounded PNG representations prepared for persistence.
struct ScreenCaptureHistoryPreparedImages: Equatable, Sendable {
    let canonicalPNG: Data
    let thumbnailPNG: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

/// Off-main image decoding, canonicalization, and thumbnail boundary.
protocol ScreenCaptureHistoryImageProcessing: Sendable {
    func prepare(pngData: Data, maximumThumbnailPixelSize: Int) async throws -> ScreenCaptureHistoryPreparedImages
    func decodePNG(_ data: Data) async throws -> ScreenCaptureHistoryImage
}
