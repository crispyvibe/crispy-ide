# Terminal Board — Threat Model

## Overview

Terminal Board stores vibespace board layout, hosts long-lived terminal sessions, renders non-terminal panes, and can reopen detached board windows. The main risks are corrupted persisted layout, incorrect cross-window tile ownership, stale detached windows, focus/spotlight confusion, and accidental process leaks when tiles move or close.

## Trust Boundaries

- VibeSpace persistence files are local app data but may be stale, partially written, or created by an older app version.
- Terminal sessions execute user-selected shells and commands; board UI must not duplicate or orphan sessions when panes move.
- Detached board windows share one vibespace but are separate AppKit windows with independent focus, geometry, and spotlight presentation.
- File, browser, ACP, and VibeCast panes may display content from vibespace files, URLs, or agent sessions, but moving a tile must not change that content's trust boundary.

## Attack Surfaces

- Persisted `VibeSpaceTerminalBoardState`, detached surface IDs, tile IDs, per-surface F003 Spotlight value snapshots, and window placement metadata.
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

### F002-T07: Temporary and persistent creation cross surfaces

- Vector: A detached toolbar request falls back to the primary coordinator, or a temporary terminal action creates a persistent tile on the wrong surface or is mistaken for conversion of the temporary process.
- Impact: Unexpected process/tile creation in the wrong window and corrupted surface layout.
- Likelihood: Medium.
- Mitigation: The local toolbar bridge opens only a temporary detached Spotlight. Persistent New Terminal and split actions call `addTile(..., surfaceID:)` exactly once on the originating surface. A split/create-new-persistent action from temporary Spotlight creates a separate persistent terminal tile; the temporary process is not converted or transferred.

### F002-T08: Local preview leaks or persists sensitive content

- Vector: Detached browser/file overview metadata captures content pixels, terminal output, commands, raw paths, or sensitive URL components.
- Impact: Local secret or browsing-context disclosure.
- Likelihood: Medium if live content is sampled.
- Mitigation: F003 safe semantic metadata only; no screenshots, terminal screen excerpts, live output, commands, or captured WebView/editor pixels. File data is filename/parent only, and browser userinfo/password/query/fragment are removed.

### F002-T09: One Spotlight host releases another host's editor

- Vector: Main and detached Spotlights display the same file tile while ownership is tracked by one global Boolean/set.
- Impact: Duplicate editor hosts, lost responder state, or a blank file pane after unrelated window dismissal.
- Likelihood: Medium.
- Mitigation: Editor ownership is leased by host ID and tile set. Board suppression uses the union of leases; dismissal clears only the calling host's lease.

### F002-T10: Stale restore or process callback mutates a detached window

- Vector: A restore descriptor's terminal/ACP/file owner disappears, a browser preview contains an invalid URL, a persistent browser tile no longer belongs to the surface, or an old temporary process exits after replacement.
- Impact: Wrong local content, blank preview, leaked process, or mutation of a newer Spotlight.
- Likelihood: Medium.
- Mitigation: Validate surface membership/tile identity for persistent members, validate terminal tabs, ACP stores, and file owners where applicable, require a decodable URL for browser previews, and allow a valid persistent browser tile to recreate or resolve through its canonical coordinator. Skip invalid descriptors, guard process exit by Spotlight ID, and release local sessions/previews/callbacks/monitors/leases on final dismissal.

### F002-T11: Cross-host cleanup deletes same-root remote tiles

- Vector: Cleanup matches a remote project by raw root text while another SSH host exposes the same root.
- Impact: Tiles and Spotlight members from the other host are deleted, or terminal reconciliation adopts them into the wrong project.
- Likelihood: Medium in standardized server layouts.
- Mitigation: Persist optional host-qualified `projectIdentifier` ownership and use it in runtime subscriptions, project context, reconciliation, and Spotlight identities. For legacy remote terminals, tab membership may prove one owner; raw-root equality alone does not. Cleanup removes only proven matches.
- Residual risk: Historically incorrect owner stamps may remain authoritative until separately repaired.

### F002-T12: Ambiguous legacy migration assigns a destructive owner

- Vector: `syncProjects` stamps a legacy remote raw-root-only tile when multiple host-qualified projects are candidates.
- Impact: Future cleanup, restoration, or synchronization crosses host boundaries.
- Likelihood: Medium for layouts persisted before ownership stamping.
- Mitigation: Optional Codable ownership preserves legacy decoding; migration requires unique evidence. Ambiguous remote raw-root-only tiles remain unstamped and retained fail-closed. Local file fallback uses standardized component-boundary containment, not string-prefix matching.
- Residual risk: Retained ambiguous tiles may remain stale or require manual closure, but this is safer than destructive guessing.

### F002-T13: Automatic cleanup leaves a stale detached window

- Vector: The final owned visible/minimized tile and Spotlight member are removed, but the detached surface or AppKit window survives.
- Impact: Blank windows, stale restoration records, focus participants, or leaked management state.
- Likelihood: Low after atomic normalization; mounted AppKit behavior still requires UI-level verification.
- Mitigation: Cleanup removes all owned collections and Spotlight members in one mutation; normalization removes empty detached surfaces; persistence records the normalized state; the detached-window manager closes windows whose surface IDs disappear.
- Residual risk: An unmanaged or pre-existing desynchronized window may still require manual closure.

### F002-T14: Host identity is lost across preview or bulk-move routing

- Vector: A terminal target or dock preview is reduced to a local-looking path, Spotlight Codable normalizes `ssh://` as a file path, remote file pruning runs before ownership migration, or Send All selects by raw root.
- Impact: A file opens through the wrong host/provider, a valid remote tile is deleted as locally stale, Spotlight identity collides, or another host's tiles move.
- Likelihood: Medium when multiple hosts expose a common root.
- Mitigation: Carry `projectIdentifier` through `TerminalFileSystemTarget`, `DockPreviewBridge`, main/detached file/browser/link routes, tile pinning, and Spotlight state; preserve SSH identifiers verbatim in Codable; migrate uniquely owned legacy remote file tiles before local stale prune; retain ambiguous legacy tiles fail-closed; and select Send All by unique owner.
- Residual risk: Unstamped ambiguous legacy panes may require manual closure.

### F002-T15: Spotlight route drops host-qualified project identity

- Vector: A main/detached direct, temporary, shortcut, split, permanent, ACP, link, file, browser, editor-pane, restore, or detached-attachment route reconstructs Spotlight state from a raw root and loses `owningProjectIdentifier`.
- Impact: Nested actions can open content, execute a shortcut, create a terminal, or resolve a provider on the wrong SSH host when projects share a root.
- Likelihood: Medium because Spotlight crosses many presentation and callback boundaries.
- Mitigation: Every route passes the exact `projectIdentifier` through `TerminalSpotlightState`; lookups prefer it before path fallback, nested actions reuse it, and detached attachment copies it unchanged. Same-root remote identifiers remain host-qualified.
- Residual risk: The full matrix is production-source inspected rather than mounted end-to-end UI coverage; a future route can regress if it omits the field.

## Residual Risks

- Programmatic AppKit frame restoration may still place a window somewhere inconvenient when displays change. The product decision is to preserve detached board state rather than merge panes automatically.
- Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. Static source covers normalization, same-root isolation, dock-preview identity, remote-file migration-before-prune, verbatim SSH Codable, and fail-closed cleanup. `SpotlightEnhancementTests` directly checks owner/callback preservation for every detached direct persistent source kind, exact-once detached temporary shortcut dispatch, and surface-local detached permanent creation. The complete mounted main/detached route matrix, additional nested actions, and unique-owner Send All remain production-source inspection; toolbar delivery, editor-lease release, gestures, and window restoration remain UI/manual gaps.

## NFR Compliance

- SEC-1, SEC-3a — local persisted layout must not expand privileges or cross vibespace boundaries.
- REL-6 — tile removal and detached window close paths must not orphan terminal processes.
- PERF-3, PERF-4 — layout mutation and persistence remain bounded by the 16-tile board limit.
- A11Y-2 — board actions remain available through context menus and keyboard-reachable controls.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-23 | Corrected direct versus production-inspection evidence for project-qualified Spotlight routes and recorded build/test-build-only validation with no executed pass. | — |
| 2026-10-23 | Added F002-T15 for exact owner retention across every main/detached Spotlight route and detached attachment; narrowed complete route evidence to production-source inspection. | — |
| 2026-10-23 | Added F002-T14 for host identity loss across previews, Spotlight persistence, stale pruning, and Send All; recorded compile/static-only coverage. | — |
| 2026-10-20 | Added F002-T11–T13 for cross-host deletion, ambiguous legacy migration, and stale detached windows, with fail-closed and lifecycle mitigations plus residual risks. Static sources only; no test pass is claimed. | — |
| 2026-10-18 | Final audit fixes: documented detached compose-history injection and clarified that split/create-new-persistent-terminal creates a separate tile rather than converting or transferring a temporary process. Static sources only; no tests or manual UI runs. | — |
| 2026-10-18 | Added temporary-versus-persistent local creation, privacy-safe metadata, host-scoped editor lease, detached restore/process-exit threats, and static/manual gap accounting. Later production-fix status is recorded above. | — |
| 2026-10-16 | Added regression controls for surface-scoped Spotlight identity and geometry-safe flattened reorder persistence, including minimized standalone terminals. | — |
