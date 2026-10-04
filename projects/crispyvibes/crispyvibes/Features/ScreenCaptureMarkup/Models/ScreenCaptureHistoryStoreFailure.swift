import Foundation

/// Named store operation associated with a non-content-bearing failure.
enum ScreenCaptureHistoryStoreOperation: Equatable, Sendable {
    case load
    case add
    case update
    case delete
    case clear
}

/// Structured failure state suitable for presentation without leaking capture details.
struct ScreenCaptureHistoryStoreFailure: Equatable, Sendable {
    let operation: ScreenCaptureHistoryStoreOperation
    let error: ScreenCaptureHistoryError
}
