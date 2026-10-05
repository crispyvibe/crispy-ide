import AppKit
import CoreGraphics

/// One-shot restoration for F062 surfaces hidden behind the compositor barrier.
@MainActor
private final class ScreenCaptureHiddenSurfaceToken: ScreenCaptureHiddenSurfaceRestoring {
    private var windows: [NSWindow]

    init(windows: [NSWindow]) {
        self.windows = windows
    }

    func restore() {
        let windows = self.windows
        self.windows.removeAll()
        windows.forEach { $0.orderFrontRegardless() }
    }
}

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

    func prepareForCapture() async -> any ScreenCaptureHiddenSurfaceRestoring {
        let visibleWindows = windows.allObjects.filter(\.isVisible)
        visibleWindows.forEach { $0.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(100))
        return ScreenCaptureHiddenSurfaceToken(windows: visibleWindows)
    }
}
