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

### F048-T01: Privilege escalation via detached window

- **Vector**: A detached board window could be manipulated to present settings or vibespace shell UI that should only appear in the primary window.
- **Impact**: Low — settings access is not a security boundary, but violates product invariants.
- **Likelihood**: Very low — architecture enforces this at the view composition level.
- **Mitigation**: Detached windows host only `VibeSpaceTerminalOnlyView`. No settings, navigation, or shell views are passed to the hosting controller. Toolbar only exposes tile-creation actions.

### F048-T02: State corruption from concurrent tile transfer

- **Vector**: Rapid tile transfers between surfaces could cause race conditions leading to duplicated or orphaned tiles.
- **Impact**: Medium — user loses tiles or sees duplicates.
- **Likelihood**: Low — all mutations are `@MainActor` and go through a single `mutate(_:)` boundary.
- **Mitigation**: `VibeSpaceTerminalBoardStore.mutate(_:)` is the single mutation point, runs on `@MainActor`, normalizes state after every change, and only publishes if the result differs. No concurrent access is possible.

### F048-T03: Malformed placement data causes window off-screen

- **Vector**: Corrupted or manually edited placement JSON could position a window entirely off-screen.
- **Impact**: Low — user cannot see or interact with the window.
- **Likelihood**: Low — requires manual file editing.
- **Mitigation**: macOS constrains window frames to visible screen areas by default. If a stored display is unavailable, the window appears on the primary display. Users can reposition manually.

### F048-T04: Resource leak from unclosed windows

- **Vector**: If vibespace shutdown fails to close detached windows, terminal sessions continue running invisibly.
- **Impact**: Low — resource consumption, potential confusion.
- **Likelihood**: Very low — `closeWindows(for:)` is called on vibespace close; `deinit` calls `closeAll()` as a safety net.
- **Mitigation**: `VibeSpaceTerminalBoardDetachedWindowManager.deinit` calls `closeAll()`. Window close notifications trigger `teardownWindow(id:)` which removes observers and event monitors. Lifecycle coupling is enforced at the workspace catalog level.

### F048-T05: Event monitor leaks

- **Vector**: If `NSEvent.addLocalMonitorForEvents` monitors are not removed, they persist beyond window lifetime and could intercept events in other windows.
- **Impact**: Low — unexpected context menu behavior.
- **Likelihood**: Very low — monitors are stored in `WindowRecord` and removed in both `closeWindow` and `teardownWindow`.
- **Mitigation**: Event monitors are tracked per window record and explicitly removed via `NSEvent.removeMonitor` on window close or teardown.

## Residual Risks

- If the app crashes during tile transfer, the persisted state may have the tile removed from source but not yet added to target. Normalization on next load handles orphaned references.
- Display topology changes between sessions may cause windows to appear on unexpected monitors (macOS default behavior).

## NFR Compliance

- **REL-1**: Single mutation boundary prevents state corruption.
- **PERF-1**: No state duplication across windows; shared store instance.
- **SEC-1**: No network communication involved in multi-monitor feature.
- **A11Y-1**: Detached windows have accessibility identifiers (`vibespace.terminal-board.detached`).
