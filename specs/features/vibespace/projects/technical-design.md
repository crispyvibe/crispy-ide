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

## Project Parking (F021-R09–R14)

### Model

Three mutually exclusive states for a path within a vibespace:
- **Live** — path is in `VibeSpaceState.projects` as an `AnyProjectSession`.
- **Unresolved** — path is in `unresolvedProjectPaths` (directory missing on disk).
- **Parked** — path is in `parkedProjectPaths` (directory exists; intentionally not loaded).

`VibeSpaceConfigFile.parkedProjectPaths: [String]` persists the set across launches. `ProjectConfigFile.isParked: Bool` mirrors the state in the per-project config file (defaults to false; backward-compatible decode via `decodeIfPresent`).

### Park Lifecycle (F021-R10)

`VibeSpaceCanvasActionsCoordinator.parkProject(id:)` orchestrates:

1. Capture browser sessions for the project via `DockedBrowserCoordinator.snapshotBrowserSessions(forProjectPath:)` and persist them into `ProjectConfigFile.browserSessionEntries`.
2. Dispatch close requests for those browsers via the standard `.closeBrowserRequested` pipeline.
3. Mark `isParked = true` in the per-project config.
4. Mutate live state via `VibeSpaceState.parkProject(id:)`, which calls `ProjectSession.shutdown()` (terminating terminals + watchers), removes the session from `projects`, and appends the path to `parkedProjectPaths`.
5. Clear the hydration startup-execution flag so re-hydration after unpark is fresh.
6. Persist the vibespace catalog so `parkedProjectPaths` is durable.

### Unpark Restoration (F021-R11)

`VibeSpaceCanvasActionsCoordinator.unparkProject(path:)`:

1. Mutate state via `VibeSpaceState.unparkProject(path:)`, which removes the path from `parkedProjectPaths`, creates a fresh `ProjectSession` via the session factory (or `identifierSessionFactory` for SSH paths via `makeIdentifierSession(identifier:)`), and focuses the new session.
2. Clear `isParked` in the per-project config.
3. Restore `browserSessionEntries` — pinned tile entries via `restoreTile(id:snapshot:)`; detailed-view entries via `restoreDetailedBrowser(reference:snapshot:)` and (when canvas is `.detailed`) surface as content-viewer tabs via `ContentViewerStore.openWebPage`.
4. Activate the new session via `vibespaceHydrationCoordinator.activateProjectForPresentation`.
5. Persist the catalog.

The existing `ProjectSession` activation flow (`activateIfNeeded` → `restoreLocalSessionState`) reads the persisted `terminalEntries` from `ProjectConfigFile`, so terminals are recreated from the saved snapshot without additional code.

### Auto-Unpark on Add

`VibeSpaceState.addProjects(from:)` checks `parkedProjectPaths` for each candidate. If a folder is parked, the path is unparked instead of being treated as a duplicate-skip — preserving the spirit of F021-S02 (existing folders are not duplicated).

### UI Surfacing (F021-R12, R13)

The Files-tab pane (`VibeSpaceSidebarFilesPane`) takes a `parkedProjectPaths` parameter and renders a "Parked Projects" section beneath the live projects list. Each parked-project row carries an "Activate Project" right-click menu item. Live projects' headers carry a "Park Project" right-click menu item (`VibeSpaceProjectFilesSectionView`). Both surfaces post notifications (`.parkProjectRequested`, `.activateProjectRequested`) which `ContentView` routes to the actions coordinator.

### Exclusion Semantics (F021-R14)

Most exclusion is automatic because parked projects are not in `VibeSpaceState.projects`:
- The rail iterates `state.projects` so parked projects do not appear.
- Hydration coordinators iterate `state.projects` so parked terminals/watchers are not started.
- VibeCast broadcast targets (which iterate `state.projects`) skip parked projects without explicit changes.
- Scope-toggle project count derives from `state.projects.count`.

## Click-to-Select Project (F021-R15–R17)

### Mechanism

`EditorGroupStore.activateTab(_:)` posts `.contentViewerTabActivated` (userInfo: `["tab": ContentViewerTab]`) on every tab activation, user-initiated or programmatic. `ContentView` listens, resolves the activated tab's owning project via `resolveOwningProjectPath(for:)`, and calls `vibespaceCanvasActionsCoordinator.focusProject(_:)` if the resolved project differs from the current focused project. Idempotency is enforced by an early-return when the resolved project's id already matches the focused project's id, which prevents recursion when programmatic activation results from a `focusProject` call.

### Tab → Project Resolution

| Tab Kind | Resolution |
|---|---|
| `.file(reference)` | longest project-root prefix match against `reference.url.standardizedFileURL.path` |
| `.webPage(reference)` | `reference.projectPath` |
| `.terminal(projectID, _)` | look up project by UUID in `state.projects` |
| `.vibeCast`, `.acpPane` | nil (no ownership) |

### Cross-Surface Coverage

| Surface | Mechanism |
|---|---|
| Content-viewer tabs (file / webPage / terminal kinds) | `EditorGroupStore.activateTab` posts `.contentViewerTabActivated` (userInfo: `tab`); ContentView listener resolves the owning project via `resolveOwningProjectPath(for:)` and calls `focusProject` if different. |
| Terminal tray (detailed mode) | `FocusedProjectView` wraps a single project's `terminalViewModel`, so the tray's terminals are by construction owned by the focused project — taps are inherently idempotent (no project switch). |
| Board tiles (board mode) | `VibeSpaceTerminalBoardStore.activateTile` posts `.boardTileActivated` (userInfo: `projectPath`); ContentView listener resolves and calls `focusProject` if different. Also covers detached board windows since they share the same store. |

All listeners apply the same idempotency guard: if the resolved project's id already matches `focusedProject?.id`, the focus call is suppressed. This makes the notifications safe to fire on every activation (programmatic or user-initiated) without recursion or telemetry inflation.

### Exclusion Side-Effects

Because parked projects are stored separately in `parkedProjectPaths` and never instantiated as `AnyProjectSession`, surfaces that enumerate live projects automatically exclude them:

- Project rail iterates `state.projects`.
- VibeCast broadcast targets (`VibeCastView.terminalSources`) derive from `state.projects`.
- Scope-toggle visibility (`if projects.count > 1`) counts only live projects.
- Hydration coordinators iterate `state.projects`.
- Click-to-select listeners only resolve owners against `state.projects`, so a notification carrying a parked project's path resolves to nil and is ignored — closing one more potential vector.
