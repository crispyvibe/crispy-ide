import AppKit
import CoreGraphics

extension CaptureSelectionViewModel {
  func beginRegion(on displayID: CGDirectDisplayID, swiftUIPoint: CGPoint) {
    guard mode == .region, countdown == nil, let display = display(displayID) else { return }
    regionDisplayID = displayID
    let point = appKitLocalPoint(swiftUIPoint, display: display)
    regionAnchor = point
    regionLocalRect = CGRect(origin: point, size: .zero)
    boundaryResistanceVisible = false
    updateMagnifier(on: display, swiftUIPoint: swiftUIPoint)
  }

  func updateRegion(on displayID: CGDirectDisplayID, swiftUIPoint: CGPoint) {
    guard mode == .region, regionDisplayID == displayID,
      let display = display(displayID), let anchor = regionAnchor
    else { return }
    let unclamped = appKitLocalPoint(swiftUIPoint, display: display)
    let bounds = CGRect(origin: .zero, size: display.appKitFrame.size)
    let clamped = CGPoint(
      x: min(max(unclamped.x, bounds.minX), bounds.maxX),
      y: min(max(unclamped.y, bounds.minY), bounds.maxY)
    )
    let resisted = clamped != unclamped
    regionLocalRect =
      CGRect(x: anchor.x, y: anchor.y, width: clamped.x - anchor.x, height: clamped.y - anchor.y)
      .standardized
    updateNativeSize()
    updateMagnifier(on: display, swiftUIPoint: swiftUIPoint)
    if resisted && !boundaryResistanceVisible {
      announce(AppStrings.ScreenCapture.regionLimitedToDisplay)
    }
    boundaryResistanceVisible = resisted
  }

  func finishRegion(on displayID: CGDirectDisplayID, swiftUIPoint: CGPoint) {
    updateRegion(on: displayID, swiftUIPoint: swiftUIPoint)
    guard let rect = regionLocalRect, rect.width >= 2, rect.height >= 2 else { return }
    commitCurrentTarget()
  }

  func hover(on displayID: CGDirectDisplayID, swiftUIPoint: CGPoint) {
    guard countdown == nil, let display = display(displayID) else { return }
    switch mode {
    case .region:
      updateMagnifier(on: display, swiftUIPoint: swiftUIPoint)
    case .window:
      let global = CGPoint(
        x: display.appKitFrame.minX + swiftUIPoint.x,
        y: display.appKitFrame.maxY - swiftUIPoint.y)
      highlightedWindowID =
        selectableWindows.first(where: { appKitFrame(for: $0).contains(global) })?.id
    case .display:
      highlightedDisplayID = displayID
    }
  }

  func clickTarget(on displayID: CGDirectDisplayID, swiftUIPoint: CGPoint) {
    hover(on: displayID, swiftUIPoint: swiftUIPoint)
    if mode != .region { commitCurrentTarget() }
  }

  func traverseTarget(forward: Bool) {
    guard countdown == nil else { return }
    switch mode {
    case .region:
      let edges = CaptureRegionEdge.allCases
      let current = edges.firstIndex(of: activeRegionEdge) ?? 0
      activeRegionEdge = edges[(current + (forward ? 1 : edges.count - 1)) % edges.count]
      announce(AppStrings.ScreenCapture.regionEdge(activeRegionEdge))
    case .window:
      let targets = selectableWindows
      guard !targets.isEmpty else { return }
      traversalIndex = wrappedIndex(traversalIndex + (forward ? 1 : -1), count: targets.count)
      highlightedWindowID = targets[traversalIndex].id
      announce(AppStrings.ScreenCapture.windowTarget(traversalIndex + 1, targets.count))
    case .display:
      guard !catalog.displays.isEmpty else { return }
      traversalIndex = wrappedIndex(
        traversalIndex + (forward ? 1 : -1), count: catalog.displays.count)
      highlightedDisplayID = catalog.displays[traversalIndex].id
      announce(AppStrings.ScreenCapture.displayTarget(traversalIndex + 1, catalog.displays.count))
    }
  }

  func selectWindow(_ id: CGWindowID) {
    guard mode == .window, catalog.windows.contains(where: { $0.id == id }) else { return }
    highlightedWindowID = id
  }

  func selectDisplay(_ id: CGDirectDisplayID) {
    guard mode == .display, catalog.displays.contains(where: { $0.id == id }) else { return }
    highlightedDisplayID = id
  }

  func adjustRegion(horizontal: CGFloat, vertical: CGFloat, largeStep: Bool) {
    guard mode == .region else { return }
    ensureKeyboardRegion()
    guard let displayID = regionDisplayID, let display = display(displayID),
      var rect = regionLocalRect
    else { return }
    let step: CGFloat = largeStep ? 10 : 1
    switch activeRegionEdge {
    case .left:
      rect.origin.x += horizontal * step
      rect.size.width -= horizontal * step
    case .right: rect.size.width += horizontal * step
    case .top: rect.size.height += vertical * step
    case .bottom:
      rect.origin.y += vertical * step
      rect.size.height -= vertical * step
    }
    rect = rect.standardized.intersection(CGRect(origin: .zero, size: display.appKitFrame.size))
    guard rect.width >= 2, rect.height >= 2 else { return }
    regionLocalRect = rect
    updateNativeSize()
    announce(dimensionsText)
  }

  func commitCurrentTarget() {
    guard countdown == nil else { return }
    let target: CaptureTarget?
    switch mode {
    case .region:
      ensureKeyboardRegion()
      guard let displayID = regionDisplayID, let display = display(displayID), let regionLocalRect,
        let pixels = try? geometry.nativePixelRect(fromLocalAppKit: regionLocalRect, on: display)
      else { return }
      target = .region(displayID: displayID, nativePixelRect: pixels)
    case .window:
      guard let id = highlightedWindowID, let window = catalog.windows.first(where: { $0.id == id })
      else { return }
      target = .window(windowID: id, placementDisplayID: window.placementDisplayID)
    case .display:
      guard let id = highlightedDisplayID else { return }
      target = .display(displayID: id)
    }
    guard let target else { return }
    let selection = CaptureSelectionDescriptor(
      target: target,
      options: options,
      catalogGeneration: catalog.generation,
      topology: catalog.topology
    )
    countdownTask?.cancel()
    if options.delay == .none {
      onCommit?(selection)
      onCommit = nil
      return
    }
    countdownTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.delayViewModel.wait(for: selection.options.delay)
        try Task.checkCancellation()
        self.onCommit?(selection)
        self.onCommit = nil
      } catch {
        self.delayViewModel.cancel()
      }
    }
  }

  func cancel() { onCancel?() }

}
