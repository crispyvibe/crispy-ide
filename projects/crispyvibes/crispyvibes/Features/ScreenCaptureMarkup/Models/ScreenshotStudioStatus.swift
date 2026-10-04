import Foundation

/// Retryable stage that failed without invalidating the in-memory Studio editor.
enum ScreenshotStudioFailureStage: Equatable, Sendable {
    case historyLoad
    case historySelection
    case render
    case encode
    case clipboard
    case historyAdd
    case historyUpdate
    case delete
    case clear

    var supportsCopyRetry: Bool {
        self == .render || self == .encode || self == .clipboard
            || self == .historyAdd || self == .historyUpdate
    }
}

/// Content-free failure suitable for Studio presentation and retry routing.
struct ScreenshotStudioFailure: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case capture(ScreenCaptureError)
        case history(ScreenCaptureHistoryError)
        case rendering
    }

    let itemID: UUID?
    let stage: ScreenshotStudioFailureStage
    let reason: Reason
}

/// Events emitted by delivery orchestration without exposing persistence implementation details.
enum ScreenCaptureDeliveryEvent: @unchecked Sendable {
    case working(UUID, Bool)
    case clipboardUpdated(UUID, Int)
    case deliveryCompleted(UUID, Int)
    case historyChanged([ScreenCaptureHistoryEntry], UUID, ScreenCaptureHistoryImage?)
    case deleted(UUID, [ScreenCaptureHistoryEntry])
    case cleared
    case failed(ScreenshotStudioFailure)
}
