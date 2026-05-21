# Previews — Technical Design

## Overview

Previews covers raster image editing (4 canvas modes), SVG read-only preview, PDF viewing, and the image persistence pipeline. Raster images use `EditableRasterImageCanvasView` with pan, crop, draw, and annotate modes. SVG uses a `WKWebView` with JavaScript disabled. PDF uses native `PDFKit`.

## Architecture

### Raster Image Canvas

`EditableRasterImageCanvasView` — scrollable, zoomable canvas with four editing modes:

| Mode | Behavior |
|------|----------|
| **Pan** | Default. Drag to scroll, pinch to zoom. Zoom range: 0.1× to 10×. |
| **Crop** | Drag to draw rectangular selection. "Apply Crop" commits. Minimum crop size: 2×2 pixels. In-bounds strokes and annotations preserved and repositioned; out-of-bounds removed. |
| **Draw** | Freehand drawing. Strokes: system green (88% opacity), 2.2pt line width, round joins and caps. |
| **Annotate** | Click to place text annotation bubble. Configurable: text, font family (any system font), font size (8–72pt, default 14). Rendered as orange rounded-rectangle bubbles with white text. |

### Toolbar

Mode buttons (Crop, Draw, Annotate), Apply Crop, Save, Clear. Status line shows mode hint or action feedback. Annotate mode adds controls for text, font family, and font size.

### SVG Preview

SVG files rendered read-only in `WKWebView` with JavaScript disabled. No editing canvas.

### PDF Preview

`PDFView` with single-page continuous vertical display and auto-scaling.

## Data Flow

### Image Persistence

Saving composites all edits (strokes + annotations) onto the working image and writes to disk via `RasterImagePersistence`.

| Format | Compression |
|--------|-------------|
| JPEG (`.jpg`, `.jpeg`) | Quality 0.92 |
| HEIC (`.heic`) | Quality 0.90 |
| HEIF (`.heif`) | Quality 0.90 |
| WebP (`.webp`) | Quality 0.90 |
| PNG (`.png`) | Lossless |
| GIF (`.gif`) | Lossless |
| BMP (`.bmp`) | Lossless |
| TIFF (`.tif`, `.tiff`) | Lossless |

After saving, the composited image becomes the new working image and all transient edits are cleared.

### File Observation

Raster image preview monitors the file on disk using a `DispatchSource` file system observer. External changes (write, extend, rename, delete) trigger automatic reload. If the image had pending edits when reloaded, a feedback message is shown.

## State Management

### Dirty State

`hasUnsavedImageEdits` tracked independently from `hasUnsavedTextChanges`. Saving clears only the image dirty flag.

### Edit Lifecycle

- Edits (crop, draw, annotate) applied to in-memory working image.
- Clear action reverts to original loaded state.
- Save failure preserves in-memory edits for retry.

## API / Command Contracts

- `RasterImagePersistence` — format-aware image encoding and disk write.
- `DispatchSource` file observer — monitors source file for external changes.

## Dependencies (frameworks, libraries)

- `EditableRasterImageCanvasView` — raster canvas with editing modes
- `RasterImagePersistence` — format-specific image encoding
- `WKWebView` — SVG rendering (JavaScript disabled)
- `PDFKit` / `PDFView` — PDF rendering
- `DispatchSource` — file system observation

## Platform Considerations

- SVG: `WKWebView` with JavaScript disabled for security.
- PDF: native `PDFKit` with continuous vertical scrolling.
- Image canvas supports macOS pinch-to-zoom and scroll gestures.
- Display backing property changes trigger re-render at appropriate scale.

## Performance Constraints

- Zoom range clamped to 0.1×–10× to bound memory usage.
- Minimum crop size 2×2 pixels to prevent degenerate operations.
- File observation uses `DispatchSource` (kernel-level, low overhead).
