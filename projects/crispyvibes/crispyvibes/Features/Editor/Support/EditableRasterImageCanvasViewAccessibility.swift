import AppKit

/// Accessibility element for one markup item, operable by VoiceOver (press to select, custom
/// actions to move or delete).
final class RasterMarkupAccessibilityElement: NSAccessibilityElement {
    let itemID: UUID
    private let onPress: () -> Void

    init(itemID: UUID, onPress: @escaping () -> Void) {
        self.itemID = itemID
        self.onPress = onPress
        super.init()
    }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }
}

/// VoiceOver exposure of the canvas: image size, markup count, one actionable element per markup
/// item, and canvas-level custom actions for the selected item and the crop box.
extension EditableRasterImageCanvasView {
    override func accessibilityValue() -> Any? {
        guard let session else { return nil }
        let pixels = session.exportTransform.pixelSize
        let count = session.markupEntries.count
        let size = "\(pixels.width) × \(pixels.height)"
        return count > 0 ? "\(size), \(AppStrings.ImageEditor.accessibilityMarkupCount(count))" : size
    }

    override func accessibilityChildren() -> [Any]? {
        guard let session, editingMode == .markup else { return super.accessibilityChildren() }
        return session.markupEntries.map { entry in
            let element = RasterMarkupAccessibilityElement(itemID: entry.item.id) { [weak self] in
                self?.selectMarkup(entry.item.id)
            }
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(entry.item.kind.accessibilityName)
            element.setAccessibilityParent(self)
            element.setAccessibilityIdentifier("editor.preview.image.markup.item")
            element.setAccessibilitySelected(entry.item.id == selectedMarkupID)
            element.setAccessibilityFrameInParentSpace(RasterImageOverlayPainter.bounds(of: entry.item))
            return element
        }
    }

    override func accessibilitySelectedChildren() -> [Any]? {
        (accessibilityChildren() as? [NSAccessibilityElement])?.filter { $0.isAccessibilitySelected() }
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions: [NSAccessibilityCustomAction] = []
        if editingMode == .markup, selectedMarkupID != nil {
            actions.append(action(AppStrings.ImageEditor.deleteItem) { $0.onCommand?(.deleteSelection) })
            for (name, delta) in moveActions {
                actions.append(action(name) { canvas in
                    let step = 10 / max(canvas.session?.document.exportScale ?? 1, 0.0001)
                    canvas.updateSelectedMarkup(coalescingKey: nil) { $0.translated(by: CGVector(dx: delta.dx * step, dy: delta.dy * step)) }
                })
            }
        }
        if editingMode == .crop, cropSelection != nil {
            actions.append(action(AppStrings.ImageEditor.accessibilityShrinkCrop) { $0.resizeCropBoxForAccessibility(by: -0.05) })
            actions.append(action(AppStrings.ImageEditor.accessibilityExpandCrop) { $0.resizeCropBoxForAccessibility(by: 0.05) })
            for (name, delta) in moveActions {
                actions.append(action(name) { canvas in
                    guard let box = canvas.cropSelection else { return }
                    let step = min(box.width, box.height) * 0.05
                    canvas.cropSelection = RasterImageCropInteraction.move(box, by: CGVector(dx: delta.dx * step, dy: delta.dy * step), bounds: canvas.canvasBounds)
                    canvas.needsDisplay = true
                    canvas.publishStateIfNeeded()
                })
            }
            if hasPendingCropSelection {
                actions.append(action(AppStrings.ImageEditor.applyCrop) { $0.onCommand?(.applyCrop) })
                actions.append(action(AppStrings.ImageEditor.cancelCrop) { $0.onCommand?(.cancelCrop) })
            }
        }
        return actions.isEmpty ? nil : actions
    }

    /// Grows (positive) or shrinks (negative) the crop box around its center by `fraction` of the
    /// canvas size, honoring the aspect constraint.
    func resizeCropBoxForAccessibility(by fraction: CGFloat) {
        guard let box = cropSelection else { return }
        let bounds = canvasBounds
        let dx = bounds.width * fraction / 2
        let dy = cropAspectRatio.map { _ in dx * box.height / max(box.width, 0.0001) } ?? bounds.height * fraction / 2
        var resized = box.insetBy(dx: -dx, dy: -dy).intersection(bounds)
        if resized.width < minimumCropCanvasSize || resized.height < minimumCropCanvasSize { resized = box }
        cropSelection = RasterImageCropInteraction.constrain(resized, to: cropAspectRatio, bounds: bounds)
        needsDisplay = true
        publishStateIfNeeded()
    }

    private var moveActions: [(String, CGVector)] {
        [
            (AppStrings.ImageEditor.accessibilityMoveLeft, CGVector(dx: -1, dy: 0)),
            (AppStrings.ImageEditor.accessibilityMoveRight, CGVector(dx: 1, dy: 0)),
            (AppStrings.ImageEditor.accessibilityMoveUp, CGVector(dx: 0, dy: -1)),
            (AppStrings.ImageEditor.accessibilityMoveDown, CGVector(dx: 0, dy: 1))
        ]
    }

    private func action(_ name: String, _ body: @escaping (EditableRasterImageCanvasView) -> Void) -> NSAccessibilityCustomAction {
        NSAccessibilityCustomAction(name: name) { [weak self] in
            guard let self, !self.isInteractionLocked else { return false }
            body(self)
            return true
        }
    }
}
