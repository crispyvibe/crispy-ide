# Terminal Surface Lifecycle Management

**Date:** 2026-03-21
**Status:** Historical design record; not updated for current runtime behavior
**Scope:** `GhosttyTerminalEngine`, `GhosttyTerminalView`, `TerminalSessionOwnershipCoordinator`, `TerminalSessionHostView`, `VibeSpaceTerminalBoardStore`, `VibeSpaceState`
**Related:** `ghostyfixes.md`, `ghostty-terminal-reliability-fixes.md`

---

## Status Note (2026-04-14)

This document is kept as commit archaeology for the March terminal surface work. It is no longer maintained as a current description of the runtime.

The older occlusion-heavy implementation was removed after repeated regressions during minimize, inactivity, and wake/restore flows:

- early CrispyVibes code treated `ghostty_surface_set_occlusion(...)` like an `occluded` flag, but Ghostty's embedded API actually takes a `visible` boolean
- the custom window and sleep occlusion path added extra lifecycle states that were easy to get wrong and hard to test
- the sections below still describe commit-era behavior that no longer exists in the app

Current code intentionally keeps a smaller embedded contract centered on native view lifecycle, responder focus, resize/display sync, and renderer-health recovery. App-level wake/minimize/occlusion notifications were removed from CrispyVibes's embedded path; the historical sections below remain useful for understanding the old investigation and the commits that introduced and later removed those hooks, but they should not be read as the current implementation.

---

## Problem

Memory footprint grows with terminal usage and does not recover. Measured on a live session:

| Metric | Value |
|---|---|
| Total footprint | 404 MB |
| Live allocated heap | 115 MB |
| IOSurface | 83.5 MB |
| IOAccelerator (GPU) | 43.1 MB |
| Thread count | ~40 |

The expensive resources are Ghostty render surfaces, not text buffers or general heap. Each live Ghostty session spawns three threads (renderer, io, io-reader) and allocates IOSurface + Metal textures proportional to the surface pixel dimensions.

---

## Root Causes

### RC-1. Surfaces are likely retained indefinitely when offscreen

`GhosttyTerminalView.createSurfaceIfNeeded()` allocates a full Metal render surface when the view enters a window (`viewDidMoveToWindow`). `destroySurface()` is only called from `terminate()`:

- `GhosttyTerminalEngine.swift:604` — `destroySurface()`
- `GhosttyTerminalEngine.swift:1100` — `terminate()` (only caller)

There is no code path that destroys or suspends a surface when a terminal becomes hidden, offscreen, or demoted. **This strongly suggests that hidden terminals keep full render resources alive indefinitely, but this has not yet been confirmed at runtime.** Phase 1 diagnostics will prove whether surfaces persist after their host leaves a window.

### RC-2. Occlusion API exists but is unused

The vendored Ghostty header exposes:

```c
void ghostty_surface_set_occlusion(ghostty_surface_t, bool);  // ghostty.h:1070
```

This tells the Ghostty renderer to stop rendering frames for occluded surfaces. The official Ghostty macOS app calls this on `NSWindow.didChangeOcclusionStateNotification`. It is never called anywhere in the CrispyVibes codebase.

### RC-3. Output polling timer may be running for offscreen sessions

Each `GhosttyTerminalEngine` runs a 300ms `DispatchSource` timer (`startOutputPolling`) that calls `captureVisibleContentsIfNeeded()`, which reads the entire visible viewport via `ghostty_surface_read_text` into a new String allocation. With 16 board tiles, this could mean 16 surface reads + 16 string allocations every 300ms, even for offscreen or inactive terminals.

Output detection is also covered by `GHOSTTY_ACTION_RENDER`, `GHOSTTY_ACTION_COMMAND_FINISHED`, `GHOSTTY_ACTION_SET_TITLE`, and `GHOSTTY_ACTION_PWD` callbacks (see `ghostty-terminal-reliability-fixes.md`). Runtime validation showed those callbacks are not sufficient for tab activity state on their own. The polling timer remains necessary, but it must be visibility-aware and explicitly re-synced after detach/reattach and window churn.

### RC-4. Ownership coordinator does not manage surface lifecycle

`TerminalHostOwnershipCoordinator` (`TerminalSessionOwnershipCoordinator.swift`) arbitrates which `TerminalContainerView` hosts a terminal view. It does not:

- Track whether a session should have a live render surface
- Call `ghostty_surface_set_occlusion` when a session loses its host
- Call `ghostty_surface_set_focus(false)` when a session is demoted
- Enforce any limit on concurrent live surfaces

### RC-5. Multiple UI paths may keep surfaces rendering simultaneously

The same terminal session can be presented through:

| Location | File |
|---|---|
| Board tiles (up to 16) | `VibeSpaceTerminalBoardTileCard.swift:91` |
| Detailed / split / stacked views | `TerminalView.swift:185`, `TerminalView.swift:230`, `TerminalViewComponents.swift:160` |
| Spotlight overlay | `ContentViewProjectCanvas.swift:1160` |

The ownership coordinator moves the view between these locations, which should mean only one host has the view at a time. **However, it has not been confirmed at runtime that transitions between presentation paths always result in clean detach-before-attach sequences, or that surfaces are never left rendering in a previous host during transitions.** Phase 1 diagnostics will track attach/detach events per source to prove whether overlapping presentations occur.

### RC-6. VibeSpace close recreates sessions instead of releasing them

`VibeSpaceState.resetSession()` calls `shutdownProjects()` (which terminates engines and destroys surfaces) but immediately recreates fresh `ProjectSession`s from stored paths. Each new `ProjectSession` eagerly creates a `TerminalViewModel` → `GhosttyTerminalEngine` → `GhosttyTerminalView` + polling timer. Surfaces are created when the view next enters a window.

There are two separate user intents that must remain separate:

**Home** — Navigation-only. Show the home screen. Keep the active vibespace session alive in memory. Allow returning with state preserved.

**Close VibeSpace** — Teardown. Shut down all runtime session state. Release terminals, explorer view models, and per-vibespace runtime objects. Keep the vibespace in the catalog for reopening later. Reopening should create a fresh session from persisted metadata.

The current implementation conflates these because `VibeSpaceState` mixes persistent vibespace metadata with runtime session objects. `projects: [ProjectSession]` acts as both the source of truth for persistence and the live runtime session graph.

### RC-7. Board standalone registry accumulates view models

`VibeSpaceTerminalBoardStandaloneRegistry.shared` (`VibeSpaceTerminalBoardStore.swift:675`) is a static singleton that caches `TerminalViewModel` instances keyed by vibespace ID. `release()` exists but depends on callers invoking it. These view models hold live sessions with Ghostty engines.

### RC-8. App-wide config leaked on every theme change

`applyThemeOverrideIfPossible()` calls `ghostty_app_update_config(app, config)` which pushes one surface's palette as the app-wide default. In multi-tile setups, the last tile to apply its theme wins the global config, causing incorrect colors on other surfaces. See `ghostyfixes.md` item #2.

Note: `ghostty_config_load_default_files(config)` is still called per theme change. Removing it was attempted but caused a rendering regression — Ghostty needs its base config for correct surface behavior. A future optimization could cache the loaded defaults at init time, but this requires careful validation.

---

## UX Impact

None for occlusion and focus changes. Occluded surfaces keep the PTY process running, preserve scrollback, and continue buffering output. Un-occluding renders the current state immediately. This is the same mechanism the official Ghostty macOS app uses for minimized/hidden windows.

Optional surface resizing (1×1 for offscreen) would cause a brief terminal reflow on restore — the same behavior as resizing any terminal window. This optimization can be deferred.

---

## Phase 1 — Diagnostics

> No behavior change. Tracing and assertions only. Goal: prove lifecycle behavior instead of inferring it from memory snapshots.

### Stable debug IDs

Give every `TerminalSession` and Ghostty surface a stable debug ID (short, human-readable, monotonically increasing). These IDs appear on every log line and in the diagnostic snapshot.

### Lifecycle event logging

Log structured events for both session and surface lifecycle. Every event includes:

- `sessionID` — stable debug ID
- `surfaceID` — stable debug ID (nil if no surface)
- `vibespaceID`
- `source` — presentation source (see below)
- `reason` — transition reason (see below)
- `timestamp`

**Events to log:**

| Event | Where |
|---|---|
| `session.create` | `TerminalSession.init` |
| `session.terminate` | `TerminalSession.close` / engine `terminate()` |
| `surface.create` | `GhosttyTerminalView.createSurfaceIfNeeded()` |
| `surface.destroy` | `GhosttyTerminalView.destroySurface()` |
| `host.attach` | `TerminalContainerView.attach(...)` |
| `host.detach` | `TerminalContainerView.detachAttachedTerminalIfNeeded()` |
| `surface.occlude` | When occlusion is set to true |
| `surface.unocclude` | When occlusion is set to false |
| `surface.resize` | `syncSurfaceGeometry()` — include pixel width, pixel height, backing scale |
| `surface.focus` | `ghostty_surface_set_focus(true)` |
| `surface.blur` | `ghostty_surface_set_focus(false)` |

**Presentation sources** (included on every event):

- `detailed`
- `stacked`
- `split`
- `rail`
- `board`
- `spotlight`
- `transient`

**Transition reasons** (included on lifecycle changes):

- `windowNil`
- `vibespaceSwitch`
- `spotlightPromote`
- `boardMinimize`
- `closeVibeSpace`
- `ownershipPreempted`

### Anomaly detection

Log or assert on the following conditions:

- Polling timer fires while `window == nil` or host is not visible → log explicitly with session/surface IDs
- Session terminates but surface still exists → assert in debug builds
- VibeSpace closes but board standalone VMs remain registered → assert in debug builds

### Central debug snapshot

A singleton `TerminalDiagnosticsSnapshot` that can be captured at any point. Reports:

**Global counters:**

| Counter | Description |
|---|---|
| Active terminal session count | Live `TerminalSession` instances |
| Active Ghostty surface count | Non-nil `ghostty_surface_t` references |
| Active terminal host count | `TerminalContainerView` instances with an attached terminal |
| Active Ghostty polling timer count | Running `outputPollTimer` instances |
| Board standalone view-model count | `VibeSpaceTerminalBoardStandaloneRegistry` entries |
| Visible board tile count | Board tiles currently in a window |
| Visible rail terminal count | Rail terminals currently in a window |
| Spotlight active | yes/no |
| Per-vibespace session counts | Map of vibespace ID → session count |

**Per-session rows:**

| Field | Description |
|---|---|
| `sessionID` | Stable debug ID |
| `surfaceID` | Stable debug ID (nil if no surface) |
| `vibespaceID` | Owning vibespace |
| `source` | Current presentation source |
| `isVisible` | Host is in a window and has nonzero frame |
| `isOccluded` | Occlusion state last sent to Ghostty |
| `isFocused` | Focus state last sent to Ghostty |
| `pixelSize` | Current surface pixel dimensions |
| `pollingActive` | Whether the 300ms output polling timer is running |
| `lastLifecycleEvent` | Most recent event name + timestamp |

### Debug snapshot action

Expose a debug-only "Terminal Diagnostics Snapshot" action (menu item or keyboard shortcut, debug builds only) that:

1. Captures the full `TerminalDiagnosticsSnapshot`
2. Writes it as a single JSON file to a known location (e.g. `~/Library/Logs/CrispyVibes/terminal-diagnostics-<timestamp>.json`)
3. Logs the file path to the console

This allows capturing one file during repro instead of piecing together from logs.

### Heap attribution

Run one short session with `MallocStackLoggingNoCompact=1` (1–2 minutes of normal usage) to separate C/heap growth from render-surface growth. Compare the heap bucket against IOSurface/IOAccelerator numbers from VM Tracker.

### Instruments configuration

- Points of Interest (for signposts)
- Metal System Trace or Core Animation (for surface rendering)
- Allocations (for heap attribution)

### What this proves

The diagnostics will definitively show whether memory growth is caused by:

- Surfaces not being destroyed
- Surfaces staying unoccluded offscreen
- Polling still running for hidden sessions
- Multiple presentation paths keeping sessions alive longer than expected

### Acceptance

- [ ] Every lifecycle event logged with session ID, surface ID, vibespace ID, source, and reason
- [ ] Anomaly assertions fire in debug builds for surface/session mismatches
- [ ] Debug snapshot action captures full JSON diagnostic file
- [ ] Signposts visible in Instruments for all surface lifecycle events
- [ ] Heap attribution run completed, C heap vs render surface growth documented

---

## Phase 2 — Occlusion Support

> Immediate memory/GPU win. Addresses RC-1, RC-2, RC-3.
>
> **Why occlusion reduces memory, not just GPU usage:** The 83.5 MB IOSurface + 43.1 MB IOAccelerator in the memory snapshot are GPU-backed memory buffers. Each IOSurface holds rendered pixels proportional to the surface's pixel dimensions. IOAccelerator holds Metal textures and render state. This memory exists because the GPU is actively rendering to those surfaces. When a surface is occluded, Ghostty stops rendering, and the GPU driver can reduce or reclaim those backing allocations. The IOSurface object still exists (the shell stays alive), but the GPU is no longer writing to it. So "stop GPU rendering" and "reduce memory" are the same action for this category of memory.

1. Call `ghostty_surface_set_occlusion(surface, true/false)` via `NSWindow.didChangeOcclusionStateNotification` — fires when the window is minimized or fully behind other windows.

2. Do NOT call occlusion from `viewDidMoveToWindow`. View-level transitions (tab switches, ownership transfers, spotlight open/close) are too brief and frequent — Ghostty does not reliably recover from rapid occlude/un-occlude cycles. This was confirmed during implementation: calling occlusion on view transitions caused terminals to become visually stuck.

3. Stop the 300ms output polling timer for occluded sessions. Resume on un-occlusion. The polling timer's `captureVisibleContentsIfNeeded()` touches the surface via `ghostty_surface_read_text`, which keeps GPU resources hot even for offscreen terminals.

4. Guard `startOutputPolling()` to only create a timer when the view is in a window. Guard the timer callback to skip work when the view has no window or no surface. This eliminates wasted viewport reads during startup and ownership transfers without using occlusion.

### Acceptance

- [ ] Minimized windows stop rendering (confirmed via Metal System Trace)
- [ ] Polling timer not running for occluded sessions
- [ ] Polling timer only starts when view is in a window
- [ ] Polling callback skips work when view has no window or no surface
- [ ] No UX change — shell processes, scrollback, output buffering unaffected
- [ ] Tab switches, spotlight, ownership transfers do not trigger occlusion

---

## Phase 3 — Central Surface Manager

> Architectural fix. Addresses RC-4, RC-5. Occlusion is driven by view lifecycle (viewDidMoveToWindow, NSWindow occlusion notification), not by vibespace membership.

5. Surface lifecycle is managed through the existing `TerminalHostOwnershipCoordinator` and view lifecycle hooks:

   - Visibility state tracked per session in `TerminalDiagnosticsSnapshot`
   - Presentation source derived from host accessibility identifier + display density
   - Focus state updated on `setAttachedSurfaceFocus`
   - Priority rules enforced by existing ownership arbitration (spotlight 300 > detailed 200 > board 200 > rail 120)

6. Board store reports tile count changes to the diagnostic snapshot via `persist()` (called at the end of `mutate` and on every `commit`).

7. Spotlight state tracked in diagnostic snapshot via `setTerminalSpotlight()`.

Note: VibeSpace-wide occlude/un-occlude was initially implemented but removed per review feedback — it was too broad and could wake hidden sessions or undo occlusion policy. Occlusion is now driven solely by actual view visibility transitions.

### Acceptance

- [ ] Only one promoted live render per session at any time (enforced by ownership coordinator)
- [ ] Offscreen views are occluded via viewDidMoveToWindow
- [ ] Minimized windows are occluded via NSWindow.didChangeOcclusionStateNotification
- [ ] Spotlight promotion transfers ownership, restores on dismiss

---

## Phase 4 — VibeSpace Close Teardown

> Session accumulation fix. Addresses RC-6, RC-7.

8. Fix `VibeSpaceState.resetSession()` to stop recreating `ProjectSession`s on close:

   - Snapshot `projectPaths` and `focusedProjectPath` before shutdown
   - Call `shutdownProjects()`
   - Set `projects = []`
   - Do not recreate `ProjectSession`s until the vibespace is reopened

9. Persist from metadata, not from live `ProjectSession`s. `persistVibeSpaceCatalog()` currently serializes using `vibespace.projects.map(\.rootURL.path)`. Change to use stored project paths so a closed vibespace persists correctly even when `projects` is empty.

10. Rebuild runtime sessions only on reopen. VibeSpace open/restore flows should instantiate fresh `ProjectSession`s from stored metadata.

11. Preserve focus by path, not by live project ID. Store `focusedProjectPath`; on reopen, resolve it back to the matching `ProjectSession.id`.

12. Audit `VibeSpaceTerminalBoardStandaloneRegistry` lifecycle — ensure `release()` is called on vibespace close and that standalone terminal view models do not accumulate across open/close cycles.

### Acceptance

- [ ] Clicking Home keeps the vibespace alive and resumable
- [ ] Clicking Close VibeSpace leaves no `ProjectSession` runtime graph alive for that vibespace
- [ ] Reopening the same vibespace creates fresh `ProjectSession`s
- [ ] Repeated open/close cycles do not ratchet the post-close heap upward
- [ ] Catalog persistence works even when a vibespace is closed and has no live `ProjectSession`s

---

## Phase 5 — Additional Optimizations

> Further savings. Addresses RC-8 and remaining surface cost.

13. Resize offscreen surfaces to minimal dimensions via `ghostty_surface_set_size(surface, 1, 1)` to reclaim IOSurface backing store. Restore original dimensions on re-promotion. (Causes minor terminal reflow on restore — deferred.)

14. Cache Ghostty default config at init time. Currently `ghostty_config_load_default_files()` is called on every theme change per surface. Removing it entirely caused a rendering regression (Ghostty needs base config for correct behavior). A future optimization could load defaults once and reuse the cached config, layering only runtime overrides on theme changes. Requires careful validation.

15. Keep the 300ms output polling timer, but scope it to visible surfaces and explicitly re-sync it on host/window lifecycle changes. Testing confirmed the timer is still needed for activity indicator state — the Ghostty callbacks don't provide equivalent coverage for idle/active detection.

16. Lazy creation of `TerminalViewModel` and `FolderExplorerViewModel` in `ProjectSession`. Currently both are `let` properties created eagerly at init. This is a codebase-wide refactor (dozens of files depend on stable object identity via `@ObservedObject`). Deferred — the vibespace close teardown fix already eliminates the main concern (sessions are no longer recreated on close).

### Acceptance

- [ ] IOSurface memory for offscreen surfaces drops to near zero (if resize implemented)
- [ ] Config load cached at init (if caching implemented)
- [ ] Polling timer remains limited to visible, in-window surfaces and resumes after host/window reattachment
- [ ] VibeSpace open does not eagerly allocate terminal engines for all projects (if lazy VMs implemented)

---

## Expected Outcome

| Metric | Before | After (estimated) |
|---|---|---|
| IOSurface + IOAccelerator | ~127 MB | Proportional to visible surfaces only |
| Thread count | ~40 (all sessions) | ~3 per visible session |
| Polling overhead | 16 reads/300ms | 0 for offscreen |
| Post-close vibespace memory | Recreated sessions | Empty |

---

## Files Affected

| File | Change |
|---|---|
| `TerminalDiagnosticsSnapshot.swift` (new) | Central debug snapshot singleton, per-session rows, JSON export |
| `TerminalLifecycleLogger.swift` (new) | Structured lifecycle event logging, stable debug IDs, anomaly checks (log-only for polling, assert for surface/registry) |
| `GhosttyTerminalEngine.swift` | Occlusion in viewDidMoveToWindow, setOccluded method, visibility-aware polling, surface/session debug IDs, resize logging, `ghostty_app_update_config` removed from theme changes |
| `TerminalSessionHostView.swift` | NSWindow.didChangeOcclusionStateNotification observer, host count tracking, presentation source + focus state wiring to snapshot |
| `TerminalSession.swift` | Session debug ID, lifecycle logging on create/terminate, surface assertion |
| `TerminalSessionDelegateAndView.swift` | Wire sessionDebugID to engine |
| `VibeSpaceState.swift` | `storedProjectPaths`, `storedFocusedProjectPath`, `resetSession()` true teardown, `configFile` stored-path fallback |
| `VibeSpaceStateProjectLifecycle.swift` | Keep storedProjectPaths in sync on addProjects/removeProject |
| `ContentViewCatalog.swift` | `persistVibeSpaceCatalog()` uses configFile |
| `ContentViewVibeSpaceHydration.swift` | Wire vibespaceID to snapshot after ensureActiveTerminal |
| `ContentViewProjectCanvas.swift` | Wire spotlightActive to snapshot |
| `VibeSpaceTerminalBoardStore.swift` | Standalone registry assertion (released key only), registeredCount accessor, tile count to snapshot |
| `CrispyVibesApp.swift` | Debug snapshot menu action, standalone registry count provider |
| `project.pbxproj` | New file references |

---

## Risks

- `ghostty_surface_set_occlusion` behavior is inferred from the official Ghostty app's usage. Phase 1 tracing will confirm whether occluded surfaces actually release render resources or just stop scheduling frames.
- The polling timer cannot be removed — activity indicators depend on the viewport diff. The timer is now visibility-aware (only runs for in-window sessions, skips work when offscreen) and must be explicitly re-synced after host detach/reattach or window moves.
- The vibespace close teardown changes persistence assumptions — `persistVibeSpaceCatalog()` now uses `vibespace.configFile` which falls back to `storedProjectPaths` when `projects` is empty. Code that assumes `projects` is non-empty after close will see an empty array.
- `ghostty_config_load_default_files()` is still called on every theme change. Removing it caused a rendering regression. Caching at init is a future optimization that needs careful validation.
- During ownership transfers (spotlight open/close, layout changes), the terminal view briefly has no window. The polling timer and occlusion calls handle this gracefully only if polling is explicitly re-synced on detach/reattach and window transitions; otherwise activity monitoring can silently stop.

---

## Implementation Notes

### Deferred items and rationale

**Resize offscreen surfaces to 1×1 (Phase 5, deferred)**
Calling `ghostty_surface_set_size(surface, 1, 1)` on offscreen surfaces would reclaim IOSurface backing store. However, Ghostty reflows all terminal content to fit the new column width — lines that were 120 columns wide get wrapped to 1 column. When the surface is restored to full size, content reflows again. The user would see a brief text reflow flash when switching back to a demoted tile. The occlusion fix already stops rendering and frees GPU scheduling resources without any visible artifact. This optimization can be revisited if IOSurface memory remains a concern after occlusion is validated.

**Remove 300ms output polling timer entirely (removed from plan)**
This proposal is no longer active. Testing confirmed the polling timer is still required for activity indicator state. Disabling it caused activity indicators to stop working entirely. The Ghostty action callbacks (`RENDER`, `COMMAND_FINISHED`, `SET_TITLE`, `PWD`) handle output detection and startup command timing, but the idle/active state for the tab activity dot relies on the viewport diff performed by `captureVisibleContentsIfNeeded()`. The correct fix is to keep polling visibility-aware and explicitly restart or stop it when the terminal view detaches, reattaches, or moves between windows.

**Cache Ghostty default config at init (Phase 5, deferred)**
Removing `ghostty_config_load_default_files()` from `applyThemeOverrideIfPossible()` caused a rendering regression — terminals became visually stuck on any layout change that triggered a theme reapply. Ghostty needs its base config (font rendering, key bindings, terminal behavior) to function correctly. The call was restored. A future optimization could cache the loaded defaults at init time and reuse them, but this requires careful validation that the cached config stays correct across appearance changes.

**Lazy TerminalViewModel / FolderExplorerViewModel creation (Phase 5, deferred)**
Both are `let` properties on `ProjectSession`, which is an `ObservableObject`. Changing them to lazy or optional computed properties would require every SwiftUI view that reads `project.terminalViewModel` to handle the possibility of it not existing yet. The `@ObservedObject` wrappers that depend on stable object identity would break. This is a codebase-wide refactor touching dozens of files. Now that `resetSession()` sets `projects = []` instead of recreating sessions, the eager creation only costs memory during an active vibespace — which is the expected state.

### What was implemented vs what was planned

| Planned | Status | Notes |
|---|---|---|
| Stable debug IDs | ✅ Done | Monotonic S1/S2/SF1/SF2 IDs on TerminalSession and GhosttyTerminalEngine |
| Structured lifecycle logging | ✅ Done | 11 events, source + reason on every log line |
| Anomaly assertions | ✅ Done | 3 checks: polling-while-hidden (log-only), surface-outlived-session (assert), standalone-VMs-after-close (assert on released key) |
| TerminalDiagnosticsSnapshot | ✅ Done | Global counters + per-session rows, all fields wired |
| Debug snapshot action | ✅ Done | Cmd+Opt+Shift+D in debug builds, JSON to ~/Library/Logs/CrispyVibes/ |
| Heap attribution run | ⏳ Manual | Requires Instruments with MallocStackLoggingNoCompact — cannot be done in code |
| `ghostty_surface_set_occlusion` | ✅ Done | Called via NSWindow.didChangeOcclusionStateNotification only. NOT called from viewDidMoveToWindow — view-level transitions are too brief and cause stuck surfaces. |
| Stop polling for occluded sessions | ✅ Done | stopOutputPolling on occlude, resume on un-occlude. Timer guarded to only start when view is in window. Callback skips work when no window/surface. |
| Surface manager wiring | ✅ Done | Diagnostics track source, visibility, focus, vibespaceID per session. Board tile count and spotlight state wired. |
| resetSession() true teardown | ✅ Done | Snapshots paths, shuts down, sets projects=[], no recreation |
| configFile uses stored paths | ✅ Done | Falls back to storedProjectPaths when projects is empty. No unresolved path duplication. |
| persistVibeSpaceCatalog() fix | ✅ Done | Uses configFile instead of direct project access |
| storedProjectPaths sync | ✅ Done | Updated in addProjects() and removeProject() |
| Standalone registry assertion | ✅ Done | Validates released vibespace key only (not global emptiness) |
| `ghostty_app_update_config` removed | ✅ Done | No longer leaks one surface's palette as app-wide default in multi-tile setups |
| `ghostty_config_load_default_files` removal | ❌ Reverted | Caused rendering regression — Ghostty needs base config. Restored. |
| VibeSpace-wide occlude/un-occlude | ❌ Removed | Too broad — could wake hidden sessions. Occlusion driven by view lifecycle only. |
| Resize offscreen to 1×1 | ⏸ Deferred | Causes terminal reflow |
| Remove polling timer entirely | ❌ Removed | Activity indicators depend on viewport diff; lifecycle-scoped polling remains required |
| Cache config at init | ⏸ Deferred | Needs validation that cached config stays correct |
| Lazy TerminalViewModel | ⏸ Deferred | Codebase-wide refactor |

### Regressions found and fixed during implementation

**1. Polling anomaly assertion crashed during ownership transfers.**
The polling anomaly assertion (`assertPollingNotRunningWhileHidden`) used `assertionFailure()` which calls `abort()` in debug builds. The 300ms polling timer fires for every live session, and during ownership transfers (spotlight open/close, layout changes), the terminal view briefly has no window. This caused the assertion to fire on every polling tick during transitions, effectively crashing the polling callback. Symptoms: terminals appeared visually stuck (frozen image, no interaction). Fix: downgraded the assertion to log-only, and guarded the polling callback to skip work when the view has no window or no surface.

**2. Removing `ghostty_config_load_default_files()` broke rendering.**
Removing the call from `applyThemeOverrideIfPossible()` left the surface config missing essential Ghostty defaults (font rendering, key bindings, terminal behavior). Any layout change that triggered a theme reapply (hiding explorer, focus mode) would apply a near-empty config, causing the surface to stop rendering. Fix: restored the call. Only `ghostty_app_update_config()` was removed (the actual multi-tile palette leak).

**3. Calling occlusion from `viewDidMoveToWindow` caused stuck tabs.**
`ghostty_surface_set_occlusion(true)` was called every time the view left a window, including during brief ownership transfers (tab switches, spotlight open/close). Ghostty does not reliably recover from rapid occlude/un-occlude cycles. Fix: removed occlusion calls from `viewDidMoveToWindow` entirely. Occlusion is now only driven by `NSWindow.didChangeOcclusionStateNotification` (stable, long-duration window-level events like minimize).

**4. Activity monitoring could stop after host/window churn.**
Polling was correctly guarded to visible surfaces, but that alone was not enough. During host ownership changes or window transitions, an existing Ghostty surface could survive while its polling timer stopped. Because the host reattach path only restored display ID and geometry, activity monitoring could remain dormant after the view came back. Fix: add an explicit `syncOutputPollingToVisibility()` path and call it from `GhosttyTerminalView.viewDidMoveToWindow()` and `TerminalSessionHostView` surface restore/detach paths.

### Points to verify during review

1. **`resetSession()` now sets `projects = []`** — any code that iterates `vibespace.projects` after close will see an empty array. The `configFile` computed property handles this by falling back to `storedProjectPaths`. Verify that no other code path assumes `projects` is non-empty after close.

2. **`persistVibeSpaceCatalog()` was changed to use `vibespace.configFile`** instead of manually constructing a `VibeSpaceConfigFile` from live projects. This means persistence now goes through the same path that handles the empty-projects fallback. The per-project config loop still iterates `vibespace.projects`, which will be empty after close — this is correct because there are no project-level settings to persist for a closed vibespace.

3. **`ghostty_config_load_default_files()` is still called on every theme change** — removing it caused a rendering regression. The `ghostty_app_update_config()` call was the actual multi-tile bug and is removed. The disk I/O from loading default files on theme changes remains as a future optimization target (cache at init).

4. **`ghostty_app_update_config()` removed from theme changes** — previously, every surface's theme change pushed its palette as the app-wide default. In multi-tile setups, the last tile to apply its theme would win. Now only `ghostty_surface_update_config()` is called, which is per-surface. The app-wide config remains as set during initial runtime setup.

5. **Occlusion is called from one path only** — `NSWindow.didChangeOcclusionStateNotification` (window-level, fires when the window is minimized or fully behind other windows). It is NOT called from `viewDidMoveToWindow` — view-level transitions are too brief and Ghostty doesn't recover reliably from rapid occlude/un-occlude cycles. This was confirmed by a regression during implementation.

6. **Polling timer is now visibility-aware** — `startOutputPolling()` guards on `terminalView.window != nil` and won't create a timer for offscreen sessions. The timer callback skips `captureVisibleContentsIfNeeded()` if the view has no window or no surface. This eliminates wasted viewport reads during startup (when sessions exist before views enter windows) and during ownership transfers.
