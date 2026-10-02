import AppKit

/// Pointer and keyboard input for the raster canvas.
extension EditableRasterImageCanvasView {
    override func resetCursorRects() {
        super.resetCursorRects()
        if isSpacePanning {
            addCursorRect(bounds, cursor: .openHand)
            return
        }
        switch editingMode {
        case .pan, .adjust:
            addCursorRect(bounds, cursor: .openHand)
        case .crop:
            addCursorRect(bounds, cursor: .crosshair)
        case .markup:
            switch markupTool {
            case .select: addCursorRect(bounds, cursor: .arrow)
            case .text: addCursorRect(bounds, cursor: .iBeam)
            default: addCursorRect(bounds, cursor: .crosshair)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard hasRenderableImage else { return }
        window?.makeFirstResponder(self)
        if editingMode == .pan || editingMode == .adjust || isSpacePanning {
            beginPan(with: event)
            return
        }
        guard !isInteractionLocked else { return }
        let location = clampedLocation(from: event)
        switch editingMode {
        case .crop:
            beginCropDrag(at: location)
        case .markup:
            beginMarkupDrag(at: location, clickCount: event.clickCount)
        case .pan, .adjust:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard hasRenderableImage else { return }
        if panAnchor != nil {
            continuePan(with: event)
            return
        }
        guard !isInteractionLocked else { return }
        let location = clampedLocation(from: event)
        switch editingMode {
        case .crop:
            continueCropDrag(to: location)
        case .markup:
            continueMarkupDrag(to: location, constrained: event.modifierFlags.contains(.shift))
        case .pan, .adjust:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard hasRenderableImage else { return }
        if panAnchor != nil {
            endPan()
            return
        }
        switch editingMode {
        case .crop:
            endCropDrag()
        case .markup:
            endMarkupDrag()
        case .pan, .adjust:
            break
        }
    }

    override func keyDown(with event: NSEvent) {
        let returnKeyCodes: Set<UInt16> = [36, 76]
        if returnKeyCodes.contains(event.keyCode), cropSelection != nil {
            onCommand?(.applyCrop)
            return
        }
        let hasCommandModifiers = !event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        if event.charactersIgnoringModifiers == " ", !hasCommandModifiers {
            if !event.isARepeat { setSpacePanning(true) }
            return
        }
        if !hasCommandModifiers, handleCropNudge(event) || handleMarkupKey(event) { return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " ", isSpacePanning {
            setSpacePanning(false)
            return
        }
        super.keyUp(with: event)
    }

    override func resignFirstResponder() -> Bool {
        setSpacePanning(false)
        return super.resignFirstResponder()
    }

    private func setSpacePanning(_ enabled: Bool) {
        guard isSpacePanning != enabled else { return }
        isSpacePanning = enabled
        window?.invalidateCursorRects(for: self)
    }

    override func cancelOperation(_ sender: Any?) {
        if cropSelection != nil {
            onCommand?(.cancelCrop)
            return
        }
        if selectedMarkupID != nil {
            selectMarkup(nil)
            return
        }
        super.cancelOperation(sender)
    }

    /// Makes the canvas key so Return, Escape, and ⌘Z reach it, without stealing focus
    /// from a text field the user is typing in.
    func focusIfPossible() {
        guard hasRenderableImage, let window, !(window.firstResponder is NSText) else { return }
        window.makeFirstResponder(self)
    }

    private func beginPan(with event: NSEvent) {
        guard let clipView = enclosingScrollView?.contentView else { return }
        panAnchor = (event.locationInWindow, clipView.bounds.origin)
        // `set()` (not push/pop) so an interrupted drag can never leave the cursor stack unbalanced;
        // cursor rects restore the open hand afterwards.
        NSCursor.closedHand.set()
    }

    private func continuePan(with event: NSEvent) {
        guard let anchor = panAnchor,
              let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        let magnification = max(scrollView.magnification, 0.01)
        let deltaX = (event.locationInWindow.x - anchor.window.x) / magnification
        let deltaY = (event.locationInWindow.y - anchor.window.y) / magnification
        var target = clipView.bounds
        target.origin = CGPoint(x: anchor.origin.x - deltaX, y: anchor.origin.y + deltaY)
        clipView.scroll(to: clipView.constrainBoundsRect(target).origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func endPan() {
        guard panAnchor != nil else { return }
        panAnchor = nil
        window?.invalidateCursorRects(for: self)
    }
}
