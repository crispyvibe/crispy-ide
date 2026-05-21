# Ghostty Integration — Bad Practices & Fixes

**Date:** 2026-03-21
**Scope:** `GhosttyTerminalEngine`, `GhosttyTerminalView`, `GhosttyTerminalRuntime`

---

## 1. Clipboard Read Auto-Confirmed Without User Consent (Security)

**Severity:** High
**File:** `GhosttyTerminalEngine.swift` — `confirm_read_clipboard_cb`

**Problem:** The callback immediately confirms clipboard read requests:

```swift
ghostty_surface_complete_clipboard_request(surface, content, state, true)
```

Any program running in the terminal can silently read the system clipboard via OSC 52. A malicious script could exfiltrate passwords, tokens, or other sensitive clipboard contents without the user knowing.

**Fix:** Either deny by default (`false`) or show a user confirmation prompt before completing the request.

---

## 2. `ghostty_app_update_config` Called With Per-Surface Colors

**Severity:** Medium
**File:** `GhosttyTerminalEngine.swift` — `applyThemeOverrideIfPossible()`

**Problem:** The method calls both:

```swift
ghostty_app_update_config(app, config)    // sets app-wide config
ghostty_surface_update_config(surface, config)  // sets surface config
```

The app-level call pushes one surface's palette as the global default. In the multi-tile terminal board, the last tile to apply its theme wins the app-wide config. If tiles ever have different themes (or race during startup), this causes incorrect colors on other surfaces.

**Fix:** Remove the `ghostty_app_update_config` call. Only call `ghostty_surface_update_config` for per-surface theme application.

---

## 3. `ghostty_config_load_default_files` Reloaded on Every Theme Change

**Severity:** Medium
**File:** `GhosttyTerminalEngine.swift` — `applyThemeOverrideIfPossible()`

**Problem:** Every call creates a fresh config and loads the user's `~/.config/ghostty/config` from disk:

```swift
let config = ghostty_config_new()
ghostty_config_load_default_files(config)
// ... then layers runtime overrides on top
```

This means:
- Disk I/O on every palette change
- User's personal Ghostty settings silently override CrispyVibes's intended config (keybindings, behaviors, scrollback-limit, etc.)
- Settings drift: a user with `scrollback-limit = 0` in their ghostty config would override the calculated value

**Fix:** Load default files once at init time. On theme changes, create a config that only contains the runtime overrides (colors, scrollback-limit) without re-reading user defaults.

---

## 4. Output Polling Is Required, But It Must Be Lifecycle-Scoped

**Severity:** Low–Medium
**File:** `GhosttyTerminalEngine.swift` — `startOutputPolling()`, `captureVisibleContentsIfNeeded()`

**Problem:** `captureVisibleContentsIfNeeded()` reads the entire visible viewport via `ghostty_surface_read_text`, allocates a String, then compares it to `lastVisibleContents` via full string equality. That work is still necessary for tab activity state because Ghostty's action callbacks do not provide a complete idle/active signal. The real bug was lifecycle drift: polling could remain stopped after detach/reattach or window churn unless the host explicitly re-synced it.

**Fix:** Keep polling, but scope it tightly:
- only run it for visible, in-window surfaces
- stop it immediately on detach or loss of visible surface
- explicitly re-sync it on host reattach and `viewDidMoveToWindow`

**Historical note:** Older guidance in this document recommended removing the timer entirely. That recommendation has been retired because real-world testing showed activity indicators regress without the viewport-diff polling path.

---

## 5. No `NSTextInputClient` Conformance — IME Is Broken

**Severity:** Medium
**File:** `GhosttyTerminalEngine.swift` — `GhosttyTerminalView`

**Problem:** The view doesn't implement `NSTextInputClient` (`insertText(_:replacementRange:)`, `setMarkedText(_:selectedRange:replacementRange:)`, etc.). This means:
- CJK input methods don't work
- Emoji composition via the character viewer doesn't work
- Dead-key accents (e.g. ´ + e → é) may not work correctly

The official Ghostty macOS app implements full `NSTextInputClient` conformance for this reason.

**Fix:** Conform `GhosttyTerminalView` to `NSTextInputClient`. Route `insertText` through `ghostty_surface_key` with the `composing` flag, and handle marked text for in-progress composition.

---

## 6. Middle Mouse Button Not Forwarded

**Severity:** Low
**File:** `GhosttyTerminalEngine.swift` — `GhosttyTerminalView`

**Problem:** `otherMouseDown` / `otherMouseUp` are not implemented. Middle-click paste (standard terminal behavior on Linux, also expected by many power users on macOS) doesn't work.

**Fix:** Implement `otherMouseDown` / `otherMouseUp` and forward to `ghostty_surface_mouse_button` with `GHOSTTY_MOUSE_MIDDLE`.

---

## Context: Memory Leak (Already Fixed)

The Ghostty PageList memory leak ([PR #10251](https://github.com/ghostty-org/ghostty/pull/10251), Jan 10 2026) and its follow-up tracked-pins regression fix ([PR #10285](https://github.com/ghostty-org/ghostty/pull/10285), Jan 11 2026) are both present in the current pinned commit (`7dd5898`, Mar 3 2026). The fork merged upstream on Feb 18 2026, well after both fixes landed. No action needed.

---

## Priority Order

1. **Clipboard security** — ship-blocking if Ghostty becomes the default engine
2. **App-wide config leak** — causes visible bugs in multi-tile setups
3. **Default files reload** — causes subtle config drift
4. **IME support** — blocks international users
5. **Polling timer** — performance waste, easy win
6. **Middle mouse** — nice-to-have
