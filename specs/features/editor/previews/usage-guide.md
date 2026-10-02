---
title: "File Previews"
feature: "F009"
domain: "editor"
audience: "user"
version: "1.5"
sidebar:
  label: "Previews"
  order: 2
---

# File Previews

## Overview

File Previews provides viewing and editing for images, PDFs, and HTML files within Crispy. Raster images support navigation, precise crop and geometry, editable markup, color adjustments, on-device text recognition, and background removal. PDFs render in a continuous scrolling viewer. HTML files open in an editable rendered mode with relative asset resolution.

## Getting Started

1. Click any image, PDF, or HTML file in the file explorer.
2. The file opens in the appropriate preview mode automatically.
3. For raster images, choose **Pan**, **Crop**, **Markup**, or **Adjust** from the segmented toolbar control.
4. For HTML, edit directly in the rendered view or switch to source mode.

## Workflows

### Viewing Images

1. Click an image file (PNG, JPG, GIF, WebP, etc.) in the explorer.
2. A loading message appears while the image decodes, then the image opens with **Zoom to Fit** selected automatically. The fit view never enlarges beyond actual pixel size.
3. **Pan** is selected by default. Drag to pan, pinch to zoom, or use the −/+ zoom buttons.
4. Open the zoom percentage menu for **Zoom to Fit** or **Actual Size**. At 100%, one image pixel maps to one device pixel, including on Retina displays.
5. Hold **Space** and drag to pan temporarily while Crop, Markup, or Adjust remains selected.
6. SVG files use a dedicated SVG preview. If an image cannot be loaded, an “Image Unavailable” state is shown.

### Editing Raster Images

Use the mode control and actions in the raster toolbar:

- **Pan**: drag to move around the image.
- **Crop**: precisely frame a region as described below.
- **Markup**: create and edit pen strokes, lines, arrows, shapes, highlights, text, blur, pixelation, or opaque redaction.
- **Adjust**: change exposure, contrast, saturation, vibrance, temperature, highlights, shadows, or sharpness.
- **Undo/Redo** or **⌘Z/⇧⌘Z**: move through committed crop, markup, adjustment, background-removal, rotation, flip, straighten, and resize edits. If an older state cannot be rendered, Crispy leaves the image and history unchanged.
- **Copy**: render current edits at full source resolution to the clipboard.
- **Revert**: return to the last loaded or successfully saved image. Revert is undoable.

All committed edits are non-destructive until Save: Crispy stores ordered edit operations and replays them at full resolution for output. Any rotate, flip, straighten, resize, applied crop, or background removal clears an uncommitted crop box because the canvas geometry has changed. A geometric edit also flattens earlier markup into pixels, so finish object edits first.

### Adding and Editing Markup

1. Select **Markup**, then choose **Select**, **Pen**, **Line**, **Arrow**, **Rectangle**, **Ellipse**, **Highlight**, **Text**, **Blur**, **Pixelate**, or **Redact**.
2. Drag to create items; click an existing item to select it. Drag the item to move it, use its eight handles to resize a rectangular item, or drag line/arrow endpoint handles.
3. Hold Shift while drawing to snap lines/arrows to 45° steps or create square boxes; hold Shift during handle resize to preserve the item's proportions.
4. Use the inspector to choose stroke color, sample a screen color with the eyedropper, enable and choose fill, set width, or edit text/font/size. Changes affect the selected item and become defaults for new items.
5. Press Tab or Shift+Tab to cycle items, Arrow keys to nudge by 1 pixel, Shift+Arrow to nudge by 10, Delete to remove, or Escape to deselect. Double-click a text item to focus its text field. Rapid changes coalesce into one Undo step only while they stay within one second and the same selection.

**Highlight** uses a translucent multiply blend. **Blur** and **Pixelate** process the image detail underneath, but they are not secure ways to hide sensitive information. Use **Redact** for an opaque exported replacement, and verify the exported result before sharing.

### Adjusting Color

1. Select **Adjust**.
2. Drag **Exposure**, **Contrast**, **Saturation**, **Vibrance**, **Temperature**, **Highlights**, **Shadows**, or **Sharpness**. The canvas previews changes while you drag and records one undoable change when you release.
3. Hold **Compare** to view the source without adjustments.
4. Select **Reset Adjustments** to return all adjustment values to their defaults. Reset is undoable.

Adjustments are applied before crop, rotation, and markup, so they remain effective after later geometry changes. Crispy keeps one adjustment operation and replaces it on each commit; Undo still restores each prior committed value without growing the operation list.

### Cropping Precisely

1. Select **Crop**. A full-image box appears with eight handles, a dimmed outside region, a rule-of-thirds grid, and live width × height in pixels.
2. The untouched full-image box is only a starting guide: it does not block Save, cannot be applied, and disappears if you leave Crop mode.
3. Drag outside the box to create a new box, drag inside a changed box to move it, or drag any corner/edge handle to resize it. If a handle step would make either edge smaller than 2 export pixels, the box stays unchanged so its anchor and ratio do not jump.
4. Choose **Freeform**, **Original**, **Square**, **4:3**, **3:2**, or **16:9** from the aspect menu. Use **Swap Orientation** for portrait/landscape on Original, 4:3, 3:2, or 16:9.
5. With the canvas focused, use an Arrow key to move the box by 1 pixel or Shift+Arrow to move it by 10 pixels.
6. Press **Return** or select **Apply Crop** to commit. Press **Escape** or select **Cancel Crop** to reset to the starting box.

A changed crop remains visible if you switch modes and blocks overwrite Save until it is applied or reset.

### Rotating, Flipping, and Straightening

The geometry controls appear in the Crop toolbar row:

1. Use **Rotate Left** or **Rotate Right** for a 90° turn.
2. Use **Flip Horizontal** or **Flip Vertical** to mirror the image.
3. Drag **Straighten** from −45° to +45°. The canvas previews the rotation with a rule-of-thirds grid.
4. Release the slider to commit. Crispy snaps the resulting same-aspect crop to export pixels, so repeated Straighten/Rotate/Resize edits keep the displayed dimensions aligned with saved output and have no transparent corners.
5. Use Undo/Redo to reverse or restore any geometry action.

### Resizing an Image

1. Select **Resize…** from the Crop toolbar row.
2. Enter pixel width and height. Leave **Keep proportions** enabled to update the other dimension automatically.
3. Optionally select **25%**, **50%**, **75%**, or **200%**.
4. Select **Resize** to commit an undoable operation.

Each edge must be from 1 through 16,384 pixels. Entering the current dimensions makes no change.

### Saving the Open Image

Choose **Save** or press **⌘S** to render at full source resolution and overwrite the open source. A shortcut request is delivered once even if the image editor is still mounting. Rendering and atomic disk writing run away from the UI thread; editing stays locked until completion and, for file sources, until Crispy re-decodes the written bytes. The clean display then matches the persisted pixels used by the next export.

Save is disabled, with an explanation in the status line, when:

- a changed crop box still needs to be applied or reset;
- the source has multiple frames or pages;
- the source uses more than 8 bits per component;
- the source contains an HDR gain map that would be lost; or
- background removal introduced transparency but the open file is JPEG/JPG, BMP, or GIF (GIF transparency is only 1-bit).

For fidelity-protected or transparency-unsafe images, **Copy** and **Export As…** still work. After background removal, choose PNG, HEIC, or TIFF to preserve transparency. A reduced-resolution display proxy never reduces saved, copied, or exported dimensions because output re-reads full-resolution source pixels.

### Exporting a Separate Flattened Copy

1. Select **Export As…**.
2. Choose **PNG**, **JPEG**, **HEIC**, or **TIFF**.
3. For JPEG or HEIC, adjust **Quality**. JPEG also warns that it cannot preserve transparency.
4. Select **Choose Location…**, then choose a destination in the macOS save panel.

Export As renders all current edits at full resolution but does not Save, rebase, or clear the open document. It refuses the currently open file even when selected through a symbolic or hard link—use Save for that. Export As remains available when overwrite Save is blocked, making it the explicit way to flatten a multi-frame, high-bit-depth, or HDR/gain-map source into a separate supported image.

### Resolving an External-Change Conflict

If a local or remote image changes while you have edits or a changed crop box, Crispy keeps your work and shows a conflict banner:

- **Reload from Disk** discards your pending work and loads the external version.
- **Keep My Edits** retains your working image and accepts the observed version as the overwrite baseline.

Save checks local file identity both before rendering and immediately before writing. For remote images, Crispy records a version before downloading and checks it before upload. A changed token, failed token lookup, or missing recorded token for a versioned provider blocks Save and keeps your edits; providers without token support are trusted. After Crispy writes successfully, the returned token becomes the new baseline. Because remote checking and writing are separate operations, very fast same-size remote changes can still evade coarse SFTP timestamps.

### Using Smart Tools

Open the **Smart Tools** menu in the raster toolbar.

#### Recognize Text

1. Choose **Recognize Text**. Crispy renders the current image at full resolution and analyzes it on-device with Apple Vision; the image is not uploaded.
2. Found text lines are outlined on the canvas and listed in reading order in the **Recognized Text** sheet.
3. Select list rows and choose **Copy Selected**, choose **Copy All Text**, or use a line's context-menu **Copy**. Text enters the clipboard only when you choose a copy action.
4. Editing or reloading the image clears the results because their boxes no longer match the document. Reloading—even the same file—cancels the Vision request; cancelled work cannot present a late result. If another document change makes a result stale, retry after the status message.

#### Remove Background

1. Choose **Remove Background**. Crispy analyzes the full-resolution current image on-device and keeps detected foreground subjects.
2. The result is one undoable edit with transparency outside the generated mask. Earlier markup is flattened into the result.
3. For PNG sources, normal Save can preserve the result. JPEG/JPG, BMP, and GIF cannot overwrite after this edit; use **Export As…** and choose PNG, HEIC, or TIFF.

### Using VoiceOver with Markup and Crop

- In Markup mode, each editable item is a button. Press it to select the item, then use the canvas custom actions **Delete**, **Move Left**, **Move Right**, **Move Up**, or **Move Down**.
- In Crop mode, use **Shrink Crop**, **Expand Crop**, the four **Move** actions, **Apply Crop**, or **Cancel Crop**. Crop is fully operable without a pointer.

### Viewing PDFs

1. Click a PDF file in the explorer.
2. The PDF opens in a PDFKit viewer with continuous vertical scrolling.
3. Auto-scaling is enabled for comfortable reading.
4. The background adapts to your active theme without affecting page content.

### Editing HTML Files

1. Open an `.html` or `.htm` file from the explorer.
2. The file renders in an editable mode with relative resources resolving against the file's parent directory.
3. A base tag is injected for relative asset resolution.
4. Edit content directly in the rendered view.
5. Toggle to source view to edit raw HTML (content preserved across toggles).
6. Use ⌘F for find and replace with match highlighting.
7. The renderer has read access scoped to the project root for resolving local file references.

### Working with Remote Files

1. Remote raster images are staged as local preview files for native rendering.
2. Safe edits are written back to the SSH source on Save or ⌘S.
3. Remote PDFs are downloaded and staged locally for PDFKit rendering.
4. Staged files are cleaned up when the active document changes.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Undo committed image edit | ⌘Z |
| Redo committed image edit | ⇧⌘Z |
| Move a pending crop by 1 pixel | Arrow keys |
| Move a pending crop or selected markup by 10 pixels | Shift+Arrow keys |
| Move selected markup by 1 pixel | Arrow keys |
| Select next/previous markup item | Tab / Shift+Tab |
| Delete selected markup item | Delete or Forward Delete |
| Apply a valid changed crop while canvas is focused | Return |
| Reset a crop or deselect markup while canvas is focused | Escape |
| Temporarily pan in any image mode | Hold unmodified Space and drag |
| Save committed image edits | ⌘S |
| Find (HTML) | ⌘F |
| Replace (HTML) | ⌘⇧H |

## Settings

- Raster ratio labels, percentages, format names, controls, and status text follow the app's localization.
- **Theme**: PDF background and HTML rendering adapt to the active application theme.
- **Large File Threshold**: Files exceeding the configured size (default 10 MB for remote) prompt before downloading.

## Tips

- Image preview preserves pan and zoom context during normal updates when feasible; opening a new image focuses the canvas unless you are typing in a text field.
- Authored HTML, compiled AsciiDoc HTML, and SVG previews follow global text size via **⌘+** or **⌘=**, **⌘-**, and **⌘0** without reloading. Raster images and PDFs keep their own magnification behavior.
- Raster images up to 4096 pixels on their longest edge display at full resolution. Larger images use one display proxy, but Save and Copy re-read the full-resolution source; progressive loading is not currently available.
- The toolbar status line explains the current mode, save restriction, or action result and announces changed action statuses to VoiceOver.
- Blur and Pixelate are visual effects, not secure redaction. Use **Redact** for sensitive text and verify the exported file.
- The initial full-image crop box is not pending. A changed crop box is a pending selection, not a committed edit, until applied.
- Command-, Option-, or Control-modified Space/Arrow events are left to app and system shortcuts rather than activating image pan or crop nudge.
- Image dirty state is tracked independently from text document dirty state.
- Display backing changes update image centering and presentation.
- HTML files store full document content including doctype on save.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Loading message remains shown | Decode is still running or the source is unusually large. Wait for completion; switching files safely supersedes the older request. |
| "Image Unavailable" shown | The image file may be corrupted or unsupported. Try opening it in Preview.app to verify. |
| Save is disabled | Read the toolbar status. Apply/reset a changed crop, resolve an external-change conflict, or use Copy/Export As when source fidelity or background-removal transparency prevents overwrite. |
| Image edits remain after save failure | This is intentional. Correct the reported file error and retry Save. |
| External-change banner shown | Choose Reload from Disk to discard your work, or Keep My Edits to retain it. Remote conflicts refresh the staged bytes before you decide. |
| Crop selects the wrong area after updating | Reopen the source and retry. Phase 0 uses top-left pixel mapping and normalized orientation; report the format and EXIF orientation if the issue persists. |
| HTML assets not loading | Ensure referenced files exist relative to the HTML file's parent directory or project root. |
| PDF appears blank | The file may be corrupted. Try opening in Preview.app. For remote PDFs, check SSH connection status. |
| HTML editor crash | The WKWebView auto-recovers from crashes by re-rendering content. No data is lost. |

## Known Limitations

- Image loading is not progressive; one loading state is replaced by the completed display image.
- A crop, rotate, flip, straighten, resize, or background-removal edit flattens earlier markup. Its appearance is preserved, but it cannot be selected or edited unless you Undo the geometric edit.
- Save and Export As create one upright 8-bit RGB frame. They do not preserve EXIF/IPTC/GPS or ICC beyond the working color space, and there is no layered Save As format such as PSD.
- Multi-frame, greater-than-8-bit, and HDR gain-map sources cannot overwrite the original; Export As creates a flattened single-image copy instead.
- Local Save has a small remaining race between its final identity check and atomic write. Remote SFTP has no compare-and-swap, and same-size changes within its one-second mtime resolution can evade conflict detection.
- Full-resolution Save/Copy/OCR/background removal can use substantial memory for very large sources. Vision requests are cancellable, but already-allocated framework buffers may persist briefly.
- A legacy synchronous canvas save API remains for standalone use/tests; Crispy's app save path uses the asynchronous editor services.
