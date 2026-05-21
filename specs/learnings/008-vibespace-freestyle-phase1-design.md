# VibeSpace Freestyle — Phase 1

**Date:** 2026-03-23
**Status:** Proposed
**Author:** Crispy Team

---

## What This Is About

CrispyVibes is a macOS terminal vibespace app. Users create vibespaces with multiple projects, each project having its own terminals, file explorer, and editor. Today the app has two vibespace canvas modes:

- **Terminal Board** — a grid of terminal tiles. Great for multi-terminal workflows but no file viewing.
- **Detailed View** — file explorer + editor on top, single terminal pinned at the bottom. Good for code reading but the terminal is stuck in one place.

Users want to design their own vibespace layout — mix terminals, files, and web pages in any arrangement. This document describes Phase 1: two incremental features that move toward that goal without a full rewrite.

---

## Context: How the App Works Today

### Terminal Lifecycle

Each `ProjectSession` owns a `TerminalViewModel` which manages terminal tabs. Each tab has a `TerminalSession` which owns a `GhosttyTerminalEngine` (or `SwiftTermTerminalEngine`). The engine creates a Ghostty surface (Metal-backed GPU renderer) when its view enters a window.

Key ownership chain:
```
VibeSpaceState → ProjectSession → TerminalViewModel → TerminalSession → Engine → Surface
```

Terminals are presented through different hosts (board tiles, spotlight overlay, rail, detailed view). The `TerminalHostOwnershipCoordinator` ensures only one host renders a terminal at a time — the view physically moves between hosts.

### File Viewer

The `ContentViewerStore` is vibespace-level. All projects share one file viewer. Files open as tabs in `EditorGroupStore`. The viewer supports split panes (up to 4) via `SplitViewStore` with a recursive `SplitPaneNode` tree. Users can drag tabs between panes and drag to edges to create new splits (IDE-style drop zones: left, right, top, bottom, center).

Tab types today: `.file(URL)`, `.vibeCast`, `.webPage(URL)`.

### Memory Model

Recent work (v1.0.2–1.0.5) addressed terminal memory issues:

- **Closure leaks** — engine `terminate()` now clears all stored closures
- **Polling overhead** — two-phase polling: full viewport reads during startup (~5s), then 1s hash-only comparison. No retained viewport strings after startup.
- **VibeSpace close** — `resetSession()` sets `projects = []`, no recreation. Sessions rebuilt only on reopen.
- **Surface occlusion** — the old experimental toggle was removed after repeated restore regressions; current terminal recovery avoids the custom occlusion path.
- **Surface context** — all surfaces now use `GHOSTTY_SURFACE_CONTEXT_SPLIT` instead of `CONTEXT_WINDOW`.

---

## Phase 1: What We're Building

### Feature 1: File Viewer Scope Toggle

**Problem:** The tab bar shows files from all projects. With multiple projects, it gets cluttered.

**Solution:** A toggle in the content viewer header — "This Project" / "All Projects".

**How it works:**
- "This Project" filters tabs to files whose path starts with the focused project's root
- "All Projects" shows everything (current behavior)
- VibeCast and webPage tabs always visible regardless of scope
- Filter is display-only — tabs are hidden, not removed. Switching scope reveals them.
- Scope preference persisted per vibespace

**Files affected:**
- `ContentViewerStore.swift` — add `ViewerScope` enum and `scopeFilter` property
- `EditorGroupStore.swift` — add `filteredTabs(projectRootPath:)` method
- `ContentViewerView.swift` — add scope toggle UI in header
- `VibeSpaceSessionState.swift` — persist scope preference

**Testing:**
- Unit test: `filteredTabs` returns correct subset for a given project root
- Unit test: VibeCast/webPage tabs pass all filters
- Unit test: active tab selection preserved when filter changes

### Feature 2: Terminal as a Content Viewer Tab

**Problem:** In detailed view, the terminal is pinned at the bottom. Users can't view a terminal side-by-side with a file, or have multiple terminals in the editor area.

**Solution:** Add `.terminal(projectID: UUID, tabID: UUID)` as a new tab kind. Terminals become first-class tabs in the split pane system.

**How it works:**

1. User right-clicks a terminal → "Open in Editor Pane"
2. A `.terminal` tab is created in the active editor group
3. The terminal view moves to the editor pane via the ownership coordinator
4. The terminal can be dragged between panes, dragged to edges to create splits
5. Closing the tab does NOT kill the session — the terminal returns to its original host

**Files affected:**
- `ContentViewerTab.swift` — add `.terminal` kind with title, icon, drag payload encoding
- `SplitPaneContentView.swift` — render `TerminalSessionHostView` for `.terminal` tabs
- `GhosttyTerminalEngine.swift` — add "Open in Editor Pane" to right-click menu
- `ContentViewerTabDragSupport` — encode/decode `.terminal` drag payloads
- `SplitViewStore.swift` — terminal tab persistence in session state
- `VibeSpaceSessionState.swift` — encode/decode terminal tab references

**Testing:**
- Unit test: `.terminal` tab ID is stable (`"terminal:\(projectID):\(tabID)"`)
- Unit test: closing terminal tab does not terminate session
- Unit test: drag payload round-trips correctly for terminal tabs
- Integration: terminal renders in editor pane, receives input, shows output

---

## How to Prevent Memory Leaks

Terminal memory is the primary concern. The ownership chain is long and every link can retain objects.

### Rules for the implementer

1. **Terminals are owned by `TerminalViewModel`, never by editor groups.** The `.terminal` tab holds IDs (projectID + tabID), not references. The editor pane looks up the session at render time. If the session is gone, show a placeholder.

2. **The ownership coordinator is the single source of truth for which host renders a terminal.** When a terminal tab becomes active, call `TerminalHostOwnershipCoordinator` to transfer the view. Never add the terminal NSView to a host directly.

3. **Closing a terminal tab must not call `session.close()` or `engine.terminate()`.** It only removes the tab from the editor group. The session stays alive in `TerminalViewModel.tabs`.

4. **No strong references from editor groups to terminal objects.** The `ContentViewerTab` stores `projectID` and `tabID` (value types). The `SplitPaneContentView` resolves the session via a lookup closure, not a stored reference.

5. **Session restore must handle missing terminals gracefully.** On vibespace reopen, if a persisted `.terminal` tab references a project or tab that no longer exists, silently remove it from the editor group. Do not crash or create orphan sessions.

6. **Test with `weak` references.** Add memory lifecycle tests that verify:
   - Closing all editor panes with terminal tabs does not leak sessions
   - Closing a vibespace releases all terminal tabs from editor groups
   - `resetSession()` clears terminal tab references from editor state

### Patterns from recent memory fixes to follow

- Clear closures on teardown (see `GhosttyTerminalEngine.terminate()`)
- Use `[weak self]` in all callbacks and timers
- Don't retain viewport strings — the two-phase polling system avoids this
- Don't restart polling after lightweight tracking transition
- Test deallocation with `WeakRef` pattern (see `TerminalMemoryLifecycleTests`)

---

## How to Use Terminals Better (Ghostty Integration Notes)

The app embeds Ghostty via `GhosttyKit.xcframework`. Key things the implementer should know:

### Surface lifecycle
- One `ghostty_app_t` for the entire app (singleton `GhosttyTerminalRuntime`)
- One `ghostty_surface_t` per terminal (created in `GhosttyTerminalView.createSurfaceIfNeeded`)
- Surface is created when the view enters a window, destroyed on `terminate()`
- All surfaces use `GHOSTTY_SURFACE_CONTEXT_SPLIT` (they share one window)

### Rendering
- Ghostty drives its own Metal render loop internally — we do NOT call `ghostty_surface_draw()`
- The `wakeup_cb` → `ghostty_app_tick()` cycle processes IO and triggers renders
- Activity detection uses a two-phase system: full viewport reads during startup, then 1s hash-only polling after interactive prompt is detected

### Focus
- `TerminalFocusCoordinator` is the single source of truth for which terminal has Ghostty focus
- `ghostty_surface_set_focus(true/false)` must be called through the coordinator, never directly
- Only one surface can be focused at a time — the coordinator enforces mutual exclusion
- Paste targeting depends on focus: `copy:/paste:` actions check `TerminalFocusCoordinator.currentSessionID`

### Control characters
- `ghostty_surface_text()` is the IME/paste path — it drops control characters
- Control signals (Ctrl+C, Ctrl+D, etc.) must be sent via `ghostty_surface_key()` with `GHOSTTY_MODS_CTRL`
- See `sendControlKey(to:keycode:mods:text:unshiftedCodepoint:)` in `GhosttyTerminalEngine`

### Config
- Each surface gets its own runtime config via `ghostty_surface_update_config()`
- Do NOT call `ghostty_app_update_config()` — it leaks one surface's palette as the app-wide default
- `ghostty_config_load_default_files()` is called per theme change (caching deferred — removal caused regression)

---

## Future Plan

### Phase 2: Freestyle Canvas Mode

A third vibespace canvas mode alongside Terminal Board and Detailed:
- All content types (terminals, files, web pages) in the split pane system
- Multi-project scope — terminals from any project in any pane
- Layout templates ("2 terminals + 1 file", "3-column code review")
- Bidirectional drag between editor panes and terminal board
- Persist freestyle layouts per vibespace

### Phase 3: VibeSpace Templates

- Pre-built vibespace layouts for common workflows
- "Backend dev" — terminal + API file + logs terminal
- "Code review" — diff view + source + terminal for tests
- Users can save their current layout as a template
- Templates shared across vibespaces

---

## Architecture Diagram

```
VibeSpaceState
├── ProjectSession (per project)
│   ├── TerminalViewModel
│   │   ├── TerminalTab[] (terminal tabs with sessions)
│   │   └── TerminalSession → GhosttyTerminalEngine → Surface
│   └── FolderExplorerViewModel
│
├── ContentViewerStore (vibespace-level, shared)
│   ├── SplitViewStore
│   │   ├── SplitPaneNode (recursive binary tree)
│   │   └── EditorGroupStore[] (one per pane)
│   │       ├── ContentViewerTab[] (.file, .terminal, .vibeCast, .webPage)
│   │       └── MarkdownViewModel
│   └── VibeCastStore
│
└── TerminalHostOwnershipCoordinator (singleton)
    └── Ensures one host per terminal view at any time
```

For Phase 1, the new `.terminal` tab kind creates a bridge between the left side (terminal ownership) and the right side (editor groups). The tab holds IDs, the pane resolves the session at render time, and the ownership coordinator handles the view transfer.

---

## Estimated Effort

| Feature | Complexity | Estimated Time |
|---|---|---|
| Scope toggle | Low | 1–2 days |
| Terminal as tab (basic rendering) | Medium | 2–3 days |
| Terminal tab drag-and-drop | Medium | 1–2 days |
| Terminal tab persistence/restore | Medium | 1 day |
| Memory lifecycle tests | Low | 1 day |
| **Total** | | **6–9 days** |
