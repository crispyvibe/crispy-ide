import CoreGraphics
import Foundation

/// Describes the on-disk source an editable raster image was decoded from.
///
/// Pixel dimensions are **oriented** (upright, after applying EXIF orientation).
struct RasterImageSourceInfo: Equatable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    let exifOrientation: UInt32
    let frameCount: Int
    let bitDepth: Int
    let hasGainMap: Bool

    /// Longest oriented edge in pixels.
    var longestEdge: Int { max(pixelWidth, pixelHeight) }
}

/// Reasons the editor refuses to overwrite the source file.
enum RasterImageSaveBlockReason: Equatable, Sendable {
    /// The editable bitmap is a downsampled proxy; saving would shrink the original.
    case reducedResolution(sourceWidth: Int, sourceHeight: Int, workingWidth: Int, workingHeight: Int)
    /// The source holds several frames/pages; saving would keep only the first.
    case multipleFrames(count: Int)
    /// The source exceeds 8 bits per channel; saving would reduce precision.
    case highBitDepth(bitsPerComponent: Int)
    /// The source carries an HDR gain map that the encoder would drop.
    case hdrGainMap

    /// User-facing explanation shown in the image toolbar status line.
    var message: String {
        switch self {
        case let .reducedResolution(sourceWidth, sourceHeight, workingWidth, workingHeight):
            return AppStrings.ImageEditor.saveBlockedReducedResolution(
                source: "\(sourceWidth)×\(sourceHeight)",
                working: "\(workingWidth)×\(workingHeight)"
            )
        case let .multipleFrames(count):
            return AppStrings.ImageEditor.saveBlockedMultipleFrames(count)
        case let .highBitDepth(bits):
            return AppStrings.ImageEditor.saveBlockedHighBitDepth(bits)
        case .hdrGainMap:
            return AppStrings.ImageEditor.saveBlockedGainMap
        }
    }
}

/// Decides whether overwriting the source file would silently lose data.
enum RasterImageSavePolicy {
    /// Returns a block reason, or `nil` when overwrite is lossless with respect to dimensions,
    /// frame count, bit depth, and HDR auxiliary data.
    static func blockReason(
        for sourceInfo: RasterImageSourceInfo,
        baselinePixelWidth: Int,
        baselinePixelHeight: Int
    ) -> RasterImageSaveBlockReason? {
        if sourceInfo.frameCount > 1 {
            return .multipleFrames(count: sourceInfo.frameCount)
        }
        if sourceInfo.hasGainMap {
            return .hdrGainMap
        }
        if sourceInfo.bitDepth > 8 {
            return .highBitDepth(bitsPerComponent: sourceInfo.bitDepth)
        }
        if baselinePixelWidth < sourceInfo.pixelWidth || baselinePixelHeight < sourceInfo.pixelHeight {
            return .reducedResolution(
                sourceWidth: sourceInfo.pixelWidth,
                sourceHeight: sourceInfo.pixelHeight,
                workingWidth: baselinePixelWidth,
                workingHeight: baselinePixelHeight
            )
        }
        return nil
    }
}
