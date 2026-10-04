import Combine
import Foundation

/// Shared visible and announced delay state for normal capture delay or selection retry.
@MainActor
final class ScreenCaptureDelayViewModel: ObservableObject {
  @Published private(set) var countdown: Int?

  private let scheduler: any ScreenCaptureScheduling
  private let announce: (String) -> Void

  init(
    scheduler: any ScreenCaptureScheduling = ContinuousScreenCaptureScheduler(),
    announce: @escaping (String) -> Void
  ) {
    self.scheduler = scheduler
    self.announce = announce
  }

  func wait(for delay: CaptureDelay, showNoneFor minimum: Duration? = nil) async throws {
    if delay == .none {
      countdown = 0
      announce(AppStrings.ScreenCapture.delayChanged(0))
      if let minimum { try await scheduler.sleep(for: minimum) }
      try Task.checkCancellation()
      countdown = nil
      return
    }

    for value in stride(from: delay.rawValue, through: 1, by: -1) {
      try Task.checkCancellation()
      countdown = value
      announce(AppStrings.ScreenCapture.countdown(value))
      try await scheduler.sleep(for: .seconds(1))
    }
    try Task.checkCancellation()
    countdown = nil
  }

  func cancel() {
    countdown = nil
  }
}
