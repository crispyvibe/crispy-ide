import CoreGraphics
import Foundation

/// Current-Space placement hints retained without persisting workspace or application identity.
struct ScreenCapturePlacementContext: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let visibleFrame: CGRect
}

/// Immutable still pixels and source metadata. `CGImage` is immutable but lacks Sendable annotations.
struct CapturedScreenImage: @unchecked Sendable {
    let cgImage: CGImage
    /// Logical canvas dimensions used by F009.
    let canvasSize: CGSize
    /// Source pixels per canvas unit.
    let exportScale: CGFloat
    let nativePixelSize: CGSize
    let colorSpaceName: String?
    let placement: ScreenCapturePlacementContext
}

/// Fully eager representations safe to hand to a clipboard or file boundary.
struct EncodedScreenCapture: Sendable, Equatable {
    let png: Data
    let tiff: Data
}

/// One successful acquisition routed to Screenshot Studio.
struct AcquiredScreenCapture: @unchecked Sendable {
    let id: UUID
    let image: CapturedScreenImage

    init(id: UUID = UUID(), image: CapturedScreenImage) {
        self.id = id
        self.image = image
    }
}
