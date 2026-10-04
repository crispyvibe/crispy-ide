import CoreGraphics

/// Immutable decoded PNG pixels loaded separately from history metadata.
struct ScreenCaptureHistoryImage: @unchecked Sendable {
    let cgImage: CGImage

    var pixelWidth: Int { cgImage.width }
    var pixelHeight: Int { cgImage.height }
}
