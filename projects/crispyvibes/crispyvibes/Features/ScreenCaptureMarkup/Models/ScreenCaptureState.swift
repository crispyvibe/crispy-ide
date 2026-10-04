import Foundation

/// User-facing Screen Recording authorization state inferred from TCC observations and request history.
enum ScreenCaptureAuthorizationState: String, Equatable, Sendable {
    case undetermined
    case deniedOrRestricted
    case revoked
    case grantedRelaunchRequired
    case granted
}

/// Recovery actions valid for structured F062 failures.
enum ScreenCaptureRecoveryAction: String, Equatable, Sendable {
    case retry
    case recheckPermission
    case openSystemSettings
    case relaunchApplication
    case beginNewCapture
    case cancel
}

/// Content-free failures safe for diagnostics and UI routing.
enum ScreenCaptureError: Error, Equatable, Sendable {
    case authorization(ScreenCaptureAuthorizationState)
    case catalogUnavailable
    case targetUnavailable
    case topologyChanged
    case protectedOrUnavailableContent
    case invalidGeometry
    case resourceLimitExceeded(pixelCount: UInt64, estimatedBytes: UInt64)
    case captureFailed
    case encodingFailed
    case clipboardFailed
    case staleOperation
    case cancelled

    var recoveryActions: [ScreenCaptureRecoveryAction] {
        switch self {
        case .authorization(.undetermined): return [.recheckPermission, .cancel]
        case .authorization(.deniedOrRestricted), .authorization(.revoked):
            return [.openSystemSettings, .recheckPermission, .cancel]
        case .authorization(.grantedRelaunchRequired):
            return [.relaunchApplication, .recheckPermission, .cancel]
        case .topologyChanged, .targetUnavailable: return [.beginNewCapture, .cancel]
        case .cancelled, .staleOperation: return [.cancel]
        default: return [.retry, .cancel]
        }
    }
}

/// Explicit main coordinator state used by UI and tests.
enum ScreenCaptureCoordinatorState: Sendable {
    case idle
    case checkingPermission(session: UInt64)
    case permissionRequired(session: UInt64, state: ScreenCaptureAuthorizationState)
    case preparingCatalog(session: UInt64)
    case selecting(session: UInt64, mode: CaptureMode, topologyGeneration: UInt64)
    case capturing(session: UInt64)
    case presentingStudio(captureID: UUID)
    case failed(session: UInt64, error: ScreenCaptureError)
    case shutDown
}
