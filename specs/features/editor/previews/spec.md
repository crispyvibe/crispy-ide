# F009 Previews

**Domain:** Editor
Status: draft

---

## Requirements

### F009-R01: Image Opening and Load States
Image files open in a scrollable image preview with no text editing controls. SVG files route to a dedicated SVG preview host. Load failures show an unavailable state.

### F009-R02: Image Preview Interaction
Raster image preview preserves user pan and pinch-zoom context during normal preview updates.

### F009-R03: Basic Image Editing
Raster image preview exposes clip/copy, crop, draw, and annotate actions. Annotate mode provides configurable text input with font-family and size controls. Edits do not break pan/zoom.

### F009-R04: Image Edit Save and Reopen
Composited edited images can be saved to disk and reopened with saved edits visible.

### F009-R05: Image Source File Change Handling
Preview reloads when source image bytes change on disk at the same path, preserving pan/zoom context.

### F009-R06: Remote Image Staging
Remote raster images stage a local preview file; edits are written back to the SSH source on save.

### F009-R07: Crop Overlay Preservation
Crop operations preserve in-bounds draw strokes and text annotations; out-of-bounds overlays are removed.

### F009-R08: Crop Failure Feedback
Crop failure feedback is reason-specific and does not imply missing selection when the cause is different.

### F009-R09: Image Edit Dirty State
Image edit dirty state is tracked independently from text document dirty state.

### F009-R10: Image Edit Save Failure Recovery
Save failure preserves in-memory edits, allows retry, and shows an actionable error message.

### F009-R11: Image Editing Accessibility
All editing controls expose stable accessibility identifiers. Save/apply/cancel are keyboard reachable. Status feedback is announced through accessibility APIs.

### F009-R12: Clear Edits Action
Clear edits reverts the image to its original loaded state.

### F009-R13: Display Backing Properties Change
Image preview re-renders at appropriate backing scale when display properties change.

### F009-R14: Thumbnail Progressive Loading
Thumbnails load progressively with a low-resolution placeholder first.

### F009-R15: Editing Mode Toolbar Hints
Each editing mode (crop, draw, annotate) shows a contextual hint in the toolbar.

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

### F009-S03: Raster image preview preserves user pan and pinch-zoom context
Given a raster image is open in preview mode
When the user pans or pinch-zooms the image
Then the viewport does not recenter unexpectedly during normal preview updates
And pinch-zoom in/out remains available

### F009-S04: Raster image preview provides basic editing controls
Given a raster image is open in preview mode
When the user opens image editing controls
Then the viewer exposes basic actions for clip/copy, crop, draw, and annotate
And annotate mode provides configurable text input with font-family selection and size controls before placement
And edits are applied to the in-view working image without breaking pan/zoom interaction

### F009-S05: Raster image edits can be saved and reopened
Given a raster image is open in preview mode
And user has applied one or more edits (crop, draw, or annotate)
When user saves image edits
Then composited edited image is written to disk
And reopening the same file shows the saved edits

#### Assertions for S05
- Assert edit + save writes updated raster bytes to disk.
- Assert reopening the same file renders the saved visual state.
- Assert save failure preserves in-memory edits and reports failure.

### F009-S06: Raster preview refreshes when source file changes at same path
Given a raster image is open in preview mode
When source image bytes change on disk at the same file path
Then preview reloads updated content without requiring project switch
And viewer preserves pan/zoom context when feasible

#### Assertions for S06
- Assert same-path file content changes refresh the active preview.
- Assert user does not need project switching to observe refreshed image.
- Assert pan/zoom context is preserved when dimensions allow.

### F009-S07: Remote raster images stage a local preview file and write edits back to the SSH source on save
Given a raster image belongs to an SSH-backed Project
When the user opens the image
Then the app materializes a temporary local preview file for the native image renderer
And the source of truth remains the remote SSH path
When the user saves image edits
Then edited bytes are written back through the shared remote file-content provider
And the staged local preview file is refreshed to match the saved remote content

### F009-S08: Crop operation preserves in-bounds overlays
Given a raster image has draw strokes and text annotations
And user creates a crop selection that intersects those overlays
When user applies crop
Then overlays within crop bounds remain in resulting working image
And overlays outside crop bounds are removed

#### Assertions for S08
- Assert crop retains draw/annotation overlays that remain in crop bounds.
- Assert overlays outside crop bounds are removed deterministically.
- Assert clip/copy uses composited post-crop output.

### F009-S09: Crop failure feedback is reason-specific
Given a raster image is open in crop mode
When crop apply fails
Then status message reflects the actual failure reason
And messaging does not imply missing selection when failure cause is different

#### Assertions for S09
- Assert no-selection crop failure shows selection-required feedback.
- Assert invalid/small selection shows size/validity feedback.
- Assert decode/crop failures show technical failure feedback (not selection prompt).

### F009-S10: Image edit dirty state is tracked independently from text document dirty state
Given a raster image is open in preview mode
When the user applies an edit (crop, draw, or annotate)
Then the image editor tracks its own dirty state separately from any text document
And saving the image clears only the image dirty flag

### F009-S11: Save failure preserves in-memory edits and shows actionable error
Given a raster image has unsaved edits
When save to disk fails
Then in-memory edits are preserved and the user can retry
And the error message describes the failure reason actionably

### F009-S12: Image editing controls expose stable accessibility identifiers
Given a raster image is open in editing mode
When editing toolbar and status area render
Then all actions and status elements have stable accessibility identifiers for UI automation

### F009-S13: Image edit save and cancel paths are keyboard reachable
Given a raster image is open in editing mode
When the user navigates via keyboard
Then save, apply, and cancel actions are reachable without pointer interaction

### F009-S14: Image edit status feedback is announced through accessibility APIs
Given a raster image edit operation succeeds or fails
When status feedback is displayed
Then the status message is announced through accessibility APIs

### F009-S15: Clear edits action resets image to original state
Given a raster image has one or more applied edits
When the user invokes the clear edits action
Then all edits are removed and the image reverts to its original loaded state

### F009-S16: Image preview handles display-backing-properties changes
Given a raster image is open in preview mode
When display backing properties change (e.g. moving between Retina and non-Retina displays)
Then the image preview re-renders at the appropriate backing scale
And visual fidelity is maintained

### F009-S17: Image thumbnails load progressively
Given an image file is referenced in a context that shows thumbnails
When the thumbnail is requested
Then a low-resolution placeholder is shown first
And the full-resolution thumbnail replaces it once loaded

### F009-S18: Image editing toolbar displays mode hints
Given a raster image is open in editing mode
When the editing toolbar is visible
Then each editing mode (crop, draw, annotate) shows a contextual hint
And hints guide the user on the active mode's interaction

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
