import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit


/// Desktop-independent source and pixel-output intent resolved before ScreenCaptureKit acquisition.
struct ScreenCaptureStillTargetConfiguration: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case desktopIndependentWindow(windowID: CGWindowID)
        case display(displayID: CGDirectDisplayID)
    }

    let source: Source
    let outputPixelSize: CGSize
    let canvasSize: CGSize
    let exportScale: CGFloat
}

/// Pure target policy used by acquisition and deterministic desktop-independent tests.
enum ScreenCaptureStillTargetPolicy {
    static func window(
        windowID: CGWindowID,
        contentRect: CGRect,
        pointPixelScale: CGFloat
    ) -> ScreenCaptureStillTargetConfiguration {
        let scale = max(pointPixelScale, 1)
        return ScreenCaptureStillTargetConfiguration(
            source: .desktopIndependentWindow(windowID: windowID),
            outputPixelSize: CGSize(
                width: max(1, ceil(contentRect.width * scale)),
                height: max(1, ceil(contentRect.height * scale))
            ),
            canvasSize: contentRect.size,
            exportScale: scale
        )
    }

    static func display(_ display: ScreenCaptureDisplayDescriptor) -> ScreenCaptureStillTargetConfiguration {
        ScreenCaptureStillTargetConfiguration(
            source: .display(displayID: display.id),
            outputPixelSize: display.nativePixelSize,
            canvasSize: display.appKitFrame.size,
            exportScale: display.backingScale
        )
    }
}
/// ScreenCaptureKit-backed region, display, and complete-window still acquisition.
actor ScreenCaptureKitStillProvider: ScreenCaptureProviding {
    private struct DisplayUIFacts: Sendable {
        let appKitFrame: CGRect
        let visibleFrame: CGRect
        let backingScale: CGFloat
    }

    private let geometry: ScreenCaptureGeometry
    private let resourcePolicy: ScreenCaptureResourcePolicy
    private var catalogGeneration: UInt64 = 0

    init(
        geometry: ScreenCaptureGeometry = .init(),
        resourcePolicy: ScreenCaptureResourcePolicy = .init()
    ) {
        self.geometry = geometry
        self.resourcePolicy = resourcePolicy
    }

    func catalog() async throws -> ScreenCaptureCatalog {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return await makeCatalog(from: content)
        } catch is CancellationError {
            throw ScreenCaptureError.cancelled
        } catch {
            throw ScreenCaptureError.catalogUnavailable
        }
    }

    func capture(
        selection: CaptureSelectionDescriptor,
        excludingWindowIDs: Set<CGWindowID>
    ) async throws -> CapturedScreenImage {
        do {
            try Task.checkCancellation()
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let freshCatalog = await makeCatalog(from: content)
            guard freshCatalog.topology == selection.topology else { throw ScreenCaptureError.topologyChanged }

            let excludedWindows = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
            let configuration = SCStreamConfiguration()
            configuration.showsCursor = selection.options.includesPointer
            configuration.capturesAudio = false

            let filter: SCContentFilter
            let canvasSize: CGSize
            let exportScale: CGFloat
            let placementDisplayID = selection.target.placementDisplayID

            switch selection.target {
            case .region(let displayID, let nativePixelRect):
                guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }),
                      let display = freshCatalog.displays.first(where: { $0.id == displayID }) else {
                    throw ScreenCaptureError.targetUnavailable
                }
                let width = Int(nativePixelRect.width.rounded())
                let height = Int(nativePixelRect.height.rounded())
                _ = try resourcePolicy.validate(pixelWidth: width, pixelHeight: height)
                filter = SCContentFilter(display: scDisplay, excludingWindows: excludedWindows)
                configuration.sourceRect = try geometry.captureKitSourceRect(
                    fromNativePixelRect: nativePixelRect,
                    on: display
                )
                configuration.width = width
                configuration.height = height
                canvasSize = configuration.sourceRect.size
                exportScale = display.backingScale

            case .display(let displayID):
                guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }),
                      let display = freshCatalog.displays.first(where: { $0.id == displayID }) else {
                    throw ScreenCaptureError.targetUnavailable
                }
                let target = ScreenCaptureStillTargetPolicy.display(display)
                _ = try resourcePolicy.validate(
                    pixelWidth: Int(target.outputPixelSize.width),
                    pixelHeight: Int(target.outputPixelSize.height)
                )
                filter = SCContentFilter(display: scDisplay, excludingWindows: excludedWindows)
                configuration.width = Int(target.outputPixelSize.width)
                configuration.height = Int(target.outputPixelSize.height)
                canvasSize = target.canvasSize
                exportScale = target.exportScale

            case .window(let windowID, _):
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    throw ScreenCaptureError.targetUnavailable
                }
                filter = SCContentFilter(desktopIndependentWindow: window)
                let info = SCShareableContent.info(for: filter)
                let target = ScreenCaptureStillTargetPolicy.window(
                    windowID: windowID,
                    contentRect: info.contentRect,
                    pointPixelScale: CGFloat(info.pointPixelScale)
                )
                exportScale = target.exportScale
                canvasSize = target.canvasSize
                let width = Int(target.outputPixelSize.width)
                let height = Int(target.outputPixelSize.height)
                _ = try resourcePolicy.validate(pixelWidth: width, pixelHeight: height)
                configuration.width = width
                configuration.height = height
            }

            try Task.checkCancellation()
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            try Task.checkCancellation()
            guard image.width > 0, image.height > 0, image.dataProvider != nil else {
                throw ScreenCaptureError.protectedOrUnavailableContent
            }
            _ = try resourcePolicy.validate(pixelWidth: image.width, pixelHeight: image.height)
            guard let placement = freshCatalog.displays.first(where: { $0.id == placementDisplayID }) else {
                throw ScreenCaptureError.topologyChanged
            }
            return CapturedScreenImage(
                cgImage: image,
                canvasSize: canvasSize,
                exportScale: exportScale,
                nativePixelSize: CGSize(width: image.width, height: image.height),
                colorSpaceName: image.colorSpace?.name.map { $0 as String },
                placement: ScreenCapturePlacementContext(
                    displayID: placementDisplayID,
                    visibleFrame: placement.visibleAppKitFrame
                )
            )
        } catch let error as ScreenCaptureError {
            throw error
        } catch is CancellationError {
            throw ScreenCaptureError.cancelled
        } catch {
            throw Self.mapCaptureFailure(error)
        }
    }

    static func mapCaptureFailure(_ error: Error) -> ScreenCaptureError {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain {
            if nsError.code == -3817 { return .cancelled }
            return .protectedOrUnavailableContent
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return mapCaptureFailure(underlying)
        }
        return .captureFailed
    }

    private func makeCatalog(from content: SCShareableContent) async -> ScreenCaptureCatalog {
        catalogGeneration &+= 1
        let generation = catalogGeneration
        let displayFacts = await MainActor.run { Self.displayUIFacts() }
        let captureDesktopBounds = content.displays.reduce(CGRect.null) { $0.union($1.frame) }
        let displays = content.displays.map { display -> ScreenCaptureDisplayDescriptor in
            let displayFilter = SCContentFilter(display: display, excludingWindows: [])
            let displayInfo = SCShareableContent.info(for: displayFilter)
            let infoScale = CGFloat(displayInfo.pointPixelScale)
            let fallbackNativeSize = CGSize(
                width: CGDisplayPixelsWide(display.displayID),
                height: CGDisplayPixelsHigh(display.displayID)
            )
            let nativeSize = infoScale > 0
                ? CGSize(
                    width: (display.frame.width * infoScale).rounded(),
                    height: (display.frame.height * infoScale).rounded()
                )
                : fallbackNativeSize
            let facts = displayFacts[display.displayID]
            let derivedScale = display.frame.width > 0 ? nativeSize.width / display.frame.width : 1
            let appKitFrame = facts?.appKitFrame ?? geometry.appKitFrame(
                fromCaptureKitFrame: display.frame,
                desktopCaptureBounds: captureDesktopBounds
            )
            return ScreenCaptureDisplayDescriptor(
                id: display.displayID,
                appKitFrame: appKitFrame,
                captureKitFrame: display.frame,
                visibleAppKitFrame: facts?.visibleFrame ?? appKitFrame,
                backingScale: derivedScale > 0 ? derivedScale : (facts?.backingScale ?? 1),
                nativePixelSize: nativeSize
            )
        }
        let windows = content.windows.map { window in
            ScreenCaptureWindowDescriptor(
                id: window.windowID,
                frame: window.frame,
                windowLayer: window.windowLayer,
                isOnScreen: window.isOnScreen,
                placementDisplayID: Self.placementDisplayID(for: window.frame, displays: content.displays)
            )
        }
        return ScreenCaptureCatalog(generation: generation, displays: displays, windows: windows)
    }

    @MainActor
    private static func displayUIFacts() -> [CGDirectDisplayID: DisplayUIFacts] {
        Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return (
                number.uint32Value,
                DisplayUIFacts(
                    appKitFrame: screen.frame,
                    visibleFrame: screen.visibleFrame,
                    backingScale: screen.backingScaleFactor
                )
            )
        })
    }

    private static func placementDisplayID(for frame: CGRect, displays: [SCDisplay]) -> CGDirectDisplayID {
        displays.max { lhs, rhs in
            lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
        }?.displayID ?? displays.first?.displayID ?? 0
    }
}

private extension CGRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}
