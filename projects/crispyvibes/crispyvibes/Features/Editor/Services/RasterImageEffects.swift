import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Core Image processing for color adjustments and pixel-effect markup.
///
/// Thread-safe: `CIContext` is safe to share across threads, so one instance serves the display
/// path (main thread) and export (background queue).
final class RasterImageEffects: @unchecked Sendable {
    private let context: CIContext

    init(context: CIContext = CIContext(options: [.cacheIntermediates: false])) {
        self.context = context
    }

    /// Returns `image` with `adjustments` applied, keeping its size and color space.
    func apply(_ adjustments: RasterImageAdjustments, to image: CGImage) -> CGImage? {
        guard !adjustments.isIdentity else { return image }
        let input = CIImage(cgImage: image)
        var output = input

        if adjustments.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = output
            filter.ev = Float(adjustments.exposure)
            output = filter.outputImage ?? output
        }
        if adjustments.temperature != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = output
            filter.neutral = CIVector(x: 6500, y: 0)
            // A lower target neutral renders the scene warmer (verified by test_temperature_warmsAndCools).
            filter.targetNeutral = CIVector(x: 6500 - CGFloat(adjustments.temperature) * 3000, y: 0)
            output = filter.outputImage ?? output
        }
        if adjustments.highlights != 0 || adjustments.shadows != 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output
            filter.highlightAmount = Float(1 + min(adjustments.highlights, 0))
            filter.shadowAmount = Float(adjustments.shadows)
            output = filter.outputImage ?? output
            if adjustments.highlights > 0 {
                let curve = CIFilter.toneCurve()
                curve.inputImage = output
                let lift = CGFloat(adjustments.highlights) * 0.12
                curve.point0 = CGPoint(x: 0, y: 0)
                curve.point1 = CGPoint(x: 0.25, y: 0.25)
                curve.point2 = CGPoint(x: 0.5, y: 0.5)
                curve.point3 = CGPoint(x: 0.75, y: min(0.75 + lift, 1))
                curve.point4 = CGPoint(x: 1, y: 1)
                output = curve.outputImage ?? output
            }
        }
        if adjustments.contrast != 0 || adjustments.saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.contrast = Float(1 + adjustments.contrast * 0.5)
            filter.saturation = Float(max(0, 1 + adjustments.saturation))
            filter.brightness = 0
            output = filter.outputImage ?? output
        }
        if adjustments.vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = output
            filter.amount = Float(adjustments.vibrance)
            output = filter.outputImage ?? output
        }
        if adjustments.sharpness > 0 {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = output
            filter.sharpness = Float(adjustments.sharpness)
            output = filter.outputImage ?? output
        }
        return render(output.cropped(to: input.extent), like: image)
    }

    /// Gaussian-blurs `image` (the pixels under a blur item). `radius` is in pixels.
    func blur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.clampedToExtent()
        filter.radius = Float(max(radius, 0.5))
        guard let output = filter.outputImage else { return nil }
        return render(output.cropped(to: input.extent), like: image)
    }

    /// Mosaics `image` into square cells of `cellSize` pixels.
    func pixelate(_ image: CGImage, cellSize: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(max(cellSize, 1))
        filter.center = CGPoint(x: input.extent.minX, y: input.extent.minY)
        guard let output = filter.outputImage else { return nil }
        return render(output.cropped(to: input.extent), like: image)
    }

    private func render(_ image: CIImage, like source: CGImage) -> CGImage? {
        let colorSpace = source.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
        return context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace)
    }
}

extension RasterMarkupItem {
    /// Blur radius / mosaic cell size in canvas units, proportional to the item so proxy and
    /// full-resolution output look the same.
    var effectStrength: CGFloat {
        guard let rect else { return 0 }
        return max(4, min(rect.width, rect.height) * 0.08)
    }
}
