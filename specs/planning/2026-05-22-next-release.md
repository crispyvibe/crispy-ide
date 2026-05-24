# Requirements — Next Release

## Intent Analysis

- **User Request**: 6 feature refinements + 2 bug RCAs for next release
- **Request Type**: Enhancement (existing features) + Bug Fix
- **Scope**: Multiple Components (Browser, VibeSpace Projects, Content Viewer, Terminal Board, Agent CLI, File Commenting)
- **Complexity**: Moderate to Complex (new subsystem for comments, cross-cutting project association changes)

---

## Implementation Status

| Item | Spec IDs | Status | Notes |
|---|---|---|---|
| Feature 1: Browser-to-Project Association | F012-R17–R20 | ✅ Implemented (2026-05-22) | Specs updated, 1024 tests passing |
| Feature 2: Project Parking | F021-R09–R14 (renumbered from R01–R06 to avoid ID collision) | ✅ Implemented (2026-05-22) | Files-tab UI; specs + threat model updated |
| Feature 3: File Commenting System | F049-R01–R07 | ⏳ Not started | Largest scope: new Rust crate, schema, UI, agent CLI |
| Feature 4: Multi-Monitor Bulk Pane Move | F048-R13–R16 | ✅ Implemented (2026-05-23) | Cmd+Opt+M move / Cmd+Opt+B recall; "Send All From This Project to New Window" tile context menu; surface-scoped + project-scoped; reuses single-mutate boundary |
| Feature 5: CLI Add/Remove/Park Project | F044-R80–R82 | ✅ Implemented (2026-05-22) | Specs updated; routes through VibeSpaceCanvasActionsCoordinator for UI parity |
| Feature 6: Click-to-Select Project | F021-R15–R17 (renumbered from R07–R09) | ✅ Implemented (2026-05-22) | Content-viewer tabs + board tiles + tray |
| BUG-001: Docked terminal double-click spotlight | F003 / F006 | ⏳ Out of scope per direction | Not in current iteration |
| BUG-002: Terminal move creates empty shell | Detailed view | ⏳ Out of scope per direction | Not in current iteration |
| BUG-003: Scope toggle missing | F006-R13 | ⏳ Out of scope per direction | Not in current iteration |

> **ID-collision note (2026-05-22):** the original draft of this document reused F021-R01–R09 which were already taken by existing requirements (Add Project, focus, etc.). Per `INDEX.md` rule "Numbers are never reused", parking + click-to-select were renumbered to F021-R09–R17. Implemented IDs in this document below remain at the renumbered values.

---

## Feature 1: Browser-to-Project Association

**Extends**: F012 (Browser)

### F012-R17: Project Ownership

Each browser instance MUST be owned by exactly one project. When a browser is created via the toolbar button, it MUST be auto-associated with the currently focused project.

### F012-R18: Project Lifecycle Coupling

When a project is removed from the vibespace OR parked (Feature 2), all browsers associated with that project MUST be closed. This follows the same lifecycle as terminals and files.

### F012-R19: Browser Tabs in Detailed View

In detailed view, project-associated browsers MUST appear as content viewer tabs using the existing `webPage` tab type. Browser tabs MUST respect viewer scope filtering (F006-R13) — when scope is "focused project," only browsers belonging to the focused project are shown.

### F012-R20: Browser Session Persistence per Project

Browser session state (URL, history stacks, zoom, theme mode per F012-R07) MUST be persisted as part of the owning project's state. On vibespace restore, browser tabs MUST be restored for active (non-parked) projects.

---

## Feature 2: Project Parking (Dormant Projects)

**Extends**: F021 (VibeSpace Projects)

### F021-R01: Park State

A project MUST support a "parked" state. Parked projects retain a full state snapshot (terminal history, open files, browser state, layout) but MUST NOT hydrate any sessions (terminals, browsers, file watchers) on vibespace open.

### F021-R02: Park Lifecycle

When a project is parked:
- All active terminals MUST be terminated
- All browser instances MUST be closed
- All file watchers MUST be stopped
- The full state snapshot MUST be persisted for later restoration

### F021-R03: Unpark (Activate) Restoration

When a parked project is activated:
- Terminal sessions MUST be recreated from the saved snapshot (presets, working directories)
- Browser tabs MUST be restored from saved URLs/state
- File state (open tabs, layout) MUST be restored
- The project MUST become the focused project

### F021-R04: Parked Project UI Placement

Parked projects MUST NOT appear in the project rail. Parked projects MUST appear in the Files tab as a distinct "Parked Projects" section.

### F021-R05: Park/Unpark Interaction

Users MUST be able to park a single project via right-click context menu on the project entry in the Files tab → "Park Project." Users MUST be able to activate a parked project via right-click context menu → "Activate Project." Bulk parking (multiple projects at once) is NOT required.

### F021-R06: Parked Project Exclusion

Parked projects MUST NOT:
- Have terminals hydrated on vibespace open
- Appear in the project rail
- Be included in VibeCast broadcast targets
- Contribute to the scope toggle project count

---

## Feature 3: File Commenting System

**New Feature**: F049 (File Comments)

### F049-R01: Supported File Types

Comments MUST be supported on all files that can be opened in the content viewer (text, markdown, code, config, web pages — any file with a content viewer plugin).

### F049-R02: Comment Storage

Comments MUST be stored in a central database per vibespace (single store). The database MUST be exposed via a Rust layer (not Swift directly) so that both the app UI and the CLI can read/write comments through the same interface.

### F049-R03: CLI Operations

The CLI MUST expose full CRUD operations for comments:
- `comments.add` — add a comment to a file at a specified anchor
- `comments.list` — list comments for a file (optionally filtered by status)
- `comments.reply` — reply to an existing comment (supports full threading)
- `comments.resolve` — mark a comment thread as resolved
- `comments.delete` — delete a comment
- `comments.update` — update comment content

### F049-R04: Threading

Comments MUST support full threading with nested replies (unlimited depth). Each comment has a parent reference (null for top-level comments).

### F049-R05: Comment Anchoring

Comments MUST be anchored using character range (start line:col → end line:col) plus a content snapshot hash. The snapshot MUST also store the last-known line words (text content at the anchored range).

When the file changes:
1. Attempt to relocate the anchor using the content snapshot (fuzzy match against stored line words)
2. If relocated successfully → update position silently
3. If content changed significantly → mark comment as "stale" with last-known position preserved

### F049-R06: Comment Visibility in UI

Comments MUST be visible in the content viewer UI:
- Gutter indicators showing lines with comments
- Comment panel/overlay showing comment threads for the selected anchor
- Visual distinction between active, resolved, and stale comments

### F049-R07: Agent Interaction

AI agents MUST be able to:
- Read all comments on a file via CLI
- Add new comments (e.g., code review feedback)
- Reply to existing comments (e.g., explaining a change)
- Resolve comments after addressing them
- Comments added by agents MUST be attributed with agent identity

---

## Feature 4: Multi-Monitor Bulk Pane Move

**Extends**: F048 (Terminal Board Multi-Monitor)

### F048-R13: Bulk Move Shortcut

A keyboard shortcut MUST move ALL panes (terminals, files, browsers) from the current project to a new detached board window in a single operation. This is a bulk equivalent of the existing single-tile transfer (F048-R07).

### F048-R14: Board Mode Only

The bulk move shortcut MUST operate in board mode only. Detailed mode is not in scope.

### F048-R15: Source Surface Reorganization

After bulk move, remaining tiles on the source board surface MUST be reorganized to fill empty space. This follows existing board layout compaction logic (same behavior as when individual tiles are moved/closed).

### F048-R16: Reverse Bulk Move

A mechanism MUST exist to move all panes back from the detached window to the original surface (recall operation).

---

## Feature 5: CLI Add/Remove Project from VibeSpace

**Extends**: F044 (Agent CLI)

### F044-R80: Add Project Command

`vibespace.addProject` MUST add a project to the currently focused vibespace.

**Parameters**:
- `path` (required): Absolute path to the project directory

**Validation**:
- Path MUST exist and be a directory
- Path MUST NOT already be in the vibespace (duplicate check)

**Behavior**:
- On success, the new project becomes focused (consistent with F021-S03)
- An active terminal MUST be ensured for the new project

### F044-R81: Remove Project Command

`vibespace.removeProject` MUST remove a project from the currently focused vibespace.

**Parameters**:
- `path` (required): Absolute path of the project to remove

**Behavior**:
- All project artifacts (terminals, browsers, files, agents) MUST be closed
- Focus fallback behavior MUST apply (consistent with F021-S06)

### F044-R82: Park Project Command

`vibespace.parkProject` MUST park a project in the currently focused vibespace (per Feature 2 semantics).

**Parameters**:
- `path` (required): Absolute path of the project to park

**Behavior**:
- Full state snapshot MUST be saved
- All active sessions MUST be terminated
- Project moves to parked state

---

## Feature 6: Click-to-Select Project

**Extends**: F021 (VibeSpace Projects)

### F021-R07: Pane Focus Selects Project

When any pane (terminal, file, browser) receives focus via single click, the project associated with that pane MUST become the focused project. This applies to all pane types that have a project association.

### F021-R08: Immediate Focus Change

Project focus change MUST happen immediately on pane focus — no deliberate action (double-click) required. Whenever a pane is in focus, its owning project is the focused project.

### F021-R09: Cross-Surface Consistency

Click-to-select MUST work consistently across:
- Content viewer tabs (detailed view)
- Terminal tray (detailed view)
- Board tiles (board mode)
- Detached board windows (multi-monitor)

---

## Bug 1: Terminal in Detailed View — Spotlight & Pane Move

**Affects**: F003 (Terminal Spotlight), F006 (Content Viewer)

### BUG-001: Docked Terminal Double-Click Spotlight Broken

**Symptom**: Terminals docked into the content viewer (via F006-R18) do not open in spotlight on double-click.

**Expected**: Double-clicking a docked terminal tab should open Terminal Spotlight overlay (per F003-R04).

**Scope**: Only terminals docked as content viewer tabs (not bottom tray terminals).

### BUG-002: Terminal Move Creates Empty Shell

**Symptom**: Moving a terminal between panes in detailed view creates an empty shell in the target. The moved terminal content only appears after closing the original terminal surface.

**Expected**: Terminal content should transfer immediately to the target pane; the source surface should be removed/hidden.

**Scope**: All terminal move operations in detailed view (tray → content viewer, between splits, content viewer → tray).

**Likely Root Cause**: The old terminal surface is not being hidden/removed when the terminal is visible on screen during the drag operation. The terminal view remains attached to the source while a new empty host is created at the target.

---

## Bug 2: Missing Project Scope Button in Detailed View

**Affects**: F006 (Content Viewer), F006-R13

### BUG-003: Scope Toggle Not Visible

**Symptom**: The project scope toggle button (filter tabs by focused project vs all projects) is no longer visible in the content viewer toolbar.

**Expected**: A segmented picker (folder/grid icons) should appear in the tab strip when multiple projects are open.

**Code Location**: `ContentViewerView.swift` line 75:
```swift
if projects.count > 1 { scopeToggle.padding(.trailing, 8) }
```

**RCA Starting Point**: The code exists and is conditionally shown when `projects.count > 1`. The button has been missing for a while. Likely causes:
1. The `projects` binding is not receiving updates from the project store
2. The projects array is being filtered/transformed before reaching this view
3. A view hierarchy change broke the environment injection of the projects list

**Timeline**: Has been missing for a while (not a recent regression).

---

## Extension Configuration

| Extension | Enabled | Decided At |
|---|---|---|
| Security Baseline | No | Requirements Analysis |
| Property-Based Testing | Partial (pure functions + serialization) | Requirements Analysis |

---

## Non-Functional Requirements

All features in this release MUST comply with the existing NFR standards in `specs/nfr/`. Key applicable constraints:

### UI (A11Y-4, PERF-3)
- All new UI elements MUST follow existing UI scaling (`AppPreferences.chromeScale`)
- All new UI elements MUST use theme style tokens from the app theme palette (no hardcoded colors)
- All new UI elements MUST use the app's font system (no hardcoded font sizes)
- UI interactions MUST respond within 100ms (PERF-3)
- UI MUST remain functional at 200% zoom (A11Y-4)

### Performance (PERF-3, PERF-4)
- Comment anchoring relocation MUST complete within 100ms for files under 10,000 lines
- Bulk pane move MUST complete as a single atomic operation (no visible intermediate states)
- Project park/unpark MUST not block the UI thread

### Data Integrity (REL-2, SEC-2)
- Comment database MUST use transactions for all write operations
- Parked project state snapshots MUST be validated on restore (skip corrupted entries gracefully)
- Persistence MUST use integrity verification per SEC-2 (HMAC-SHA256)
- Write operations MUST use atomic file writes per REL-2

### Accessibility (A11Y-1, A11Y-2, A11Y-6)
- All new interactive elements MUST have accessibility identifiers per A11Y-6 naming convention
- All new features MUST be operable via keyboard (A11Y-2)
- Screen reader labels MUST be provided for new UI elements (A11Y-1)

### Testability (TEST-2)
- Every new scenario MUST have at least one automated test
- Bug fixes MUST include regression tests
- New Rust crate (comments) MUST maintain ≥80% line coverage

### Observability (OBS-1, OBS-2)
- New subsystems MUST emit structured lifecycle events
- Errors MUST use structured error types, not raw strings

### Compatibility
- Comment CLI commands MUST follow existing F044 Agent CLI patterns (JSON-RPC over XPC)
- Browser project association MUST be backward-compatible with existing vibespace persistence format
- No feature flags required — all features ship directly

### Documentation (CONVENTION.md)
- **F049 (File Comments)**: MUST have all 4 docs created: `spec.md`, `technical-design.md`, `threat-model.md`, `usage-guide.md` in `specs/features/editor/file-comments/`
- **F012 (Browser)**: All 4 existing docs MUST be updated with project association requirements (R17–R20)
- **F021 (VibeSpace Projects)**: All 4 existing docs MUST be updated with parking (R01–R06) and click-to-select (R07–R09)
- **F048 (Terminal Board Multi-Monitor)**: All 4 existing docs MUST be updated with bulk move (R13–R16)
- **F044 (Agent CLI)**: All existing docs MUST be updated with new commands (R80–R82)
- Threat models MUST reference applicable NFR IDs (SEC-*, A11Y-*, etc.)
- Usage guides MUST include YAML frontmatter per convention
- No feature ships without all 4 docs reviewed
