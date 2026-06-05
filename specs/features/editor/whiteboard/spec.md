# Whiteboarding — Spec

Status: implemented

## Overview

F052 adds freeform whiteboards to Crispy: an embedded, fully offline [Excalidraw](https://excalidraw.com) canvas for drawing diagrams, sketches, and notes. Whiteboards are ordinary `.excalidraw` JSON files on disk, edited in a dedicated editor surface and autosaved like any other document. A new whiteboard is created into the app-global **Shelf** as a draft, then dragged into a project's file tree to give it a permanent home.

The feature reuses Crispy's existing file-backed editor plumbing (document-type detection → editor plugin → `DocumentBuffer`/autosave) and the Shelf move-to-project flow; the only net-new infrastructure is the vendored offline Excalidraw runtime and its `WKWebView` host.

## Dependencies

- F006 (Content Viewer) — hosts the whiteboard as an editor tab.
- F007 (Editing) / F039 (Document Buffer) — buffer + autosave pipeline the scene JSON flows through.
- F033 (Shelf) — staging location for newly created whiteboards and the drag-to-project source.
- F025 (Drag & Drop) / F024 (File Explorer) — the project file tree is the move-to-project drop target.

## Requirements

### F052-R01: Offline Excalidraw editor
`.excalidraw` files open in an embedded Excalidraw canvas. The runtime is vendored in the app bundle; the editor MUST function with no network access and MUST NOT contact any remote origin at runtime.

### F052-R02: File-backed, autosaving
A whiteboard is a real `.excalidraw` (Excalidraw v2 JSON) file. Edits on the canvas are persisted to that file through the standard document buffer + autosave path. No separate database.

### F052-R03: Create into the Shelf
A "New Whiteboard" action (toolbar) creates an empty `.excalidraw` in an app-global staging directory, adds it to the Shelf, and opens it. New whiteboards are uniquely named (`Untitled Whiteboard`, `Untitled Whiteboard 2`, …).

### F052-R04: Move to a project
Dragging a Shelf row onto a project's file tree moves the file into that project directory, retargets the open editor tab to the new path, and removes the item from the Shelf. The drop target MUST be a directory inside an open project.

### F052-R05: Theme-aware
The canvas follows the app's light/dark appearance.

### F052-R06: Navigation containment
The hosting web view is confined to the local runtime scheme. External links open in the system browser; no in-app navigation to remote or `data:` origins is permitted.

### F052-R07: Graceful degradation
If the vendored runtime is missing, the editor shows an explanatory message rather than a blank pane.

### F052-R08: Reproducible runtime build
The offline runtime is produced from pinned dependencies by a checked-in build script and committed as a bundle artifact.

## Scenarios

### Scenario F052-S01: Create a whiteboard (Given / When / Then)
- **Given** an open VibeSpace, **when** the user clicks the New Whiteboard toolbar button, **then** an empty `Untitled Whiteboard.excalidraw` is created in the Shelf staging dir, added to the Shelf, and opened on the canvas in Detailed view.

### Scenario F052-S02: Draw and autosave
- **Given** an open whiteboard, **when** the user draws shapes/text, **then** the scene serializes and autosaves to the file within ~1–2 s with no explicit save action.

### Scenario F052-S03: Reopen
- **Given** a previously saved `.excalidraw`, **when** the user opens it, **then** the saved scene renders on the canvas.

### Scenario F052-S04: Move to project
- **Given** a whiteboard in the Shelf that is open in the editor, **when** the user drags its Shelf row onto a project folder in the file tree, **then** the file moves into that folder, the open tab follows to the new path, and the Shelf entry is removed.

### Scenario F052-S05: Name collision on move
- **Given** the target directory already contains a file of the same name, **when** the whiteboard is moved there, **then** it is moved under a uniquely-suffixed name (no overwrite).

### Scenario F052-S06: Offline guarantee
- **Given** no network connectivity, **when** a whiteboard is opened and edited, **then** the canvas, fonts, and locale assets all load from the bundle and editing works normally.

### Scenario F052-S07: Dark mode
- **Given** the app is in dark appearance, **when** a whiteboard opens, **then** the canvas renders with a theme-appropriate background (no white flash).

### Scenario F052-S08: Runtime missing
- **Given** a build without the vendored runtime, **when** a whiteboard is opened, **then** an "unavailable" message is shown instead of a blank pane.

### Scenario F052-S09: External link
- **Given** a link inside the Excalidraw UI to a remote URL, **when** the user activates it, **then** it opens in the system browser, not in the embedded web view.

## Acceptance Criteria

- Opening/creating/editing/moving whiteboards works with networking disabled (S01–S06).
- Autosave persists scene changes through `DocumentBuffer` (S02); unsaved edits are flushed before a move (S04).
- Move-to-project only targets directories inside an open project; collisions never overwrite (S04, S05).
- No remote origin is reachable from the host page (CSP + custom scheme + navigation policy).
- `xcodebuild -scheme crispyvibes-local` builds; the runtime build script reproduces the bundle from pinned versions.

## Open Questions

1. Should moving a whiteboard into a project optionally keep a Shelf reference, or always remove it (current: remove)?
2. Multi-window: should the same whiteboard open in two surfaces share a live canvas (like the notebook arbiter), or is per-surface reload acceptable (current: per-surface)?
3. Is a `whiteboard.*` agent CLI (`new|list|open|move`) worth adding for automation? (Deferred.)

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-06-05 | Initial implementation: offline Excalidraw editor, Shelf create, drag-to-project move, autosave, theming. Reviewed (multi-agent) and hardened (symlink containment, CSP/script externalization, pre-move buffer flush, target-in-project validation). | — |
