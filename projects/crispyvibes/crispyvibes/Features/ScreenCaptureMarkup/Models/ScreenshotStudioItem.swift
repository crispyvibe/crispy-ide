import CoreGraphics
import Foundation

/// One image installed in Screenshot Studio as a fresh F009 annotation session.
struct ScreenshotStudioItem: Identifiable, @unchecked Sendable {
    enum Source: Equatable, Sendable {
        case capture
        case history
    }

    let id: UUID
    let capture: CapturedScreenImage
    let source: Source

    var image: CGImage { capture.cgImage }
    var canvasSize: CGSize { capture.canvasSize }
}
