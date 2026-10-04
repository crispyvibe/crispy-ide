import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Canonical display-local ScreenCaptureKit request produced by `ScreenCaptureGeometry`.
struct ScreenCaptureMagnifierRequest: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let sourceRect: CGRect
    let outputSize: CGSize
    let excludingWindowIDs: Set<CGWindowID>
}

/// Live pointer-neighborhood sampling boundary for the Region magnifier.
protocol ScreenCaptureMagnifierSampling: Sendable {
    func sample(_ request: ScreenCaptureMagnifierRequest) async -> CGImage?
}

/// ScreenCaptureKit still sampler used only for the coalesced Region magnifier.
actor ScreenCaptureKitMagnifierSampler: ScreenCaptureMagnifierSampling {
    private var cachedContent: SCShareableContent?
    private var cachedAt = Date.distantPast

    func sample(_ request: ScreenCaptureMagnifierRequest) async -> CGImage? {
        guard request.sourceRect.width > 0, request.sourceRect.height > 0,
              request.outputSize.width > 0, request.outputSize.height > 0 else { return nil }
        do {
            try Task.checkCancellation()
            let content = try await contentSnapshot(requiredWindowIDs: request.excludingWindowIDs)
            guard let display = content.displays.first(where: { $0.displayID == request.displayID }) else { return nil }
            let excluded = content.windows.filter { request.excludingWindowIDs.contains($0.windowID) }
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = request.sourceRect
            configuration.width = max(1, Int(request.outputSize.width.rounded()))
            configuration.height = max(1, Int(request.outputSize.height.rounded()))
            configuration.showsCursor = false
            try Task.checkCancellation()
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            return nil
        }
    }

    private func contentSnapshot(requiredWindowIDs: Set<CGWindowID>) async throws -> SCShareableContent {
        if let cachedContent, Date().timeIntervalSince(cachedAt) < 1 {
            let cachedWindowIDs = Set(cachedContent.windows.map(\.windowID))
            if requiredWindowIDs.isSubset(of: cachedWindowIDs) {
                return cachedContent
            }
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        cachedContent = content
        cachedAt = Date()
        return content
    }
}
