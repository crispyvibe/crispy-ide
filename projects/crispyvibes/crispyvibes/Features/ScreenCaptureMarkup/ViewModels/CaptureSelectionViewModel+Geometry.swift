import AppKit
import CoreGraphics

extension CaptureSelectionViewModel {
  func localWindowRects(on displayID: CGDirectDisplayID) -> [(CGWindowID, CGRect)] {
    guard let display = display(displayID) else { return [] }
    return selectableWindows.compactMap { window in
      let intersection = appKitFrame(for: window).intersection(display.appKitFrame)
      guard !intersection.isNull, !intersection.isEmpty else { return nil }
      let localAppKit = intersection.offsetBy(
        dx: -display.appKitFrame.minX, dy: -display.appKitFrame.minY)
      return (
        window.id,
        CGRect(
          x: localAppKit.minX,
          y: display.appKitFrame.height - localAppKit.maxY,
          width: localAppKit.width,
          height: localAppKit.height
        )
      )
    }
  }

  var selectableWindows: [ScreenCaptureWindowDescriptor] {
    catalog.windows.filter { $0.isOnScreen && $0.windowLayer == 0 && !$0.frame.isEmpty }
  }

  func display(_ id: CGDirectDisplayID) -> ScreenCaptureDisplayDescriptor? {
    catalog.displays.first { $0.id == id }
  }

  func ensureKeyboardRegion() {
    guard regionLocalRect == nil, let display = catalog.displays.first else { return }
    let size = CGSize(
      width: min(480, display.appKitFrame.width * 0.5),
      height: min(320, display.appKitFrame.height * 0.5))
    regionDisplayID = display.id
    regionLocalRect = CGRect(
      x: (display.appKitFrame.width - size.width) / 2,
      y: (display.appKitFrame.height - size.height) / 2,
      width: size.width,
      height: size.height
    )
    updateNativeSize()
  }

  func updateNativeSize() {
    guard let id = regionDisplayID, let display = display(id), let rect = regionLocalRect else {
      return
    }
    nativePixelSize = try? geometry.nativePixelSize(fromLocalAppKit: rect, on: display)
  }

  func appKitLocalPoint(_ point: CGPoint, display: ScreenCaptureDisplayDescriptor) -> CGPoint {
    CGPoint(x: point.x, y: display.appKitFrame.height - point.y)
  }

  func appKitFrame(for window: ScreenCaptureWindowDescriptor) -> CGRect {
    let captureDesktop = catalog.displays.reduce(CGRect.null) { $0.union($1.captureKitFrame) }
    return geometry.appKitFrame(
      fromCaptureKitFrame: window.frame, desktopCaptureBounds: captureDesktop)
  }

  func wrappedIndex(_ value: Int, count: Int) -> Int { (value % count + count) % count }
}
