import Foundation

/// Wall-clock boundary used for history timestamps and retention.
protocol ScreenCaptureHistoryClock: Sendable {
    var now: Date { get }
}

/// Production wall clock injected by the later composition-root integration.
struct SystemScreenCaptureHistoryClock: ScreenCaptureHistoryClock {
    var now: Date { Date() }
}
