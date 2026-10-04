import AppKit
import Combine
import CoreGraphics

/// Shared state for every display overlay in one capture session.
@MainActor
final class CaptureSelectionViewModel: ObservableObject {
  @Published var mode: CaptureMode
  @Published var options: CaptureOptions
  @Published var regionDisplayID: CGDirectDisplayID?
  @Published var regionLocalRect: CGRect?
  @Published var highlightedWindowID: CGWindowID?
  @Published var highlightedDisplayID: CGDirectDisplayID?
  @Published var nativePixelSize: CGSize?
  @Published var boundaryResistanceVisible = false
  @Published var magnifierImage: CGImage?
  @Published var countdown: Int?
  @Published var activeRegionEdge: CaptureRegionEdge = .right

  let catalog: ScreenCaptureCatalog
  let geometry: ScreenCaptureGeometry
  let magnifierSampler: any ScreenCaptureMagnifierSampling
  let excludedWindowIDs: () -> Set<CGWindowID>
  let announce: (String) -> Void
  let scheduler: any ScreenCaptureScheduling
  let delayViewModel: ScreenCaptureDelayViewModel
  var delayCancellable: AnyCancellable?
  var regionAnchor: CGPoint?
  var traversalIndex = 0
  var countdownTask: Task<Void, Never>?
  var magnifierTask: Task<Void, Never>?
  var pendingMagnifierRequest: PendingMagnifierRequest?
  var magnifierRequestSequence: UInt64 = 0

  struct PendingMagnifierRequest {
    let request: ScreenCaptureMagnifierRequest
    let sequence: UInt64
    let generation: UInt64
  }
  var magnifierGeneration: UInt64 = 0
  var magnifierLoopGeneration: UInt64?
  var isShutdown = false
  var onCommit: ((CaptureSelectionDescriptor) -> Void)?
  var onCancel: (() -> Void)?

  init(
    catalog: ScreenCaptureCatalog,
    initialMode: CaptureMode,
    options: CaptureOptions,
    geometry: ScreenCaptureGeometry = .init(),
    magnifierSampler: any ScreenCaptureMagnifierSampling,
    excludedWindowIDs: @escaping () -> Set<CGWindowID>,
    scheduler: any ScreenCaptureScheduling = ContinuousScreenCaptureScheduler(),
    announce: @escaping (String) -> Void
  ) {
    self.catalog = catalog
    mode = initialMode
    self.options = options
    self.geometry = geometry
    self.magnifierSampler = magnifierSampler
    self.excludedWindowIDs = excludedWindowIDs
    self.announce = announce
    self.scheduler = scheduler
    let delayViewModel = ScreenCaptureDelayViewModel(scheduler: scheduler, announce: announce)
    self.delayViewModel = delayViewModel
    delayCancellable = delayViewModel.$countdown.sink { [weak self] in self?.countdown = $0 }
    highlightedDisplayID = catalog.displays.first?.id
    highlightedWindowID = selectableWindows.first?.id
  }

  var dimensionsText: String {
    guard let nativePixelSize else { return AppStrings.ScreenCapture.dimensionsUnavailable }
    return AppStrings.ScreenCapture.dimensions(
      Int(nativePixelSize.width), Int(nativePixelSize.height))
  }

  func selectMode(_ mode: CaptureMode) {
    guard countdown == nil else { return }
    self.mode = mode
    traversalIndex = 0
    boundaryResistanceVisible = false
    if mode != .region { invalidateMagnifier() }
    if mode == .window { highlightedWindowID = selectableWindows.first?.id }
    if mode == .display { highlightedDisplayID = catalog.displays.first?.id }
    announce(AppStrings.ScreenCapture.modeChanged(mode))
  }

  func selectDelay(_ delay: CaptureDelay) {
    guard countdown == nil else { return }
    options.delay = delay
    announce(AppStrings.ScreenCapture.delayChanged(delay.rawValue))
  }

  func setIncludesPointer(_ included: Bool) {
    guard countdown == nil else { return }
    options.includesPointer = included
    announce(
      included ? AppStrings.ScreenCapture.pointerIncluded : AppStrings.ScreenCapture.pointerExcluded
    )
  }

  func shutdown() {
    isShutdown = true
    countdownTask?.cancel()
    countdownTask = nil
    delayViewModel.cancel()
    delayCancellable?.cancel()
    delayCancellable = nil
    invalidateMagnifier()
    onCommit = nil
    onCancel = nil
  }

}
