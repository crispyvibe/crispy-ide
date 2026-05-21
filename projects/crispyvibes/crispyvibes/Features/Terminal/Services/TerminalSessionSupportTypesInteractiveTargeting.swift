import AppKit
import Foundation
import SwiftTerm

@MainActor
protocol TerminalInteractiveTargeting: AnyObject {
    var pendingPrimaryMouseDownPoint: CGPoint? { get set }
    var primaryMouseDidDrag: Bool { get set }
    var pendingContextMenuMouseDownPoint: CGPoint? { get set }
    var contextMenuMouseDidDrag: Bool { get set }
    var interactiveTargetClickMovementThreshold: CGFloat { get }
    var hoveredInteractiveHit: TerminalInteractiveTargetHit? { get set }
    var hoveredInteractiveTarget: TerminalInteractiveTarget? { get set }
    var hoveredInteractiveTargetPoint: CGPoint? { get set }
    var isPointingHandCursorActive: Bool { get set }
    var toolTip: String? { get set }
    var interactiveTargetMenuPresenterForTesting: ((TerminalInteractiveTarget, CGPoint) -> Void)? { get set }

    func interactiveTargetHit(at point: CGPoint) -> TerminalInteractiveTargetHit?
    func updateInteractiveHoverHighlight(_ hit: TerminalInteractiveTargetHit?)
    func openInteractiveTargetLink(_ url: URL)
    func openInteractiveFileSystemTarget(_ target: TerminalFileSystemTarget)
}

@MainActor
extension TerminalInteractiveTargeting {
    func interactiveTarget(at point: CGPoint) -> TerminalInteractiveTarget? {
        interactiveTargetHit(at: point)?.target
    }

    func recordInteractiveTargetMouseDown(at point: CGPoint) {
        pendingPrimaryMouseDownPoint = point
        primaryMouseDidDrag = false
    }

    func beginInteractiveTargetClick(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard shouldActivateInteractiveTarget(for: modifierFlags) else {
            resetInteractiveTargetTracking()
            return false
        }
        guard interactiveTarget(at: point) != nil else {
            resetInteractiveTargetTracking()
            return false
        }
        recordInteractiveTargetMouseDown(at: point)
        updateHoveredInteractiveTarget(at: point, modifierFlags: modifierFlags)
        return true
    }

    func beginInteractiveTargetContextMenuClick(
        at point: CGPoint,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard shouldPresentInteractiveTargetContextMenu(for: modifierFlags) else {
            resetInteractiveTargetContextMenuTracking()
            return false
        }
        guard interactiveTarget(at: point) != nil else {
            resetInteractiveTargetContextMenuTracking()
            return false
        }
        pendingContextMenuMouseDownPoint = point
        contextMenuMouseDidDrag = false
        updateHoveredInteractiveTarget(at: point, modifierFlags: modifierFlags)
        return true
    }

    func updateInteractiveTargetDrag(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        if let pendingPrimaryMouseDownPoint,
           hypot(point.x - pendingPrimaryMouseDownPoint.x, point.y - pendingPrimaryMouseDownPoint.y)
            > interactiveTargetClickMovementThreshold {
            primaryMouseDidDrag = true
        }
        if let pendingContextMenuMouseDownPoint,
           hypot(point.x - pendingContextMenuMouseDownPoint.x, point.y - pendingContextMenuMouseDownPoint.y)
            > interactiveTargetClickMovementThreshold {
            contextMenuMouseDidDrag = true
        }
        updateHoveredInteractiveTarget(at: point, modifierFlags: modifierFlags)
    }

    func activatedInteractiveTargetOnMouseUp(
        at point: CGPoint,
        modifierFlags: NSEvent.ModifierFlags,
        clickCount: Int = 1
    ) -> TerminalInteractiveTarget? {
        defer { resetInteractiveTargetTracking() }
        guard let pendingPrimaryMouseDownPoint else { return nil }
        guard !primaryMouseDidDrag else { return nil }
        guard clickCount == 1 else { return nil }
        guard hypot(point.x - pendingPrimaryMouseDownPoint.x, point.y - pendingPrimaryMouseDownPoint.y)
            <= interactiveTargetClickMovementThreshold else { return nil }
        guard shouldActivateInteractiveTarget(for: modifierFlags) else { return nil }
        return interactiveTarget(at: point)
    }

    func interactiveTargetForContextMenuOnMouseUp(
        at point: CGPoint,
        modifierFlags: NSEvent.ModifierFlags,
        clickCount: Int = 1
    ) -> TerminalInteractiveTarget? {
        defer { resetInteractiveTargetContextMenuTracking() }
        guard let pendingContextMenuMouseDownPoint else { return nil }
        guard !contextMenuMouseDidDrag else { return nil }
        guard clickCount == 1 else { return nil }
        guard hypot(point.x - pendingContextMenuMouseDownPoint.x, point.y - pendingContextMenuMouseDownPoint.y)
            <= interactiveTargetClickMovementThreshold else { return nil }
        guard shouldPresentInteractiveTargetContextMenu(for: modifierFlags) else { return nil }
        return interactiveTarget(at: point)
    }

    func resetInteractiveTargetTracking() {
        pendingPrimaryMouseDownPoint = nil
        primaryMouseDidDrag = false
    }

    func resetInteractiveTargetContextMenuTracking() {
        pendingContextMenuMouseDownPoint = nil
        contextMenuMouseDidDrag = false
    }

    func shouldActivateInteractiveTarget(for modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let relevantModifiers = modifierFlags.intersection([.command, .option, .control, .shift])
        return relevantModifiers == [.command]
    }

    func shouldPresentInteractiveTargetContextMenu(for modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let relevantModifiers = modifierFlags.intersection([.command, .option, .control, .shift])
        return relevantModifiers.isEmpty
    }

    func updateHoveredInteractiveTarget(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        let hit = interactiveTargetHit(at: point)
        hoveredInteractiveHit = hit
        hoveredInteractiveTarget = hit?.target
        hoveredInteractiveTargetPoint = point
        toolTip = hit?.target.hoverHint
        updateInteractiveHoverHighlight(hit)

        if hit != nil && shouldActivateInteractiveTarget(for: modifierFlags) {
            activatePointingHandCursorIfNeeded()
        } else {
            deactivateInteractiveTargetCursorIfNeeded()
        }
    }

    func clearHoveredInteractiveTarget() {
        hoveredInteractiveHit = nil
        hoveredInteractiveTarget = nil
        hoveredInteractiveTargetPoint = nil
        toolTip = nil
        updateInteractiveHoverHighlight(nil)
        deactivateInteractiveTargetCursorIfNeeded()
    }

    func activateInteractiveTarget(_ target: TerminalInteractiveTarget) {
        switch target {
        case .link(let link):
            guard let url = URL(string: link) else { return }
            openInteractiveTargetLink(url)
        case .fileSystem(let fileSystemTarget):
            openInteractiveFileSystemTarget(fileSystemTarget)
        }
    }

    func showInteractiveTargetContextMenu(for target: TerminalInteractiveTarget, at point: CGPoint) {
        if let interactiveTargetMenuPresenterForTesting {
            interactiveTargetMenuPresenterForTesting(target, point)
            return
        }
        guard let view = self as? NSView else { return }
        let menu = NSMenu(title: "Open Target")

        switch target {
        case .link(let link):
            guard let url = URL(string: link) else { return }
            menu.addActionItem(title: "Open in Crispy") {
                self.openInteractiveTargetLink(url)
            }
            menu.addActionItem(title: "Open in Default Browser") {
                NSWorkspace.shared.open(url)
            }
            menu.addItem(.separator())
            menu.addActionItem(title: "Copy Link") {
                Self.copyToPasteboard(link)
            }

        case .fileSystem(let fileTarget):
            let url = fileTarget.url
            let isDirectory = Self.isDirectoryURL(url)

            menu.addActionItem(title: "Open") {
                self.openInteractiveFileSystemTarget(fileTarget)
            }
            if !isDirectory {
                menu.addActionItem(title: "Open in Shelf") {
                    NotificationCenter.default.post(
                        name: .terminalAddFileToShelfRequested,
                        object: nil,
                        userInfo: [AppCommandUserInfoKey.url: url]
                    )
                }
            }
            menu.addActionItem(title: "Open in System") {
                NSWorkspace.shared.open(url)
            }
            if !isDirectory {
                menu.addActionItem(title: "Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            menu.addItem(.separator())
            menu.addActionItem(title: "Copy Path") {
                Self.copyToPasteboard(url.path)
            }
        }

        menu.popUp(positioning: nil, at: point, in: view)
    }

    private static func isDirectoryURL(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return url.hasDirectoryPath
        }
        return isDirectory.boolValue
    }

    private static func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func activatePointingHandCursorIfNeeded() {
        guard !isPointingHandCursorActive else { return }
        NSCursor.pointingHand.push()
        isPointingHandCursorActive = true
    }

    func deactivateInteractiveTargetCursorIfNeeded() {
        guard isPointingHandCursorActive else { return }
        NSCursor.pop()
        isPointingHandCursorActive = false
    }
}

private final class TerminalInteractiveMenuAction: NSObject {
    let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @MainActor func perform() {
        handler()
    }
}

private final class TerminalInteractiveMenuTarget: NSObject {
    static let shared = TerminalInteractiveMenuTarget()

    @MainActor @objc func performMenuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? TerminalInteractiveMenuAction else { return }
        action.perform()
    }
}

private extension NSMenu {
    func addActionItem(title: String, handler: @escaping @MainActor () -> Void) {
        let item = NSMenuItem(
            title: title,
            action: #selector(TerminalInteractiveMenuTarget.performMenuAction(_:)),
            keyEquivalent: ""
        )
        item.target = TerminalInteractiveMenuTarget.shared
        item.representedObject = TerminalInteractiveMenuAction(handler: handler)
        addItem(item)
    }
}

final class TerminalInteractiveHoverOverlayView: NSView {
    var highlightRects: [CGRect] = [] {
        didSet {
            guard oldValue != highlightRects else { return }
            needsDisplay = true
        }
    }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.width, .height]
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !highlightRects.isEmpty else { return }

        let fillColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
        let underlineColor = NSColor.controlAccentColor.withAlphaComponent(0.7)

        for rect in highlightRects {
            let clippedRect = rect.intersection(bounds)
            guard !clippedRect.isNull, !clippedRect.isEmpty else { continue }

            let highlightRect = clippedRect.insetBy(dx: 0.5, dy: 2)
            if !highlightRect.isNull, !highlightRect.isEmpty {
                fillColor.setFill()
                let highlightPath = NSBezierPath(
                    roundedRect: highlightRect,
                    xRadius: 3,
                    yRadius: 3
                )
                highlightPath.fill()
            }

            let underlineRect = CGRect(
                x: clippedRect.minX + 1,
                y: clippedRect.minY + 1,
                width: max(clippedRect.width - 2, 1),
                height: 2
            )
            underlineColor.setFill()
            let underlinePath = NSBezierPath(
                roundedRect: underlineRect,
                xRadius: 1,
                yRadius: 1
            )
            underlinePath.fill()
        }
    }
}

final class MonitoredTerminalView: LocalProcessTerminalView, TerminalInteractiveTargeting {
    var ownerSessionID: UUID?
    var focusCoordinator: TerminalFocusCoordinator?
    var vibespaceInteraction: VibeSpaceInteractionService?

    var onRenderableOutputReceived: ((String?) -> Void)?
    var onSignificantOutputReceived: (() -> Void)?
    var onSplitTerminalRequested: (() -> Void)?
    var onTemporaryTerminalRequested: (() -> Void)?
    var currentDirectoryProvider: (() -> URL?)?
    var onLinkTargetActivated: ((URL) -> Void)?
    var onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?
    var onInlineTriggerTextInput: ((String) -> Bool)?
    var onInlineTriggerCommand: ((TerminalInlineTriggerCommand) -> Bool)?
    let significantChangeThreshold = 10
    let outputClassificationQueue = DispatchQueue(
        label: "com.crispyvibe.terminal.output-classification",
        qos: .userInitiated
    )
    let callbackCoalescingInterval: TimeInterval = 0.05
    var hasDispatchedInitialRenderableCallback = false
    var pendingRenderableCallback = false
    var pendingRenderableSample: String?
    var pendingSignificantCallback = false
    var callbackFlushScheduled = false
    var contextualInteractiveTarget: TerminalInteractiveTarget?
    var interactiveTargetEventMonitor: Any?
    var interactiveTargetModifierEventMonitor: Any?
    var interactiveTargetTrackingArea: NSTrackingArea?
    lazy var interactiveTargetTrackingOwner = InteractiveTargetTrackingOwner(terminalView: self)
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
    let interactiveHoverOverlay = TerminalInteractiveHoverOverlayView(frame: .zero)
    var inlineTriggerEventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        configureInteractiveHoverOverlay()
        configureInlineTriggerEventMonitor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
        configureInteractiveHoverOverlay()
        configureInlineTriggerEventMonitor()
    }

    deinit {
        if let inlineTriggerEventMonitor {
            NSEvent.removeMonitor(inlineTriggerEventMonitor)
        }
        teardownInteractiveTargetRecognition()
    }

    override func insertText(_ insertString: Any) {
        let text: String
        if let attributed = insertString as? NSAttributedString {
            text = attributed.string
        } else if let plain = insertString as? NSString {
            text = plain as String
        } else {
            super.insertText(insertString)
            return
        }

        if !text.isEmpty, onInlineTriggerTextInput?(text) == true {
            return
        }

        super.insertText(insertString)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        let bytes = Array(slice)
        guard !bytes.isEmpty else { return }
        let threshold = significantChangeThreshold
        outputClassificationQueue.async { [weak self] in
            guard let self else { return }
            let classification = Self.classifyOutput(for: bytes, significantChangeThreshold: threshold)
            guard classification.hasRenderableText || classification.hasSignificantText else { return }
            self.enqueueClassificationResult(classification)
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        TerminalFileDropSupport.dragOperation(for: sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = TerminalFileDropSupport.fileURLs(from: sender.draggingPasteboard)
        guard let text = TerminalFileDropSupport.droppedText(
            for: urls,
            currentDirectory: currentDirectoryProvider?()
        ) else {
            return false
        }
        TerminalFileDropSupport.requestFocus(for: self)
        send(txt: text)
        return true
    }

    private func configureInteractiveHoverOverlay() {
        interactiveHoverOverlay.frame = bounds
        addSubview(interactiveHoverOverlay)
    }

    private func configureInlineTriggerEventMonitor() {
        inlineTriggerEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.window?.firstResponder === self else { return event }
            return self.consumeInlineTriggerCommand(event) ? nil : event
        }
    }

    private func consumeInlineTriggerCommand(_ event: NSEvent) -> Bool {
        guard let command = inlineTriggerCommand(for: event) else { return false }
        return onInlineTriggerCommand?(command) == true
    }

    private func inlineTriggerCommand(for event: NSEvent) -> TerminalInlineTriggerCommand? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let effectiveFlags = flags.subtracting([.capsLock, .numericPad, .function])
        guard effectiveFlags.isEmpty else { return nil }

        switch event.keyCode {
        case 126:
            return .moveUp
        case 125:
            return .moveDown
        case 124:
            return .moveRight
        case 36, 48, 76:
            return .confirm
        case 51:
            return .deleteBackward
        case 53:
            return .dismiss
        default:
            return nil
        }
    }
}
