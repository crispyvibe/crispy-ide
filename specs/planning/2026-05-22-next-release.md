# Requirements — Next Release

## Intent Analysis

- **User Request**: 1 feature + 3 bug RCAs remaining for next release
- **Request Type**: New Feature (file commenting) + Bug Fix
- **Scope**: Cross-cutting (file commenting touches editor, content viewer, agent CLI; bug RCAs in terminal spotlight, detailed-view pane move, scope toggle)
- **Complexity**: Moderate to Complex (new subsystem for comments)

---

## Implementation Status

| Item | Spec IDs | Status | Notes |
|---|---|---|---|
| Feature 3: File Commenting System | F049-R01–R07 | ⏳ Not started | Largest scope: new Rust crate, schema, UI, agent CLI |
| BUG-001: Docked terminal double-click spotlight | F003 / F006 | ⏳ Out of scope per direction | Not in current iteration |
| BUG-002: Terminal move creates empty shell | Detailed view | ⏳ Out of scope per direction | Not in current iteration |
| BUG-003: Scope toggle missing | F006-R13 | ⏳ Out of scope per direction | Not in current iteration |

> **Cleanup note (2026-05-25):** Five implemented features were removed from this document — F012-R17–R20 (browser-project association), F021-R09–R17 (project parking + click-to-select), F048-R13–R16 (multi-monitor bulk move), F044-R80–R82 (CLI add/remove/park). Their canonical specs and threat models live in the respective feature folders. The earlier ID-collision note (F021 renumbering) was retained in those feature specs and dropped here.

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

All remaining items in this release MUST comply with the existing NFR standards in `specs/nfr/`. Key applicable constraints:

### UI (A11Y-4, PERF-3)
- All new UI elements MUST follow existing UI scaling (`AppPreferences.chromeScale`)
- All new UI elements MUST use theme style tokens from the app theme palette (no hardcoded colors)
- All new UI elements MUST use the app's font system (no hardcoded font sizes)
- UI interactions MUST respond within 100ms (PERF-3)
- UI MUST remain functional at 200% zoom (A11Y-4)

### Performance (PERF-3)
- Comment anchoring relocation MUST complete within 100ms for files under 10,000 lines

### Data Integrity (REL-2, SEC-2)
- Comment database MUST use transactions for all write operations
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
- No feature flags required — all features ship directly

### Documentation (CONVENTION.md)
- **F049 (File Comments)**: MUST have all 4 docs created: `spec.md`, `technical-design.md`, `threat-model.md`, `usage-guide.md` in `specs/features/editor/file-comments/`
- Threat models MUST reference applicable NFR IDs (SEC-*, A11Y-*, etc.)
- Usage guides MUST include YAML frontmatter per convention
- No feature ships without all 4 docs reviewed
