# Terminal Board — Threat Model

## Overview

Terminal Board stores vibespace board layout, hosts long-lived terminal sessions, renders non-terminal panes, and can reopen detached board windows. The main risks are corrupted persisted layout, incorrect cross-window tile ownership, stale detached windows, focus/spotlight confusion, and accidental process leaks when tiles move or close.

## Trust Boundaries

- VibeSpace persistence files are local app data but may be stale, partially written, or created by an older app version.
- Terminal sessions execute user-selected shells and commands; board UI must not duplicate or orphan sessions when panes move.
- Detached board windows share one vibespace but are separate AppKit windows with independent focus, geometry, and spotlight presentation.
- File, browser, ACP, and VibeCast panes may display content from vibespace files, URLs, or agent sessions, but moving a tile must not change that content's trust boundary.

## Attack Surfaces

- Persisted `VibeSpaceTerminalBoardState`, detached surface IDs, tile IDs, and window placement metadata.
- Drag-and-drop and context-menu transfer between primary and detached board surfaces.
- Spotlight actions that create persistent terminal tiles from a board window.
- Window restoration after vibespace reopen or display topology changes.
- Close/minimize/remove paths for terminal, file, browser, ACP, and VibeCast tiles.

## Threats

### F002-T01: Corrupted or duplicated persisted board state

- Vector: A stale or malformed vibespace layout contains duplicate tile IDs, duplicate surface IDs, empty detached surfaces, invalid weights, or more tiles than the board limit.
- Impact: Blank panes, missing tiles, crashes during hydration, or duplicated terminal ownership.
- Likelihood: Medium because layout is persisted across app versions and crashes.
- Mitigation: Normalize board state on load and mutation, deduplicate surface and tile IDs, remove empty detached surfaces, clamp layout weights, enforce the 16-tile board limit, and keep the primary surface ID stable.

### F002-T02: Cross-vibespace tile transfer

- Vector: A drag or context-menu transfer targets a detached window from a different vibespace.
- Impact: A tile could appear in the wrong vibespace or lose access to its backing project/session context.
- Likelihood: Low with current window manager filtering, but high impact if regressed.
- Mitigation: Detached window lookup filters by `vibespaceID`; transfer target lists include only open board windows for the same vibespace; source surfaces are excluded from target lists.

### F002-T03: Bulk move, blank shell, or stale position after transfer

- Vector: Moving one tile accidentally moves sibling tiles, leaves duplicate identities, leaves an empty placeholder in the source layout, or carries a source-surface position into a destination surface where that position conflicts.
- Impact: User loses board organization, sees blank shells, or hits duplicate-key crashes.
- Likelihood: Medium because drag and context-menu paths both mutate multi-surface state.
- Mitigation: Transfer uses one `VibeSpaceTerminalBoardTile` value through `detachTile` / `moveTile`; layout removal covers visible and minimized tiles; duplicate terminal identities are removed before reattach; destination placement is assigned by the destination surface rather than by source column/row/index; emptied detached source windows close after transfer.

### F002-T04: Spotlight appears in the wrong window

- Vector: A detached board action routes through the primary vibespace spotlight coordinator.
- Impact: Focus jumps unexpectedly, persistent splits are created on the wrong surface, or temporary previews appear away from the initiating window.
- Likelihood: Medium because spotlight is a cross-cutting feature.
- Mitigation: Detached board windows own local `TerminalSpotlightCoordinator` instances; split-to-persistent actions pass the initiating `surfaceID`; non-board panes continue to use the primary or detailed-mode fallback path.

### F002-T05: Detached window lifecycle leak

- Vector: Closing a vibespace or transferring the last tile out of a detached window leaves the AppKit window or backing sessions registered.
- Impact: Hidden windows, stale focus participants, memory leaks, or orphaned terminal sessions.
- Likelihood: Medium for multi-window flows.
- Mitigation: `VibeSpaceTerminalBoardDetachedWindowManager` tracks windows by vibespace and surface; vibespace close closes managed detached windows; emptied detached source surfaces close after transfer; tile close still uses existing terminal/tab cleanup paths.

### F002-T06: Unsafe display placement restore

- Vector: A detached board window restores to a stale frame from a missing monitor.
- Impact: Window may appear in an inconvenient location or require user repositioning.
- Likelihood: Medium for laptop/dock workflows.
- Mitigation: Placement restore is best-effort and does not merge user panes unexpectedly. Moving or resizing the window writes new placement metadata. User can manually reposition if monitor topology changed.

## Residual Risks

- Programmatic AppKit frame restoration may still place a window somewhere inconvenient when displays change. The product decision is to preserve detached board state rather than merge panes automatically.
- Multi-window UI behavior still needs regression coverage beyond build validation, especially drag-to-existing-window, minimized transfer, and mixed tile-kind transfer.

## NFR Compliance

- SEC-1, SEC-3a — local persisted layout must not expand privileges or cross vibespace boundaries.
- REL-6 — tile removal and detached window close paths must not orphan terminal processes.
- PERF-3, PERF-4 — layout mutation and persistence remain bounded by the 16-tile board limit.
- A11Y-2 — board actions remain available through context menus and keyboard-reachable controls.
