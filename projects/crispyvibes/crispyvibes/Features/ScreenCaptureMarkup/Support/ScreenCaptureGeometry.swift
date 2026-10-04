import CoreGraphics
import Foundation

/// Sole converter between AppKit desktop, overlay-local, ScreenCaptureKit, and native-pixel spaces.
struct ScreenCaptureGeometry: Sendable {
    /// Converts a global AppKit rectangle to display-local points and visibly clamps it to one display.
    func clampedLocalRect(
        fromAppKit rect: CGRect,
        on display: ScreenCaptureDisplayDescriptor
    ) -> CGRect {
        let standardized = rect.standardized.offsetBy(dx: -display.appKitFrame.minX, dy: -display.appKitFrame.minY)
        let localBounds = CGRect(origin: .zero, size: display.appKitFrame.size)
        return standardized.intersection(localBounds)
    }

    /// Converts display-local AppKit points to a covering native-pixel rectangle with a top-left origin.
    func nativePixelRect(
        fromLocalAppKit rect: CGRect,
        on display: ScreenCaptureDisplayDescriptor
    ) throws -> CGRect {
        let bounds = CGRect(origin: .zero, size: display.appKitFrame.size)
        let local = rect.standardized.intersection(bounds)
        guard !local.isNull, !local.isEmpty, display.backingScale > 0 else {
            throw ScreenCaptureError.invalidGeometry
        }

        let scale = display.backingScale
        let minimumX = floor(local.minX * scale)
        let maximumX = ceil(local.maxX * scale)
        let minimumY = floor((bounds.height - local.maxY) * scale)
        let maximumY = ceil((bounds.height - local.minY) * scale)
        let covering = CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
        let nativeBounds = CGRect(origin: .zero, size: display.nativePixelSize)
        let result = covering.intersection(nativeBounds)
        guard !result.isNull, !result.isEmpty else { throw ScreenCaptureError.invalidGeometry }
        return result.integral
    }

    /// Converts a display-local SwiftUI top-left point to one clamped native top-left pixel.
    func nativePixelPoint(
        fromLocalSwiftUIPoint point: CGPoint,
        on display: ScreenCaptureDisplayDescriptor
    ) throws -> CGPoint {
        let pointSize = display.appKitFrame.size
        let nativeSize = display.nativePixelSize
        guard pointSize.width > 0, pointSize.height > 0,
              nativeSize.width > 0, nativeSize.height > 0 else {
            throw ScreenCaptureError.invalidGeometry
        }
        let xRatio = nativeSize.width / pointSize.width
        let yRatio = nativeSize.height / pointSize.height
        let x = min(max(floor(point.x * xRatio), 0), nativeSize.width - 1)
        let y = min(max(floor(point.y * yRatio), 0), nativeSize.height - 1)
        return CGPoint(x: x, y: y)
    }

    /// Returns a fixed native-pixel sample shifted inside display bounds at every edge.
    func nativeSampleRect(
        centeredAt point: CGPoint,
        size: CGSize,
        on display: ScreenCaptureDisplayDescriptor
    ) throws -> CGRect {
        let nativeSize = display.nativePixelSize
        guard size.width > 0, size.height > 0,
              size.width <= nativeSize.width, size.height <= nativeSize.height else {
            throw ScreenCaptureError.invalidGeometry
        }
        let origin = CGPoint(
            x: min(max(floor(point.x - size.width / 2), 0), nativeSize.width - size.width),
            y: min(max(floor(point.y - size.height / 2), 0), nativeSize.height - size.height)
        )
        return CGRect(origin: origin, size: size)
    }

    /// Converts a native top-left pixel rectangle to ScreenCaptureKit display-local source points.
    func captureKitSourceRect(
        fromNativePixelRect rect: CGRect,
        on display: ScreenCaptureDisplayDescriptor
    ) throws -> CGRect {
        let nativeBounds = CGRect(origin: .zero, size: display.nativePixelSize)
        let capturePointSize = display.captureKitFrame.size
        guard nativeBounds.contains(rect), !rect.isEmpty,
              capturePointSize.width > 0, capturePointSize.height > 0 else {
            throw ScreenCaptureError.invalidGeometry
        }
        let xRatio = capturePointSize.width / display.nativePixelSize.width
        let yRatio = capturePointSize.height / display.nativePixelSize.height
        return CGRect(
            x: rect.minX * xRatio,
            y: rect.minY * yRatio,
            width: rect.width * xRatio,
            height: rect.height * yRatio
        )
    }

    /// Converts a Quartz/ScreenCaptureKit global frame into AppKit's bottom-left desktop space.
    func appKitFrame(fromCaptureKitFrame frame: CGRect, desktopCaptureBounds: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: desktopCaptureBounds.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    /// Native dimensions represented by a committed local AppKit rectangle.
    func nativePixelSize(fromLocalAppKit rect: CGRect, on display: ScreenCaptureDisplayDescriptor) throws -> CGSize {
        try nativePixelRect(fromLocalAppKit: rect, on: display).size
    }
}
