---
title: "File Previews"
feature: "F009"
domain: "editor"
audience: "user"
version: "1.0"
sidebar:
  label: "Previews"
  order: 2
---

# File Previews

## Overview

File Previews provides viewing and basic editing for images, PDFs, and HTML files within Crispy. Raster images support pan, zoom, crop, draw, and annotate operations. PDFs render in a continuous scrolling viewer. HTML files open in an editable rendered mode with relative asset resolution.

## Getting Started

1. Click any image, PDF, or HTML file in the file explorer.
2. The file opens in the appropriate preview mode automatically.
3. For images, use the editing toolbar to crop, draw, or annotate.
4. For HTML, edit directly in the rendered view or switch to source mode.

## Workflows

### Viewing Images

1. Click an image file (PNG, JPG, GIF, WebP, etc.) in the explorer.
2. The image opens in a scrollable preview with no text editing controls.
3. Pan by dragging and pinch-zoom to inspect details.
4. SVG files route to a dedicated SVG preview host.
5. If the image cannot be loaded, an "Image Unavailable" state is shown.

### Editing Raster Images

1. Open a raster image and access the editing toolbar.
2. Available actions: **Clip/Copy**, **Crop**, **Draw**, **Annotate**.
3. **Crop**: Select a region and apply. In-bounds overlays are preserved; out-of-bounds overlays are removed.
4. **Draw**: Freehand drawing on the image surface.
5. **Annotate**: Place configurable text with font-family and size controls.
6. Edits do not break pan/zoom interaction.
7. Save edits to disk — the composited image is written and visible on reopen.
8. Use **Clear Edits** to revert to the original loaded state.

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
2. Edits are written back to the SSH source on save.
3. Remote PDFs are downloaded and staged locally for PDFKit rendering.
4. Staged files are cleaned up when the active document changes.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Find (HTML) | ⌘F |
| Replace (HTML) | ⌘⇧H |
| Save image edits | ⌘S |

## Settings

- **Theme**: PDF background and HTML rendering adapt to the active application theme.
- **Large File Threshold**: Files exceeding the configured size (default 10 MB for remote) prompt before downloading.

## Tips

- Image preview preserves your pan and zoom context during normal preview updates and when the source file changes on disk.
- Image thumbnails load progressively — a low-resolution placeholder appears first, then the full-resolution version.
- Each editing mode (crop, draw, annotate) shows a contextual hint in the toolbar.
- Image edit dirty state is tracked independently from text document dirty state.
- If a crop fails, the error message reflects the actual failure reason (not a generic "select area" message).
- Display backing property changes (e.g., moving between Retina and non-Retina displays) trigger re-rendering at the appropriate scale.
- HTML files store full document content including doctype on save.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Image Unavailable" shown | The image file may be corrupted or in an unsupported format. Try opening it in Preview.app to verify. |
| Image edits lost after save failure | In-memory edits are preserved on save failure. Retry the save operation. |
| HTML assets not loading | Ensure referenced files exist relative to the HTML file's parent directory or project root. |
| PDF appears blank | The file may be corrupted. Try opening in Preview.app. For remote PDFs, check SSH connection status. |
| HTML editor crash | The WKWebView auto-recovers from crashes by re-rendering content. No data is lost. |
| Crop shows unexpected error | Check the error message — it distinguishes between no selection, invalid selection, and decode failures. |
