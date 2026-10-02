# F009 Previews

**Domain:** Editor
Status: draft

## Status Notes (2026-10-01)

The final audit reports 1,683 unit tests passing with 0 failures. Remaining limitations: markup before a later crop/rotate/flip/straighten/resize/background-removal operation is flattened and becomes non-editable until Undo; local Save retains a final identity-check-to-atomic-write TOCTOU window, while remote SFTP has no provider CAS and uses one-second mtime tokens; output is one upright 8-bit sRGB-or-source-RGB frame without EXIF/IPTC/GPS or ICC beyond the working color space; no layered Save As format such as PSD is available. The legacy synchronous `EditableRasterImageCanvasView.saveCompositedImage(to:)` remains only for standalone use/tests and is not used by the app save path.

---

## Requirements

### F009-R01: Image Opening and Load States
Image files open in a scrollable image preview with no text editing controls. SVG files route to a dedicated SVG preview host. Load failures show an unavailable state.

### F009-R02: Image Preview Interaction
Raster image preview starts in Pan mode. Dragging pans, pinch/scroll gestures zoom from 0.1× to 10×, and normal preview updates preserve viewport context when feasible.

### F009-R03: Basic Image Editing
A segmented control exposes Pan, Crop, Markup, and Adjust modes. The toolbar also provides Undo, Redo, Smart Tools, Copy, Revert, Export As, and Save. Edits remain aligned with the pan/zoom canvas.

### F009-R04: Image Edit Save and Reopen
Save and ⌘S write a composited, upright image when overwrite is safe. Reopening the file shows the saved crop, strokes, and annotations.

### F009-R05: Image Source File Change Handling
When source bytes change at the same path, a clean preview reloads while preserving viewport context when feasible. If edits or a crop marquee are pending, reload is deferred and the user chooses Reload from Disk or Keep My Edits.

### F009-R06: Remote Image Staging
Remote raster images stage a local preview file; safe edits are written back to the SSH source on save and the staged baseline is refreshed.

### F009-R07: Crop Overlay Preservation
Applying a crop preserves the visible in-bounds result of earlier markup, repositions it into cropped coordinates, and removes out-of-bounds pixels. The earlier markup is flattened by the geometric edit.

### F009-R08: Crop Failure Feedback
Crop failure feedback distinguishes no selection, an invalid or smaller-than-2×2-pixel selection, decode failure, and crop failure.

### F009-R09: Image Edit Dirty State
Committed bitmap, markup, adjustment, and background-removal edits are tracked independently from text document dirty state. A crop marquee alone is transient selection state and is not a dirty edit.

### F009-R10: Image Edit Save Failure Recovery
Save failure preserves the submitted in-memory edits, unlocks interaction, allows retry, and shows the failure reason.

### F009-R11: Image Editing Accessibility
Editing controls expose stable accessibility identifiers. ⌘S routes to image Save; the focused canvas supports crop and markup keyboard commands; status changes post VoiceOver announcements; and markup tools/items expose selected state and semantic accessibility values.

### F009-R12: Revert Action
Revert discards unsaved edits and any crop marquee, restoring the last loaded or successfully saved baseline. Reverting committed edits is itself undoable.

### F009-R13: Display Backing Properties Change
Image preview updates centering and backing-scale presentation when display properties change. A read-only proxy may be regenerated when appropriate.

### F009-R14: Raster Decode Policy (No Progressive Loading)
Sources whose longest oriented edge is at most 4096 pixels decode at full resolution for display. Larger sources decode to a viewport-sized display proxy, while output re-decodes the source at full resolution. True progressive loading is not implemented, and no low-resolution placeholder is replaced incrementally.

### F009-R15: Editing Mode Toolbar Hints
Pan, Crop, Markup, and Adjust each show a contextual toolbar hint. Crop identifies Return/Apply Crop and Escape/Cancel Crop; markup hints describe selection, constraints, and secure Redact versus Blur/Pixelate.

### F009-R16: PDF Opening
PDF files open in a PDFKit viewer with continuous vertical scrolling and auto-scaling.

### F009-R17: Remote PDF Staging
Remote PDFs materialize a staged local preview file for PDFKit; the staged file is cleaned up on document change.

### F009-R18: Theme-Aware PDF Background
PDF preview background adapts to the active theme without affecting page content rendering.

### F009-R19: HTML Opening and Editing
HTML files open in an editable rendered mode with relative resources resolving against the file parent directory.

### F009-R20: HTML Content Sync and Asset Resolution
HTML mode stores full document content including doctype. A base tag is injected for relative asset resolution.

### F009-R21: HTML Rich/Source View Mode Toggle
HTML editor supports toggling between rendered rich view and raw HTML source view with content preserved.

### F009-R22: HTML Find and Replace
Find and replace is available in the HTML editor with match highlighting.

### F009-R23: HTML Root-Level Read Access
The HTML renderer has read access scoped to the project root for resolving local file references outside the parent directory.

### F009-R24: HTML WKWebView Crash Recovery
The HTML editor detects WKWebView crashes and re-renders content automatically with no data loss.

### F009-R25: Web Preview Presentation Scale
Authored HTML rich mode and SVG WKWebView previews MUST apply the shared global document-size ratio live through `pageZoom`. Raster image magnification and PDFKit scaling remain independent viewer state.

### F009-R26: Crop Pixel Mapping
Crop selections map from the flipped canvas to integral pixels using a top-left origin and independent X/Y scales. Minimum edges round down and maximum edges round up to cover every touched pixel, except an edge within 1e-6 pixel of an integer snaps to that integer so floating-point error cannot add a row or column. Mapping clamps to source bounds and does not invert Y. The canvas transform and renderer use this same covering-pixel-rectangle contract.

### F009-R27: Orientation Normalization
Every full-resolution and proxy decode path normalizes EXIF orientations 1–8 into upright pixels exactly once. Exported images contain upright pixels and write orientation 1.

### F009-R28: Overwrite Safety Gate
Save is disabled with an actionable message when the source is multi-frame, greater than 8 bits per component, or carries an HDR gain map. A reduced-resolution display proxy does not block Save because output re-decodes the source at full resolution. Copy remains available.

### F009-R29: Pending Crop Semantics
Entering Crop mode initializes a full-image crop box with dimmed outside area, but the untouched full-image box is transient UI rather than a pending crop: it does not block Save, cannot be applied, and disappears outside Crop mode. A crop box that differs from the full canvas remains visible across mode changes and blocks Save until Return/Apply Crop commits it or Escape/Cancel Crop resets it.

### F009-R30: Image Save Routing and Locking
⌘S follows the image save path rather than text save. Each owner-issued save request is pending until acknowledged and is delivered exactly once, including when the raster editor mounts after the request. While Save or its required post-save file reload is in flight, pointer edits and mutating toolbar actions are locked, and repeated save attempts are ignored.

### F009-R31: External-Change Conflict
An external local or remote file change never silently replaces pending edits or a pending crop. A conflict banner offers Reload from Disk or Keep My Edits. Local Save checks file identity before rendering and again immediately before writing; remote Save revalidates the last observed remote modification token before writing.

### F009-R32: Non-Destructive Document and History
Raster editing retains an immutable file or in-memory source plus an ordered list of edit operations. History retains at most 200 undo steps, records ordinary appends as remove-last entries, records Revert as one prior-list snapshot, and clears redo after a new edit. Undo and Redo are available from toolbar buttons and the standard ⌘Z/⇧⌘Z responder commands.

### F009-R33: Full-Resolution Asynchronous Output
Save and Copy replay the current operation list against full-resolution source pixels off the main thread. The display proxy is never an export source, and output completion returns to the main actor.

### F009-R34: Stale Output and Lifecycle Protection
Each output job captures its document revision and editor operation generation. A Save render whose revision, session, or operation generation is no longer current is discarded and cannot write or clear newer edits. Shutdown increments the generation, cancels work, resets busy state, and unlocks the canvas so late completions cannot mutate a torn-down editor.

### F009-R35: Asynchronous Raster Loading, Initial Fit, and Focus
Raster decode runs off the main thread and shows a loading placeholder. Only the latest load generation may install its result. A newly opened image initially fits within the viewport without enlargement beyond actual size, then the canvas takes keyboard focus unless a text field is active; mode changes use the same focus rule.

### F009-R36: Raster File Identity and Save Revalidation
External-change detection includes file size, modification date, and the file-system resource identifier so same-size atomic replacement is detected. Save compares that identity before starting output and again after rendering, immediately before the write, and requires conflict resolution if the source changed at either check.


### F009-R37: Non-Text Preview Line-Number Isolation

Browser, raster image, SVG preview, PDF, notebook, whiteboard, terminal, and Office preview surfaces MUST NOT receive editor file line-number gutters. Their domain-specific zoom/pan/presentation controls remain independent of the global line-number preference. Editable HTML iframe mode is also excluded because rendered DOM rows do not map reliably to source lines.

### F009-R38: Precision Crop Interaction
Crop mode shows a crop box with eight resize handles, interior move interaction, a dimmed outside region, a rule-of-thirds grid, and live pixel dimensions on the box and status line. A finished crop must be at least 2×2 export pixels; a handle drag that would cross below that minimum leaves the prior box unchanged so its fixed anchor and aspect are preserved.

### F009-R39: Crop Ratios and Keyboard Adjustment
Crop provides Freeform, Original, Square, 4:3, 3:2, and 16:9 aspect presets, with portrait/landscape swapping for orientable ratios. Unmodified Arrow keys move a pending crop by one export pixel, Shift+Arrow moves it by ten, Escape resets the box, and Return applies a valid pending crop. Command-, Option-, or Control-modified arrows remain available to app and system shortcuts.

### F009-R40: Undoable Geometric Editing
Rotate Left/Right, Flip Horizontal/Vertical, and Straighten are represented as ordered, undoable `ImageEditOperation`s. Straighten previews continuously from −45° through +45° with a thirds grid, then commits on slider release as a rotation cropped to the largest inscribed rectangle with the source aspect ratio so no transparent corners remain. Any committed geometric edit clears a crop box drawn in the prior canvas space.

### F009-R41: Explicit Raster Resize
Resize accepts pixel width and height, an optional proportional lock, and 25%, 50%, 75%, and 200% presets. Width and height must each be between 1 and 16,384 pixels. A changed size commits an undoable resize operation; an unchanged size is a no-op.

### F009-R42: Raster Export As
Export As offers PNG, JPEG, HEIC, and TIFF, with a quality control for JPEG/HEIC and a warning that JPEG drops transparency. After the options sheet, `NSSavePanel` selects the destination. Export As renders current operations at full resolution, writes the selected format, never saves or rebases the open document, and remains available when overwrite Save is blocked. It refuses destinations that are the open file directly or resolve to it through a symbolic or hard link.

### F009-R43: Raster Navigation Controls
The raster toolbar provides Zoom Out, Zoom In, a current zoom percentage menu, Zoom to Fit, and Actual Size. New images fit on open; Actual Size defines 100% as one image pixel per device pixel. Pinch magnification remains supported, and holding Space temporarily enables drag-pan in every editing mode.

### F009-R44: Post-Save File Baseline Consistency
After a successful file-source Save, the editor re-decodes the written file and keeps editing locked until that result installs. The displayed baseline therefore matches the persisted, potentially lossy pixels that the next full-resolution export will decode.

### F009-R45: Remote Raster Refresh and Save Token Safety
Remote materialization captures `remoteImageBaselineToken` before reading source bytes. Polling mirrors changed bytes into staging; a clean editor reloads while pending work produces Reload/Keep conflict handling. Save fails with `RasterImageSaveError.remoteChanged` when token lookup throws, a version-capable provider has no baseline, or the token differs. Providers that return `nil` tokens are trusted, and a successful write records the new token as the baseline.

### F009-R46: Raster Save Request Delivery
The document owner represents ⌘S as a `RasterImageSaveRequest` with pending and acknowledge operations. The raster host acknowledges a pending request only when a renderable editor can consume it, preventing lost mount-time requests and duplicate delivery.

### F009-R47: Raster Preview Main-Actor and Localized UI
Raster preview SwiftUI/AppKit UI types are main-actor isolated. Raster editor controls, status text, save errors, ratio titles, percentages, and format names use `AppStrings.ImageEditor`, including conflict, stale-revision, remote-change, decode, encoding, and unsupported-format failures.

### F009-R48: Balanced Pan Cursor State
Pan uses cursor-rect invalidation and `NSCursor.set()` for the temporary closed-hand cursor rather than cursor-stack push/pop, so an interrupted drag cannot leave an unmatched cursor-stack entry.

### F009-R49: Canonical Geometric Pixel Output
Commit canonicalizes Straighten to `.straighten(radians:outputSize:)` with an export-pixel-snapped output size. Replay keeps a fixed per-axis pixel scale, swapping axes after odd quarter turns, so rendered output pixels always equal `RasterImageCanvasTransform.pixelSize` without compounded rounding drift.

### F009-R50: Transactional Undo and Redo
Undo and Redo render the target operation state before installing it. If rendering fails, the document, display bitmap, and both history stacks remain unchanged, and the command returns failure.

### F009-R51: Off-Main Atomic Raster Writes
Local Save, Export As, and remote staged-file writes perform atomic disk I/O away from the main thread. Their completions return to the main actor and editor-owned writes are rejected when their captured operation generation is stale.

### F009-R52: Raster Shortcut Coexistence
Space-to-pan and crop Arrow-key handling ignore events carrying Command, Option, or Control so application and system shortcuts are not swallowed. Shift remains the ten-pixel crop-nudge modifier.

### F009-R53: Markup Tool Set
Markup mode provides Select, Pen, Line, Arrow, Rectangle, Ellipse, Highlight, Text, Blur, Pixelate, and Redact. Highlight uses multiply blending; Redact exports an opaque replacement rather than a recoverable visual effect.

### F009-R54: Editable Markup Objects
Each new markup is an editable `.markup(RasterMarkupItem)` operation until a later geometric edit flattens it. Users can select, move, resize through eight handles, drag line/arrow endpoints, constrain drawing or proportional resize with Shift, cycle with Tab/Shift+Tab, delete, nudge by one or ten pixels, deselect with Escape, and focus selected text by double-clicking it.

### F009-R55: Markup Inspector and History
The inspector controls stroke color, screen color sampling, optional fill, line width, and text/font/size. Inspector changes update both new-item defaults and the selected item; repeated changes to one property, typing, and keyboard nudges coalesce into one undo step until one second of inactivity or a selection change. History supports append, set, insert, remove, and replacement inverses.

### F009-R56: Pixel Effects and Secure Redaction Guidance
Blur and Pixelate process the pixels composited beneath their rectangles through Core Image, with effect strength scaled from canvas size so display proxies and full-resolution output match. The live display uses a latest-wins asynchronous composite. UI guidance MUST state that Blur and Pixelate are not secure for sensitive text and direct users to Redact.

### F009-R57: Non-Destructive Image Adjustments
Adjust mode provides Exposure, Contrast, Saturation, Vibrance, Temperature, Highlights, Shadows, and Sharpness. Dragging previews live; release commits the current values as one undoable `.adjust`. Repeated commits replace that single operation through undoable history `.set` entries, so the operation list does not grow; the adjustment applies source-first. Reset and hold-to-Compare are available.

### F009-R58: Raster Accessibility Semantics and Localization
Raster status messages use `RasterImageAccessibilityAnnouncing`; the canvas accessibility value includes output size and markup count; Markup mode exposes each editable item as a pressable button whose press selects it; selected tool buttons expose the selected trait. The canvas supplies VoiceOver actions to delete or move the selected item and to resize, move, apply, or cancel a crop. Raster editor user-facing strings resolve through `AppStrings.ImageEditor`.

### F009-R59: On-Device Text Recognition
Smart Tools → Recognize Text analyzes a full-resolution render with accurate Vision OCR, language correction, and automatic language detection. Results are sorted in reading order, outlined on the canvas, and presented in a selectable sheet with Copy Selected and Copy All. Text reaches the clipboard only after an explicit copy action.

### F009-R60: On-Device Background Removal
Smart Tools → Remove Background analyzes a full-resolution render with Vision foreground-instance masking and commits a grayscale mask as one undoable `.removeBackground` operation. Replay clips to the mask at display or output scale, and the geometric operation flattens earlier markup.

### F009-R61: Analysis Freshness and Transparency-Safe Save
OCR and background-removal results install only while their captured editor generation, session identity, and document revision remain current. Every image load or reload, including the same path, cancels analysis and clears OCR boxes. After background removal, overwrite Save is blocked for JPEG/JPG, BMP, and GIF (whose transparency is only 1-bit), with guidance to Export As PNG, HEIC, or TIFF. Analysis is on-device and has no network path.

### F009-R62: Cancellable Vision Requests
OCR and foreground-mask analyzer calls return a `RasterImageWorkHandle`. Cancelling it calls `VNRequest.cancel()`, prevents completion delivery, and is performed when work is superseded or the editor shuts down.

### F009-R63: Pointer-Free Raster Editing
VoiceOver users can press a markup item to select it, then invoke Delete or Move Left/Right/Up/Down. In Crop mode they can invoke Shrink Crop, Expand Crop, Move Left/Right/Up/Down, Apply Crop, and Cancel Crop without pointer input.

### F009-R64: Live Composite Freshness
A live composite may draw only when its session identity and revision match the displayed session and no markup item is being dragged. A failed live render clears any older composite rather than leaving stale pixels visible.

### F009-R65: Bounded Edit Coalescing and Adjustment Storage
Same-key markup changes coalesce only within one second and end when selection changes. The document stores at most one `.adjust`; later adjustment commits replace it in place with undoable `.set` history.

### F009-R66: Raster Editor Type Boundaries
Output, file-loading, file-observation, viewport, pixel-rendering, and markup-painting responsibilities are split into focused extensions rather than retained in their large owner types.


---

## Scenarios

### F009-S01: Image files open in image preview
Given selected file is detected as image
When preview loads
Then image is displayed with scroll support
And no text editing controls are shown
And SVG files are routed to a dedicated SVG preview host

### F009-S02: Image load failure placeholder
Given selected image cannot be loaded
When image preview renders
Then `Image Unavailable` state is shown

### F009-S03: Raster image preview supports stable pan and zoom
Given a raster image is open
When the user drags in default Pan mode or pinch/scroll-zooms
Then the viewport moves or magnifies without creating an edit
And normal preview updates do not unexpectedly recenter it

### F009-S04: Raster image preview provides editing modes and actions
Given a raster image is open
When the toolbar renders
Then a segmented control exposes Pan, Crop, Markup, and Adjust
And Undo, Redo, Smart Tools, Copy, Revert, Export As, and Save actions are present
And Markup and Adjust expose their contextual controls

### F009-S05: Safe raster image edits can be saved and reopened
Given a saveable raster image has a committed crop, markup, adjustment, or background-removal edit
When the user chooses Save or presses ⌘S
Then the composited upright image is written to disk
And reopening the file shows the saved visual state

#### Assertions for S05
- Assert edit and save write updated raster bytes.
- Assert reopening preserves upright pixels and committed edits.
- Assert save failure preserves in-memory edits for retry.

### F009-S06: Raster preview handles same-path source changes
Given a raster image is open
When its bytes change at the same file path
Then a clean preview reloads and preserves viewport context when feasible
But pending edits or a crop marquee produce a conflict instead of an automatic reload

### F009-S07: Remote raster images stage locally and save through the remote provider
Given a raster image belongs to an SSH-backed Project
When the user opens it
Then the app materializes a temporary local preview file while the remote path remains the source of truth
When the user saves safe edits
Then bytes are written through the remote file-content provider
And the staged preview baseline is refreshed

### F009-S08: Applying crop preserves and flattens in-bounds markup
Given a raster image has editable markup
And a valid crop intersects that markup
When the user applies the crop
Then the visible in-bounds result remains in cropped coordinates
And out-of-bounds pixels are removed
And the earlier markup is flattened into the geometric result
And Copy and Save composite the post-crop result

### F009-S09: Crop failure feedback is reason-specific
Given a raster image is open
When crop apply fails
Then feedback identifies no selection, invalid size, decode failure, or crop failure as applicable
And it does not report a missing selection for a different cause

### F009-S10: Image dirty state excludes a crop marquee
Given a raster image is open
When the user adds markup, adjusts color, removes a background, or applies a crop
Then image dirty state changes independently from text dirty state
But drawing a crop marquee alone does not mark a persistable edit

### F009-S11: Save failure preserves edits and permits retry
Given a raster image has unsaved edits
When save fails
Then interaction is unlocked
And the edits remain in memory
And an actionable error is shown so the user can retry

### F009-S12: Image editing controls expose stable accessibility identifiers
Given a raster image toolbar, canvas, status, or conflict banner is visible
When accessibility automation inspects it
Then controls and status elements expose stable identifiers

### F009-S13: Crop apply and cancel are keyboard reachable
Given the canvas is focused and a crop marquee exists
When the user presses Return
Then the crop is applied
When the user presses Escape
Then the marquee is cancelled

### F009-S14: Status feedback is announced to VoiceOver
Given an image edit operation succeeds or fails
When status feedback changes
Then the visible status text updates
And a distinct non-empty status posts an `NSAccessibility.announcementRequested` announcement

### F009-S15: Revert restores the current baseline
Given a raster image has unsaved edits or a crop marquee
When the user invokes Revert
Then all unsaved work is discarded
And the image returns to the last loaded or successfully saved baseline
And Undo restores the reverted committed edits

### F009-S16: Image preview handles display-backing changes
Given a raster image is open
When display backing properties change
Then centering and presentation update for the current display
And a read-only proxy may be regenerated without silently overwriting edits

### F009-S17: Raster display decode is bounded but not progressive
Given a raster image is requested
When its longest oriented edge is at most 4096 pixels
Then its display decode uses full-resolution pixels
When it is larger
Then one viewport-sized display proxy is decoded
And Save and Copy still replay edits against a fresh full-resolution decode
And no progressive placeholder-to-full-resolution transition occurs

### F009-S18: Image editing toolbar displays mode hints
Given a raster image toolbar is visible
When Pan, Crop, Markup, or Adjust is selected
Then the status line shows that mode's interaction hint
And Crop identifies Return/Apply Crop and Escape/Cancel Crop
And Blur/Pixelate directs sensitive-text obscuration to Redact

### F009-S19: PDF files open in PDF preview
Given selected file is detected as PDF
When preview loads
Then PDFKit viewer displays continuous vertically scrolling pages
And auto-scaling is enabled

### F009-S20: Remote PDFs materialize a staged local preview file for native PDF rendering
Given a PDF belongs to an SSH-backed Project
When the user opens the document
Then the app downloads the remote PDF bytes through the shared file-content provider
And the app materializes a temporary local preview file for PDFKit
And the staged preview file is cleaned up when the active document changes

### F009-S21: PDF preview background adapts to active theme
Given a PDF document is open in preview
When the active application theme changes
Then the PDF viewer background color updates to match the theme
And page content rendering remains unaffected

### F009-S22: HTML files open in editable rendered mode
Given selected file extension is `.html` or `.htm`
When file load succeeds
Then HTML source is loaded
And editable HTML rendering host is shown
And relative resources resolve against file parent directory

### F009-S23: HTML mode stores full HTML document content
Given HTML editor is active
When user edits content in iframe host
Then synchronized content includes doctype (if present) and document outer HTML
And native view model receives updated HTML source

### F009-S24: HTML mode injects base tag for relative assets
Given HTML content has no `<base>` tag and base directory is known
When content is loaded into iframe
Then a base tag is injected so relative links resolve from the document folder

### F009-S25: HTML editor supports rich/source view mode toggle
Given an HTML document is open
When the user toggles view mode
Then the editor switches between rendered rich view and raw HTML source view
And content state is preserved across toggles

### F009-S26: Find and replace is available in HTML editor
Given an HTML document is open
When the user invokes find (Cmd+F)
Then a find and replace bar appears
And search matches are highlighted in the active view

### F009-S27: HTML renderer has root-level read access for resolving local file references
Given an HTML document references local assets outside its parent directory
When content is loaded into the renderer
Then the renderer has read access scoped to the project root
And referenced local files resolve correctly

### F009-S28: HTML editor recovers from WKWebView crash
Given an HTML document is rendered in WKWebView
When the web process crashes
Then the editor detects the crash and re-renders content automatically
And no user data is lost

### F009-S29: Global text size scales HTML and SVG WebViews
Given an authored HTML document or SVG preview is visible
When global text size changes via Cmd+/Cmd=/Cmd-/Cmd0 or the View menu
Then the existing WKWebView applies the clamped global document-size ratio without reloading
And HTML editing state or SVG file state remains intact
And raster-image and PDF zoom remain controlled by their native viewers

### F009-S30: Crop maps the selected top-left pixels without inversion
Given an image has distinct pixel regions and may have non-unit or non-uniform point-to-pixel scale
When a fractional, reversed, or edge-crossing crop marquee is applied
Then minimum edges round down and maximum edges round up after independent per-axis scaling
And an edge within 1e-6 pixel of an integer snaps instead of growing by a row or column
And the rectangle is clamped to the bitmap
And a top selection crops top pixel rows without Y inversion

Coverage: `RasterImageCropGeometryTests/test_coveringPixelRect_snapsFloatingErrorInsteadOfGrowing`, `test_coveringPixelRect_usesIndependentAxisScalesForRoundedProxies`, `test_coveringPixelRect_stillRoundsGenuineFractionsOutward`, `EditableRasterImageCanvasViewTests/test_proxyCropOnOddDimensions_matchesFullResolutionCoverage`, `test_cropEachCorner_keepsThatQuadrantsPixels`, and `test_cropOnRetinaBackedImage_mapsPointsToPixels`.

### F009-S31: Every decode and export remains upright
Given a JPEG or HEIC uses any EXIF orientation from 1 through 8
When it follows the full-resolution or proxy decode path and is exported
Then each decoded result has the same upright orientation
And the export contains upright pixels with orientation 1

Coverage: `RasterImageDecoderTests/test_jpegOrientations1Through8_fullResolutionMatchesImageIOTransform`, `test_heicOrientations1Through8_fullResolutionMatchesImageIOTransform`, and `test_export_writesOrientation1AndUprightPixels`.

### F009-S32: Unsupported source fidelity is blocked without blocking Copy
Given a raster source has multiple frames, exceeds 8 bits per component, or contains an HDR gain map
When editing controls render
Then Save is disabled with the specific fidelity-loss reason
And Copy remains available
But a reduced-resolution display proxy alone does not disable Save

Coverage: `RasterImageDecoderTests` save-policy tests, `RasterImageRendererTests/test_exportFromFile_usesFullResolutionNotDisplayProxy`, and `RasterImageEditorViewModelTests/test_save_isBlockedBySavePolicy`.

### F009-S33: Only a changed crop box is pending
Given the user enters Crop mode
When the initialized box still covers the full image
Then it is not a pending crop, does not block Save, cannot be applied, and disappears after leaving Crop mode
When the user changes the box and switches modes
Then that pending box remains visible with the outside area dimmed and blocks Save
Until Return/Apply Crop commits it or Escape/Cancel Crop resets it

Coverage: `EditableRasterImageCanvasViewTests/test_enteringCropMode_showsFullImageBox_thatIsNotPending`, `test_applyingFullImageBox_isRejected`, `test_cropMarquee_isNotAPersistableEdit`, `test_returnAndEscape_forwardCropCommands`, and `RasterImageEditorViewModelTests/test_save_isBlockedWhileCropSelectionPending`.

### F009-S34: Image save routing delivers and locks one request
Given an image has committed unsaved edits
When the user presses ⌘S before or after the raster editor mounts
Then `saveActiveDocument()` leaves one pending request until the raster host acknowledges it
And that request reaches raster Save exactly once
And the canvas locks mutating interaction until Save and any post-save file reload complete

Coverage: `RasterImageEditorViewModelTests/test_saveActiveDocument_routesImagesToRasterEditor_exactlyOnce` and `test_save_rendersOffMain_locksUntilWritten_thenRebases`.

### F009-S35: External change requires an explicit conflict choice
Given an image has pending edits or a crop marquee
When the source changes on disk
Then the current work is not silently replaced
And a conflict banner offers Reload from Disk and Keep My Edits

Coverage: `RasterImageEditorViewModelTests/test_externalChangeConflict_offersReloadOrKeep`.

### F009-S36: Undo and Redo replay committed edits
Given a raster image has committed crop, markup, adjustment, or background-removal operations
When the user chooses toolbar Undo/Redo or presses ⌘Z/⇧⌘Z with the canvas in the responder chain
Then bounded history restores the corresponding operation list
And command and menu availability follows the history state
And a new edit after Undo clears Redo

Coverage: `RasterImageDocumentTests/test_history_undoRedo_andRedoInvalidation`, `test_history_isBounded`, `test_history_appendEntriesDoNotSnapshotOperations`, `EditableRasterImageCanvasViewTests/test_undoRedo_roundTripsCropAndStroke`, `test_revertIsUndoable`, and `test_undoMenuValidation_followsHistory`.

### F009-S37: Save and Copy render full resolution off the main thread
Given a file-backed image is displayed through a reduced-resolution proxy
When the user chooses Save or Copy
Then the exporter re-decodes the immutable file source at full resolution
And replays the same ordered operations on its serial background queue
And delivers the result on the main actor

Coverage: `RasterImageRendererTests/test_exportFromFile_usesFullResolutionNotDisplayProxy` and `test_exportService_deliversOnMain_andHonorsCancellation`, plus `RasterImageEditorViewModelTests/test_save_rendersOffMain_locksUntilWritten_thenRebases` and `test_copy_rendersFullResolutionToPasteboard`.

### F009-S38: A stale or post-shutdown completion cannot replace work
Given a Save output job captured one document revision and operation generation
When its result no longer matches the active session, revision, or editor generation
Then the result is rejected or ignored
And no stale bytes are submitted for persistence
And shutdown cancels work, clears busy flags, and unlocks the canvas for reuse

Coverage: `RasterImageEditorViewModelTests/test_staleRender_isDiscarded` and `test_shutdown_cancelsInFlightWork_andLeavesEditorUsable`.

### F009-S39: Async decode installs only the current request and focuses the canvas
Given raster loading is in progress
When the preview renders or a newer load supersedes the request
Then a loading placeholder is visible until decode completes
And only the latest load generation installs a result
And a newly opened image is fit to the viewport at no more than actual size
And its canvas becomes first responder unless a text field is active
And selecting another mode applies the same non-text-focus rule

Coverage: `RasterImageFilePreviewIntegrationTests/test_exifRotatedJPEG_cropAndSave_writesUprightFullResolutionCrop` exercises asynchronous installation. Load-generation supersession, fit, and conditional focus are source-grounded in `RasterImageFilePreviewCoordinator.install`, `RasterImageFilePreview.updatePreview`, and `EditableRasterImageCanvasView.focusIfPossible`.

### F009-S40: Same-size replacement and render-time changes are detected before write
Given an open raster source is atomically replaced by another file with the same size and modification date
When identity is checked before rendering or again immediately before writing
Then the changed file-resource identifier is detected
And Save presents an external-change conflict without overwriting the replacement

Coverage: `RasterImageDocumentTests/test_fileState_detectsSameSizeReplacement`, `RasterImageEditorViewModelTests/test_save_isBlockedByExternalChange_untilKeepMine`, and `test_externalChangeDuringRender_blocksWrite`.

### F009-S41: Non-text previews remain unchanged by line-number settings

Given a non-text preview is open
When the global line-number mode changes among Off, Source Editors, and All Text Views
Then no file line-number gutter is added
And the preview's own zoom, pan, page, or presentation behavior is unchanged.

### F009-S42: Crop box supports precision pointer feedback
Given Crop mode is active
When the user creates, moves, or resizes the crop box from any of its eight handles
Then the box stays within image bounds and obeys its minimum size
And a handle drag below that minimum leaves the prior anchor, ratio, and box unchanged
And the outside area is dimmed
And a rule-of-thirds grid, live W×H pixel label, and matching status line are shown

Coverage: `RasterImageCropInteractionTests/test_minimumSize_keepsAnchorAndAspect_forEveryHandle` and `EditableRasterImageCanvasViewTests/test_enteringCropMode_showsFullImageBox_thatIsNotPending`.

### F009-S43: Crop presets and keyboard adjustment are deterministic
Given a pending crop uses Freeform, Original, Square, 4:3, 3:2, or 16:9
When the user changes the preset or swaps an orientable preset to portrait
Then the crop box preserves that ratio inside image bounds
When the focused canvas receives an unmodified Arrow or Shift+Arrow
Then the box moves by one or ten export pixels respectively
And Command-, Option-, or Control-modified Arrow events are not consumed
And Escape resets it while Return applies a valid changed box

Coverage: `RasterImageCropInteractionTests/test_aspectPresets`, `test_cornerResize_withAspect_preservesRatio`, `EditableRasterImageCanvasViewTests/test_aspectRatio_constrainsCropBox`, `test_arrowKeys_nudgeCropBox`, and `RasterImageEditorViewModelTests/test_cropAspectSelection_entersCropMode_andComputesRatio`.

### F009-S44: Rotate, flip, and straighten are full-resolution undoable edits
Given a raster image has pixels and overlays
When Rotate Left/Right, Flip Horizontal/Vertical, or a non-zero Straighten is committed
Then an ordered geometric operation updates the canvas and clears an old pending crop box
And Undo/Redo restores the prior and transformed operation lists
And Straighten output has the original aspect ratio with no transparent corners
And Save/Copy/Export As replay the operation against full-resolution source pixels

Coverage: `RasterImageGeometryTests`, `EditableRasterImageCanvasViewTests/test_geometricEdit_clearsPendingMarquee`, `test_rotateClockwise_movesTopLeftToTopRight`, and `RasterImageEditorViewModelTests/test_rotateFlipStraightenResize_areUndoableGeometricEdits`.

### F009-S45: Resize commits bounded pixel dimensions
Given the Resize sheet is open
When the user enters width/height, toggles Keep proportions, or selects 25%, 50%, 75%, or 200%
Then valid changed dimensions up to 16,384 pixels per edge commit one undoable resize
And unchanged or out-of-range dimensions do not commit

Coverage: `RasterImageGeometryTests/test_resize_scalesPixels_andPreservesLayout`, `RasterImageEditorViewModelTests/test_resize_rejectsOversizeAndNoOp`, and `test_rotateFlipStraightenResize_areUndoableGeometricEdits`.

### F009-S46: Export As flattens to a separate chosen file
Given a raster image is renderable, including a source whose overwrite Save is fidelity-blocked
When the user chooses PNG, JPEG, HEIC, or TIFF, adjusts quality when offered, and selects a destination in the system save panel
Then current operations render at full resolution and encoded bytes are written atomically to that destination
And JPEG warns that transparency is dropped
And the open document source, operation list, dirty state, and baseline are unchanged
But selecting the open file directly or through a symbolic or hard link is refused

Coverage: `RasterImageGeometryTests/test_exportOptions_encodeRequestedFormatAndQuality`, `RasterImageEditorViewModelTests/test_exportAs_writesChosenFormat_withoutTouchingDocument`, `test_exportAs_ontoOpenFile_isRefused`, `test_exportAs_ontoSymlinkOfOpenFile_isRefused`, and `test_exportAs_cancelledPicker_doesNothing`.

### F009-S47: Raster navigation distinguishes fit and actual pixels
Given a raster image is open on a display with a known backing scale
When the user chooses Zoom Out, Zoom In, Zoom to Fit, Actual Size, pinch zoom, or Space-drag
Then magnification and the displayed zoom percentage update without creating an edit
And Actual Size reports 100% at one export pixel per device pixel
And Space-drag pans temporarily without changing the selected editing mode

Coverage: `RasterImageEditorViewModelTests/test_viewportCommands_forwardToViewport` and `EditableRasterImageCanvasViewTests/test_spaceKey_enablesTemporaryPan`; actual-size/backing-scale math is implemented by `RasterImageFilePreviewCoordinatorViewport`.

### F009-S48: Successful file Save installs the encoded baseline
Given a file-backed raster edit is saved successfully
When encoded bytes have been written
Then the editor remains locked while the file is decoded again
And that decoded file becomes the displayed clean session
And the next export begins from the same persisted pixels

Coverage: `RasterImageEditorViewModelTests/test_save_rendersOffMain_locksUntilWritten_thenRebases`; the post-save reload gate is `RasterImageEditorViewModel.isAwaitingPostSaveReload`.

### F009-S49: Remote polling refreshes staging without losing edits
Given a remote raster image captured its baseline token before materialization read
When polling observes a different token
Then remote bytes replace the staged preview bytes
And a clean editor reloads while a dirty editor receives Reload/Keep conflict handling
When Save discovers a mismatch, token-read failure, or missing baseline for a versioned provider
Then it fails with the remote-change error, preserves edits, and refreshes staging when possible
But a provider returning no token is trusted
And a successful later write records its new remote token

Coverage: `MarkdownViewModelRemoteImageTests/test_openCapturesBaseline_soImmediateSaveSucceeds_andTracksOwnWrite`, `test_remoteChangeAfterStaging_blocksSave_andRefreshesStagedFile`, `test_versionLookupFailure_failsClosed`, `test_missingBaseline_withVersionedProvider_failsClosed`, and `test_providerWithoutVersions_isTrusted`.

### F009-S50: Pan cursor and focus recovery do not corrupt UI state
Given the raster canvas opens or the user changes editing mode
When no text field owns focus
Then the canvas takes focus for crop, pan, and undo keys
When a pan starts or is interrupted
Then the cursor uses direct set plus cursor-rect restoration rather than an unmatched push/pop stack

Coverage: source-grounded in `EditableRasterImageCanvasView.focusIfPossible`, `beginPan`, `endPan`, and `RasterImageFilePreview.updatePreview`.

### F009-S51: Repeated geometry keeps model and pixels synchronized
Given Straighten, quarter-turn rotation, and Resize operations are committed in sequence
When the operation list is replayed for display or full-resolution output
Then each Straighten uses its committed export-pixel-snapped output size
And fixed per-axis replay scale, swapped after odd quarter turns, produces exactly `RasterImageCanvasTransform.pixelSize`

Coverage: `RasterImageGeometryTests/test_repeatedStraighten_keepsModelAndRenderedPixelsInSync` and `test_fixedScaleReplay_onOddProxy_tracksCanonicalSize`.

### F009-S52: Undo and Redo fail transactionally
Given an Undo or Redo target contains geometric operations
When rendering that target fails
Then the command returns false
And the document, rendered pixels, and undo/redo availability remain unchanged

Coverage: `RasterImageDocumentTests/test_undo_whenTargetFailsToRender_leavesStateUntouched`.

### F009-S53: Append history remains compact
Given more edits are appended than the configured history limit
When history records those edits
Then each ordinary append is represented by a remove-last count rather than an operation-list snapshot
And Revert uses one prior-list snapshot
And retained history memory is O(limit) entries rather than O(limit × operation count)

Coverage: `RasterImageDocumentTests/test_history_appendEntriesDoNotSnapshotOperations` and `test_history_isBounded`.

### F009-S54: Atomic raster writes do not block UI state
Given local Save, Export As, or remote staging has encoded bytes to persist
When atomic disk writing begins
Then the write runs on `RasterImageEditorServices.ioQueue` or a detached task
And completion returns to the main actor
And editor-owned local Save/Export completion cannot install after its generation becomes stale

Coverage: `RasterImageEditorViewModelTests/test_localSave_writesOffMainThenFinishes`; remote staging is source-grounded in `MarkdownViewModel.writeOffMain`.

### F009-S55: Modified canvas keys remain available to shortcuts
Given the raster canvas has focus
When Space or an Arrow key arrives with Command, Option, or Control
Then temporary pan and crop nudge do not consume or act on the event
But unmodified Space pans and unmodified/Shift Arrow nudges still work

Coverage: `EditableRasterImageCanvasViewTests/test_modifiedSpaceAndArrows_areNotConsumed`, `test_spaceKey_enablesTemporaryPan`, and `test_arrowKeys_nudgeCropBox`.

### F009-S56: Markup exposes the implemented tool palette
Given Markup mode is selected
When its tool palette renders
Then Select, Pen, Line, Arrow, Rectangle, Ellipse, Highlight, Text, Blur, Pixelate, and Redact are available
And selecting a tool exposes its localized hint and selected accessibility trait

Coverage: `RasterImageEditorViewModelTests/test_toolSelection_entersMarkupMode_andShowsHint`; tool enumeration and selected traits are source-grounded in `RasterMarkupTool` and `RasterImageMarkupToolbar`.

### F009-S57: Markup objects remain editable until geometry flattens them
Given one or more markup items follow the last geometric operation
When the user selects, moves, resizes, nudges, edits, cycles, or deletes an item
Then the item changes through undoable set/remove history
And repeated nudges, typing, or same-property inspector changes coalesce only within one second and the current selection
When a later crop, rotate, flip, straighten, resize, or background removal commits
Then the visual result is preserved but earlier markup is flattened and no longer selectable
And Undo restores the pre-geometry editable state

Coverage: `EditableRasterImageCanvasViewTests/test_rectangleTool_createsSelectsAndMovesItem`, `test_selectTool_resizesWithHandle_andClickOnEmptyDeselects`, `test_keyboard_deleteNudgeTabEscape`; `RasterImageMarkupTests/test_updateAndDeleteMarkup_areUndoable`, `test_coalescedUpdates_formOneUndoStep`, and `test_markupBeforeGeometricEdit_isFlattenedAndNoLongerEditable`.

### F009-S58: Pixel effects and Redact produce scale-consistent output
Given markup covers visible image detail
When Blur or Pixelate is added
Then it processes the composited pixels underneath and the asynchronous display composite tracks the latest revision
When Redact is added and output is rendered
Then its opaque fill replaces the covered pixels
And the UI warns that Blur and Pixelate are not secure substitutes for Redact

Coverage: `RasterImageMarkupTests/test_redact_isOpaque_andUnderlyingPixelsAreGone`, `test_pixelate_replacesDetailWithinRectOnly`, `test_blurUsesPixelsComposedSoFar_includingEarlierMarkup`, `test_proxyAndFullResolutionMarkupMatch`, and `EditableRasterImageCanvasViewTests/test_pixelEffect_usesAsyncComposite`.

### F009-S59: Adjustments preview live and remain compact
Given Adjust mode is active
When the user repeatedly drags and commits adjustment sliders
Then the canvas previews intermediate values without committing each one
And the document retains one `.adjust` operation replaced through undoable `.set` history
And Undo steps through prior committed adjustment states without operation-list growth
And Reset restores identity while Compare temporarily shows the unadjusted source

Coverage: `RasterImageEditorViewModelTests/test_adjustments_previewThenCommitOnce_andReset`; `RasterImageMarkupTests/test_onlyLastAdjustCounts`, `test_sessionAdjust_rerendersFlattenedDisplay_andUndoRestores`, and `test_exportAppliesAdjustmentsAtFullResolution`.

### F009-S60: Markup and status expose accessible state
Given a raster image and markup items are visible
When accessibility inspects the editor
Then the canvas value reports image size and markup count
And each editable markup item exposes a labeled pressable button whose press selects it
And selected markup tools expose the selected trait
When a distinct action status changes
Then it is announced through the injected accessibility announcer

Coverage: `EditableRasterImageCanvasViewTests/test_accessibility_exposesMarkupItems` and `RasterImageEditorViewModelTests/test_statusMessages_areAnnounced`.

### F009-S61: Recognize Text returns selectable reading-order lines
Given a raster document is renderable
When the user chooses Smart Tools → Recognize Text
Then current operations render at full resolution before on-device Vision OCR
And found lines are sorted top-to-bottom and left-to-right, outlined on the canvas, and shown in a selectable sheet
And only Copy Selected, Copy All, or a per-line Copy writes recognized text to the clipboard

Coverage: `RasterImageVisionTests/test_recognizeText_findsLinesInReadingOrder_withTopLeftBoxes`, `test_recognizeText_onBlankImage_reportsNoText`, and `RasterImageEditorViewModelTests/test_recognizeText_analyzesFullResolution_presentsAndCopies`.

### F009-S62: Stale recognition cannot annotate changed pixels
Given text recognition is in flight
When the editor generation, session identity, or document revision no longer matches its analysis token
Then the result is discarded
And a stale active-session result reports that the image changed during analysis
When any image load or reload installs a session, including at the same path
Then in-flight analysis is cancelled and its text list and canvas boxes are cleared

Coverage: `RasterImageEditorViewModelTests/test_recognizeText_staleResultIsDiscarded`, `test_recognizedText_isClearedWhenDocumentChanges`, and `test_shutdownDuringAnalysis_ignoresResult`.

### F009-S63: Remove Background is scale-independent and undoable
Given Vision finds one or more foreground instances
When the user chooses Smart Tools → Remove Background
Then a grayscale mask becomes one undoable operation
And pixels outside the mask are transparent at display and output scales
And earlier markup is flattened into the masked result

Coverage: `RasterImageVisionTests/test_removeBackground_makesMaskedOutPixelsTransparent_atAnyScale`, `test_removeBackground_flattensEarlierMarkup_andIsUndoable`, and `RasterImageEditorViewModelTests/test_removeBackground_commitsUndoableMask`.

### F009-S64: Transparency-unsafe overwrite is blocked
Given background removal has introduced transparency
And the open file is JPEG/JPG, BMP, or GIF
When Save availability is evaluated
Then overwrite Save is disabled with guidance to Export As PNG, HEIC, or TIFF
And Export As remains available

Coverage: `RasterImageEditorViewModelTests/test_removeBackground_onJPEG_blocksSave_butAllowsExport` and `test_removeBackground_onGIF_blocksSave`; the gate is `RasterImageEditorViewModel.formatsWithoutAlpha`.

### F009-S65: Same-file reload invalidates Vision state
Given OCR or background removal belongs to the currently displayed session
When that image reloads, even at the same path and revision number
Then the Vision work handle is cancelled
And OCR boxes and text are cleared
And a late result cannot install into the replacement session

Coverage: `RasterImageEditorViewModelTests/test_reloadingTheSameFile_cancelsAnalysis_andClearsOCR` and `test_backgroundMaskForReplacedSession_isNotApplied`.

### F009-S66: Cancelling Vision suppresses completion
Given a Vision OCR or foreground-mask request is queued or running
When its returned work handle is cancelled or the editor shuts down
Then `VNRequest.cancel()` is invoked
And the cancelled request does not call its completion.

### F009-S67: VoiceOver operates markup and crop
Given VoiceOver is navigating the raster canvas
When a markup item is pressed
Then it becomes selected and Delete or directional Move actions can edit it
When Crop mode is active
Then Shrink, Expand, directional Move, Apply, and Cancel actions make crop pointer-independent.

Coverage: `EditableRasterImageCanvasViewTests/test_accessibility_itemsArePressable_andCustomActionsOperate`.

### F009-S68: Live composite cannot ghost edits
Given an asynchronous adjustment or pixel-effect composite exists
When the session or revision changes, a markup drag begins, or a replacement render fails
Then the stale composite is not drawn
And drag preview appears once rather than over its baked copy
And a render failure clears the previous composite.

Coverage: `EditableRasterImageCanvasViewTests/test_liveComposite_isNotUsedWhileDraggingAnItem`.

### F009-S69: Coalescing has time and selection boundaries
Given repeated edits use the same coalescing key
When more than one second passes or the selected item changes
Then the next edit starts a new undo step.

Coverage: `RasterImageDocumentTests/test_coalescing_endsAfterWindowOrExplicitBoundary`.

### F009-S70: Repeated adjustment commits keep one operation
Given several adjustment states are committed
When the operation list and Undo history are inspected
Then exactly one `.adjust` remains
And Undo restores earlier values through `.set` inverses.

Coverage: `RasterImageEditorViewModelTests/test_repeatedAdjustments_keepOneOperation_andUndoStepsBack`.

### F009-S71: Final raster types have focused extensions
Given the raster editor implementation is maintained
When output, loading, observation, viewport, pixel, or markup behavior changes
Then it resides in the corresponding focused extension file rather than enlarging the owner type.


## Change History

- 2026-10-01: Documented final audit fixes for analysis/session cancellation, GIF alpha safety, pointer-free VoiceOver editing, live-composite freshness, bounded coalescing, compact adjustments, type splits, and known output/save limitations; reported full suite: 1,683 tests, 0 failures.
- 2026-10-01: Documented Phase 3 markup, adjustments, history coalescing, and accessibility, plus Phase 4 on-device OCR and background removal.

- 2026-10-01: Documented Phase 2 audit fixes: canonical pixel geometry, fail-closed remote versioning, alias-safe Export As, stable minimum crop drags, transactional compact history, off-main atomic writes, shortcut coexistence, and remaining localization.
- 2026-10-01: Documented Phase 1 audit fixes: covering crop snapping, lifecycle generation invalidation, pre-write identity recheck, persisted-file reload, remote token safety, exact-once ⌘S, focus/cursor behavior, main-actor previews, and localized save errors.
- 2026-10-01: Documented Phase 2 precision crop, aspect presets, geometric operations, resize, Export As, and navigation controls.
- 2026-10-01: Documented Phase 1 non-destructive operations/history, full-resolution background output, revision checks, asynchronous decode, service injection, and file identity checks.
- 2026-10-01: Documented Phase 0 raster crop, orientation, overwrite-safety, save-routing, baseline, and conflict fixes; recorded accessibility and progressive-loading limits.
