import AppKit
import CoreGraphics
import Foundation

/// Persisted non-sensitive request history needed because TCC exposes only boolean observations.
enum ScreenCaptureAuthorizationHistory: String, Sendable {
    case neverRequested
    case requestDenied
    case previouslyGranted
    case grantedPendingRelaunch
}

/// Storage boundary for permission request history; it stores no capture or application data.
@MainActor
protocol ScreenCaptureAuthorizationHistoryStoring: AnyObject {
    var history: ScreenCaptureAuthorizationHistory { get set }
}

/// UserDefaults-backed request history with the defaults suite injected by AppContainer.
@MainActor
final class UserDefaultsScreenCaptureAuthorizationHistoryStore: ScreenCaptureAuthorizationHistoryStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String = "screenCapture.authorizationHistory") {
        self.defaults = defaults
        self.key = key
    }

    var history: ScreenCaptureAuthorizationHistory {
        get {
            guard let rawValue = defaults.string(forKey: key),
                  let value = ScreenCaptureAuthorizationHistory(rawValue: rawValue) else {
                return .neverRequested
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: key) }
    }
}

/// Honest UX mapping over TCC's preflight/request booleans and the app's own request history.
@MainActor
final class ScreenCaptureTCCAuthorizer: ScreenCaptureAuthorizing {
    private let historyStore: any ScreenCaptureAuthorizationHistoryStoring
    private let preflightAccess: () -> Bool
    private let requestAccess: () -> Bool
    private let openSettings: (URL) -> Void

    var cachedAuthorizationState: ScreenCaptureAuthorizationState {
        switch historyStore.history {
        case .neverRequested: return .undetermined
        case .requestDenied: return .deniedOrRestricted
        case .previouslyGranted: return .granted
        case .grantedPendingRelaunch: return .grantedRelaunchRequired
        }
    }

    init(
        historyStore: any ScreenCaptureAuthorizationHistoryStoring,
        preflightAccess: @escaping () -> Bool,
        requestAccess: @escaping () -> Bool,
        openSettings: @escaping (URL) -> Void
    ) {
        self.historyStore = historyStore
        self.preflightAccess = preflightAccess
        self.requestAccess = requestAccess
        self.openSettings = openSettings
    }

    func authorizationStatus() -> ScreenCaptureAuthorizationState {
        if preflightAccess() {
            historyStore.history = .previouslyGranted
            return .granted
        }
        switch historyStore.history {
        case .neverRequested: return .undetermined
        case .requestDenied: return .deniedOrRestricted
        case .previouslyGranted: return .revoked
        case .grantedPendingRelaunch: return .grantedRelaunchRequired
        }
    }

    func requestAuthorization() -> ScreenCaptureAuthorizationState {
        let requestReportedGranted = requestAccess()
        if preflightAccess() {
            historyStore.history = .previouslyGranted
            return .granted
        }
        if requestReportedGranted {
            historyStore.history = .grantedPendingRelaunch
            return .grantedRelaunchRequired
        }
        historyStore.history = .requestDenied
        return .deniedOrRestricted
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        openSettings(url)
    }
}
