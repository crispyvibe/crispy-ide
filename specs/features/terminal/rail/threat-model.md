# Terminal Rail — Threat Model

## Overview

Terminal Rail manages compact terminal presentation in the stacked project rail. It handles activity detection from terminal output, project-stack grouping and ordering, hover/focus expansion, and hide/unhide controls. The feature performs no I/O beyond reading terminal session state — it is a pure presentation layer over existing terminal sessions. The threat surface is minimal, limited to activity indicator spoofing, resource consumption from rapid state changes, and information disclosure through rail previews.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Terminal session output ↔ Activity detection | `TerminalSession.markRenderableActivityFromOutput()` sets `isCurrentlyActive` based on incoming data. The activity state propagates to rail card indicators via `TerminalTabActivityState`. |
| Rail card presentation ↔ Terminal session content | Rail cards render a compact terminal preview using the same `TerminalSessionEngine.hostedView`. The preview shows live terminal output at reduced font size. |
| Hide/unhide state ↔ Persistence | Hidden terminal state is persisted in vibespace layout. A hidden terminal's process remains alive but is not rendered. |
| Ownership coordinator ↔ Rail host | `TerminalHostOwnershipCoordinator` arbitrates which host (focused pane vs. rail card) owns the terminal view. Only the owning host applies density settings. |

## Attack Surfaces

1. **Activity indicator manipulation** — A malicious process can generate rapid output to keep the activity indicator permanently lit, or craft output that triggers/suppresses activity detection.
2. **Rail preview content visibility** — Compact rail previews show live terminal output. Sensitive content (passwords being typed with echo, tokens in output) is visible in the rail even when the terminal is not focused.
3. **Hide/unhide state tampering** — Tampered persistence could mark all terminals as hidden, or unhide terminals the user intentionally hid.
4. **Ownership handoff race conditions** — Rapid project focus switching could cause brief moments where density is applied incorrectly or the terminal view is momentarily unowned.

## Threats

### F004-T01: Activity indicator flooding via rapid terminal output

- **Vector:** A malicious or misbehaving process generates continuous output (e.g., infinite loop printing, `yes` command, log flooding). The activity indicator stays permanently lit, and the idle reset timer (`idleThreshold: 1.5s`) never fires.
- **Impact:** Misleading UI — the activity indicator loses its signal value. Minor CPU overhead from continuous `scheduleIdleReset()` calls creating and cancelling `DispatchWorkItem` instances.
- **Likelihood:** Medium — common in development (runaway processes, verbose logging, `tail -f` on active logs).
- **Mitigation:** The idle reset uses `DispatchWorkItem` cancellation — each new activity cancels the previous timer, so only one pending work item exists at a time. The activity state is a simple boolean toggle with no accumulation. Startup and resize suppression windows (`startupActivitySuppression: 0.9s`, `resizeActivitySuppression: 0.35s`) prevent false positives during initialization. The indicator is purely cosmetic — it does not trigger any automated actions. Linked NFR: PERF-Responsiveness.

### F004-T02: Sensitive content visible in compact rail preview

- **Vector:** A terminal session displays sensitive information (API keys, passwords in output, database connection strings). The rail preview renders this content at compact font size, visible to anyone viewing the screen — even when the user is focused on a different project.
- **Impact:** Information disclosure to shoulder surfers or screen recording.
- **Likelihood:** Medium — developers frequently work with secrets in terminals. The rail preview is always visible for non-focused projects.
- **Mitigation:** The rail preview uses compact density font sizing (`railTerminalCompactFontSize`) which makes text harder to read at a glance. The preview shows the same content as the full terminal — no additional exposure beyond what the terminal already displays. Users can hide terminals from the rail via context menu (F004-R08), removing them from the visible stack. The hide action preserves the process without rendering. Linked NFR: SEC-Data-Protection.

### F004-T03: Hidden terminal state tampering via persistence

- **Vector:** An attacker modifies vibespace JSON to change hidden terminal flags, either hiding all terminals (denial of service — user sees empty rail) or unhiding terminals the user intentionally hid.
- **Impact:** UI confusion; previously hidden sensitive terminals become visible in the rail.
- **Likelihood:** Very low — vibespace persistence is HMAC-signed.
- **Mitigation:** Persistence integrity is protected by HMAC signing. Hidden terminals can be re-hidden via the rail context menu. The hide/unhide operation is non-destructive — it only affects rendering, not process state. Linked NFR: SEC-Data-Protection.

### F004-T04: Ownership handoff density flicker during rapid focus switching

- **Vector:** Rapidly switching project focus causes the ownership coordinator to transfer terminal view ownership between the focused pane host and the rail card host. During the handoff, the terminal view may briefly render at the wrong density (regular size in rail, or compact size in focused pane).
- **Impact:** Visual glitch — text appears at wrong size momentarily. No security impact.
- **Likelihood:** Low — the coordinator uses synchronous ownership transfer with priority-based arbitration.
- **Mitigation:** `TerminalHostOwnershipCoordinator.ensureOwnership()` is synchronous and uses `ownershipArbitrationPriority` to resolve conflicts deterministically. The non-owning host defers attach until ownership is acquired (F001-R13). Only the owning host applies density (F001-R14). The grace period on hover collapse prevents flicker during pointer movement. Linked NFR: PERF-Responsiveness.

### F004-T05: Resource consumption from many visible rail terminals

- **Vector:** A vibespace with many projects, each having multiple visible terminals, creates many `TerminalTabActivityState` objects and activity summary observers. Each terminal in the rail maintains a live `NSView` even when collapsed behind the representative terminal.
- **Impact:** Memory and GPU overhead from maintaining many live terminal views.
- **Likelihood:** Low — typical vibespaces have 2-5 projects with 1-3 terminals each.
- **Mitigation:** Collapsed stacks show only the representative terminal on top — other terminals are not rendered until hover/focus expansion (F004-R05). The ownership coordinator ensures only one host owns the view at a time. Hidden terminals are excluded from the stack entirely (F004-R03). Activity state objects are lightweight (`@Published` boolean). Linked NFR: PERF-Responsiveness.

## Residual Risks

- Rail previews inherently show terminal content. There is no content filtering or redaction — the rail shows exactly what the terminal shows. Users working with sensitive data must be aware of shoulder-surfing risk.
- The activity detection threshold is fixed at ~1 second. Very brief bursts of output (single line) may not trigger the indicator, while continuous slow output (one line per 0.9s) keeps it permanently active. This is a UX tuning issue, not a security concern.
- Terminal view ownership is managed by a coordinator that uses weak references. If a host is deallocated without unregistering, the coordinator's `pruneDeadHosts()` cleans up on next access, but there may be a brief window where ownership state is stale.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | N/A | Rail does not accept user input or parse external data; it reads existing session state. |
| SEC-Data-Protection | Compliant | Hidden state persisted with HMAC integrity; no additional secrets stored. |
| PERF-Responsiveness | Compliant | Single pending `DispatchWorkItem` for idle reset; collapsed stacks minimize rendered views; activity state is lightweight. |
| A11Y | Compliant | Hover expansion has keyboard-reachable equivalent (F004-R05); context menu for hide/unhide. |
| OBS | Compliant | Activity state changes logged per acceptance criteria. |
