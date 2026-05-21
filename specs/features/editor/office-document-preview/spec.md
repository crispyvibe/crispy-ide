# Office Document Preview — Spec

Status: draft

## Overview

Render Microsoft Office documents (Word, PowerPoint, Excel) and other common document formats inline within Crispy's Content Viewer using macOS Quick Look (`QLPreviewView`).

## Dependencies

- F006 (Content Viewer) — required for tab routing and preview infrastructure

## Requirements

### F045-R01: Supported Formats

The feature MUST render the following formats inline:
- Word: `.docx`, `.doc`
- PowerPoint: `.pptx`, `.ppt`
- Excel: `.xlsx`, `.xls`

Note: PDF is excluded — it is already handled by the Content Viewer via PDFKit (F006).

### F045-R02: Native Quick Look Rendering

Documents MUST be rendered using macOS `QLPreviewView` (QuickLookUI framework) — no third-party dependencies or network calls.

### F045-R03: Read-Only Display

The preview is read-only. No editing capabilities are required.

### F045-R04: Content Viewer Integration

Office documents MUST open in the same tab infrastructure as other file types (markdown, code, images). File-type routing determines the preview backend.

### F045-R05: Performance Bounds

- Documents under 50 MB MUST render within 3 seconds on Apple Silicon.
- Documents over 50 MB MAY show a loading indicator and render asynchronously.

### F045-R06: Fallback Behavior

If Quick Look cannot render a file (unsupported or corrupt), the viewer MUST display a user-friendly error message with the file name and a suggestion to open in an external app.

### F045-R07: Behavioral Parity with Other File Previewers

Office document tabs MUST behave identically to other file tabs in the Content Viewer. Because rendering is integrated via the pluggable registry (F006-R07), the following behaviors are inherited from F006 and MUST work without additional implementation:

| Behavior | Source |
|----------|--------|
| Single-click → preview tab; double-click → persistent tab | F006-R03, F006-S08, F006-S09 |
| Pinning preview tab to persistent (re-opening as persistent) | F006-R03 |
| Reopening already-tabbed file reuses existing tab | F006-S10 |
| Close tab → fallback to adjacent tab | F006-R03, F006-S11 |
| Open in detached editor window | F006-R04, F006-S12, F006-S13 |
| Split pane support (open in horizontal/vertical split) | F006-R12, F006-S30, F006-S32 |
| Drag-and-drop file URL into pane | F006-S32 |
| Project color tags on tab | F006-R16, F006-S45 |
| File rename retargeting (move/rename open documents) | F006-R17, F006-S48, F006-S49 |
| Session snapshot and restore across sessions | F006-R14, F006-S36, F006-S37 |
| Reload on external file change | F006-R08, F006-S20 |
| Viewer scope filtering (focused project / all projects) | F006-R13, F006-S34, F006-S35 |
| Docked file viewer in terminal board context | F006-R11, F006-S23 |
| Tab icon resolution by extension | F006 (Tab Icons) |

Office tabs MUST NOT introduce custom tab lifecycle, drag, or persistence logic that diverges from this contract.

## Scenarios

### Scenario F045-S01: Open Word Document from Explorer

- **Given** a workspace with a `.docx` file
- **When** the user opens the file from the file explorer
- **Then** the Content Viewer opens a new tab rendering the document via Quick Look

### Scenario F045-S02: Open PowerPoint from Shelf

- **Given** a `.pptx` file pinned to the Shelf
- **When** the user clicks the shelf item
- **Then** the Content Viewer opens a tab with the presentation rendered inline

### Scenario F045-S03: Unsupported or Corrupt File

- **Given** a file with an Office extension that Quick Look cannot render
- **When** the user opens the file
- **Then** the viewer displays an error state with the option to reveal in Finder or open with default app

### Scenario F045-S04: Large Document Loading

- **Given** a `.xlsx` file larger than 50 MB
- **When** the user opens the file
- **Then** a loading indicator is shown until rendering completes

### Scenario F045-S05: Reopening Already-Tabbed Document

- **Given** a `.docx` file is already open in a persistent tab
- **When** the user opens the same file again (from explorer or shelf)
- **Then** the existing tab is activated (no duplicate created, per F006-S10)

### Scenario F045-S06: Single-Click Preview vs Double-Click Persistent Tab

- **Given** a `.pptx` file in the explorer
- **When** the user single-clicks the file
- **Then** it opens as a preview tab with the "Preview" badge (per F006-R03)
- **When** the user then double-clicks the same file
- **Then** the preview tab is converted to a persistent tab

### Scenario F045-S07: Open Office Document in Split Pane

- **Given** an editor pane is open with another file
- **When** the user drags a `.xlsx` file onto a split zone (left/right/top/bottom)
- **Then** a new split pane opens hosting the spreadsheet preview (per F006-S30, F006-S32)

### Scenario F045-S08: Office Document Tab Restored Across Sessions

- **Given** an Office document is open in a tab when the vibespace closes
- **When** the vibespace is reopened
- **Then** the tab is restored with the document re-rendered (per F006-S37)

### Scenario F045-S09: Office Document Retargets on File Rename

- **Given** an Office document is open in a tab
- **When** the file is renamed or moved (in or out of the editor)
- **Then** the open tab follows the new path (per F006-S48)

## Acceptance Criteria

- All formats in F045-R01 render correctly with standard test documents.
- Tab lifecycle (open, close, reopen) works identically to other Content Viewer tabs.
- No network requests are made during rendering.
- Memory usage returns to baseline after closing a document tab.

## Open Questions

- Should we support page navigation controls (e.g., slide picker for PowerPoint)?

## Change History

| Date | Change |
|------|--------|
| 2026-05-19 | Initial draft |
