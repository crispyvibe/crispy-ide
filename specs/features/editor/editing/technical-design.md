# Editing — Technical Design

## Overview

Editing covers autosave, manual save, unsaved change tracking, markup view mode toggling (rich/source), and find-and-replace for editable document types. Editable types: Markdown, HTML, Python, JSON, R, Plain Text.

## Architecture

### Editable Document Pipeline

Each editable document flows through:

1. File loaded from disk via pane worker → `rawContent` populated.
2. Content displayed in appropriate editor surface (rich rendered, code, or plain text).
3. Edits update `rawContent` in the view model.
4. Autosave or manual save writes `rawContent` snapshot to disk via pane worker.

### Markup View Mode Toggle

Markdown and HTML documents support toggling between **Rich** and **Source** views via a segmented control.

- Mode stored per document, keyed by file path.
- Rich mode is default; switching to source stores the preference.
- Switching back to rich removes the stored preference.
- Rich mode: formatting toolbar shown. Source mode: label ("Markdown Source" or "HTML Source") replaces toolbar.

### Find and Replace

Activated for the current document. Supports:

- Text search with match count display and navigation ("1 of N").
- Replace next and replace all (editable documents only).
- Dismiss with Escape.

## Data Flow

### Autosave

Text changes trigger autosave with a **0.45-second debounce**. Each keystroke cancels the previous pending save and schedules a new one. The save writes the current `rawContent` snapshot to disk via the pane worker with a **10-second timeout**.

After a successful save, the editor compares current content against the saved snapshot. If content changed during the save, the unsaved flag remains set.

### Manual Save

Triggered by save notification (`Cmd+S`). Performs the same write operation as autosave but immediately (no debounce).

### External File Refresh

File watcher notifications are filtered to the active editable document path and its parent directory. If the change did not come from Crispy's own save path (`lastSaveDate` guard), the view model performs a same-document reload instead of routing through the full `openFile(...)` reset path.

That reload path keeps document identity, title, and current content in place while fresh bytes are read. Once replacement text arrives, the AppKit editor host swaps the string, restores the previous selection, and restores the enclosing scroll view origin for same-document updates. Pending source-selection jumps still override the restored viewport.

## State Management

### Unsaved Changes Tracking

Two independent dirty flags:

- `hasUnsavedTextChanges` — set when `rawContent` differs from `lastSavedContent`.
- `hasUnsavedImageEdits` — set when the raster image canvas has pending edits.

Combined `hasUnsavedChanges` = logical OR of both. "Unsaved" badge displayed in top bar when true.

## API / Command Contracts

| Command | Timeout | Purpose |
|---------|---------|---------|
| Pane worker file write | 10 s | Persist `rawContent` to disk |
| Pane worker file read | 10 s | Reload externally changed editable content without resetting document identity |

## Dependencies (frameworks, libraries)

- `MarkdownViewModel` — document content and dirty state
- `MarkupRenderedEditor` — rich mode rendering (WKWebView-based)
- Code editor — source mode with language definitions
- `PaneWorkerClient` — file write operations

## Platform Considerations

- Rich mode uses `WKWebView`; source mode uses native code editor.
- `Cmd+S` routed via notification for manual save.

## Performance Constraints

- Autosave debounce: 0.45 seconds.
- Pane worker write timeout: 10 seconds.
