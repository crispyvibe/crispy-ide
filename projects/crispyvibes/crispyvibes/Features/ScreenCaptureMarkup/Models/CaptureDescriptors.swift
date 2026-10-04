import CoreGraphics
import Foundation

/// Stable facts needed to map one active display across AppKit and ScreenCaptureKit.
struct ScreenCaptureDisplayDescriptor: Equatable, Sendable {
    let id: CGDirectDisplayID
    /// Global AppKit desktop frame, whose Y axis points upward.
    let appKitFrame: CGRect
    /// Global ScreenCaptureKit frame, whose Y axis follows Quartz display space.
    let captureKitFrame: CGRect
    let visibleAppKitFrame: CGRect
    let backingScale: CGFloat
    let nativePixelSize: CGSize

    var nativePixelWidth: Int { Int(nativePixelSize.width.rounded()) }
    var nativePixelHeight: Int { Int(nativePixelSize.height.rounded()) }
}

/// Privacy-minimized window facts exposed to selection UI.
struct ScreenCaptureWindowDescriptor: Equatable, Sendable {
    let id: CGWindowID
    let frame: CGRect
    let windowLayer: Int
    let isOnScreen: Bool
    let placementDisplayID: CGDirectDisplayID
}

/// Exact display facts used to reject stale target geometry before acquisition.
struct DisplayTopologyEntry: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let appKitFrame: CGRect
    let captureKitFrame: CGRect
    let backingScale: CGFloat
    let nativePixelSize: CGSize
}

/// Order-independent snapshot used to reject stale selections.
struct DisplayTopologyFingerprint: Equatable, Sendable {
    let entries: [DisplayTopologyEntry]

    init(displays: [ScreenCaptureDisplayDescriptor]) {
        entries = displays
            .map {
                DisplayTopologyEntry(
                    displayID: $0.id,
                    appKitFrame: $0.appKitFrame,
                    captureKitFrame: $0.captureKitFrame,
                    backingScale: $0.backingScale,
                    nativePixelSize: $0.nativePixelSize
                )
            }
            .sorted { $0.displayID < $1.displayID }
    }
}

/// One generation of selectable ScreenCaptureKit content without window titles or app names.
struct ScreenCaptureCatalog: Equatable, Sendable {
    let generation: UInt64
    let displays: [ScreenCaptureDisplayDescriptor]
    let windows: [ScreenCaptureWindowDescriptor]
    let topology: DisplayTopologyFingerprint

    init(generation: UInt64, displays: [ScreenCaptureDisplayDescriptor], windows: [ScreenCaptureWindowDescriptor]) {
        self.generation = generation
        self.displays = displays
        self.windows = windows
        topology = DisplayTopologyFingerprint(displays: displays)
    }
}

/// The concrete target committed by release, click, or Return.
enum CaptureTarget: Equatable, Sendable {
    /// Display-local native pixels with a top-left origin.
    case region(displayID: CGDirectDisplayID, nativePixelRect: CGRect)
    case window(windowID: CGWindowID, placementDisplayID: CGDirectDisplayID)
    case display(displayID: CGDirectDisplayID)

    var mode: CaptureMode {
        switch self {
        case .region: return .region
        case .window: return .window
        case .display: return .display
        }
    }

    var placementDisplayID: CGDirectDisplayID {
        switch self {
        case .region(let displayID, _), .display(let displayID): return displayID
        case .window(_, let displayID): return displayID
        }
    }
}

/// A visibly committed, generation-bound target ready for delay and acquisition.
struct CaptureSelectionDescriptor: Equatable, Sendable {
    let target: CaptureTarget
    let options: CaptureOptions
    let catalogGeneration: UInt64
    let topology: DisplayTopologyFingerprint
}
