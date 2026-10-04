import AppKit
import CoreGraphics

/// Tracks capture-owned windows for ScreenCaptureKit exclusion and the compositor hide barrier.
@MainActor
final class ScreenCaptureSurfaceRegistry: ScreenCaptureUIExclusionProviding {
    private let windows = NSHashTable<NSWindow>.weakObjects()

    var excludedCaptureWindowIDs: Set<CGWindowID> {
        Set(windows.allObjects.compactMap { window in
            guard window.windowNumber > 0 else { return nil }
            return CGWindowID(window.windowNumber)
        })
    }

    func register(_ window: NSWindow) { windows.add(window) }
    func unregister(_ window: NSWindow) { windows.remove(window) }

    func prepareForCapture() async {
        windows.allObjects.forEach { $0.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(100))
    }
}
