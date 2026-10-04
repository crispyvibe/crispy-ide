import AppKit
import CoreGraphics

extension CaptureSelectionViewModel {
  func updateMagnifier(on display: ScreenCaptureDisplayDescriptor, swiftUIPoint: CGPoint) {
    guard !isShutdown,
      let nativePoint = try? geometry.nativePixelPoint(
        fromLocalSwiftUIPoint: swiftUIPoint,
        on: display
      ),
      let nativeRect = try? geometry.nativeSampleRect(
        centeredAt: nativePoint,
        size: CGSize(width: 20, height: 20),
        on: display
      ),
      let sourceRect = try? geometry.captureKitSourceRect(
        fromNativePixelRect: nativeRect,
        on: display
      )
    else { return }
    magnifierRequestSequence &+= 1
    pendingMagnifierRequest = PendingMagnifierRequest(
      request: ScreenCaptureMagnifierRequest(
        displayID: display.id,
        sourceRect: sourceRect,
        outputSize: nativeRect.size,
        excludingWindowIDs: excludedWindowIDs()
      ),
      sequence: magnifierRequestSequence,
      generation: magnifierGeneration
    )
    startMagnifierLoopIfNeeded()
  }

  func startMagnifierLoopIfNeeded() {
    guard magnifierTask == nil, let pendingMagnifierRequest,
      pendingMagnifierRequest.generation == magnifierGeneration,
      !isShutdown, mode == .region
    else { return }
    let generation = magnifierGeneration
    magnifierLoopGeneration = generation
    magnifierTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.runMagnifierLoop(generation: generation)
      self.finishMagnifierLoop(generation: generation)
    }
  }

  func runMagnifierLoop(generation: UInt64) async {
    while !Task.isCancelled, !isShutdown, mode == .region,
      generation == magnifierGeneration,
      let pending = pendingMagnifierRequest,
      pending.generation == generation
    {
      pendingMagnifierRequest = nil
      let image = await magnifierSampler.sample(pending.request)
      guard !Task.isCancelled, !isShutdown, mode == .region,
        generation == magnifierGeneration
      else { return }
      if pendingMagnifierRequest == nil,
        pending.sequence == magnifierRequestSequence
      {
        magnifierImage = image
      }
      do {
        try await scheduler.sleep(for: .milliseconds(100))
      } catch {
        return
      }
    }
  }

  func finishMagnifierLoop(generation: UInt64) {
    guard magnifierLoopGeneration == generation else { return }
    magnifierTask = nil
    magnifierLoopGeneration = nil
    startMagnifierLoopIfNeeded()
  }

  func invalidateMagnifier() {
    magnifierGeneration &+= 1
    pendingMagnifierRequest = nil
    magnifierImage = nil
    magnifierTask?.cancel()
  }

}
