import Foundation

/// Flattened PNG pixels and non-sensitive geometry supplied for an add or update.
struct ScreenCaptureHistoryContent: Equatable, Sendable {
    let pngData: Data
    let canvasWidth: Double
    let canvasHeight: Double
    let exportScale: Double

    init(pngData: Data, canvasWidth: Double, canvasHeight: Double, exportScale: Double) {
        self.pngData = pngData
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.exportScale = exportScale
    }
}
