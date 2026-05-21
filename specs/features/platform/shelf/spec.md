# Shelf — Spec

Status: draft

## Overview

Shelf is a persistent pinned-files section shown at the top of the Files sidebar. It lets users keep standalone files close at hand, open them in the main content viewer, receive files from Finder or external open requests, and restore the pinned list across launches.

## Dependencies

- F007 (Editing) — Shelf entries open through the standard content viewer and editor pipeline

## Requirements

### F033-R01: Shelf Presentation

Shelf MUST render as a collapsible section at the top of the Files sidebar, not as a separate app surface.

### F033-R02: File Management

Files MUST be addable, removable, and clearable with collision-safe deduplication and persistence.

### F033-R03: External File Integration

Files opened from Finder or external sources MUST land in Shelf.

### F033-R04: Persistence

Shelf state MUST persist across app launches via `shelf-state.json`.

### F033-R05: Content Viewer Sync

Shelf selection MUST stay in sync with the active file in the content viewer whenever that file is part of Shelf.

## Scenarios

### Scenario F033-S01: Shelf appears at the top of the Files sidebar

**Given** Shelf contains one or more files
**When** the Files sidebar renders
**Then** a Shelf section is shown above the project tree
**And** the section header shows a disclosure chevron, Shelf icon, and Shelf title
**And** each row shows the file name with missing-file state when applicable
**And** the full file path is available on hover

### Scenario F033-S02: Shelf remains hidden when empty

**Given** Shelf has no files
**When** the Files sidebar renders
**Then** the Shelf section is omitted from the Files sidebar

### Scenario F033-S03: Shelf is accessible from the welcome surface

**Given** the welcome surface is displayed
**When** the user clicks the Shelf action
**Then** the app reveals the Files sidebar for the active or fallback vibespace
**And** the first valid Shelf selection is opened in the main content viewer when present

### Scenario F033-S04: Files and folders are added to Shelf

**Given** one or more file or folder URLs are added via `addFiles`
**When** Shelf processes the URLs
**Then** URLs are normalized and prepended to the file list
**And** duplicates are removed preserving the newest position
**And** the first added item becomes the selected Shelf entry
**And** the Shelf state is persisted to `shelf-state.json`

### Scenario F033-S05: User selects a file from Shelf

**Given** Shelf contains multiple files
**When** the user clicks a Shelf entry
**Then** that file becomes the selected Shelf file
**And** the file opens in the main content viewer
**And** the selection is persisted

### Scenario F033-S06: User removes a file from Shelf

**Given** Shelf contains a file entry
**When** the user chooses `Remove from Shelf` from the Shelf file context menu
**Then** the file is removed from Shelf
**And** if it was the selected Shelf file the next available Shelf file becomes selected
**And** the Shelf state is persisted

### Scenario F033-S07: User clears Shelf

**Given** Shelf contains one or more files
**When** the user chooses `Clear` from the Shelf header context menu
**Then** all Shelf entries are removed
**And** the in-memory selection is cleared
**And** the persisted `shelf-state.json` file is deleted

### Scenario F033-S08: Missing files are indicated in Shelf

**Given** a Shelf entry references a file that no longer exists on disk
**When** the Shelf row renders
**Then** a warning icon is shown instead of the standard document icon
**And** the row renders at reduced opacity

### Scenario F033-S09: Files opened from Finder or external sources land in Shelf

**Given** the app receives an external open request containing file URLs
**When** `openFilesInShelf` is called
**Then** the files are added to Shelf
**And** when a vibespace is available the Files sidebar is revealed and the first selected file opens in the main content viewer
**And** when no vibespace is available the files remain persisted in Shelf until a vibespace is shown

### Scenario F033-S10: Folders are supported in Shelf

**Given** an add request includes directory URLs
**When** `addFiles` processes the URLs
**Then** directories are added to Shelf alongside files
**And** directory entries display a folder icon

### Scenario F033-S11: Shelf state persists across app launches

**Given** Shelf contains files and a selected file
**When** the app is relaunched and `loadIfNeeded` is called
**Then** the file list and selected file are restored from `shelf-state.json`
**And** paths are normalized and deduplicated
**And** if the persisted selected path is no longer in the list the first file is selected

### Scenario F033-S12: Shelf state loads only once per session

**Given** `loadIfNeeded` has already been called
**When** `loadIfNeeded` is called again
**Then** the load is skipped using the `didLoad` guard

### Scenario F033-S13: Shelf resets cleanly on app state reset

**Given** the app performs a full local state reset
**When** `resetForFreshStart` is called on the Shelf store
**Then** file paths, selection, and the `didLoad` flag are cleared
**And** no persistence write is performed during the reset

### Scenario F033-S14: Shelf selection stays in sync with the content viewer

**Given** a Shelf file is open in the main content viewer
**When** the active content viewer file changes to another Shelf file
**Then** `syncSelection(from:)` updates the Shelf selection to match
**And** the updated selection is persisted

### Scenario F033-S15: Shelf ensures a valid selection when revealed

**Given** Shelf contains files but has no valid selection
**When** `ensureSelectionIfNeeded` is called
**Then** the first Shelf file becomes selected

### Scenario F033-S16: Shelf file rows expose explorer-style context actions

**Given** Shelf contains one or more files
**When** the user opens the context menu for a Shelf file
**Then** the menu provides file actions including open, open in terminal, reveal in Finder, copy path, rename, remove from Shelf, and delete when the file exists


### Scenario F033-S17: Shelf folders are expandable to browse contents inline

**Given** Shelf contains a folder entry
**When** the user clicks the folder row
**Then** the folder expands to show its contents as an indented tree
**And** directories are sorted before files, both alphabetically
**And** nested folders are recursively expandable
**And** clicking the folder again collapses it

### Scenario F033-S18: Add to Shelf button opens Finder with hidden files visible

**Given** the Files sidebar header is visible
**When** the user clicks the "Add to Shelf" button
**Then** an NSOpenPanel opens allowing selection of files and folders
**And** multiple selection is enabled
**And** hidden files are visible in the panel
**And** selected items are added to Shelf

### Scenario F033-S19: Shelf files open in spotlight on terminal board mode

**Given** the vibespace is in terminal-only canvas mode
**When** the user clicks a file in Shelf
**Then** the file opens as a spotlight file preview
**And** the vibespace does not switch to detailed mode

### Scenario F033-S20: Shelf files open in editor tab on detailed mode

**Given** the vibespace is in detailed canvas mode
**When** the user clicks a file in Shelf
**Then** the file opens in the content viewer editor tab

## Acceptance Criteria

- Shelf renders as part of the Files sidebar rather than a dedicated view.
- File add deduplicates and persists atomically.
- Missing files display a warning indicator without crashing.
- External file open routes to Shelf correctly.
- Shelf state restores on relaunch.

## Open Questions

_None._

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-16 | Updated Shelf to the Files-sidebar pinned-files model | — |
| 2026-04-15 | Migrated from docs/features/shelf/feature.md (SHF-001–016) | — |
