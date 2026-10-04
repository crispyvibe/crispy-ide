import AppKit
import XCTest
@testable import CrispyVibes

/// F009 Phase 0: canvas crop pixels, marquee semantics, export orientation, and revert.
@MainActor
final class EditableRasterImageCanvasViewTests: XCTestCase {
    private let fixtures = RasterImageTestFixtures.self
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("CanvasTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeCanvas(width: Int = 100, height: Int = 60, pointScale: CGFloat = 1) -> EditableRasterImageCanvasView {
        let canvas = EditableRasterImageCanvasView(frame: .zero)
        let cg = fixtures.quadrantImage(width: width, height: height)
        canvas.loadImage(NSImage(cgImage: cg, size: NSSize(width: CGFloat(width) / pointScale, height: CGFloat(height) / pointScale)))
        return canvas
    }

    private func applyCrop(_ canvas: EditableRasterImageCanvasView, _ rect: CGRect) -> CGImage? {
        canvas.cropSelection = rect
        XCTAssertEqual(canvas.applyCropSelection(), .success)
        return canvas.workingImage.flatMap(fixtures.cgImage)
    }

    func test_cropEachCorner_keepsThatQuadrantsPixels() throws {
        // Quadrant order: top-left, top-right, bottom-left, bottom-right.
        let corners = [
            CGRect(x: 0, y: 0, width: 50, height: 30),
            CGRect(x: 50, y: 0, width: 50, height: 30),
            CGRect(x: 0, y: 30, width: 50, height: 30),
            CGRect(x: 50, y: 30, width: 50, height: 30)
        ]
        for (index, rect) in corners.enumerated() {
            let canvas = makeCanvas()
            let cropped = try XCTUnwrap(applyCrop(canvas, rect))
            XCTAssertEqual(cropped.width, 50)
            XCTAssertEqual(cropped.height, 30)
            for (x, y) in [(2, 2), (47, 2), (2, 27), (47, 27)] {
                XCTAssertTrue(
                    fixtures.matches(fixtures.pixel(cropped, x: x, y: y), fixtures.quadrantColors[index], tolerance: 2),
                    "corner \(index) pixel (\(x),\(y)) = \(fixtures.pixel(cropped, x: x, y: y))"
                )
            }
        }
    }

    func test_cropOnRetinaBackedImage_mapsPointsToPixels() throws {
        let canvas = makeCanvas(width: 200, height: 120, pointScale: 2)
        let cropped = try XCTUnwrap(applyCrop(canvas, CGRect(x: 0, y: 0, width: 50, height: 30)))
        XCTAssertEqual(cropped.width, 100)
        XCTAssertEqual(cropped.height, 60)
        XCTAssertEqual(canvas.workingImage?.size, NSSize(width: 50, height: 30))
        XCTAssertTrue(fixtures.matches(fixtures.pixel(cropped, x: 50, y: 30), fixtures.quadrantColors[0], tolerance: 2))
    }

    func test_compositedExport_isNotVerticallyFlipped() throws {
        let canvas = makeCanvas()
        canvas.commit(.stroke(RasterStroke(points: [CGPoint(x: 5, y: 5), CGPoint(x: 95, y: 5)])))
        let composited = try XCTUnwrap(canvas.compositedImage().flatMap(fixtures.cgImage))
        XCTAssertTrue(fixtures.matches(fixtures.pixel(composited, x: 10, y: 40), fixtures.quadrantColors[2], tolerance: 2),
                      "bottom-left must stay blue, got \(fixtures.pixel(composited, x: 10, y: 40))")
        XCTAssertTrue(fixtures.matches(fixtures.pixel(composited, x: 80, y: 15), fixtures.quadrantColors[1], tolerance: 2),
                      "top-right must stay green")
        // The stroke drawn near the top (y = 5) must land in the top rows (green stroke over red).
        let strokePixel = fixtures.pixel(composited, x: 30, y: 5)
        XCTAssertLessThan(Int(strokePixel.r), 200, "stroke expected at top, found \(strokePixel)")
        let bottomPixel = fixtures.pixel(composited, x: 30, y: 54)
        XCTAssertTrue(fixtures.matches(bottomPixel, fixtures.quadrantColors[2], tolerance: 2), "no stroke at bottom")
    }

    func test_cropThenSave_roundTripsUprightPixels() throws {
        let canvas = makeCanvas()
        _ = try XCTUnwrap(applyCrop(canvas, CGRect(x: 50, y: 0, width: 50, height: 30)))
        let url = tempRoot.appendingPathComponent("cropped.png")
        guard case .success = canvas.saveCompositedImage(to: url) else { return XCTFail("save failed") }
        let reopened = try XCTUnwrap(RasterImageDecoder().decode(contentsOf: url, maxPixelSize: 1024))
        XCTAssertEqual(reopened.image.width, 50)
        XCTAssertEqual(reopened.image.height, 30)
        XCTAssertTrue(fixtures.matches(fixtures.pixel(reopened.image, x: 25, y: 15), fixtures.quadrantColors[1], tolerance: 2))
    }

    func test_cropMarquee_isNotAPersistableEdit() {
        let canvas = makeCanvas()
        canvas.editingMode = .crop
        canvas.cropSelection = CGRect(x: 10, y: 10, width: 30, height: 20)
        XCTAssertFalse(canvas.hasPendingEdits)
        XCTAssertTrue(canvas.state.hasCropSelection)
        XCTAssertTrue(canvas.state.canApplyCrop)

        canvas.editingMode = .markup
        XCTAssertTrue(canvas.state.hasCropSelection, "switching modes must not silently drop or hide the marquee")

        XCTAssertTrue(canvas.cancelCropSelection())
        XCTAssertFalse(canvas.state.hasCropSelection)
        XCTAssertFalse(canvas.hasPendingEdits)
    }

    func test_invalidMarquee_cannotBeApplied() {
        let canvas = makeCanvas()
        canvas.cropSelection = CGRect(x: 10, y: 10, width: 1, height: 1)
        XCTAssertFalse(canvas.state.canApplyCrop)
        XCTAssertEqual(canvas.applyCropSelection(), .invalidSelection)
        XCTAssertEqual(canvas.workingImage.flatMap(fixtures.cgImage)?.width, 100)
    }

    func test_revertAfterAppliedCrop_restoresOriginalPixels() throws {
        let canvas = makeCanvas()
        _ = try XCTUnwrap(applyCrop(canvas, CGRect(x: 0, y: 0, width: 20, height: 20)))
        XCTAssertTrue(canvas.hasPendingEdits)
        XCTAssertTrue(canvas.clearEdits())
        let restored = try XCTUnwrap(canvas.workingImage.flatMap(fixtures.cgImage))
        XCTAssertEqual(restored.width, 100)
        XCTAssertEqual(restored.height, 60)
        XCTAssertFalse(canvas.hasPendingEdits)
        XCTAssertFalse(canvas.clearEdits())
    }

    func test_successfulSave_promotesSavedImageToBaseline() throws {
        let canvas = makeCanvas()
        _ = try XCTUnwrap(applyCrop(canvas, CGRect(x: 0, y: 0, width: 40, height: 30)))
        let url = tempRoot.appendingPathComponent("baseline.png")
        guard case .success = canvas.saveCompositedImage(to: url) else { return XCTFail("save failed") }
        canvas.commit(.stroke(RasterStroke(points: [CGPoint(x: 1, y: 1), CGPoint(x: 10, y: 10)])))
        XCTAssertTrue(canvas.clearEdits())
        XCTAssertEqual(canvas.workingImage.flatMap(fixtures.cgImage)?.width, 40, "revert returns to the saved crop, not the original")
    }

    func test_returnAndEscape_forwardCropCommands() {
        let canvas = makeCanvas()
        var commands: [RasterImageCanvasCommand] = []
        canvas.onCommand = { commands.append($0) }
        canvas.cropSelection = CGRect(x: 0, y: 0, width: 10, height: 10)
        canvas.cancelOperation(nil)
        let returnEvent = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        )
        canvas.keyDown(with: returnEvent!)
        XCTAssertEqual(commands, [.cancelCrop, .applyCrop])
    }

    func test_stateObserver_reportsSelectionChanges() {
        let canvas = makeCanvas()
        var states: [RasterImageCanvasState] = []
        canvas.setStateObserver { states.append($0) }
        canvas.cropSelection = CGRect(x: 0, y: 0, width: 10, height: 10)
        canvas.publishStateIfNeeded()
        XCTAssertEqual(states.last?.hasCropSelection, true)
        XCTAssertEqual(states.last?.canApplyCrop, true)
        XCTAssertEqual(states.last?.cropPixelSize, CGSize(width: 10, height: 10))
        XCTAssertEqual(states.last?.imagePixelSize, CGSize(width: 100, height: 60))
    }

    func test_undoRedo_roundTripsCropAndStroke() throws {
        let canvas = makeCanvas()
        canvas.commit(.stroke(RasterStroke(points: [CGPoint(x: 1, y: 1), CGPoint(x: 90, y: 50)])))
        _ = try XCTUnwrap(applyCrop(canvas, CGRect(x: 0, y: 0, width: 50, height: 30)))
        let session = try XCTUnwrap(canvas.session)
        XCTAssertEqual(session.canvasSize, CGSize(width: 50, height: 30))
        XCTAssertTrue(canvas.state.canUndo)

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.canvasSize, CGSize(width: 100, height: 60))
        XCTAssertEqual(canvas.frame.size, CGSize(width: 100, height: 60), "canvas follows the document size")
        XCTAssertTrue(session.undo())
        XCTAssertFalse(canvas.hasPendingEdits, "undoing every edit returns to a clean document")
        XCTAssertTrue(session.redo())
        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.canvasSize, CGSize(width: 50, height: 30))
        XCTAssertFalse(session.canRedo)
    }

    func test_revertIsUndoable() throws {
        let canvas = makeCanvas()
        _ = try XCTUnwrap(applyCrop(canvas, CGRect(x: 0, y: 0, width: 20, height: 20)))
        XCTAssertTrue(canvas.clearEdits())
        let session = try XCTUnwrap(canvas.session)
        XCTAssertEqual(session.canvasSize, CGSize(width: 100, height: 60))
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.canvasSize, CGSize(width: 20, height: 20))
    }

    func test_interactionLock_blocksCommits() {
        let canvas = makeCanvas()
        canvas.isInteractionLocked = true
        canvas.commit(.stroke(RasterStroke(points: [CGPoint(x: 1, y: 1), CGPoint(x: 9, y: 9)])))
        XCTAssertFalse(canvas.hasPendingEdits)
    }

    func test_undoMenuValidation_followsHistory() {
        let canvas = makeCanvas()
        let undoItem = NSMenuItem(title: "Undo", action: #selector(EditableRasterImageCanvasView.undo(_:)), keyEquivalent: "z")
        XCTAssertFalse(canvas.validateMenuItem(undoItem))
        canvas.commit(.stroke(RasterStroke(points: [CGPoint(x: 1, y: 1), CGPoint(x: 9, y: 9)])))
        XCTAssertTrue(canvas.validateMenuItem(undoItem))
        var commands: [RasterImageCanvasCommand] = []
        canvas.onCommand = { commands.append($0) }
        canvas.undo(nil)
        XCTAssertEqual(commands, [.undo])
    }

    func test_textAnnotationExport_landsWhereItWasPlaced() throws {
        let canvas = makeCanvas()
        canvas.commit(.annotation(RasterTextAnnotation(text: "Hi", location: CGPoint(x: 0, y: 0), fontSize: 12)))
        let composited = try XCTUnwrap(canvas.compositedImage().flatMap(fixtures.cgImage))
        let bubble = fixtures.pixel(composited, x: 8, y: 9)
        XCTAssertGreaterThan(Int(bubble.g), 100, "orange bubble expected near the top-left, got \(bubble)")
        XCTAssertTrue(fixtures.matches(fixtures.pixel(composited, x: 8, y: 55), fixtures.quadrantColors[2], tolerance: 2),
                      "bottom-left stays blue: annotation must not be mirrored to the bottom")
    }

    func test_proxyCropOnOddDimensions_matchesFullResolutionCoverage() throws {
        let renderer = RasterImageRenderer()
        let canvasSize = CGSize(width: 1001, height: 333)
        let crop = ImageEditOperation.crop(CGRect(x: 501, y: 0, width: 500, height: 333))
        let full = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: 1001, height: 333), baseCanvasSize: canvasSize, operations: [crop]))
        let proxy = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: 301, height: 100), baseCanvasSize: canvasSize, operations: [crop]))
        XCTAssertEqual(full.width, 500)
        XCTAssertEqual(full.height, 333)
        XCTAssertEqual(proxy.height, 100, "proxy height uses its own axis scale")
        XCTAssertEqual(Double(proxy.width) / 301.0, 500.0 / 1001.0, accuracy: 0.01)
    }

    // MARK: - Phase 2: crop box, geometry

    func test_enteringCropMode_showsFullImageBox_thatIsNotPending() {
        let canvas = makeCanvas()
        canvas.editingMode = .crop
        XCTAssertEqual(canvas.cropSelection, CGRect(x: 0, y: 0, width: 100, height: 60))
        XCTAssertFalse(canvas.state.hasCropSelection, "an untouched full-image box does not block Save")
        XCTAssertFalse(canvas.state.canApplyCrop)
        canvas.editingMode = .markup
        XCTAssertNil(canvas.cropSelection, "the untouched box disappears outside Crop mode")
    }

    func test_aspectRatio_constrainsCropBox() throws {
        let canvas = makeCanvas()
        canvas.cropAspectRatio = 1
        canvas.editingMode = .crop
        let box = try XCTUnwrap(canvas.cropSelection)
        XCTAssertEqual(box.width, box.height, accuracy: 0.001)
        XCTAssertEqual(box.height, 60, accuracy: 0.001)
        XCTAssertEqual(box.midX, 50, accuracy: 0.001)
        XCTAssertTrue(canvas.state.hasCropSelection)
    }

    func test_cancelInCropMode_resetsToFullBox() {
        let canvas = makeCanvas()
        canvas.editingMode = .crop
        canvas.cropSelection = CGRect(x: 10, y: 10, width: 20, height: 20)
        XCTAssertTrue(canvas.cancelCropSelection())
        XCTAssertEqual(canvas.cropSelection, CGRect(x: 0, y: 0, width: 100, height: 60))
        XCTAssertFalse(canvas.cancelCropSelection(), "nothing pending to cancel")
    }

    func test_applyingFullImageBox_isRejected() {
        let canvas = makeCanvas()
        canvas.editingMode = .crop
        XCTAssertEqual(canvas.applyCropSelection(), .invalidSelection)
        XCTAssertFalse(canvas.hasPendingEdits)
    }

    func test_arrowKeys_nudgeCropBox() throws {
        let canvas = makeCanvas()
        canvas.editingMode = .crop
        canvas.cropSelection = CGRect(x: 10, y: 10, width: 20, height: 20)
        let right = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: String(UnicodeScalar(NSRightArrowFunctionKey)!), charactersIgnoringModifiers: String(UnicodeScalar(NSRightArrowFunctionKey)!),
            isARepeat: false, keyCode: 124
        ))
        canvas.keyDown(with: right)
        XCTAssertEqual(canvas.cropSelection?.minX, 11)
        let shiftDown = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0, context: nil,
            characters: String(UnicodeScalar(NSDownArrowFunctionKey)!), charactersIgnoringModifiers: String(UnicodeScalar(NSDownArrowFunctionKey)!),
            isARepeat: false, keyCode: 125
        ))
        canvas.keyDown(with: shiftDown)
        XCTAssertEqual(canvas.cropSelection?.minY, 20)
    }

    func test_geometricEdit_clearsPendingMarquee() {
        let canvas = makeCanvas()
        canvas.cropSelection = CGRect(x: 10, y: 10, width: 20, height: 20)
        XCTAssertTrue(canvas.session?.commit(.flip(horizontal: true)) ?? false)
        XCTAssertNil(canvas.cropSelection, "a marquee from the old geometry must not survive a flip")
    }

    func test_rotateClockwise_movesTopLeftToTopRight() throws {
        let canvas = makeCanvas()
        XCTAssertTrue(canvas.session?.commit(.rotate(quarterTurns: 1)) ?? false)
        let image = try XCTUnwrap(canvas.compositedImage().flatMap(fixtures.cgImage))
        XCTAssertEqual(image.width, 60)
        XCTAssertEqual(image.height, 100)
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 45, y: 25), fixtures.quadrantColors[0], tolerance: 2), "red moves to top-right")
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 15, y: 25), fixtures.quadrantColors[2], tolerance: 2), "blue moves to top-left")
    }

    func test_spaceKey_enablesTemporaryPan() throws {
        let canvas = makeCanvas()
        canvas.editingMode = .markup
        let down = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                  context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        let up = try XCTUnwrap(NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        canvas.keyDown(with: down)
        XCTAssertTrue(canvas.isSpacePanning)
        canvas.keyUp(with: up)
        XCTAssertFalse(canvas.isSpacePanning)
    }

    func test_modifiedSpaceAndArrows_areNotConsumed() throws {
        let canvas = makeCanvas()
        canvas.editingMode = .crop
        canvas.cropSelection = CGRect(x: 10, y: 10, width: 20, height: 20)
        for modifier: NSEvent.ModifierFlags in [.command, .option, .control] {
            let modifiedSpace = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifier, timestamp: 0, windowNumber: 0,
                context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
            ))
            canvas.keyDown(with: modifiedSpace)
            XCTAssertFalse(canvas.isSpacePanning, "modified Space must remain available to system/app shortcuts")
        }
        let arrow = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        let optionRight = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option], timestamp: 0, windowNumber: 0,
                                                         context: nil, characters: arrow, charactersIgnoringModifiers: arrow, isARepeat: false, keyCode: 124))
        canvas.keyDown(with: optionRight)
        XCTAssertEqual(canvas.cropSelection?.minX, 10)
    }

    // MARK: - Phase 3: markup interaction

    private func drag(_ canvas: EditableRasterImageCanvasView, from start: CGPoint, to end: CGPoint) {
        canvas.beginMarkupDrag(at: start, clickCount: 1)
        canvas.continueMarkupDrag(to: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), constrained: false)
        canvas.continueMarkupDrag(to: end, constrained: false)
        canvas.endMarkupDrag()
    }

    func test_rectangleTool_createsSelectsAndMovesItem() throws {
        let canvas = makeCanvas()
        canvas.editingMode = .markup
        canvas.markupTool = .rectangle
        drag(canvas, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 30))
        let created = try XCTUnwrap(canvas.state.selectedMarkup)
        XCTAssertEqual(created.rect, CGRect(x: 10, y: 10, width: 30, height: 20))
        XCTAssertEqual(canvas.state.markupCount, 1)

        canvas.markupTool = .select
        drag(canvas, from: CGPoint(x: 25, y: 20), to: CGPoint(x: 35, y: 25))
        XCTAssertEqual(canvas.state.selectedMarkup?.rect, CGRect(x: 20, y: 15, width: 30, height: 20), "dragging inside moves the item")
        XCTAssertTrue(canvas.session?.undo() ?? false)
        XCTAssertEqual(canvas.session?.markupItem(id: created.id)?.rect, CGRect(x: 10, y: 10, width: 30, height: 20))
    }

    func test_selectTool_resizesWithHandle_andClickOnEmptyDeselects() throws {
        let canvas = makeCanvas()
        canvas.editingMode = .markup
        canvas.markupTool = .ellipse
        drag(canvas, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 30))
        canvas.markupTool = .select
        drag(canvas, from: CGPoint(x: 40, y: 30), to: CGPoint(x: 60, y: 50))
        XCTAssertEqual(canvas.state.selectedMarkup?.rect, CGRect(x: 10, y: 10, width: 50, height: 40))
        canvas.beginMarkupDrag(at: CGPoint(x: 90, y: 55), clickCount: 1)
        canvas.endMarkupDrag()
        XCTAssertNil(canvas.state.selectedMarkup)
    }

    func test_tinyDrag_doesNotCreateItem() {
        let canvas = makeCanvas()
        canvas.editingMode = .markup
        canvas.markupTool = .arrow
        drag(canvas, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10.5, y: 10.5))
        XCTAssertEqual(canvas.state.markupCount, 0)
        XCTAssertFalse(canvas.hasPendingEdits)
    }

    func test_textTool_placesTemplateText() throws {
        let canvas = makeCanvas()
        canvas.editingMode = .markup
        canvas.markupTool = .text
        canvas.annotationTextTemplate = "Hello"
        canvas.beginMarkupDrag(at: CGPoint(x: 12, y: 8), clickCount: 1)
        canvas.endMarkupDrag()
        XCTAssertEqual(canvas.state.selectedMarkup?.kind, .text("Hello", origin: CGPoint(x: 12, y: 8)))
    }

    func test_keyboard_deleteNudgeTabEscape() throws {
        let canvas = makeCanvas()
        canvas.editingMode = .markup
        canvas.markupTool = .rectangle
        drag(canvas, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 20))
        drag(canvas, from: CGPoint(x: 50, y: 30), to: CGPoint(x: 70, y: 50))
        var commands: [RasterImageCanvasCommand] = []
        canvas.onCommand = { commands.append($0) }
        func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        }
        let second = try XCTUnwrap(canvas.state.selectedMarkup)
        let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        canvas.keyDown(with: key(124, right))
        canvas.keyDown(with: key(124, right))
        XCTAssertEqual(canvas.state.selectedMarkup?.rect?.minX, 52)
        XCTAssertTrue(canvas.session?.undo() ?? false)
        XCTAssertEqual(canvas.session?.markupItem(id: second.id)?.rect?.minX, 50, "nudges coalesce into one undo step")

        canvas.keyDown(with: key(48, "\t"))
        XCTAssertNotEqual(canvas.state.selectedMarkup?.id, second.id, "Tab cycles selection")
        canvas.keyDown(with: key(51, "\u{7f}"))
        XCTAssertEqual(commands, [.deleteSelection])
        XCTAssertTrue(canvas.deleteSelectedMarkup())
        XCTAssertEqual(canvas.state.markupCount, 1)
        canvas.cycleMarkupSelection(backwards: false)
        canvas.cancelOperation(nil)
        XCTAssertNil(canvas.state.selectedMarkup, "Escape deselects")
    }

    func test_pixelEffect_usesAsyncComposite() throws {
        let canvas = makeCanvas()
        canvas.editingMode = .markup
        canvas.markupTool = .pixelate
        drag(canvas, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 30))
        XCTAssertTrue(canvas.needsLiveComposite)
        let deadline = Date().addingTimeInterval(3)
        while canvas.liveComposite == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertNotNil(canvas.liveComposite, "composite renders off-main and is delivered")
        XCTAssertEqual(canvas.liveComposite?.key.revision, canvas.session?.revision)
    }

    func test_accessibility_exposesMarkupItems() {
        let canvas = makeCanvas()
        canvas.editingMode = .markup
        canvas.markupTool = .text
        canvas.annotationTextTemplate = "Label"
        canvas.beginMarkupDrag(at: CGPoint(x: 5, y: 5), clickCount: 1)
        canvas.endMarkupDrag()
        let children = canvas.accessibilityChildren() as? [NSAccessibilityElement]
        XCTAssertEqual(children?.count, 1)
        XCTAssertEqual(children?.first?.accessibilityLabel(), AppStrings.ImageEditor.accessibilityTextItem("Label"))
        XCTAssertEqual(children?.first?.isAccessibilitySelected(), true)
        XCTAssertTrue((canvas.accessibilityValue() as? String)?.contains("100 × 60") ?? false)
    }

    func test_accessibility_itemsArePressable_andCustomActionsOperate() throws {
        let canvas = makeCanvas()
        canvas.editingMode = .markup
        canvas.markupTool = .rectangle
        drag(canvas, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))
        canvas.selectMarkup(nil)
        let element = try XCTUnwrap((canvas.accessibilityChildren() as? [NSAccessibilityElement])?.first)
        XCTAssertTrue(element.accessibilityPerformPress())
        XCTAssertNotNil(canvas.state.selectedMarkup, "pressing selects the item")

        let moveRight = try XCTUnwrap(canvas.accessibilityCustomActions()?.first { $0.name == AppStrings.ImageEditor.accessibilityMoveRight })
        XCTAssertTrue(moveRight.handler?() ?? false)
        XCTAssertEqual(canvas.state.selectedMarkup?.rect?.minX, 20)

        canvas.editingMode = .crop
        let shrink = try XCTUnwrap(canvas.accessibilityCustomActions()?.first { $0.name == AppStrings.ImageEditor.accessibilityShrinkCrop })
        XCTAssertTrue(shrink.handler?() ?? false)
        XCTAssertTrue(canvas.state.hasCropSelection, "VoiceOver can create a pending crop")
        XCTAssertTrue(canvas.accessibilityCustomActions()?.contains { $0.name == AppStrings.ImageEditor.applyCrop } ?? false)
    }

    func test_liveComposite_isNotUsedWhileDraggingAnItem() throws {
        let canvas = makeCanvas()
        canvas.editingMode = .markup
        canvas.markupTool = .pixelate
        drag(canvas, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 30))
        let deadline = Date().addingTimeInterval(3)
        while canvas.liveComposite == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertNotNil(canvas.liveComposite)
        canvas.markupTool = .select
        canvas.beginMarkupDrag(at: CGPoint(x: 20, y: 15), clickCount: 1)
        canvas.continueMarkupDrag(to: CGPoint(x: 30, y: 20), constrained: false)
        XCTAssertNotNil(canvas.markupPreview, "drag preview is drawn instead of the baked composite")
        canvas.endMarkupDrag()
    }
}
