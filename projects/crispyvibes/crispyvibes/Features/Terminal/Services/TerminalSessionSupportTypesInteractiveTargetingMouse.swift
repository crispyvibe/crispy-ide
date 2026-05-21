import AppKit

extension MonitoredTerminalView {
    @MainActor
    final class InteractiveTargetTrackingOwner: NSObject {
        weak var terminalView: MonitoredTerminalView?

        init(terminalView: MonitoredTerminalView) {
            self.terminalView = terminalView
        }

        @objc(mouseMoved:) func mouseMoved(_ event: NSEvent) {
            terminalView?.handleTrackedMouseMoved(event)
        }

        @objc(mouseEntered:) func mouseEntered(_ event: NSEvent) {
            terminalView?.handleTrackedMouseMoved(event)
        }

        @objc(mouseExited:) func mouseExited(_ event: NSEvent) {
            terminalView?.clearHoveredInteractiveTarget()
            terminalView?.teardownInteractiveTargetRecognition()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let interactiveTargetTrackingArea {
            removeTrackingArea(interactiveTargetTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .enabledDuringMouseDrag],
            owner: interactiveTargetTrackingOwner,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        interactiveTargetTrackingArea = trackingArea
    }

    func configureInteractiveTargetRecognition() {
        guard interactiveTargetEventMonitor == nil else { return }
        interactiveTargetEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleInteractiveTargetEvent(event) ?? event
        }
        interactiveTargetModifierEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged]
        ) { [weak self] event in
            self?.handleInteractiveTargetModifierEvent(event) ?? event
        }
    }

    func teardownInteractiveTargetRecognition() {
        if let interactiveTargetEventMonitor {
            NSEvent.removeMonitor(interactiveTargetEventMonitor)
            self.interactiveTargetEventMonitor = nil
        }
        if let interactiveTargetModifierEventMonitor {
            NSEvent.removeMonitor(interactiveTargetModifierEventMonitor)
            self.interactiveTargetModifierEventMonitor = nil
        }
        if let interactiveTargetTrackingArea {
            removeTrackingArea(interactiveTargetTrackingArea)
            self.interactiveTargetTrackingArea = nil
        }
        deactivateInteractiveTargetCursorIfNeeded()
    }

    func handleTrackedMouseMoved(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else {
            clearHoveredInteractiveTarget()
            teardownInteractiveTargetRecognition()
            return
        }
        configureInteractiveTargetRecognition()
        updateHoveredInteractiveTarget(at: point, modifierFlags: event.modifierFlags)
    }

    func handleInteractiveTargetEvent(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        let point = convert(event.locationInWindow, from: nil)

        switch event.type {
        case .leftMouseDown:
            if bounds.contains(point) {
                if beginInteractiveTargetContextMenuClick(at: point, modifierFlags: event.modifierFlags) {
                    return nil
                }
                recordInteractiveTargetMouseDown(at: point)
            } else {
                resetInteractiveTargetTracking()
                resetInteractiveTargetContextMenuTracking()
            }
        case .leftMouseDragged:
            guard pendingPrimaryMouseDownPoint != nil || pendingContextMenuMouseDownPoint != nil else { return event }
            updateInteractiveTargetDrag(at: point, modifierFlags: event.modifierFlags)
            if pendingContextMenuMouseDownPoint != nil {
                return nil
            }
        case .leftMouseUp:
            guard bounds.contains(point) else { return event }
            if let target = interactiveTargetForContextMenuOnMouseUp(
                at: point,
                modifierFlags: event.modifierFlags,
                clickCount: event.clickCount
            ) {
                showInteractiveTargetContextMenu(for: target, at: point)
                return nil
            }
            guard pendingPrimaryMouseDownPoint != nil else { return event }
            guard let target = activatedInteractiveTargetOnMouseUp(
                at: point,
                modifierFlags: event.modifierFlags,
                clickCount: event.clickCount
            ) else { return event }
            activateInteractiveTarget(target)
            return nil
        default:
            break
        }

        return event
    }

    func handleInteractiveTargetModifierEvent(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }

        switch event.type {
        case .flagsChanged:
            guard let hoveredInteractiveTargetPoint else {
                clearHoveredInteractiveTarget()
                return event
            }
            updateHoveredInteractiveTarget(at: hoveredInteractiveTargetPoint, modifierFlags: event.modifierFlags)
        default:
            break
        }

        return event
    }

    func openInteractiveTargetLink(_ url: URL) {
        if let onLinkTargetActivated {
            onLinkTargetActivated(url)
        } else {
            terminalDelegate?.requestOpenLink(source: self, link: url.absoluteString, params: [:])
        }
    }

    func openInteractiveFileSystemTarget(_ target: TerminalFileSystemTarget) {
        if let onFileSystemTargetActivated {
            onFileSystemTargetActivated(target)
        } else {
            guard let vibespaceInteraction else {
                assertionFailure("MonitoredTerminalView requires VibeSpaceInteractionService to open file system targets.")
                return
            }
            vibespaceInteraction.open(target.url)
        }
    }
}
