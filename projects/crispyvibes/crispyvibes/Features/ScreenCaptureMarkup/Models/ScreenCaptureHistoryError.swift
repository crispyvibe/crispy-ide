import Foundation

/// Structured failures exposed by screenshot history persistence.
enum ScreenCaptureHistoryError: Error, Equatable, Sendable {
    case invalidRoot
    case invalidContent
    case encodingFailed
    case decodingFailed
    case itemAlreadyExists
    case itemNotFound
    case corruptItem
    case staleOperation
    case cancelled
    case fileOperationFailed
}
