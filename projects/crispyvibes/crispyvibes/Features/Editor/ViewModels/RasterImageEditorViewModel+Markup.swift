import Foundation

/// Markup tool selection and inspector editing (style, text, delete, eyedropper).
extension RasterImageEditorViewModel {
    var hasSelectedMarkup: Bool { canvasState.selectedMarkup != nil }

    /// `true` when the inspector edits a text item or the text tool is active.
    var showsTextControls: Bool {
        markupTool == .text || { if case .text? = canvasState.selectedMarkup?.kind { return true } else { return false } }()
    }

    func selectMarkupTool(_ tool: RasterMarkupTool) {
        markupTool = tool
        if editingMode != .markup { selectMode(.markup) }
        actionStatus = nil
    }

    /// Changes the stroke color for new items and the selected item.
    func setStrokeColor(_ color: RasterColor) {
        updateStyle(key: "stroke") { $0.strokeColor = color }
    }

    /// Changes the fill (`nil` = none) for new items and the selected item.
    func setFillColor(_ color: RasterColor?) {
        updateStyle(key: "fill") { $0.fillColor = color }
    }

    func setLineWidth(_ width: Double) {
        updateStyle(key: "width") { $0.lineWidth = CGFloat(min(max(width, 1), 40)) }
    }

    func setFontName(_ name: String) {
        updateStyle(key: "font") { $0.fontName = name }
    }

    func setFontSize(_ size: Double) {
        updateStyle(key: "fontSize") { $0.fontSize = CGFloat(min(max(size, 8), 144)) }
    }

    /// Updates the default text and, if a text item is selected, its text (typing coalesces).
    func setText(_ text: String) {
        annotationText = text
        guard case .text? = canvasState.selectedMarkup?.kind, !isSaving else { return }
        canvas?.updateSelectedMarkup(coalescingKey: "text") { $0.withText(text) }
        refreshCanvasState()
    }

    func deleteSelectedMarkup() {
        guard !isSaving, canvas?.deleteSelectedMarkup() == true else { return }
        refreshCanvasState()
        actionStatus = AppStrings.ImageEditor.statusItemDeleted
    }

    /// Eyedropper: samples a screen color into the stroke color.
    func sampleStrokeColor() {
        services.colorSampler.sampleColor { [weak self] color in
            guard let color else { return }
            MainActor.assumeIsolated { self?.setStrokeColor(color) }
        }
    }

    /// Loads the inspector from the newly selected item.
    func syncInspectorWithSelection() {
        canvas?.session?.endCoalescing()
        guard let item = canvasState.selectedMarkup else { return }
        markupStyle = item.style
        if case let .text(text, _) = item.kind { annotationText = text }
    }

    // MARK: - Private

    private func updateStyle(key: String, _ change: (inout RasterMarkupStyle) -> Void) {
        change(&markupStyle)
        guard hasSelectedMarkup, !isSaving else { return }
        let style = markupStyle
        canvas?.updateSelectedMarkup(coalescingKey: key) { item in
            var updated = item
            updated.style = style
            return updated
        }
        refreshCanvasState()
    }

    func refreshCanvasState() {
        if let canvas { canvasState = canvas.state }
    }
}

/// Color adjustments: live preview while dragging, one undoable `.adjust` per release.
extension RasterImageEditorViewModel {
    var canAdjust: Bool { hasRenderableImage && !isSaving }

    /// Updates one slider value and shows a live preview.
    func previewAdjustment(_ keyPath: WritableKeyPath<RasterImageAdjustments, Double>, to value: Double) {
        guard canAdjust else { return }
        isAdjusting = true
        adjustments[keyPath: keyPath] = value
    }

    /// Commits the current slider values (no-op if unchanged).
    func commitAdjustments() {
        isAdjusting = false
        guard canAdjust, let canvas, let session = canvas.session,
              adjustments != session.effectiveAdjustments else { return }
        if !session.commit(.adjust(adjustments)) {
            actionStatus = AppStrings.ImageEditor.statusTransformFailed
            adjustments = session.effectiveAdjustments
        }
        refreshCanvasState()
    }

    func resetAdjustments() {
        guard !adjustments.isIdentity else { return }
        adjustments = .identity
        commitAdjustments()
    }

    func setComparing(_ comparing: Bool) {
        isComparing = comparing && hasRenderableImage
    }

    /// Override the canvas should display, if any.
    var previewAdjustmentsOverride: RasterImageAdjustments? {
        if isComparing { return .identity }
        return isAdjusting ? adjustments : nil
    }
}
