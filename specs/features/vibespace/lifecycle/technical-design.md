# VibeSpace Lifecycle — Technical Design

## Overview

Covers the full vibespace lifecycle: four creation paths, catalog persistence, hydration/restore sequence, session teardown, and file integrity signing. A vibespace is represented by `VibeSpaceState` (in-memory) and `VibeSpaceConfigFile` (on disk).

## Architecture

### Terminology

- **VibeSpace** — user-facing name for a vibespace
- **Project** — a folder within a vibespace with its own terminal sessions, file explorer, pane layout, and optional per-project settings (`ProjectSession`)
- **Unresolved project** — a project path whose directory no longer exists on disk at load time

### Four Creation Paths

| Path | Trigger | Name Resolution | Notes |
|------|---------|-----------------|-------|
| Folder picker | `NSOpenPanel` multi-select | Single folder → folder name; multiple → auto-incremented "VibeSpace N" | Deduplicates against open + recent vibespaces |
| Creation wizard | `VibeSpaceCreationResult` | User-entered name | Optional CLI profile selection applied as first startup profile; per-project CLI overrides applied |
| External open | URLs via `ExternalOpenRelay` (Finder, other process) | Auto-generated | Directories → project candidates, files → shelf. If vibespace active, directories added to it; otherwise new vibespace. `preferTerminal` flag forces terminal-only mode |
| Terminal quick start | Utility dock button | "Terminal" | Home directory as sole project, terminal-only canvas mode |

In all cases: previous vibespace shut down, new vibespace immediately persisted and hydrated.

### VibeSpace Contents

| Field | Type | Description |
|-------|------|-------------|
| `projects` | `[ProjectSession]` | Ordered list of resolved folder projects |
| `focusedProjectID` | `UUID` | Currently focused project; falls back to first if invalid |
| `unresolvedProjectPaths` | `[String]` | Paths not found on disk |
| `storedProjectPaths` | `[String]` | Snapshot of all paths (resolved + unresolved) for session reset |
| `storedFocusedProjectPath` | `String` | Focused project path preserved across resets |
| `projectColorTagsByPath` | `[String: ProjectColorTag]` | Color tag per project |
| `startupSettings` | `VibeSpaceStartupSettings` | VibeSpace-level terminal startup config |
| `projectStartupOverridesByPath` | `[String: Override]` | Per-project startup overrides |
| `defaultTerminalShell` | `TerminalShellPreference?` | VibeSpace-level shell preference |
| `projectTerminalShellOverridesByPath` | `[String: Preference]` | Per-project shell overrides |
| `projectShortcutByPath` | `[String: Int]` | Keyboard shortcut index (1–9) per project |
| `sourceControlSettings` | `VibeSpaceSourceControlSettings` | Scan depth, max repos, ignored dirs, auto-presented limit |

## Data Flow

### Hydration Sequence

When a vibespace opens or is restored:

1. **Layout restoration** — persisted layout loaded (editor session state, split view config, content viewer scope)
2. **Hydration targets** — focused project first, then remaining projects in order; all include vibespace-default startup settings
3. **Focused project activation** — session activated (lazy on first access), file open handler wired, terminal shell resolution context applied (vibespace default + app default), active terminal ensured
4. **Startup command execution** — if persisted terminal tabs have preset origins, re-execute on matching tabs; otherwise compute startup launch plan (terminal count per config, each profile's command on corresponding tab). Startup marked as executed per project path per vibespace to prevent re-running
5. **Background project hydration** — remaining projects activated and wired in parallel via task group, without startup command execution or terminal focus

### Startup Configuration

**VibeSpace-level (`VibeSpaceStartupSettings`):**
- `startupTerminalCount` — 1–8 terminals per project on open
- `startupProfiles` — up to 8 `VibeSpaceTerminalStartupProfile` entries (optional `presetID` + `command`; command takes priority)
- `focusTerminalOnProjectSwitch` — auto-focus terminal on project switch

**Per-project override (`VibeSpaceProjectStartupOverride`):**
- Same structure, scoped to single project path
- When present, completely replaces vibespace default for that project

**Resolution:** Per-project override → vibespace default (if `includeVibeSpaceDefault`) → single terminal with no startup command.

### Restoration

- On launch, load most recent vibespace ID from `AppStateFile`
- Load vibespace config + project configs from disk
- Verify directory existence asynchronously (off main thread)
- Create `ProjectSession` for available paths; missing paths → unresolved
- Catalog load cancellable if user takes action before completion
- UI test auto-restore via `CRISPYVIBES_UI_TEST_MODE` + `CRISPYVIBES_UI_TEST_START_IN_VIBESPACE` env vars

## State Management

### Close / Remove / Delete

| Operation | Behavior |
|-----------|----------|
| Close session (`resetSession`) | Tear down all project sessions, clear project list and focused ID, preserve `storedProjectPaths` and `storedFocusedProjectPath`. VibeSpace stays in catalog + recent list. Standalone terminal boards released. Startup flags cleared. Navigate to home. |
| Remove vibespace (`removeDisplayedVibeSpace`) | Shut down all sessions, release terminal boards, remove from displayed list. Returns fallback vibespace ID (first remaining). |
| Delete vibespace (`deleteVibeSpace`) | Remove vibespace directory from disk (config + project configs), remove from recent list in app state, cancel pending debounced writes. |

### Persistence

| Data | File | Notes |
|------|------|-------|
| VibeSpace config (`VibeSpaceConfigFile`) | Per-vibespace directory | ID, name, project paths, unresolved paths, focused path, startup settings, shell, source control. Signed with HMAC-SHA256. Writes debounced (200ms). |
| Project configs (`ProjectConfigFile`) | Per-project within vibespace dir | Color tag, shortcut index, startup override, shell override, terminal session entries, active terminal dir. Saved immediately on mutation. |
| Layout state | Per-project root URL + per-vibespace ID | Pane layout fractions, editor session state. |
| App state (`AppStateFile`) | App-level | Recent vibespace IDs (max 20), sidebar width, disclaimer flag. Pruned on launch. |
| Recent vibespace list | In app state | Touched on create/restore/rename/persist. Capped at 20. Dashboard shows up to 5 (loads up to 12). |

All vibespace and project config files saved with cryptographic integrity signing and verified on load.

### Trust and Integrity

- **Untrusted vibespace handling:** Failed integrity verification → flagged as untrusted, `untrustedVibeSpaceName` surfaced to UI. All project startup commands suppressed (paths marked as "startup executed" without running).
- **HMAC-SHA256 signing:** Centralized in `AppPersistenceDataStore` via `saveWithIntegrity` / `loadWithIntegrity`. No service duplicates crypto logic.
- **Layout files exempt:** `layout.json` files have no signing or verification.
- **Re-saving restores trust:** User reviews and re-saves settings → file re-signed, startup execution re-enabled.

## Dependencies (frameworks, libraries)

- Foundation (`FileManager` for directory existence checks)
- CryptoKit (HMAC-SHA256 signing)
- Security (macOS Keychain for signing key storage)
- Combine (debounced writes, async hydration)

## Platform Considerations

- macOS only — Keychain access for signing key, `NSOpenPanel` for folder selection
- Async directory existence checks run off main thread
- `DistributedNotificationCenter` for single-instance URL forwarding

## Performance Constraints

- Hydration is async with focused project prioritized
- Background project hydration runs in parallel task group
- Config writes debounced at 200ms to avoid disk thrashing (debounce timing needs verification)
- Catalog load cancellable to avoid blocking user actions

## Migration / Rollout Notes

- VibeSpace startup settings decode from `startupProfiles`; legacy single-terminal keys not migrated
- Unverified (untrusted) configs are loadable but flagged — no data loss on integrity failure
- Recent vibespace list pruned on launch to remove stale entries
