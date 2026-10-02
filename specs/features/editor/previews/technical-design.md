# Previews — Technical Design

## Overview

Previews covers raster image editing, SVG read-only preview, PDF viewing, and HTML rendered editing. The raster path is non-destructive: an immutable source and ordered operations drive a discardable display proxy and a separate full-resolution output pipeline. Phase 3 adds editable markup, Core Image adjustments, asynchronous pixel-effect previews, and accessibility semantics; Phase 4 adds on-device Vision OCR and foreground masking. Decode, export, compositing, and analysis run off the main actor through injected services; preview UI types are main-actor isolated. SVG uses a `WKWebView` with JavaScript disabled; PDF uses native `PDFKit`.

## Architecture

### Raster Image Editor

```text
AppContainer.makeRasterImageEditorServices()
  → MarkdownViewModel.rasterImageEditorServices
    → ImageFilePreview
      → RasterImagePreviewHost
        → RasterImageEditorViewModel(services:)
          → RasterImageFilePreview / RasterImageFilePreviewCoordinator
            → EditableRasterImageCanvasView
              → RasterImageEditSession
                → RasterImageDocument + RasterImageEditHistory
          → RasterImageDecoding / Rendering / Exporting / PasteboardWriting
          → RasterImageColorSampling / AccessibilityAnnouncing / Analyzing
```

`RasterImageEditorViewModel` owns toolbar, command gating, save/copy state, and conflicts. Views call named methods; the view model reaches AppKit through `RasterImageCanvasControlling` and `RasterImageFileSessionControlling`. Service contracts live in `Protocols/RasterImageEditing.swift`; production implementations are assembled as `RasterImageEditorServices` by `AppContainer` and passed through the active `MarkdownViewModel`.

`EditableRasterImageCanvasView` is a flipped, top-left-origin input/render adapter. It holds only transient crop, in-progress stroke, and pan state; `RasterImageEditSession` owns the document, display rendering, and history. Its input and rendering extensions handle pointer/keyboard input and canvas drawing.

| Mode | Behavior |
|------|----------|
| **Pan** | Default. Drag to pan; pinch/scroll to zoom from 0.1× to 10×. |
| **Crop** | Starts with a non-pending full-image box. Create, move, or resize through eight handles; presets constrain aspect. Return applies a valid changed box, Escape resets it. Minimum result is 2×2 export pixels. |
| **Markup** | Select or create Pen, Line, Arrow, Rectangle, Ellipse, Highlight, Text, Blur, Pixelate, and Redact objects; edit the selected object through pointer, keyboard, and inspector controls. |
| **Adjust** | Preview and commit Exposure, Contrast, Saturation, Vibrance, Temperature, Highlights, Shadows, and Sharpness; reset or compare with the unadjusted source. |

### Non-Destructive Document, Coordinates, and History

`RasterImageDocument` contains an immutable `RasterImageSource` (`.file(URL)` or `.memory(CGImage)`), its base canvas size/export scale, an ordered `[ImageEditOperation]`, and a monotonically increasing revision. File-backed canvas units equal upright/oriented source pixels (`exportScale == 1`); in-memory sources retain their point-size scale. `RasterImageCanvasTransform` is the shared top-left canvas-to-pixel mapping used for crop snapping and replay.

Operations include legacy strokes/text annotations, editable markup items, effective color adjustments, crops, quarter-turn rotations, horizontal/vertical flips, straighten rotations, resize, and foreground-mask background removal. At commit, `ImageEditOperation.canonicalized(for:exportScale:)` converts Straighten to `.straighten(radians:outputSize:)` with an export-pixel-snapped size. `RasterImageRenderer` replays with one fixed per-axis pixel scale for the whole operation list and swaps its axes after odd quarter turns; it does not derive a new scale from each rounded intermediate. Thus output dimensions remain exactly `RasterImageCanvasTransform.pixelSize`. Before each geometric operation, preceding overlays are flattened into the current base; a geometric session change also clears any crop marquee from the prior canvas space.

`RasterImageCropGeometry.coveringPixelRect` is the common canvas-to-bitmap crop primitive used by `RasterImageCanvasTransform.pixelRect` and renderer replay. It scales X and Y independently, rounds minimum edges down and maximum edges up, clamps to bitmap bounds, and first snaps values within 1e-6 pixel of an integer. This preserves true fractional coverage without letting proxy rounding error add an extra row or column.

`RasterImageEditHistory` stores ordinary appends as `.removeLast(n)` entries and their redo inverses as appended operations. Editable-object changes use set/insert/remove inverses. A coalescing key retains the first prior value only while changes remain within `coalescingWindow` (one second); `endCoalescing()` ends the run when selection changes. Non-append replacement such as Revert stores one prior-list snapshot. It drops entries beyond 200 and clears redo after a new edit, keeping common-case retained memory O(limit) entries instead of O(limit × operation count). Undo/Redo first render the target flattened prefix and install document/history state only on success; a render failure restores the popped history entry and returns false without changing pixels or operations. Toolbar and responder-chain commands expose the result. Successful Save rebases the clean source and clears history.

### Raster Decode and Display

`RasterImageDecoder` inspects source metadata and normalizes EXIF orientations 1–8 exactly once. Sources with longest oriented edge ≤4096 use full-resolution display pixels; larger sources use a viewport-sized proxy clamped to 1024–4096 pixels. Decode runs on the coordinator's serial user-initiated queue. A load generation prevents superseded results from installing, while the AppKit placeholder distinguishes loading from failure. New files call `fitToWindow()` (capped at 100%); same-file reloads restore viewport context when feasible. This is bounded one-shot display decode, not progressive loading.

`RasterImageSourceInfo` gates overwrite only for multiple frames/pages, >8-bit components, and HDR/ISO gain maps. Proxy resolution is not a Save block because file export performs a fresh full-resolution decode.

### Raster Export and Persistence

`RasterImageExportService` receives an immutable `RasterImageExportJob` containing source, canvas size, operations, revision, and optional destination. Its serial user-initiated queue performs full-resolution file decode, operation replay, and optional encoding under an autorelease pool. `RasterImageWorkHandle` is a lock-protected cancellation token checked between decode, render, and encode; non-cancelled results are delivered on the main actor.

Save and Copy both use this path. Copy renders without encoding and writes the full-resolution output to the pasteboard on the main actor. Save encodes upright orientation-1 pixels, then local Save and Export As perform `.atomic` writes on `RasterImageEditorServices.ioQueue`. Remote staged-file writes use a detached user-initiated task. Completions return to the main actor; editor-owned writes compare `operationGeneration` before installing results. A failed save leaves the session and history intact.

Before output starts, Save checks the current on-disk identity. After rendering, it requires the result revision to equal the session revision and the session object to remain active, then checks file identity again immediately before the write; `RasterImageSaveError.fileChangedDuringSave` reports that second-check conflict. Every completion also compares the captured `operationGeneration`. `shutdown()` increments that generation, cancels Save/Copy/Export handles, clears all busy and post-save-reload flags, and unlocks the canvas, so a late completion is ignored.

After a successful file-source Save, the session is rebased but the editor remains locked through `isAwaitingPostSaveReload` while the coordinator re-decodes the written file. Installing that decode unlocks editing. This makes the visible clean baseline match the persisted, potentially lossy pixels that a later file-source export will decode.

| Format | Compression |
|--------|-------------|
| JPEG (`.jpg`, `.jpeg`) | Quality 0.92 |
| HEIC/HEIF/WebP | Quality 0.90 |
| PNG/GIF/BMP/TIFF | Lossless encoder setting |

### Raster Save Command Flow

```text
MarkdownViewModel.saveActiveDocument()
  → imageSaveRequestToken += 1 (request remains pending)
    → RasterImagePreviewHost sees a renderable editor
      → RasterImageSaveRequest.acknowledge() exactly once
        → RasterImageEditorViewModel.save()
          → identity check → full-resolution export → revision/session/generation check
            → second identity check → atomic local write or remote RasterImageSaveDataHandler
              → file-source re-decode → unlock editing
```

Toolbar Save invokes the same view-model command. `RasterImageSaveRequest` separates request issuance from consumption, so a ⌘S issued before host mount remains pending and the host acknowledges it only when a renderable editor can call Save. A changed crop box, unsupported source fidelity, transparency introduced into JPEG/JPG/BMP/GIF, no edits, external identity change, and an existing in-flight save gate overwrite Save; the untouched full-canvas crop box is not pending. GIF is blocked because its 1-bit transparency cannot faithfully encode the background-removal alpha mask.

### Raster File Observation and Conflict State

`RasterImageFileState` captures file size, content modification date, and `fileResourceIdentifier`, reading fresh URL resource values. The resource identifier detects same-size/same-date atomic replacement. `DispatchSource` observes write, extend, rename, delete, and revoke events. A clean image reloads; pending edits or a changed crop box produce Reload from Disk / Keep My Edits conflict state. Save independently checks identity before export and immediately before the write. A replacement can still occur after the second check and before the atomic URL write.

Remote providers cannot rely on local file events for source-of-truth changes. `MarkdownViewModelFileLifecycle.materializeRemotePreview` captures `remoteImageBaselineToken` before reading source bytes, then stages them. Polling calls `refreshStagedRemoteImage()`; its local observer reloads a clean editor or raises Reload/Keep for pending work. The save path in `MarkdownViewModel+RasterImage.swift` throws `RasterImageSaveError.remoteChanged` when current-token lookup throws, when a version-capable provider returns a token but no baseline exists, or when tokens differ. A provider returning `nil` declares token support unavailable and is trusted. After its own remote write, the view model stores the resulting token as the next baseline.


### Phase 2 Crop and Geometric Editing

Crop state is transient canvas state, separate from `RasterImageDocument.operations`. Entering Crop creates the full canvas or the largest centered rectangle for an active aspect constraint. The untouched full box cannot apply or block Save and is removed outside Crop mode, while a changed box remains visible across modes. `RasterImageCropInteraction` performs bounded create/move/resize and ratio constraints; a handle step below the minimum returns the previous rectangle, preserving the fixed anchor and aspect. Unmodified Arrow and Shift+Arrow nudge by one or ten export pixels. Rendering adds outside dimming, eight fixed-screen-size handles, a thirds grid, and live pixel dimensions.

`ImageEditOperation.rotate`, `.flip`, `.straighten`, and `.resize` share the same replay/history path as crop. Straighten slider changes set `straightenDegrees`; live drawing rotates and scales the image to its inscribed crop and overlays a thirds grid. Slider release commits `.straighten` for non-trivial angles. `straightenedSize` retains source aspect ratio at the largest scale fitting inside the rotated bounds, avoiding transparent corners. Resize converts requested export pixels back through `exportScale` and rejects either edge above 16,384.

### Phase 3 Markup, Adjustments, and Accessibility

`RasterMarkupItem` is the editable scene object carried by `.markup`. The tool set is Select, Pen, Line, Arrow, Rectangle, Ellipse, Highlight, Text, Blur, Pixelate, and Redact. Pointer hit-testing selects the topmost object; rect objects expose eight resize handles, lines/arrows expose endpoint handles, and dragging the body translates the object. Shift snaps line/arrow creation to 45° increments, makes dragged boxes square, and preserves the selected rectangle's proportions during handle resize. Tab/Shift+Tab cycles objects, Delete removes, Arrow/Shift+Arrow nudges by one/ten export pixels with coalesced history, Escape deselects, and double-clicking selected text asks SwiftUI to focus the text field.

`RasterImageMarkupToolbar` edits `RasterMarkupStyle`: stroke `ColorPicker`, `NSColorSampler` eyedropper, optional fill and fill picker, width, plus text/font/size. Defaults apply to future objects; when an item is selected, the same setters replace its operation with a per-property coalescing key. Highlight draws at reduced alpha using multiply blend. Redact draws an alpha-1 fill, while the localized Blur/Pixelate hint warns that those visual effects are not secure for sensitive text.

Blur and Pixelate operate on a snapshot of pixels composited so far. `RasterImageRenderer.applyPixelEffect` maps the item rectangle to the current bitmap and delegates to `RasterImageEffects` Core Image Gaussian blur or pixellate. Strength is proportional to item size and converted by bitmap scale, keeping proxy and output appearance aligned. `RasterImageLiveCompositor` renders pixel-effect and adjustment previews on a serial user-interactive queue; a monotonically increasing request rejects superseded work before and after main-actor delivery. The canvas draws a composite only when both revision and session identity match and no item is being dragged, preventing a baked item plus drag preview from ghosting. A failed render assigns `nil` and clears the older composite.

`RasterImageAdjustments` contains Exposure, Contrast, Saturation, Vibrance, Temperature, Highlights, Shadows, and Sharpness. Rendering applies the adjustment source-first. Slider changes append an override only to the asynchronous display job; each commit replaces the sole stored `.adjust` in place and records the prior value through history `.set`, so Undo remains granular without operation-list growth. Reset commits identity and Compare supplies identity as a temporary display override.

`RasterImageEditorViewModel.actionStatus` sends each distinct non-empty status to the injected `RasterImageAccessibilityAnnouncing`; production posts `NSAccessibility.announcementRequested`. Each editable markup child has button role and press-to-select behavior. Canvas custom actions provide Delete and Move Left/Right/Up/Down for the selected item; Crop provides Shrink, Expand, Move in four directions, Apply, and Cancel, making crop operable without a pointer. Tool buttons publish the selected trait. Phase 3/4 raster strings live in `AppStrings.ImageEditor`.

### Phase 4 On-Device Vision

`RasterImageAnalyzing` isolates OCR and foreground masking; `RasterImageVisionService` runs both on a serial user-initiated queue using Vision without a network service. Before analysis, the normal exporter renders current operations from the immutable source at full resolution. `VNRecognizeTextRequest` uses `.accurate`, language correction, and automatic language detection, converts Vision boxes to top-left normalized coordinates, and sorts lines by row then X. The canvas outlines boxes; `RasterImageRecognizedTextSheet` provides selectable lines, per-line Copy, Copy Selected, and Copy All through `RasterImagePasteboardWriting.writeText`.

`VNGenerateForegroundInstanceMaskRequest` combines all detected instances and generates a scaled grayscale L8 mask. `.removeBackground(RasterImageMask)` is geometric: replay flattens preceding overlays, clips the composited image through the mask at the current bitmap size, and records one undoable operation. If the open extension is JPEG/JPG, BMP, or GIF, `transparencySaveBlockMessage` disables overwrite Save and directs the user to PNG, HEIC, or TIFF Export As.

`AnalysisToken` captures `operationGeneration`, session `ObjectIdentifier`, and document revision. Installation requires all three to match, so a replacement revision-0 session cannot accept an older revision-0 result. `didLoadImage` calls `cancelAnalysis()` on every load/reload, including the same path, cancelling work and clearing OCR text/boxes. Analyzer methods return `RasterImageWorkHandle`; `onCancel` calls the underlying `VNRequest.cancel()`, and delivery checks cancellation before invoking completion. `shutdown()` cancels both export-stage and Vision-stage analysis and invalidates the editor generation.

### Export As

`RasterImageExportSheet` selects PNG/JPEG/HEIC/TIFF and exposes quality only for lossy JPEG/HEIC; JPEG shows the no-transparency warning. `SystemRasterImageExportDestinationPicker` presents `NSSavePanel` constrained to the selected content type. `RasterImageEditorViewModel.export(to:options:)` creates a normal full-resolution export job with explicit encoder options, writes returned data atomically on the I/O queue, and never rebases or clears dirty state. `canExport` ignores overwrite `saveBlockReason`, making Export As the explicit flatten path. `isSameFile(_:_:)` standardizes and resolves symlinks, then compares `fileResourceIdentifier` when paths differ, refusing the open file through direct, symbolic-link, and hard-link destinations.

### Raster Navigation and Input Focus

`RasterImageFilePreviewCoordinatorViewport` owns Fit, Actual Size, zoom-step, percentage reporting, and viewport preservation. Actual magnification is `exportScale / backingScale`; percentage is its inverse expression, so 100% means one export pixel per device pixel. First load calls Fit (capped at actual size). Toolbar −/+ use 0.8×/1.25× steps, the percentage menu exposes Fit and Actual Size, and `NSScrollView` continues to handle pinch magnification.

The canvas treats unmodified Space as temporary pan without changing `editingMode`; unmodified Arrow and Shift+Arrow perform crop nudges. Space or Arrow events carrying Command, Option, or Control fall through to the responder chain so app shortcuts are not swallowed. Pan uses `NSCursor.closedHand.set()` plus cursor-rect invalidation rather than push/pop. First install and mode changes call `focusIfPossible()`, which makes the canvas first responder unless an `NSText` field is active.


### SVG Preview

SVG files rendered read-only in `WKWebView` with JavaScript disabled. No editing canvas. `SVGFilePreview` applies `WebViewPresentationScale` during creation and update so the global document-size ratio changes the existing page zoom without reloading the SVG.

### Authored HTML Presentation Scale

HTML rich editing uses `MarkupRenderedEditor`, while compiler-produced AsciiDoc HTML uses `HTMLDocPreviewView`. Both read `crispyvibesUIScale` and idempotently apply the shared 0.25×–5.0× current/default code-size ratio through `WKWebView.pageZoom`. This is presentation-only and does not rewrite authored CSS or rebuild the document.

Raster image and PDF previews do not use the adapter: `NSScrollView.magnification` and `PDFView.autoScales` remain domain-owned.

### PDF Preview

`PDFView` with single-page continuous vertical display and auto-scaling.

## State Management

- Editable markup exists only after the last geometric operation; a later crop/rotate/flip/straighten/resize/background removal preserves its pixels but flattens the item. Undo restores the editable operation state.
- Inspector, typing, and nudge changes replace selected operations through set history, coalesced for at most one second and ended by selection changes.
- Adjustment slider values are transient during drag; commits replace one stored `.adjust` through undoable `.set`; Compare is display-only.
- OCR lines and analysis installation are scoped to editor generation, session identity, and revision; every reload cancels and clears them.
- `RasterImageEditorViewModel`, the edit session, canvas, and coordinator are main-actor UI state.
- `RasterImageDocument.revision` changes with each operation-list replacement; export jobs capture it.
- `RasterImageEditSession` owns compact transactional history and separates display pixels from immutable export source.
- A crop box is transient and independent from committed dirty operations; only a box differing from the full canvas is pending.
- Load generation and output revision/session/generation checks discard stale asynchronous results.
- Save remains busy through post-save file re-decode; Export As has independent `isExporting` state.
- Image dirty state remains independent from text document dirty state.

## API / Command Contracts

- `RasterImageCanvasControlling` — transient crop/edit commands and access to current session/state.
- `RasterImageFileSessionControlling` — reload, identity baseline, pre-save change check, and viewport reset.
- `RasterImageDecoding` — upright proxy/full-resolution decode.
- `RasterImageRendering` — deterministic ordered operation replay at any bitmap scale.
- `RasterImageExporting` — cancellable off-main full-resolution render/encode with main-actor completion.
- `RasterImagePasteboardWriting` — main-thread image/plain-text clipboard boundary.
- `RasterImageColorSampling` — main-thread screen eyedropper boundary.
- `RasterImageAccessibilityAnnouncing` — VoiceOver status announcement boundary.
- `RasterImageAnalyzing` — off-main on-device OCR and foreground-mask analysis; each method returns a cancellable `RasterImageWorkHandle`, and non-cancelled completion returns on the main actor.
- `RasterImageSaveDataHandler` — local/remote byte sink whose completion may arrive on any thread.
- `RasterImageExportDestinationPicking` — main-thread user destination selection, implemented with `NSSavePanel`.
- `RasterImageViewportControlling` — Fit, Actual Size, and relative zoom commands.
- `RasterImagePersistence` / `RasterImageEncoder` — extension- or option-selected encoding, lossy quality, and orientation 1.

## Dependencies (frameworks, libraries)

- AppKit / SwiftUI — canvas, scroll view, toolbar, responder chain, and representable bridge
- ImageIO / CoreGraphics — metadata, decode, orientation, replay, crop, masking, and encoding
- Core Image — color adjustments, blur, and pixelation
- Vision — on-device accurate text recognition and foreground-instance masks
- `os.OSAllocatedUnfairLock` — export cancellation state
- `WKWebView` — SVG and HTML rendering
- `PDFKit` — PDF rendering
- GCD / `DispatchSource` — serial decode/export queues and file observation

## Platform Considerations

The image canvas supports macOS drag-pan, Space-drag temporary pan, pinch magnification, crop and markup Arrow/Shift+Arrow nudges, Return/Escape crop commands, Tab/Shift+Tab markup traversal, Delete, ⌘Z/⇧⌘Z responder commands, and menu validation. Display backing changes update centering, device-pixel actual-size math, and may rebuild a clean display proxy. Preview views and coordinators are `@MainActor`; canvas focus is restored on open and mode changes unless a text field is active. User-visible ratio titles, percentages, and format names are resolved through `AppStrings.ImageEditor`.

## Implementation Decomposition

Large owners are split by responsibility: `RasterImageEditSession+Output`, `RasterImageFilePreviewCoordinatorLoading`, `RasterImageFilePreviewCoordinatorObservation`, `RasterImageFilePreviewCoordinatorViewport`, `RasterImageRenderer+Pixels`, and `RasterImageOverlayPainter+Markup`. The base types retain state and coordination while these extensions own output, loading, observation, viewport, bitmap, and markup details respectively.

The app Save/Copy/Export path uses injected asynchronous services. The synchronous `EditableRasterImageCanvasView.saveCompositedImage(to:)` remains only as a standalone/test compatibility API and is not called by the app path.

## Performance Constraints

- Display zoom is 0.1×–10×; first-open fit never enlarges beyond 100%.
- Display proxy requests are clamped to 1024–4096 pixels; output always uses full-resolution source pixels.
- Decode and export use separate serial user-initiated queues; atomic local writes use a dedicated I/O queue, and remote staged writes use detached tasks.
- Undo history retains at most 200 entries; ordinary appends store counts, while Revert stores one snapshot.
- Minimum crop output is 2×2 export pixels.
- Export As and Vision analysis use the full-resolution export path; Vision work then runs on its own serial user-initiated queue.
- Live adjustment/pixel-effect display composition is serialized and latest-request-wins.
- Explicit Resize limits requested output edges to 16,384 pixels; pre-existing source decode can still exceed that size.

## Known Limits

- Display loading is one-shot, not progressive.
- A geometric edit (crop/rotate/flip/straighten/resize/background removal) flattens earlier markup: its visual result remains, but it is not editable unless Undo restores the prior operation state.
- Save and Export As write one 8-bit RGB frame (source RGB when usable, otherwise sRGB) with orientation 1. They do not preserve EXIF/IPTC/GPS or ICC beyond the working color space, and multi-frame, >8-bit, and HDR gain-map sources remain blocked from overwrite Save.
- There is no layered Save As format such as PSD; output is flattened.
- Two local identity checks narrow but do not close the final identity-check-to-atomic-write TOCTOU window. Remote SFTP writes have no provider-level compare-and-swap; tokens use size plus one-second-resolution mtime.
- Vision analyzes a full-resolution composite. Cancellation reaches `VNRequest`, but already-allocated decode/render/Vision buffers can still create substantial memory pressure for huge sources.
- The legacy synchronous `EditableRasterImageCanvasView.saveCompositedImage(to:)` remains for standalone use/tests only and is not used by the app path.
