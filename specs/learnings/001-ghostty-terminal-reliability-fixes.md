# Ghostty Terminal Reliability Fixes

**Date:** 2026-03-09
**Status:** Proposed
**Scope:** `GhosttyTerminalEngine`, `TerminalSession`, `TerminalSessionCommandDispatch`

---

## Problem Statement

The Ghostty terminal integration has four reliability gaps:

1. **Startup commands fire at the wrong moment** — some shells/vibespaces see commands dispatched before the prompt is ready.
2. **Activity animation is mis-timed** — the indicator can miss real activity or flicker during bursty output.
3. **Readiness detection is heuristic-only** — the app infers "ready" from regex prompt matching instead of a clean signal.
4. **Parity with SwiftTerm is incomplete** — the Ghostty engine follows a different startup-command dispatch path that hasn't been proven equivalent.

---

## API Constraints (validated against vendored header)

The following was verified against `projects/crispyvibes/vendor/GhosttyKit.xcframework/macos-arm64_x86_64/Headers/ghostty.h`:

| Capability | Available? | Notes |
|---|---|---|
| `GHOSTTY_ACTION_COMMAND_FINISHED` | ✅ Yes (line 901) | Payload: `exit_code` (int16, -1 if none), `duration` (uint64, nanoseconds) |
| `GHOSTTY_ACTION_RENDER` | ✅ Yes (line 871) | Fires on every render frame |
| Prompt-start action (OSC 133;A) | ❌ No | Ghostty processes this internally but does not surface it to embedders |
| Child PID API | ❌ No | Only `ghostty_surface_process_exited()` → bool is available |
| Shell integration auto-injection | ✅ Yes | Ghostty auto-injects for bash, zsh, fish, elvish (see ghostty.org/docs/features/shell-integration) |

**Key insight:** Since Ghostty auto-injects shell integration, `COMMAND_FINISHED` fires reliably for the vast majority of users after every command — including the shell's own startup sequence. This makes it a trustworthy "prompt is ready" signal.

---

## Fixes

### Fix 1: Dead-end scheduling — startup commands stuck forever

**File:** `TerminalSessionCommandDispatch.swift` — `nextPendingCommandEvaluationDate` and `commandDispatchReady`

**Root cause:** When `requiresInteractivePromptForStartupCommands = true` (Ghostty) and `lastOutputReceivedAt` is nil (no output detected yet), `nextPendingCommandEvaluationDate` returns `nil`. This causes `schedulePendingCommandEvaluationIfNeeded` to cancel the evaluation timer permanently. The startup command sits in the queue with no timer to ever re-evaluate it.

The only things that call `flushPendingCommandsIfReady` are delegate callbacks (resize, directory change, output detection). If none of those fire before the timer is cancelled, the command is permanently stuck.

**Fix:** Always schedule a hard fallback timer based on `enqueuedAt` (3× the normal delay = 3.6s). This guarantees the evaluation timer is never nil when commands are pending.

Additionally, `commandDispatchReady` now has a matching hard fallback: if `queuedAge >= startupCommandFallbackDelay * 3`, dispatch regardless of output/prompt state.

### Fix 2: PWD action not used for readiness or activity

**File:** `GhosttyTerminalEngine.swift` — `handleWorkingDirectoryChange`

**Root cause:** `GHOSTTY_ACTION_PWD` fires when Ghostty's shell integration reports the working directory. This is a definitive signal that the shell is alive and has completed initialization. But the handler only forwarded the directory to the delegate — it didn't mark the engine as interactive or report output.

This meant that even when shell integration was working and PWD was firing, the engine still waited for the regex heuristic in `captureVisibleContentsIfNeeded` to detect the prompt.

**Fix:** `handleWorkingDirectoryChange` now also sets `hasObservedInteractivePrompt = true` and reports renderable output. This immediately unblocks startup commands and triggers activity.

### Fix 3: Title change not used for output detection

**File:** `GhosttyTerminalEngine.swift` — `handleTitleChange`

**Root cause:** `GHOSTTY_ACTION_SET_TITLE` fires when the shell sets the terminal title (common in zsh/bash). This is another signal the shell is running, but it wasn't used to mark output received.

**Fix:** `handleTitleChange` now marks `hasReportedRenderableOutput` and reports to the delegate, which triggers `markReadyFromOutput` in the session.

### Fix 4: `handleCommandFinished` → also mark interactive readiness

**File:** `GhosttyTerminalEngine.swift` — `handleCommandFinished`

**Problem:** `GHOSTTY_ACTION_COMMAND_FINISHED` only called `terminalEngineDidReceiveSignificantOutput`. A finished command means the shell is back at its prompt.

**Fix:** Also sets `hasObservedInteractivePrompt` and calls `terminalEngineDidBecomeInteractive`.

### Fix 5: `ghostty_surface_text` does not execute commands — Enter key must be sent via `ghostty_surface_key`

**File:** `GhosttyTerminalEngine.swift` — `send(text:)`

**Root cause:** `ghostty_surface_text` is the IME/paste text input path. It does not pass control characters (`\r`, `\n`) through to the PTY as keypresses. So appending `\n` or `\r` to command text made the text appear on screen but never executed — the shell's line editor never received an Enter keypress.

**Fix:** `send(text:)` now detects a trailing `\r` or `\n`, strips it, sends the command body via `ghostty_surface_text`, then simulates an Enter keypress via `ghostty_surface_key` with `GHOSTTY_KEY_ENTER` (press + release). This matches exactly what happens when a user physically presses Return.

### Fix 6: Defer banner suppression clear to next run loop tick

**File:** `GhosttyTerminalEngine.swift` — `captureVisibleContentsIfNeeded`

**Problem:** Sending the clear command inline during render caused a re-entrant render cycle.

**Fix:** Wrapped in `DispatchQueue.main.async`.

### Fix 7: Bump `idleThreshold` from 1.0s to 1.5s

**File:** `TerminalSession.swift`

**Fix:** Reduces activity indicator flicker during bursty output.

### Fix 7: Extract `COMMAND_FINISHED` payload

**File:** `GhosttyTerminalEngine.swift`

**Fix:** `handleCommandFinished(exitCode:duration:)` now receives the exit code and duration from the action payload.

---

## Files Modified

| File | Change |
|---|---|
| `GhosttyTerminalEngine.swift` | Fixes 2, 3, 4, 5, 6, 8 |
| `TerminalSessionCommandDispatch.swift` | Fix 1 (dead-end scheduling + hard timeout) |
| `TerminalSession.swift` | Fix 7 |

## What Is NOT Changed

- **Delegate protocol** (`TerminalSessionEngineDelegate`) — no signature changes.
- **SwiftTerm engine** — unaffected; it doesn't use `requiresInteractivePromptForStartupCommands`.
- **Regex heuristic** (`likelyInteractivePrompt`) — kept as fallback for shells without integration.
- **Tests** — not modified unless explicitly requested.

## Risks

- Fix 1 hard timeout (3.6s) means startup commands fire even if the shell isn't ready. This is a last resort — the PWD/title/COMMAND_FINISHED signals should fire well before 3.6s in normal operation.
- Fix 2 (PWD → interactive) assumes a PWD report means the shell is at a prompt. This is true for initial shell startup but could theoretically fire during a `cd` command. In practice this is fine because `hasObservedInteractivePrompt` is only checked once.
- Fix 6 (1.5s threshold) means the activity indicator stays lit slightly longer after a command finishes.
