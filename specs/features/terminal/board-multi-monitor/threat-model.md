# Terminal Board Multi-Monitor — Threat Model

## Overview

This feature adds auxiliary NSWindows for terminal board surfaces. The threat surface is primarily around window management integrity, state consistency, and the interaction between multiple windows sharing mutable state.

## Trust Boundaries

1. **Primary window ↔ Detached windows**: Detached windows must not gain shell capabilities (settings, vibespace switching).
2. **Board store ↔ Multiple surfaces**: Tile transfer must maintain data integrity — no duplication, no orphaned tiles.
3. **Window placement persistence ↔ Filesystem**: Stored frame data is read back and applied to window positioning.

## Attack Surfaces

- Persisted placement data (JSON on disk)
- Shared mutable board state across windows
- NSWindow lifecycle and observer management
- Titlebar context menu event interception

## Threats

### F048-T01: Detached host crosses the primary-shell or Spotlight ownership boundary

- **Vector**: A detached board is composed with primary settings/navigation services, routes Spotlight through the primary coordinator, or clears a primary/other-window editor lease.
- **Impact**: Focus and previews jump windows, content is created on the wrong surface, or another window loses its live editor; shell invariants are violated.
- **Likelihood**: Medium because detached windows reuse shared VibeSpace services.
- **Mitigation**: Detached windows host board content only and receive narrow callbacks. Each owns a local coordinator, restore stack, preview owner, monitor, and host ID; all presentation/creation APIs carry `surfaceID`. Editor leases are keyed by host and unioned. Settings/navigation remain primary-window flows.

### F048-T02: State corruption from concurrent tile transfer

- **Vector**: Rapid tile transfers between surfaces could cause race conditions leading to duplicated or orphaned tiles.
- **Impact**: Medium — user loses tiles or sees duplicates.
- **Likelihood**: Low — all mutations are `@MainActor` and go through a single `mutate(_:)` boundary.
- **Mitigation**: `VibeSpaceTerminalBoardStore.mutate(_:)` is the single mutation point, runs on `@MainActor`, normalizes state after every change, and only publishes if the result differs. No concurrent access is possible.

### F048-T03: Malformed placement data causes window off-screen

- **Vector**: Corrupted or manually edited placement JSON could position a window entirely off-screen.
- **Impact**: Low — user cannot see or interact with the window.
- **Likelihood**: Low — requires manual file editing.
- **Mitigation**: Placement metadata is loaded from signed layout persistence and the saved frame is reapplied directly. The current registry does not use the captured display identity to select a screen and does not explicitly clamp the frame or choose the primary display. Recovery depends on macOS window behavior or manual repositioning.

### F048-T04: Resource leak from unclosed windows

- **Vector**: If vibespace shutdown fails to close detached windows, terminal sessions continue running invisibly.
- **Impact**: Low — resource consumption, potential confusion.
- **Likelihood**: Very low — `closeWindows(for:)` is called on vibespace close; `deinit` calls `closeAll()` as a safety net.
- **Mitigation**: `VibeSpaceTerminalBoardDetachedWindowManager.deinit` calls `closeAll()`. Window close notifications trigger `teardownWindow(id:)` which removes observers and event monitors. Lifecycle coupling is enforced through `VibeSpaceCatalogStore`.

### F048-T05: Event monitor leaks

- **Vector**: If `NSEvent.addLocalMonitorForEvents` monitors are not removed, they persist beyond window lifetime and could intercept events in other windows.
- **Impact**: Low — unexpected context menu behavior.
- **Likelihood**: Very low — monitors are stored in `WindowRecord` and removed in both `closeWindow` and `teardownWindow`.
- **Mitigation**: Event monitors are tracked per window record and explicitly removed via `NSEvent.removeMonitor` on window close or teardown.

### F048-T06: Toolbar creates the wrong lifetime or surface

- **Vector**: A temporary toolbar submission directly inserts a tile, a persistent submission defaults to primary, or documentation implies that the temporary process becomes persistent.
- **Impact**: Unexpected persistent processes and corrupted board ownership.
- **Likelihood**: Medium.
- **Mitigation**: `preferTemporary` uses the per-window bridge and local coordinator with no tile. Persistent and split/create-new-persistent paths call `addTile(..., surfaceID:)` once to create a separate tile on the originating surface; they do not convert or transfer the temporary process.

### F048-T07: Detached overview discloses live or sensitive content

- **Vector**: Grid cards capture screenshots, terminal screen excerpts, commands/live output, raw file paths, or browser credentials/query data.
- **Impact**: Secret or private-context disclosure.
- **Likelihood**: Medium if rendering samples live surfaces.
- **Mitigation**: Metadata-only semantic cards in persisted order; terminal active/idle plus basename, file filename/parent from current owner, browser title and redacted host/path. No captured terminal/browser/editor content is read or persisted.

### F048-T08: Stale restore/process callback mutates or leaks a detached host

- **Vector**: A persistent descriptor no longer belongs to the surface, its terminal/ACP/file owner disappears, a browser preview contains an invalid URL, or a temporary process exits after another presentation replaces it.
- **Impact**: Wrong-window content, leaked process/preview, or cleared ownership in another host.
- **Likelihood**: Medium.
- **Mitigation**: Validate persistent surface membership/tile identity and terminal/ACP/file owners where applicable, require a decodable URL for browser previews, allow valid persistent browser tiles to recreate or resolve through their canonical coordinator, skip invalid descriptors, guard exit by Spotlight ID, and clear only local previews, monitors, callbacks, sessions, and editor leases on dismissal.

## Residual Risks

- If the app crashes between the bulk move's source-removal mutation and destination-creation mutation, persisted state may contain the removal without the new surface. Normalization can keep the remaining board state structurally valid but does not guarantee recovery of the removed tile values.
- Display topology changes between sessions may cause windows to appear on unexpected monitors (macOS default behavior).
- Static inspection found local coordinator, toolbar bridge, per-surface layout, restore guard, AppContainer compose-history injection, visible-plus-minimized singleton checks, and Terminal Board recall guarding, but no tests or manual UI checks were run for this documentation update. Mounted detached toolbar delivery, local preview UI, multi-host lease release, physical gestures, and complete NSWindow restore remain unverified gaps.

## Bulk Pane Move (F048-R13 to R16) — Threat Addendum

The bulk-move keyboard shortcuts and tile context menu use the same main-actor store APIs as single-tile transfer, but the complete move spans two mutations and therefore adds a partial-completion risk:

- **State corruption (T02 reuse)**: `bulkDetachTilesForProject` removes every matching tile in one source mutation; `createDetachedSurface` then persists the destination in a second mutation. Each step is serialized and normalized, but a crash or failure between them can persist removal before destination creation. Re-entrancy from the keyboard shortcut path is bounded by `@MainActor` isolation on `handleKeyboardShortcut`; the context-menu path is serialized through SwiftUI's main-actor view updates.
- **Resource leak (T04 reuse)**: the new detached window created by R13 is registered with the same `VibeSpaceTerminalBoardDetachedWindowManager` as user-initiated detached windows; the existing `closeWindows(for:)` cleanup on vibespace close still reaches it, regardless of whether the window was created via shortcut or context menu.
- **No new attack surface**: the keyboard shortcut dispatches through the existing `AppShortcutRegistry` and `Notification.Name` plumbing; the context menu uses the existing tile-card closure plumbing already used by single-tile transfer (`onTileSendToNewBoardWindowRequested`). Both surfaces converge on the same `bulkMoveProjectToNewWindow(projectPath:sourceSurfaceID:)` orchestrator.

## NFR Compliance

- **REL-1**: Individual store mutations are main-actor serialized and normalized; the full bulk move spans two persisted mutations and retains a crash-between-steps residual risk.
- **PERF-1**: No state duplication across windows; shared store instance.
- **SEC-1**: No network communication involved in multi-monitor feature.
- **A11Y-1**: Detached windows have accessibility identifiers (`vibespace.terminal-board.detached`).

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-18 | Final audit fixes: documented detached compose-history injection, visible-plus-minimized singleton checks, and the recall mode guard; clarified that split/create-new-persistent-terminal creates a separate tile rather than converting a temporary process. Static sources only; no tests or manual UI runs. | — |
| 2026-10-18 | Review expanded F048-T01 and added T06–T08 for independent local ownership, temporary-versus-persistent toolbar routing, safe semantic metadata, host-scoped editor leases, restore/process cleanup, placement limitations, and the crash-between-mutations bulk-move risk. Later production-fix status is recorded above. | — |
