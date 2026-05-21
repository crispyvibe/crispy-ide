import AppKit
import Foundation
import QuartzCore
import GhosttyKit

@MainActor
final class GhosttyTerminalView: NSView, TerminalInteractiveTargeting {
    struct SurfaceGeometry: Equatable {
        let pixelWidth: UInt32
        let pixelHeight: UInt32
        let backingScale: Double
    }

    weak var engine: GhosttyTerminalEngine?
    var overrideBackgroundColor: NSColor? {
        didSet { applyBackgroundColor() }
    }

    var surface: ghostty_surface_t?
    var surfaceCallbackContextPointer: UnsafeMutableRawPointer?
    var trackingAreaRef: NSTrackingArea?
    var desiredPixelSize = CGSize(width: 960, height: 520)
    var keyTextAccumulator: [String]? = nil
    /// Accumulates typed characters across keyDown events for compose history recording.
    var composeHistoryInputBuffer = ""
    var markedTextStorage: NSAttributedString?
    var markedSelectionRange = NSRange(location: NSNotFound, length: 0)
    var lastSyncedSurfaceGeometry: SurfaceGeometry?
    var committedTextSinkForTesting: ((String) -> Void)?
    var onWindowScreenChangeHandledForTesting: (() -> Void)?
    weak var observedWindowForScreenChanges: NSWindow?
    var screenChangeObserver: NSObjectProtocol?
    var pendingPrimaryMouseDownPoint: CGPoint?
    var primaryMouseDidDrag = false
    var pendingContextMenuMouseDownPoint: CGPoint?
    var contextMenuMouseDidDrag = false
    let interactiveTargetClickMovementThreshold: CGFloat = 4
    var hoveredInteractiveHit: TerminalInteractiveTargetHit?
    var hoveredInteractiveTarget: TerminalInteractiveTarget?
    var hoveredInteractiveTargetPoint: CGPoint?
    var isPointingHandCursorActive = false
    var interactiveTargetMenuPresenterForTesting: ((TerminalInteractiveTarget, CGPoint) -> Void)?
    var visibleContentsProviderForTesting: (() -> String)?
    var dimensionsProviderForTesting: (() -> (cols: Int, rows: Int))?
    let interactiveHoverOverlay = TerminalInteractiveHoverOverlayView(frame: .zero)
    nonisolated static let surfaceFreeQueue = DispatchQueue(
        label: "com.crispyvibe.app.ghostty.surface-free",
        qos: .utility
    )

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .textArea
    }

    override func accessibilityHelp() -> String? {
        "Terminal content area"
    }

    override func accessibilityValue() -> Any? {
        accessibilitySelectedText() ?? ""
    }

    override func setAccessibilityValue(_ value: Any?) {
        let content: String
        switch value {
        case let attributed as NSAttributedString:
            content = attributed.string
        case let string as String:
            content = string
        default:
            return
        }

        guard !content.isEmpty else { return }

        if Thread.isMainThread {
            insertText(content, replacementRange: NSRange(location: NSNotFound, length: 0))
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.insertText(content, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
    }

    override func accessibilitySelectedTextRange() -> NSRange {
        selectedRange()
    }

    override func accessibilitySelectedText() -> String? {
        guard let surface else { return nil }

        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }

        guard let pointer = text.text, text.text_len > 0 else { return nil }
        let selectedData = Data(bytes: pointer, count: Int(text.text_len))
        let selected = String(decoding: selectedData, as: UTF8.self)
        return selected.isEmpty ? nil : selected
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = makeBackingLayer()
        applyBackgroundColor()
        registerForDraggedTypes([.fileURL])
        configureInteractiveHoverOverlay()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = makeBackingLayer()
        applyBackgroundColor()
        registerForDraggedTypes([.fileURL])
        configureInteractiveHoverOverlay()
    }

    override func makeBackingLayer() -> CALayer {
        let metalLayer = CAMetalLayer()
        metalLayer.framebufferOnly = false
        return metalLayer
    }

    deinit {
        var surfaceToFree: ghostty_surface_t?
        var callbackContextPointerToRelease: UnsafeMutableRawPointer?
        MainActor.assumeIsolated {
            if let trackingAreaRef {
                removeTrackingArea(trackingAreaRef)
            }
            deactivateInteractiveTargetCursorIfNeeded()
            if let screenChangeObserver {
                NotificationCenter.default.removeObserver(screenChangeObserver)
            }
            surfaceToFree = surface
            callbackContextPointerToRelease = surfaceCallbackContextPointer
            surface = nil
            surfaceCallbackContextPointer = nil
        }
        if let surfaceToFree {
            Self.freeSurfaceAsync(
                surfaceToFree,
                callbackContextPointer: callbackContextPointerToRelease
            )
        } else if let callbackContextPointerToRelease {
            Self.releaseSurfaceCallbackContext(callbackContextPointerToRelease)
        }
    }

    nonisolated static func freeSurfaceAsync(
        _ surface: ghostty_surface_t,
        callbackContextPointer: UnsafeMutableRawPointer?
    ) {
        let surfaceAddress = UInt(bitPattern: surface)
        let callbackContextAddress = callbackContextPointer.map { UInt(bitPattern: $0) }
        surfaceFreeQueue.async {
            guard let surface = ghostty_surface_t(bitPattern: surfaceAddress) else { return }
            ghostty_surface_free(surface)
            if let callbackContextAddress,
               let callbackContextPointer = UnsafeMutableRawPointer(bitPattern: callbackContextAddress) {
                releaseSurfaceCallbackContext(callbackContextPointer)
            }
        }
    }

    nonisolated static func releaseSurfaceCallbackContext(_ pointer: UnsafeMutableRawPointer) {
        Unmanaged<GhosttySurfaceCallbackContext>.fromOpaque(pointer).release()
    }

    func setDesiredGridSize(columns: Int, rows: Int, font: NSFont) {
        let sampleAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let cellWidth = max(ceil(("M" as NSString).size(withAttributes: sampleAttributes).width), 1)
        let cellHeight = max(ceil(NSLayoutManager().defaultLineHeight(for: font)), 1)
        desiredPixelSize = CGSize(width: CGFloat(columns) * cellWidth, height: CGFloat(rows) * cellHeight)
        syncSurfaceGeometry()
    }

    func visibleContents() -> String {
        if let visibleContentsProviderForTesting {
            return visibleContentsProviderForTesting()
        }
        guard let surface else { return "" }
        var text = ghostty_text_s()
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false
        )
        guard ghostty_surface_read_text(surface, selection, &text) else {
            return ""
        }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let pointer = text.text, text.text_len > 0 else {
            return ""
        }
        return decodeUTF8(pointer, count: Int(text.text_len))
    }

    func currentInteractiveVisibleContents() -> String {
        if let visibleContentsProviderForTesting {
            return visibleContentsProviderForTesting()
        }
        if let engine, !engine.lastVisibleContents.isEmpty {
            return engine.lastVisibleContents
        }
        return visibleContents()
    }

    func copySelectionToPasteboard() {
        guard let surface else { return }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let pointer = text.text, text.text_len > 0 else { return }
        let value = decodeUTF8(pointer, count: Int(text.text_len))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func applyBackgroundColor() {
        let color = overrideBackgroundColor ?? .clear
        layer?.backgroundColor = color.cgColor
    }

    func updateMarkedTextInSurface() {
        guard let surface else { return }
        let text = markedTextStorage?.string ?? ""
        guard !text.isEmpty else {
            ghostty_surface_preedit(surface, nil, 0)
            return
        }
        text.withCString { pointer in
            ghostty_surface_preedit(surface, pointer, UInt(text.utf8.count))
        }
    }

    func imeScreenRect(fallbackRange range: NSRange) -> NSRect {
        _ = range
        guard let surface, let window else {
            return fallbackCaretScreenRect()
        }

        var x = 0.0
        var y = 0.0
        var width = 0.0
        var height = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)

        let backingRect = NSRect(
            x: x,
            y: y,
            width: max(width, 1),
            height: max(height, 1)
        )
        let localRect = convertFromBacking(backingRect)
        guard localRect.hasFiniteCoordinates, !localRect.isEmpty else {
            return fallbackCaretScreenRect()
        }
        return window.convertToScreen(convert(localRect, to: nil))
    }

    private func fallbackCaretScreenRect() -> NSRect {
        guard let window else { return .zero }
        let lineHeight = max(
            NSLayoutManager().defaultLineHeight(for: engine?.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)),
            1
        )
        let caretRect = NSRect(x: 0, y: max(bounds.height - lineHeight, 0), width: 1, height: lineHeight)
        return window.convertToScreen(convert(caretRect, to: nil))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if beginInteractiveTargetClick(at: point, modifierFlags: event.modifierFlags) {
            return
        }
        if beginInteractiveTargetContextMenuClick(at: point, modifierFlags: event.modifierFlags) {
            return
        }
        sendMousePosition(for: event)
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods(from: event))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let target = activatedInteractiveTargetOnMouseUp(
            at: point,
            modifierFlags: event.modifierFlags,
            clickCount: event.clickCount
        ) {
            activateInteractiveTarget(target)
            updateHoveredInteractiveTarget(at: point, modifierFlags: event.modifierFlags)
            return
        }
        if let target = interactiveTargetForContextMenuOnMouseUp(
            at: point,
            modifierFlags: event.modifierFlags,
            clickCount: event.clickCount
        ) {
            showInteractiveTargetContextMenu(for: target, at: point)
            updateHoveredInteractiveTarget(at: point, modifierFlags: event.modifierFlags)
            return
        }
        if pendingPrimaryMouseDownPoint != nil {
            resetInteractiveTargetTracking()
            updateHoveredInteractiveTarget(at: point, modifierFlags: event.modifierFlags)
            return
        }
        if pendingContextMenuMouseDownPoint != nil {
            resetInteractiveTargetContextMenuTracking()
            updateHoveredInteractiveTarget(at: point, modifierFlags: event.modifierFlags)
            return
        }
        sendMousePosition(for: event)
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods(from: event))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if pendingPrimaryMouseDownPoint != nil || pendingContextMenuMouseDownPoint != nil {
            updateInteractiveTargetDrag(at: point, modifierFlags: event.modifierFlags)
            return
        }
        sendMousePosition(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePosition(for: event)
        let point = convert(event.locationInWindow, from: nil)
        updateHoveredInteractiveTarget(at: point, modifierFlags: event.modifierFlags)
    }

    override func mouseEntered(with event: NSEvent) {
        sendMousePosition(for: event)
        let point = convert(event.locationInWindow, from: nil)
        updateHoveredInteractiveTarget(at: point, modifierFlags: event.modifierFlags)
    }

    override func mouseExited(with event: NSEvent) {
        clearHoveredInteractiveTarget()
        guard let surface else { return }
        ghostty_surface_mouse_pos(surface, -1, -1, mods(from: event))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        TerminalFileDropSupport.dragOperation(for: sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let engine else { return false }
        let urls = TerminalFileDropSupport.fileURLs(from: sender.draggingPasteboard)
        let currentDirectory = URL(fileURLWithPath: engine.currentDirectoryPath, isDirectory: true)
        guard let text = TerminalFileDropSupport.droppedText(for: urls, currentDirectory: currentDirectory) else {
            return false
        }
        TerminalFileDropSupport.requestFocus(for: self)
        engine.send(text: text)
        return true
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else {
            super.rightMouseDown(with: event)
            return
        }
        if !ghostty_surface_mouse_captured(surface) {
            super.rightMouseDown(with: event)
            return
        }
        sendMousePosition(for: event)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods(from: event))
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else {
            super.rightMouseUp(with: event)
            return
        }
        if !ghostty_surface_mouse_captured(surface) {
            super.rightMouseUp(with: event)
            return
        }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods(from: event))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precise = event.hasPreciseScrollingDeltas
        if precise {
            x *= 2
            y *= 2
        }

        var packed = precise ? 0b0000_0001 : 0
        let momentum: Int32
        switch event.momentumPhase {
        case .began:
            momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_BEGAN.rawValue)
        case .stationary:
            momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_STATIONARY.rawValue)
        case .changed:
            momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_CHANGED.rawValue)
        case .ended:
            momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_ENDED.rawValue)
        case .cancelled:
            momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_CANCELLED.rawValue)
        case .mayBegin:
            momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN.rawValue)
        default:
            momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_NONE.rawValue)
        }
        packed |= Int(momentum) << 1
        ghostty_surface_mouse_scroll(surface, x, y, ghostty_input_scroll_mods_t(packed))
    }

    fileprivate func sendMousePosition(for event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, mods(from: event))
    }

    func releaseSurfaceCallbackContext() {
        guard let surfaceCallbackContextPointer else { return }
        Self.releaseSurfaceCallbackContext(surfaceCallbackContextPointer)
        self.surfaceCallbackContextPointer = nil
    }

    func configureInteractiveHoverOverlay() {
        interactiveHoverOverlay.frame = bounds
        addSubview(interactiveHoverOverlay)
    }

    func ensureSurfaceCallbackContext() -> UnsafeMutableRawPointer {
        if let surfaceCallbackContextPointer {
            return surfaceCallbackContextPointer
        }
        guard let engine else {
            preconditionFailure("GhosttyTerminalView requires an engine before creating a surface callback context")
        }
        let callbackContextPointer = Unmanaged.passRetained(
            GhosttySurfaceCallbackContext(engine: engine)
        ).toOpaque()
        self.surfaceCallbackContextPointer = callbackContextPointer
        return callbackContextPointer
    }

    func interactiveTargetHit(at point: CGPoint) -> TerminalInteractiveTargetHit? {
        guard let hit = visibleGridPosition(at: point) else { return nil }
        let dimensions = currentGridDimensions()
        let grid = GhosttyTerminalInteractiveGrid(
            visibleContents: currentInteractiveVisibleContents(),
            cols: dimensions.cols,
            rows: dimensions.rows
        )
        let currentDirectoryURL = engine.map {
            URL(fileURLWithPath: $0.currentDirectoryPath, isDirectory: true).standardizedFileURL
        }
        return TerminalInteractiveTargetDetector.detectHit(
            in: grid,
            visibleColumn: hit.col,
            visibleRow: hit.row,
            currentDirectory: currentDirectoryURL
        )
    }

    func updateInteractiveHoverHighlight(_ hit: TerminalInteractiveTargetHit?) {
        interactiveHoverOverlay.highlightRects = hit.flatMap { interactiveHighlightRect(for: $0) }.map { [$0] } ?? []
    }

    func openInteractiveTargetLink(_ url: URL) {
        guard let engine else {
            NSWorkspace.shared.open(url)
            return
        }

        let currentDirectoryURL = URL(fileURLWithPath: engine.currentDirectoryPath, isDirectory: true)
            .standardizedFileURL
        if !engine.terminalServices.routeGhosttyNativeLinkTarget(
            url,
            currentDirectoryURL: currentDirectoryURL,
            sessionID: engine.sessionID
        ) {
            engine.terminalServices.vibespaceInteraction.open(url)
        }
    }

    func openInteractiveFileSystemTarget(_ target: TerminalFileSystemTarget) {
        guard let engine else {
            NSWorkspace.shared.open(target.url)
            return
        }

        let currentDirectoryURL = URL(fileURLWithPath: engine.currentDirectoryPath, isDirectory: true)
            .standardizedFileURL
        if !engine.terminalServices.routeGhosttyNativeFileSystemTarget(
            target,
            currentDirectoryURL: currentDirectoryURL,
            sessionID: engine.sessionID
        ) {
            engine.terminalServices.vibespaceInteraction.open(target.url)
        }
    }

    func currentGridDimensions() -> (cols: Int, rows: Int) {
        if let dimensionsProviderForTesting {
            return dimensionsProviderForTesting()
        }
        return engine?.currentDimensions() ?? (0, 0)
    }

    func visibleGridPosition(at point: CGPoint) -> (col: Int, row: Int)? {
        let dimensions = currentGridDimensions()
        guard dimensions.cols > 0, dimensions.rows > 0 else { return nil }
        guard bounds.contains(point) else { return nil }

        let cellWidth = bounds.width / CGFloat(dimensions.cols)
        let cellHeight = bounds.height / CGFloat(dimensions.rows)
        guard cellWidth.isFinite, cellWidth > 0, cellHeight.isFinite, cellHeight > 0 else { return nil }

        let column = min(max(Int(point.x / cellWidth), 0), dimensions.cols - 1)
        let row = min(max(Int((bounds.height - point.y) / cellHeight), 0), dimensions.rows - 1)
        return (col: column, row: row)
    }

    func interactiveHighlightRect(for hit: TerminalInteractiveTargetHit) -> CGRect? {
        let dimensions = currentGridDimensions()
        guard dimensions.cols > 0, dimensions.rows > 0 else { return nil }

        let cellWidth = bounds.width / CGFloat(dimensions.cols)
        let cellHeight = bounds.height / CGFloat(dimensions.rows)
        guard cellWidth.isFinite, cellWidth > 0, cellHeight.isFinite, cellHeight > 0 else { return nil }

        let minX = CGFloat(hit.columns.lowerBound) * cellWidth
        let width = CGFloat(max(hit.columns.upperBound - hit.columns.lowerBound, 1)) * cellWidth
        let minY = bounds.height - (CGFloat(hit.row + 1) * cellHeight)

        let rect = CGRect(x: minX, y: minY, width: width, height: cellHeight)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }
}

private extension NSRect {
    var hasFiniteCoordinates: Bool {
        origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
    }
}
