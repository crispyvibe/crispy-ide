import CoreGraphics

/// Pure initial-fit policy for the in-memory raster preview.
enum RasterImageInitialFitPolicy {
  static func magnification(
    imageSize: CGSize,
    viewportSize: CGSize,
    minimum: CGFloat = 0.1,
    maximum: CGFloat = 1
  ) -> CGFloat? {
    guard imageSize.width.isFinite, imageSize.height.isFinite,
      viewportSize.width.isFinite, viewportSize.height.isFinite,
      imageSize.width > 0, imageSize.height > 0,
      viewportSize.width >= 16, viewportSize.height >= 16,
      minimum > 0, maximum >= minimum
    else { return nil }
    let fit = min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
    guard fit.isFinite, fit > 0 else { return nil }
    return min(max(fit, minimum), maximum)
  }
}
