# VibeSpace Projects — Technical Design

## Overview

Covers project management within a vibespace: add, remove, reorder, relink, and reconcile operations. Each project is a `ProjectSession` backed by a folder path with its own terminal sessions, file explorer, layout state, and optional per-project overrides.

## Architecture

### Project Operations

#### Add Projects

- Accepts a list of URLs
- Duplicates by normalized path silently skipped
- If directory exists → `ProjectSession` created and appended
- If directory missing → path added to `unresolvedProjectPaths`
- Auto color tag assigned via `assignAutoColorTagIfNeeded(forPath:)`
- Returns last added or matched project

#### Remove Project

1. Shut down project session (terminals terminated)
2. Remove from project list
3. Clean up all associated per-project state: color tag, startup override, shell override, shortcut
4. If removed project was focused → focus moves to last remaining project
5. Shortcuts renormalized after removal

#### Reorder Projects

- Move projects within list by index offsets
- Shortcut indices reindexed to match new order
- Persisted immediately

#### Relink Unavailable Projects

- Unresolved path relinked to a new URL
- If replacement path exists on disk → new session created, unresolved entry removed
- Associated state migrated from old path to new: color tag, startup override, shell override
- If replacement points to already-existing project → state merged, unresolved entry removed

#### Reconcile Project Availability

- Checks all project paths (resolved + unresolved) against filesystem
- Projects whose directories disappeared → shut down, moved to unresolved
- Previously unresolved paths that now exist → recovered as live projects
- Focus reassigned if focused project was lost

### Project Shortcuts

- Each project can be assigned shortcut index 1–9 via `projectShortcutByPath`
- Shortcuts normalized after any add, remove, or reorder operation
- Duplicate slots resolved automatically during normalization

## Data Flow

### Hydration Order

1. Focused project hydrated first (session activated, terminal ensured)
2. Remaining projects hydrated progressively in parallel task group for rail previews
3. Background projects activated and wired without startup command execution or terminal focus
4. Each background project exposes one grouped rail preview with a representative terminal on top and additional visible terminals retained as stack members for hover/focus expansion

### Focus Management

- `focusedProjectID` tracks current focus (UUID)
- Falls back to first project if stored ID no longer valid
- New project becomes focused on add (last processed project)
- Closing focused project → focus falls back to last remaining
- Closing last project → empty state UI
- Expanding a collapsed sidebar project calls `project.activate()` and `project.ensureExplorerLoaded()` before expanding, ensuring the file tree is ready

### Stacked Project Preview Selection

- A stacked project card is backed by that project's visible rail terminals rather than a flat vibespace-wide terminal list.
- Representative terminal selection uses:
  - live terminal activity first
  - then most recently focused/selected terminal within that project
  - then the project's current active terminal tab
  - then stable tab order fallback
- Hover or keyboard focus expands the project card to reveal the rest of that project's visible terminals without changing the focused project until the user explicitly selects one.

### Layout Persistence

- Pane layout (explorer/terminal split fractions and point sizes) persisted per project root URL in app layout state store
- Editor session state (split view config, content viewer scope) persisted per vibespace ID
- Restored on project reopen

## State Management

### Per-Project Config (`ProjectConfigFile`)

| Field | Type | Notes |
|-------|------|-------|
| `colorTag` | `String?` | Hex `#RRGGBB` or `#RRGGBBAA` |
| `shortcutIndex` | `Int?` | 1–9 keyboard shortcut |
| `startupOverride` | `VibeSpaceProjectStartupOverride?` | Terminal count + profiles |
| `shellOverride` | `TerminalShellPreference?` | Per-project shell |
| `terminalSessionEntries` | `[TerminalSessionEntry]` | Working dir, custom name, origin per tab |
| `activeTerminalDirectory` | `String?` | Active terminal working dir |

Saved immediately on mutation with integrity signing.

### State Migration on Relink

When a project path changes (relink), `moveProjectAssociatedState` transfers:
- Color tag
- Startup override
- Shell override
- Shortcut index

From old path key to new path key in all `*ByPath` dictionaries.

### State Cleanup on Remove

`removeProjectAssociatedState` deletes entries for the removed path from:
- `projectColorTagsByPath`
- `projectStartupOverridesByPath`
- `projectTerminalShellOverridesByPath`
- `projectShortcutByPath`

## Dependencies (frameworks, libraries)

- Foundation (`FileManager` for directory existence, URL normalization)
- Combine (tab publishers for rail store)

## Platform Considerations

- macOS only — `NSOpenPanel` for folder selection in add project flow
- Path normalization via `URL(fileURLWithPath:).standardizedFileURL.path`

## Performance Constraints

- Background project hydration runs in parallel task group
- Reconciliation runs filesystem checks off main thread
- Shortcut normalization is O(n) on project count

## Migration / Rollout Notes

- Color tokens are hex-only; legacy named token decoding removed
- Project config files use integrity signing; unverified configs loadable but flagged
