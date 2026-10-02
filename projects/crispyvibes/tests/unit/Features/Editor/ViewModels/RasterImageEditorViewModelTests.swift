import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CrispyVibes

@MainActor
private final class FakeRasterCanvas: RasterImageCanvasControlling {
    var isInteractionLocked = false
    var cropSelection: CGRect?
    var session: RasterImageEditSession?

    init(session: RasterImageEditSession) {
        self.session = session
    }

    var state: RasterImageCanvasState {
        RasterImageCanvasState(
            hasPendingEdits: session?.isDirty ?? false,
            hasCropSelection: cropSelection != nil,
            canApplyCrop: cropSelection.flatMap { session?.snappedCropRect(forSelection: $0) } != nil,
            canUndo: session?.canUndo ?? false,
            canRedo: session?.canRedo ?? false,
            cropPixelSize: nil,
            imagePixelSize: session.map { CGSize(width: $0.exportTransform.pixelSize.width, height: $0.exportTransform.pixelSize.height) },
            selectedMarkup: selectedMarkupID.flatMap { session?.markupItem(id: $0) },
            markupCount: session?.markupEntries.count ?? 0
        )
    }

    func applyCropSelection() -> RasterImageCropResult {
        guard let session else { return .decodeFailure }
        let result = session.applyCrop(selection: cropSelection)
        if result.didApply { cropSelection = nil }
        return result
    }

    func cancelCropSelection() -> Bool {
        defer { cropSelection = nil }
        return cropSelection != nil
    }

    func clearEdits() -> Bool {
        let hadSelection = cancelCropSelection()
        return (session?.revert() ?? false) || hadSelection
    }

    var selectedMarkupID: UUID?

    func updateSelectedMarkup(coalescingKey: String?, _ change: (RasterMarkupItem) -> RasterMarkupItem) -> Bool {
        guard let selectedMarkupID, let item = session?.markupItem(id: selectedMarkupID) else { return false }
        return session?.updateMarkup(id: selectedMarkupID, to: change(item), coalescingKey: coalescingKey) ?? false
    }

    func deleteSelectedMarkup() -> Bool {
        guard let selectedMarkupID, session?.deleteMarkup(id: selectedMarkupID) == true else { return false }
        self.selectedMarkupID = nil
        return true
    }
}

@MainActor
private final class FakeFileSession: RasterImageFileSessionControlling {
    var reloadCount = 0
    var markCurrentCount = 0
    var resetScrollCount = 0
    var externallyChanged = false
    func reloadFromDisk() { reloadCount += 1 }
    func markFileStateCurrent() { markCurrentCount += 1; externallyChanged = false }
    func hasExternalChangeSinceLoad() -> Bool { externallyChanged }
    func resetScrollPosition() { resetScrollCount += 1 }
}

/// Exporter that records jobs and lets the test decide when (and how) they finish.
private final class ControlledExporter: RasterImageExporting, @unchecked Sendable {
    var jobs: [RasterImageExportJob] = []
    var completions: [@MainActor (Result<RasterImageExportResult, Error>) -> Void] = []
    var handles: [RasterImageWorkHandle] = []

    func export(
        _ job: RasterImageExportJob,
        completion: @escaping @MainActor (Result<RasterImageExportResult, Error>) -> Void
    ) -> RasterImageWorkHandle {
        jobs.append(job)
        completions.append(completion)
        let handle = RasterImageWorkHandle()
        handles.append(handle)
        return handle
    }

    /// Runs the real pipeline synchronously for job `index` and delivers the result.
    @MainActor
    func finish(_ index: Int = 0) {
        let result = RasterImageExportService.run(
            jobs[index], handle: nil, decoder: RasterImageDecoder(), renderer: RasterImageRenderer(), encoder: RasterImageEncoder()
        )
        completions[index](result)
    }
}

private final class StubDestinationPicker: RasterImageExportDestinationPicking {
    var destination: URL?
    var requests: [(name: String, type: String)] = []
    func pickDestination(suggestedName: String, contentType: UTType, completion: @escaping (URL?) -> Void) {
        requests.append((suggestedName, contentType.identifier))
        completion(destination)
    }
}

private final class RecordingAnnouncer: RasterImageAccessibilityAnnouncing {
    var messages: [String] = []
    func announce(_ message: String) { messages.append(message) }
}

private struct StubColorSampler: RasterImageColorSampling {
    let color: RasterColor?
    func sampleColor(completion: @escaping (RasterColor?) -> Void) { completion(color) }
}

private struct RecordingPasteboard: RasterImagePasteboardWriting {
    let box: Box
    final class Box { var images: [CGImage] = []; var texts: [String] = [] }
    func write(_ image: CGImage, size: CGSize) -> Bool {
        box.images.append(image)
        return true
    }
    func writeText(_ text: String) -> Bool {
        box.texts.append(text)
        return true
    }
}

/// Analyzer whose results the test supplies; records the images it was given.
private final class StubAnalyzer: RasterImageAnalyzing, @unchecked Sendable {
    var textResult: Result<[RecognizedTextLine], Error> = .success([])
    var maskResult: Result<RasterImageMask, Error> = .failure(RasterImageAnalysisError.noSubjectFound)
    var analyzedWidths: [Int] = []
    var pendingText: (@MainActor (Result<[RecognizedTextLine], Error>) -> Void)?
    var textHandle: RasterImageWorkHandle?

    func recognizeText(in image: CGImage, completion: @escaping @MainActor (Result<[RecognizedTextLine], Error>) -> Void) -> RasterImageWorkHandle {
        analyzedWidths.append(image.width)
        pendingText = completion
        let handle = RasterImageWorkHandle()
        textHandle = handle
        return handle
    }

    func foregroundMask(for image: CGImage, completion: @escaping @MainActor (Result<RasterImageMask, Error>) -> Void) -> RasterImageWorkHandle {
        analyzedWidths.append(image.width)
        MainActor.assumeIsolated { completion(maskResult) }
        return RasterImageWorkHandle()
    }

    /// Delivers like the real service: never after cancellation.
    @MainActor func deliverText() {
        guard textHandle?.isCancelled != true else { return }
        pendingText?(textResult)
    }
}

/// F009: save gating, async export, undo/redo, and conflict handling in the editor view model.
@MainActor
final class RasterImageEditorViewModelTests: XCTestCase {
    private var viewModel: RasterImageEditorViewModel!
    private var canvas: FakeRasterCanvas!
    private var session: FakeFileSession!
    private var exporter: ControlledExporter!
    private var pasteboard: RecordingPasteboard.Box!
    private var picker: StubDestinationPicker!
    private var announcer: RecordingAnnouncer!
    private var analyzer: StubAnalyzer!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("RasterVMTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        exporter = ControlledExporter()
        pasteboard = RecordingPasteboard.Box()
        picker = StubDestinationPicker()
        announcer = RecordingAnnouncer()
        var services = RasterImageEditorServices(
            decoder: RasterImageDecoder(),
            renderer: RasterImageRenderer(),
            exporter: exporter,
            pasteboard: RecordingPasteboard(box: pasteboard),
            destinationPicker: picker
        )
        services.announcer = announcer
        analyzer = StubAnalyzer()
        services.analyzer = analyzer
        services.colorSampler = StubColorSampler(color: RasterColor(red: 0, green: 0, blue: 1))
        viewModel = RasterImageEditorViewModel(services: services)
        canvas = FakeRasterCanvas(session: .inMemory(RasterImageTestFixtures.quadrantImage(width: 100, height: 60), canvasSize: CGSize(width: 100, height: 60)))
        session = FakeFileSession()
        viewModel.attach(canvas: canvas, fileSession: session)
        viewModel.fileURL = tempRoot.appendingPathComponent("image.png")
        viewModel.didLoadImage(rendered: true, saveBlockReason: nil, isNewFile: true)
    }

    override func tearDownWithError() throws {
        viewModel.shutdown()
        viewModel = nil
        canvas = nil
        session = nil
        exporter = nil
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    private func addStroke() {
        canvas.session?.commit(.stroke(RasterStroke(points: [CGPoint(x: 1, y: 1), CGPoint(x: 50, y: 30)])))
        viewModel.canvasStateDidChange(canvas.state)
    }

    private func waitUntilIdle(_ condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition())
    }

    private func drainMain() {
        let done = expectation(description: "main drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    func test_defaultMode_isPan() {
        XCTAssertEqual(viewModel.editingMode, .pan)
    }

    func test_save_isBlockedWhileCropSelectionPending() {
        addStroke()
        canvas.cropSelection = CGRect(x: 0, y: 0, width: 10, height: 10)
        viewModel.canvasStateDidChange(canvas.state)
        XCTAssertFalse(viewModel.canSave)
        viewModel.save()
        XCTAssertTrue(exporter.jobs.isEmpty)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusPendingCropBeforeSave)
    }

    func test_save_usesLiveCanvasStateEvenIfPublishedStateIsStale() {
        addStroke()
        canvas.cropSelection = CGRect(x: 0, y: 0, width: 10, height: 10)
        viewModel.save()
        XCTAssertTrue(exporter.jobs.isEmpty, "a marquee missing from the published state must still block save")
    }

    func test_save_isBlockedBySavePolicy() {
        viewModel.didLoadImage(rendered: true, saveBlockReason: .multipleFrames(count: 3), isNewFile: false)
        addStroke()
        XCTAssertFalse(viewModel.canSave)
        viewModel.save()
        XCTAssertTrue(exporter.jobs.isEmpty)
        XCTAssertEqual(viewModel.statusLine, RasterImageSaveBlockReason.multipleFrames(count: 3).message)
        XCTAssertTrue(viewModel.canCopy)
    }

    func test_save_isBlockedByExternalChange_untilKeepMine() {
        addStroke()
        session.externallyChanged = true
        viewModel.save()
        XCTAssertTrue(exporter.jobs.isEmpty)
        XCTAssertTrue(viewModel.hasExternalChangeConflict)
        viewModel.keepMyEdits()
        viewModel.save()
        XCTAssertEqual(exporter.jobs.count, 1)
    }

    func test_applyCrop_requiresValidSelection_andIsUndoable() {
        canvas.cropSelection = CGRect(x: 0, y: 0, width: 1, height: 1)
        viewModel.canvasStateDidChange(canvas.state)
        XCTAssertFalse(viewModel.canApplyCrop)
        XCTAssertTrue(viewModel.canCancelCrop)

        canvas.cropSelection = CGRect(x: 0, y: 0, width: 40, height: 30)
        viewModel.canvasStateDidChange(canvas.state)
        XCTAssertTrue(viewModel.canApplyCrop)
        viewModel.applyCrop()
        XCTAssertEqual(session.resetScrollCount, 1)
        XCTAssertTrue(viewModel.canSave)
        XCTAssertTrue(viewModel.canUndo)

        viewModel.undo()
        XCTAssertEqual(canvas.session?.canvasSize, CGSize(width: 100, height: 60))
        XCTAssertFalse(viewModel.canSave)
        XCTAssertTrue(viewModel.canRedo)
        viewModel.redo()
        XCTAssertEqual(canvas.session?.canvasSize, CGSize(width: 40, height: 30))
    }

    func test_canvasCommands_routeToActions() {
        canvas.cropSelection = CGRect(x: 0, y: 0, width: 10, height: 10)
        viewModel.handleCanvasCommand(.cancelCrop)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusCropCancelled)
        canvas.cropSelection = CGRect(x: 0, y: 0, width: 10, height: 10)
        viewModel.handleCanvasCommand(.applyCrop)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusCropApplied)
        viewModel.handleCanvasCommand(.undo)
        XCTAssertEqual(canvas.session?.canvasSize, CGSize(width: 100, height: 60))
        viewModel.handleCanvasCommand(.redo)
        XCTAssertEqual(canvas.session?.canvasSize, CGSize(width: 10, height: 10))
    }

    func test_save_rendersOffMain_locksUntilWritten_thenRebases() throws {
        canvas.cropSelection = CGRect(x: 50, y: 0, width: 50, height: 30)
        viewModel.applyCrop()
        var written: Data?
        viewModel.saveDataHandler = { _, data, completion in
            written = data
            completion(.success(()))
        }
        viewModel.save()
        XCTAssertTrue(viewModel.isSaving)
        XCTAssertTrue(canvas.isInteractionLocked)
        XCTAssertFalse(viewModel.canSave)
        XCTAssertFalse(viewModel.canUndo)
        viewModel.save()
        XCTAssertEqual(exporter.jobs.count, 1, "repeat save while saving is ignored")

        exporter.finish()
        drainMain()

        XCTAssertFalse(viewModel.isSaving)
        XCTAssertFalse(canvas.isInteractionLocked)
        XCTAssertEqual(session.markCurrentCount, 1)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusSaved)
        XCTAssertFalse(canvas.session?.isDirty ?? true)
        XCTAssertFalse(viewModel.canUndo, "history starts fresh after save")

        let data = try XCTUnwrap(written)
        let image = try XCTUnwrap(NSBitmapImageRep(data: data)?.cgImage)
        XCTAssertEqual(image.width, 50)
        XCTAssertEqual(image.height, 30)
        XCTAssertTrue(RasterImageTestFixtures.matches(RasterImageTestFixtures.pixel(image, x: 25, y: 15), RasterImageTestFixtures.quadrantColors[1], tolerance: 2))
    }

    func test_staleRender_isDiscarded() {
        addStroke()
        viewModel.save()
        // Simulate the document changing underneath the render (e.g. external reload).
        canvas.isInteractionLocked = false
        canvas.session?.commit(.stroke(RasterStroke(points: [CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 3)])))
        var handlerCalled = false
        viewModel.saveDataHandler = { _, _, completion in
            handlerCalled = true
            completion(.success(()))
        }
        exporter.finish()
        XCTAssertFalse(handlerCalled)
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertTrue(canvas.session?.isDirty ?? false)
    }

    func test_failedWrite_preservesEditsForRetry() {
        addStroke()
        viewModel.saveDataHandler = { _, _, completion in
            completion(.failure(CocoaError(.fileWriteNoPermission)))
        }
        viewModel.save()
        exporter.finish()
        drainMain()

        XCTAssertFalse(viewModel.isSaving)
        XCTAssertTrue(canvas.session?.isDirty ?? false)
        XCTAssertTrue(viewModel.canSave)
        XCTAssertTrue(viewModel.canUndo, "history survives a failed save")
    }

    func test_shutdown_cancelsInFlightWork_andLeavesEditorUsable() {
        addStroke()
        viewModel.save()
        viewModel.copy()
        viewModel.shutdown()
        XCTAssertTrue(exporter.handles.allSatisfy(\.isCancelled))
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertFalse(viewModel.isCopying)
        XCTAssertFalse(canvas.isInteractionLocked)

        // Late completions from the torn-down generation are ignored.
        var handlerCalled = false
        viewModel.saveDataHandler = { _, _, completion in handlerCalled = true; completion(.success(())) }
        exporter.finish(0)
        exporter.finish(1)
        XCTAssertFalse(handlerCalled)
        XCTAssertTrue(pasteboard.images.isEmpty)
        XCTAssertTrue(canvas.session?.isDirty ?? false)

        // The reappearing editor can save again.
        viewModel.save()
        XCTAssertEqual(exporter.jobs.count, 3)
        XCTAssertTrue(viewModel.isSaving)
    }

    func test_externalChangeDuringRender_blocksWrite() {
        addStroke()
        var handlerCalled = false
        viewModel.saveDataHandler = { _, _, completion in handlerCalled = true; completion(.success(())) }
        viewModel.save()
        session.externallyChanged = true
        exporter.finish()
        XCTAssertFalse(handlerCalled, "a file replaced while rendering must not be overwritten")
        XCTAssertTrue(viewModel.hasExternalChangeConflict)
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertFalse(canvas.isInteractionLocked)
        XCTAssertTrue(canvas.session?.isDirty ?? false)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusSaveConflict)
    }

    func test_copy_rendersFullResolutionToPasteboard() {
        addStroke()
        viewModel.copy()
        XCTAssertFalse(viewModel.canCopy)
        XCTAssertNil(exporter.jobs.first?.destinationURL)
        exporter.finish()
        XCTAssertEqual(pasteboard.images.first?.width, 100)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusCopied)
        XCTAssertTrue(viewModel.canCopy)
    }

    func test_revert_reportsOutcome() {
        addStroke()
        viewModel.revert()
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusReverted)
        viewModel.revert()
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusNothingToRevert)
    }

    func test_externalChangeConflict_offersReloadOrKeep() {
        viewModel.didDetectExternalChangeWithPendingEdits()
        XCTAssertTrue(viewModel.hasExternalChangeConflict)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusExternalChange)

        viewModel.keepMyEdits()
        XCTAssertFalse(viewModel.hasExternalChangeConflict)
        XCTAssertEqual(session.markCurrentCount, 1)

        viewModel.didDetectExternalChangeWithPendingEdits()
        viewModel.reloadFromDisk()
        XCTAssertFalse(viewModel.hasExternalChangeConflict)
        XCTAssertEqual(session.reloadCount, 1)
    }

    func test_saveActiveDocument_routesImagesToRasterEditor_exactlyOnce() {
        let container = AppContainer.makeDefault()
        let markdown = container.makeMarkdownViewModel(bufferStore: DocumentBufferStore())
        markdown.documentType = .image
        XCTAssertFalse(markdown.isImageSaveRequestPending)
        let before = markdown.imageSaveRequestToken
        markdown.saveActiveDocument()
        XCTAssertEqual(markdown.imageSaveRequestToken, before + 1)
        XCTAssertTrue(markdown.isImageSaveRequestPending, "request survives until an editor consumes it")
        markdown.acknowledgeImageSaveRequest()
        XCTAssertFalse(markdown.isImageSaveRequestPending, "a remounted editor must not replay it")
    }

    // MARK: - Phase 2: geometry, export as, viewport

    func test_rotateFlipStraightenResize_areUndoableGeometricEdits() throws {
        viewModel.rotate(clockwise: true)
        XCTAssertEqual(canvas.session?.canvasSize, CGSize(width: 60, height: 100))
        XCTAssertTrue(viewModel.canSave)
        viewModel.flip(horizontal: true)
        viewModel.previewStraighten(degrees: 10)
        XCTAssertEqual(viewModel.straightenDegrees, 10)
        viewModel.commitStraighten()
        XCTAssertEqual(viewModel.straightenDegrees, 0, "slider resets after commit")
        let straightened = try XCTUnwrap(canvas.session?.canvasSize)
        XCTAssertLessThan(straightened.width, 60)

        viewModel.resize(toPixelWidth: 30, height: 50)
        XCTAssertEqual(canvas.session?.canvasSize, CGSize(width: 30, height: 50))
        XCTAssertFalse(viewModel.isResizeSheetPresented)

        for _ in 0..<4 { viewModel.undo() }
        XCTAssertEqual(canvas.session?.canvasSize, CGSize(width: 100, height: 60))
        XCTAssertFalse(viewModel.canSave)
    }

    func test_straightenAtZero_isNoOp() {
        viewModel.previewStraighten(degrees: 0.01)
        viewModel.commitStraighten()
        XCTAssertFalse(canvas.session?.isDirty ?? true)
        viewModel.previewStraighten(degrees: 80)
        XCTAssertEqual(viewModel.straightenDegrees, 45, "angle is clamped")
    }

    func test_resize_rejectsOversizeAndNoOp() {
        viewModel.resize(toPixelWidth: 100, height: 60)
        XCTAssertFalse(canvas.session?.isDirty ?? true)
        viewModel.resize(toPixelWidth: RasterImageEditorViewModel.maximumPixelEdge + 1, height: 10)
        XCTAssertFalse(canvas.session?.isDirty ?? true)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusResizeTooLarge(RasterImageEditorViewModel.maximumPixelEdge))
    }

    func test_geometryIsBlockedWhileSaving() {
        addStroke()
        viewModel.save()
        viewModel.rotate(clockwise: true)
        XCTAssertEqual(canvas.session?.canvasSize, CGSize(width: 100, height: 60))
    }

    func test_exportAs_writesChosenFormat_withoutTouchingDocument() throws {
        canvas.session?.commit(.crop(CGRect(x: 0, y: 0, width: 50, height: 30)))
        viewModel.canvasStateDidChange(canvas.state)
        let destination = tempRoot.appendingPathComponent("copy.jpg")
        picker.destination = destination
        viewModel.presentExport()
        XCTAssertTrue(viewModel.isExportSheetPresented)
        XCTAssertEqual(viewModel.exportOptions.format, .png, "defaults to the open file's format")
        viewModel.exportOptions = RasterImageExportOptions(format: .jpeg, quality: 0.5)
        viewModel.exportAs()
        XCTAssertFalse(viewModel.isExportSheetPresented)
        XCTAssertEqual(picker.requests.first?.name, "image-edited.jpg")
        XCTAssertEqual(exporter.jobs.first?.options, RasterImageExportOptions(format: .jpeg, quality: 0.5))
        exporter.finish()
        waitUntilIdle { !self.viewModel.isExporting }

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 50)
        XCTAssertTrue(canvas.session?.isDirty ?? false, "export does not save or rebase the document")
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusExported("copy.jpg"))
    }

    func test_exportAs_ontoOpenFile_isRefused() {
        viewModel.export(to: try! XCTUnwrap(viewModel.fileURL), options: .default)
        XCTAssertTrue(exporter.jobs.isEmpty)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusExportOverOpenFile)
    }

    func test_exportAs_cancelledPicker_doesNothing() {
        picker.destination = nil
        viewModel.exportAs()
        XCTAssertTrue(exporter.jobs.isEmpty)
    }

    func test_cropAspectSelection_entersCropMode_andComputesRatio() {
        viewModel.canvasStateDidChange(canvas.state)
        viewModel.selectCropAspectRatio(.ratio16x9)
        XCTAssertEqual(viewModel.editingMode, .crop)
        XCTAssertEqual(viewModel.cropAspectValue!, 16.0 / 9.0, accuracy: 0.0001)
        viewModel.toggleCropOrientation()
        XCTAssertEqual(viewModel.cropAspectValue!, 9.0 / 16.0, accuracy: 0.0001)
        viewModel.selectCropAspectRatio(.original)
        XCTAssertEqual(viewModel.cropAspectValue!, 60.0 / 100.0, accuracy: 0.0001, "portrait of a 100×60 original")
        viewModel.selectCropAspectRatio(.free)
        XCTAssertNil(viewModel.cropAspectValue)
    }

    func test_viewportCommands_forwardToViewport() {
        final class Viewport: RasterImageViewportControlling {
            var calls: [String] = []
            func fitToWindow() { calls.append("fit") }
            func zoomToActualSize() { calls.append("actual") }
            func zoom(by factor: CGFloat) { calls.append("zoom \(factor)") }
        }
        let viewport = Viewport()
        viewModel.attach(canvas: canvas, fileSession: session, viewport: viewport)
        viewModel.fitToWindow()
        viewModel.zoomToActualSize()
        viewModel.zoomIn()
        viewModel.zoomOut()
        XCTAssertEqual(viewport.calls, ["fit", "actual", "zoom 1.25", "zoom 0.8"])
        viewModel.viewportDidChange(zoomPercent: 250)
        XCTAssertEqual(viewModel.zoomPercent, 250)
    }

    func test_exportAs_ontoSymlinkOfOpenFile_isRefused() throws {
        let open = try XCTUnwrap(viewModel.fileURL)
        try Data([1]).write(to: open)
        let link = tempRoot.appendingPathComponent("alias.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: open)
        let hardLink = tempRoot.appendingPathComponent("hard.png")
        try FileManager.default.linkItem(at: open, to: hardLink)
        XCTAssertTrue(RasterImageEditorViewModel.isSameFile(link, open))
        XCTAssertTrue(RasterImageEditorViewModel.isSameFile(hardLink, open))
        XCTAssertFalse(RasterImageEditorViewModel.isSameFile(tempRoot.appendingPathComponent("other.png"), open))
        viewModel.export(to: link, options: .default)
        XCTAssertTrue(exporter.jobs.isEmpty)
    }

    func test_localSave_writesOffMainThenFinishes() throws {
        addStroke()
        viewModel.saveDataHandler = nil
        viewModel.save()
        exporter.finish()
        XCTAssertTrue(viewModel.isSaving, "write happens asynchronously on the I/O queue")
        waitUntilIdle { !self.viewModel.isSaving }
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(viewModel.fileURL).path))
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusSaved)
    }

    // MARK: - Phase 3: markup inspector, adjustments, announcements

    private func addSelectedText() -> RasterMarkupItem {
        let text = RasterMarkupItem(kind: .text("Hi", origin: CGPoint(x: 5, y: 5)), style: .default)
        canvas.session?.commit(.markup(text))
        canvas.selectedMarkupID = text.id
        viewModel.canvasStateDidChange(canvas.state)
        return text
    }

    func test_selectingItem_loadsInspector_andStyleEditsApplyToIt() throws {
        var style = RasterMarkupStyle.default
        style.lineWidth = 9
        let rect = RasterMarkupItem(kind: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), style: style)
        canvas.session?.commit(.markup(rect))
        canvas.selectedMarkupID = rect.id
        viewModel.canvasStateDidChange(canvas.state)
        XCTAssertEqual(viewModel.markupStyle.lineWidth, 9, "inspector mirrors the selection")

        viewModel.setStrokeColor(RasterColor(red: 0, green: 1, blue: 0))
        viewModel.setLineWidth(3)
        viewModel.setFillColor(RasterColor(red: 1, green: 1, blue: 1))
        let updated = try XCTUnwrap(canvas.session?.markupItem(id: rect.id))
        XCTAssertEqual(updated.style.strokeColor, RasterColor(red: 0, green: 1, blue: 0))
        XCTAssertEqual(updated.style.lineWidth, 3)
        XCTAssertNotNil(updated.style.fillColor)
        viewModel.undo()
        XCTAssertNil(canvas.session?.markupItem(id: rect.id)?.style.fillColor)
    }

    func test_textEditing_updatesSelectedItem_andCoalesces() {
        let text = addSelectedText()
        XCTAssertTrue(viewModel.showsTextControls)
        XCTAssertEqual(viewModel.annotationText, "Hi")
        viewModel.setText("Hi t")
        viewModel.setText("Hi there")
        XCTAssertEqual(canvas.session?.markupItem(id: text.id)?.kind, .text("Hi there", origin: CGPoint(x: 5, y: 5)))
        viewModel.undo()
        XCTAssertEqual(canvas.session?.markupItem(id: text.id)?.kind, .text("Hi", origin: CGPoint(x: 5, y: 5)))
    }

    func test_deleteSelection_andCanvasCommands() {
        let text = addSelectedText()
        viewModel.handleCanvasCommand(.deleteSelection)
        XCTAssertNil(canvas.session?.markupItem(id: text.id))
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusItemDeleted)
        let before = viewModel.textFocusRequest
        viewModel.handleCanvasCommand(.editSelectedText)
        XCTAssertEqual(viewModel.textFocusRequest, before + 1)
    }

    func test_eyedropper_setsStrokeColor() {
        viewModel.sampleStrokeColor()
        XCTAssertEqual(viewModel.markupStyle.strokeColor, RasterColor(red: 0, green: 0, blue: 1))
    }

    func test_toolSelection_entersMarkupMode_andShowsHint() {
        viewModel.selectMarkupTool(.redact)
        XCTAssertEqual(viewModel.editingMode, .markup)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.hintRedact)
    }

    func test_adjustments_previewThenCommitOnce_andReset() throws {
        viewModel.previewAdjustment(\.exposure, to: 0.5)
        viewModel.previewAdjustment(\.exposure, to: 1)
        XCTAssertTrue(viewModel.isAdjusting)
        XCTAssertEqual(viewModel.previewAdjustmentsOverride, RasterImageAdjustments(exposure: 1))
        XCTAssertFalse(canvas.session?.isDirty ?? true, "nothing committed while dragging")
        viewModel.commitAdjustments()
        XCTAssertFalse(viewModel.isAdjusting)
        XCTAssertNil(viewModel.previewAdjustmentsOverride)
        XCTAssertEqual(canvas.session?.effectiveAdjustments, RasterImageAdjustments(exposure: 1))
        XCTAssertTrue(viewModel.canSave)

        viewModel.setComparing(true)
        XCTAssertEqual(viewModel.previewAdjustmentsOverride, .identity)
        viewModel.setComparing(false)

        viewModel.resetAdjustments()
        XCTAssertTrue(canvas.session?.effectiveAdjustments.isIdentity ?? false)
        viewModel.undo()
        XCTAssertEqual(canvas.session?.effectiveAdjustments, RasterImageAdjustments(exposure: 1))
        viewModel.canvasStateDidChange(canvas.state)
        XCTAssertEqual(viewModel.adjustments, RasterImageAdjustments(exposure: 1), "sliders follow undo")
    }

    func test_statusMessages_areAnnounced() {
        viewModel.copy()
        exporter.finish()
        XCTAssertEqual(announcer.messages.last, AppStrings.ImageEditor.statusCopied)
    }

    // MARK: - Phase 4: Vision

    private func lines(_ texts: [String]) -> [RecognizedTextLine] {
        texts.enumerated().map { RecognizedTextLine(text: $1, normalizedBox: CGRect(x: 0, y: Double($0) * 0.2, width: 0.5, height: 0.1), confidence: 1) }
    }

    func test_recognizeText_analyzesFullResolution_presentsAndCopies() {
        analyzer.textResult = .success(lines(["one", "two"]))
        viewModel.recognizeText()
        XCTAssertTrue(viewModel.isAnalyzing)
        XCTAssertFalse(viewModel.canAnalyze)
        exporter.finish()
        XCTAssertEqual(analyzer.analyzedWidths, [100])
        analyzer.deliverText()
        XCTAssertFalse(viewModel.isAnalyzing)
        XCTAssertTrue(viewModel.isRecognizedTextPresented)
        XCTAssertEqual(viewModel.recognizedFullText, "one\ntwo")
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusTextFound(2))

        viewModel.copyRecognizedText()
        viewModel.copyRecognizedText([viewModel.recognizedText[1]])
        XCTAssertEqual(pasteboard.texts, ["one\ntwo", "two"])
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusTextCopied)
    }

    func test_recognizedText_isClearedWhenDocumentChanges() {
        analyzer.textResult = .success(lines(["one"]))
        viewModel.recognizeText()
        exporter.finish()
        analyzer.deliverText()
        XCTAssertFalse(viewModel.recognizedText.isEmpty)
        addStroke()
        XCTAssertTrue(viewModel.recognizedText.isEmpty, "boxes would no longer line up")
    }

    func test_recognizeText_staleResultIsDiscarded() {
        analyzer.textResult = .success(lines(["one"]))
        viewModel.recognizeText()
        exporter.finish()
        canvas.session?.commit(.flip(horizontal: true))
        analyzer.deliverText()
        XCTAssertTrue(viewModel.recognizedText.isEmpty)
        XCTAssertFalse(viewModel.isAnalyzing)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusAnalysisStale)
    }

    func test_recognizeText_failureReportsReason() {
        analyzer.textResult = .failure(RasterImageAnalysisError.noTextFound)
        viewModel.recognizeText()
        exporter.finish()
        analyzer.deliverText()
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusNoTextFound)
        XCTAssertFalse(viewModel.isRecognizedTextPresented)
    }

    func test_shutdownDuringAnalysis_ignoresResult() {
        analyzer.textResult = .success(lines(["one"]))
        viewModel.recognizeText()
        exporter.finish()
        viewModel.shutdown()
        analyzer.deliverText()
        XCTAssertTrue(viewModel.recognizedText.isEmpty)
        XCTAssertFalse(viewModel.isAnalyzing)
    }

    func test_removeBackground_commitsUndoableMask() {
        let maskImage = RasterImageTestFixtures.quadrantImage(width: 100, height: 60)
        analyzer.maskResult = .success(RasterImageMask(image: maskImage))
        viewModel.removeBackground()
        exporter.finish()
        XCTAssertFalse(viewModel.isAnalyzing)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusBackgroundRemoved)
        XCTAssertTrue(viewModel.canSave, "PNG keeps transparency")
        viewModel.undo()
        XCTAssertFalse(canvas.session?.isDirty ?? true)
    }

    func test_removeBackground_onJPEG_blocksSave_butAllowsExport() {
        viewModel.fileURL = tempRoot.appendingPathComponent("photo.jpg")
        analyzer.maskResult = .success(RasterImageMask(image: RasterImageTestFixtures.quadrantImage(width: 100, height: 60)))
        viewModel.removeBackground()
        exporter.finish()
        XCTAssertFalse(viewModel.canSave)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.saveBlockedTransparency)
        viewModel.save()
        XCTAssertEqual(exporter.jobs.count, 1, "save did not start a render")
        XCTAssertTrue(viewModel.canExport)
    }

    func test_removeBackground_noSubject_reportsReason() {
        analyzer.maskResult = .failure(RasterImageAnalysisError.noSubjectFound)
        viewModel.removeBackground()
        exporter.finish()
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusNoSubjectFound)
        XCTAssertFalse(canvas.session?.isDirty ?? true)
    }

    // MARK: - Final audit regressions

    func test_reloadingTheSameFile_cancelsAnalysis_andClearsOCR() {
        analyzer.textResult = .success(lines(["one"]))
        viewModel.recognizeText()
        exporter.finish()
        analyzer.deliverText()
        XCTAssertFalse(viewModel.recognizedText.isEmpty)

        // Start another analysis, then the same file reloads into a fresh revision-0 session.
        viewModel.recognizeText()
        exporter.finish(1)
        canvas.session = .inMemory(RasterImageTestFixtures.quadrantImage(width: 100, height: 60), canvasSize: CGSize(width: 100, height: 60))
        viewModel.didLoadImage(rendered: true, saveBlockReason: nil, isNewFile: false)
        XCTAssertTrue(viewModel.recognizedText.isEmpty, "boxes from the old pixels are dropped")
        XCTAssertTrue(analyzer.textHandle?.isCancelled ?? false, "in-flight Vision request is cancelled")
        analyzer.deliverText()
        XCTAssertTrue(viewModel.recognizedText.isEmpty)
        XCTAssertFalse(viewModel.isAnalyzing)
    }

    func test_backgroundMaskForReplacedSession_isNotApplied() {
        analyzer.maskResult = .success(RasterImageMask(image: RasterImageTestFixtures.quadrantImage(width: 100, height: 60)))
        viewModel.removeBackground()
        canvas.session = .inMemory(RasterImageTestFixtures.quadrantImage(width: 100, height: 60), canvasSize: CGSize(width: 100, height: 60))
        exporter.finish()
        XCTAssertFalse(canvas.session?.isDirty ?? true, "mask from the old session must not land on the new one")
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusAnalysisStale)
    }

    func test_removeBackground_onGIF_blocksSave() {
        viewModel.fileURL = tempRoot.appendingPathComponent("anim.gif")
        analyzer.maskResult = .success(RasterImageMask(image: RasterImageTestFixtures.quadrantImage(width: 100, height: 60)))
        viewModel.removeBackground()
        exporter.finish()
        XCTAssertFalse(viewModel.canSave)
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.saveBlockedTransparency)
    }

    func test_repeatedAdjustments_keepOneOperation_andUndoStepsBack() throws {
        for value in [0.2, 0.4, 0.6] {
            viewModel.previewAdjustment(\.contrast, to: value)
            viewModel.commitAdjustments()
        }
        let operations = try XCTUnwrap(canvas.session?.document.operations)
        XCTAssertEqual(operations.count, 1, "superseded adjustments are replaced, not appended")
        viewModel.undo()
        XCTAssertEqual(canvas.session?.effectiveAdjustments.contrast, 0.4)
        viewModel.undo()
        viewModel.undo()
        XCTAssertFalse(canvas.session?.isDirty ?? true)
    }
}
