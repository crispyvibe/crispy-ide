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

1. Capture the exact `projectIdentifier`, raw root, terminal IDs, and browser ownership keys while the session is live.
2. Remove proven board/file presentations and collect all project-keyed outstanding/displaced flush tasks.
3. Remove the project from live state with `shutdown:false`, then close browsers using frozen keys.
4. Race the complete flush set against a true 30-second timeout; cancel the losing monitor and call session shutdown exactly once.
5. Clean up associated per-project state and apply focus fallback.
6. Normalize shortcut assignments after removal.

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

- Each project can be assigned one shortcut slot 1–9 via `projectShortcutByPath`, keyed by the exact `projectIdentifier` rather than raw remote root.
- Local identifiers are standardized filesystem paths; `ssh://` identifiers are preserved verbatim, so same-root projects on different hosts have distinct keys.
- `setShortcut` evicts any prior owner of an assigned slot, and normalization retains at most one project per slot.
- Shortcuts normalize after add, remove, or reorder operations.

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

1. Build browser lookup keys from the host-qualified `projectIdentifier` plus the raw root only when that legacy key is unambiguous; query both, deduplicate by browser ID, and persist the result once under the qualified identifier, including an empty result.
2. Mark `isParked = true` in the per-project config.
3. Remove proven project-owned board content, including pinned file groups and a matching unpinned preview, collecting close-flush tasks.
4. Mutate live state with `VibeSpaceState.parkProject(id:shutdown:false)`, removing the session from `projects` and appending the identifier to `parkedProjectPaths` without shutting resources down yet.
5. Close browsers using the frozen lookup keys.
6. Collect every displaced/outstanding flush tracked under the exact project identifier plus the newly returned close tasks. Race one monitor that awaits the complete set against a true 30-second timeout monitor; the first result cancels the loser, and the retained session shuts down exactly once.
7. Clear hydration startup state and persist the catalog.

The ordering is query/deduplicate/persist-one-qualified-browser-snapshot → mark parked → board/file cleanup → state removal without shutdown → browser close → collect project-keyed flushes → flush-vs-timeout race → exactly-once shutdown. Removing live state before browser close prevents fallback refocus, while retaining the session until the race resolves keeps its remote provider available for close writes.

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

## Project External Actions (F021-R20, R21, R23)

`ProjectNodeContextMenu` derives external actions from the active project's location while remaining the shared component for both explorer surfaces. Every active root exposes Open in System. A local root forwards its original directory URL to `VibeSpaceInteractionService`, propagates the `NSWorkspace.open` Boolean, reports failure through the existing local alert, and retains Reveal in Finder. An SSH root suppresses Reveal in Finder and exposes Download… in addition to Open in System; both remote actions delegate to the app-wide `RemoteTransferCoordinator` described by F034.

The coordinator slot is shared only by explorer file/folder actions and active project roots. It exposes preparing, transferring, cancelling, publishing, completed, and failed overlay states. Cancel disappears during cancelling and publication, structured cancellation retains the slot through SFTP termination and partial staging cleanup, and remote failure remains in the overlay until dismissed. Before destination publication, the transfer service synchronously awaits MainActor acknowledgment of the publishing state and checks task cancellation again immediately before replace/move. Cancellation after that final check may coincide with the atomic publication boundary and may not prevent publication. Transfer lifecycle and newly relevant diagnostics are recorded through `AppDiagnostics`; exported event metadata sanitizes path-like strings. Editor-triggered remote HTML Open in System is independent: F009 uses `ExternalFileOpenService`, editor busy/error state, and no dedicated bulk-transfer channel or global overlay. No broader global exclusivity is implied.

The existing Open in Terminal, create, copy-path, park, remove, and make-current routes remain project-scoped. Remote system-open and download do not activate Finder against an `ssh://` identifier and do not reinterpret that URI as a local path.

## Project-Qualified Source Control and Spotlight

Source-control project references, discovered repository IDs, and repository view models retain the exact `projectIdentifier`. For project-backed SSH Git, `attachedProjects` first resolves that identifier and returns only the exact project; it does not attach a same-root repository from another host. Tracked remote diffs call that project's `gitExplorer.loadDiff`, which combines non-empty staged and working-tree output and opens a `previewGitDiffContent` tab carrying the exact identifier. Untracked/new files open with that project's own `FileContentProviding` instance.

The same identifier is the canonical owner for main/detached direct Spotlight, temporary terminals, project shortcuts, split and permanent creation, ACP, link, file, browser, editor-pane, restore, and detached-attachment routes. Nested actions carry it forward, and detached attachment copies it unchanged. Project focus shortcuts and project-scoped terminal shortcuts are keyed by this exact identifier; SSH URI normalization preserves the full host-qualified value and slot normalization retains only one project per numeric shortcut.

## Parked Remote Rows (F021-R24)

Parked rows have no live `ProjectSession`, so their presentation is derived solely from the persisted identifier. `SSHConnectionProfile.parseIdentifierLocation` is shared with live restoration. New identifiers are produced with `URLComponents` percent encoding; backward parsing treats legacy query and fragment delimiters as literal remote-path content. A parsed SSH row uses the server icon and SSH badge, displays the literal host (appending the port only when it is not 22) plus only `…/basename`, and omits the username and ancestor path components. Its accessibility label follows the same privacy-minimized host/name presentation, while the stable accessibility identifier contains only `AppDiagnostics.pathToken(identifier)`. Badge, host/non-default-port, abbreviated path, combined detail, and accessibility sentence are formatted through localized `AppStrings` entries. The dormant row wires only Activate Project and Remove Project; Open in System, Download…, Reveal in Finder, terminal, explorer, and mutation actions require activation and a live remote session.

## Automatic Board Cleanup (F021-R25–R29)

### Frozen Ownership Evidence

Before parking or removing an active project, `VibeSpaceCanvasActionsCoordinator` captures a cleanup descriptor while the live session still exists. The descriptor contains the project's unique, host-qualified `projectIdentifier`, its raw root, all terminal tab IDs, and the browser ownership keys. This avoids deriving ownership from state after `ProjectSession.shutdown()` or project-array mutation has discarded the authoritative context.

For park, browser snapshots are queried under the host-safe project identifier and the legacy raw-root key only when that key is unambiguous, then deduplicated by browser ID. `saveBrowserSessions` is called once for only the host-safe identifier, including with an empty array, so an older snapshot cannot reappear and no legacy-key duplicate is persisted. For remove, browser lookup keys are frozen before state mutation. Both paths remove board/file presentations, mutate project state with `shutdown:false`, close browsers, await file-flush tasks, and only then shut down the retained project session; a 30-second watchdog prevents indefinite retention.

### Board Cleanup Boundary

The coordinator passes the frozen descriptor to `VibeSpaceTerminalBoardStore`. The store performs one `mutate` transaction across the complete multi-surface state. It removes proven owned tiles from both visible columns and `minimizedTiles` on primary and detached surfaces, removes every corresponding member from each surface's F003 `spotlightLayout`, normalizes once, publishes once, and persists once.

Ownership is proven by the strongest available evidence:

- terminal and browser tile `projectIdentifier` equality;
- terminal tab-ID membership for legacy remote terminal tiles;
- stamped file-tile `projectIdentifier` equality;
- local file URL containment under the project root using path-component boundaries, never a plain string prefix;
- ACP tile `selectedProjectIdentifier` equality.

The optional Codable tile `projectIdentifier` is migration-safe: absent values decode as legacy state. `syncProjects` stamps current host-qualified ownership and migrates a legacy tile only when one project can be proven uniquely. Same raw remote roots on different SSH hosts are therefore isolated. A legacy remote raw-root-only tile that could belong to more than one host is retained fail-closed rather than guessed or deleted.

File cleanup also dismisses an unpinned preview when `previewProjectIdentifier` matches and closes every tab in each removed tile group. `DockedFileViewerCoordinator` records flushes produced by displaced previews/groups and later removals as `(projectIdentifier, task)` entries; lifecycle cleanup repeatedly takes only matching outstanding tasks, so an earlier replacement flush cannot be orphaned or attributed to another same-root host. Each close uses the tab's stored provider and a writer that strongly retains provider and worker; returned tasks preserve dirty buffers on failure.

When matching flush tasks exist, project teardown creates a `ProjectFileFlushRace`: one monitor awaits every task and counts failures while a second sleeps for a true 30 seconds. The first result resolves the race, both monitors are cancelled, and `project.shutdown()` runs once after the result. With no tasks, shutdown runs immediately once. Failure/timeout diagnostics are emitted after shutdown selection; timeout bounds provider retention without pretending the flush succeeded.

Normalization removes detached surfaces made empty by cleanup. The detached-window manager observes the resulting surface set and closes managed windows whose surfaces disappeared. This prevents a stale blank window from surviving after the final owned tile is removed.

### Unpark Restoration

Unpark restores each saved pinned browser on the primary surface using its original tile ID and browser snapshot, and creates the browser view model with the unique project owner. Terminal entries remain persisted project state; board terminal reconciliation recreates the restored project's terminal tabs and tiles. For remote projects, board runtime terminal subscriptions, project context, reconciliation keys, and Spotlight member identities all use the host-qualified owner rather than raw remote root text.

`VibeSpaceHydrationCoordinator` eagerly calls `removeAllGroups()` when hydration switches from one VibeSpace ID to another and in the non-prehydrated active-ID transition path, preventing outgoing docked file groups from surviving into the incoming identity. Automatic lifecycle cleanup does not alter user-initiated remote drag/transfer behavior. Dragging a remote tile between board surfaces continues to use the existing one-tile transfer and destination-placement contract.

## Canonical SSH Persistence Migration

`VibeSpaceValidator.normalizedPath` parses every `ssh://` value and rebuilds it with `SSHConnectionProfile.projectIdentifier(remotePath:)`, so live `projectPaths`, `unresolvedProjectPaths`, `focusedProjectPath`, and `parkedProjectPaths` converge on the same percent-encoded host-qualified form. Validation deduplicates parked values and removes any parked identifier already represented as live or unresolved. `VibeSpaceManagementService.loadVibeSpace` immediately saves a changed parent config only when its integrity signature verified; an untrusted payload is normalized in memory without blessing it with a new signature.

Per-project persistence resolves the canonical identifier first, then migration aliases: the raw remote path, the prior raw full identifier `profile.sshURI + remotePath`, and the historical malformed local-file normalization. A successful alias load copies the complete `ProjectConfigFile`—terminal state, browsers, color, numeric shortcut, ACP override, shell/startup overrides, and scoped shortcuts—to the canonical key and removes the old file/cache entry. All per-project mutations load through this helper before writing; browser and project-shortcut reads/writes use the same canonical path. `loadProjectConfigs` enumerates live, unresolved, and parked identifiers and keys its result by each loaded config's canonical `projectPath`.

At runtime, `VibeSpaceState` canonicalizes configured live/unresolved/focused/parked identities before session creation and deduplicates parked values. `pruneColorTags` and `normalizeProjectShortcuts` include live, unresolved, and parked identifiers, preserving dormant color, startup, ACP-agent, terminal-shell, scoped-shortcut, and numeric shortcut slots instead of pruning them merely because no session is live.

## Verification Scope

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. `VibeSpaceManagementServiceTests.testCanonicalRemoteIdentifierMigratesPriorRawFullIdentifierAndAllProjectState` directly covers complete config migration from the prior raw full SSH identifier, browser and shortcut reads, alias deletion, canonical dictionary keys, parked deduplication, and immediate rewrite of a verified parent; raw-path and malformed-normalization alias tests also exist. Runtime retention across every unresolved/parked settings dictionary is production-source inspection. Static tests additionally cover document close serialization/failure retention, per-tab provider lifetime, shortcut uniqueness, board ownership, detached attachment, and narrow detached shortcut/permanent routes. Exact same-root repository attachment, staged-then-working non-empty diff concatenation into a preloaded qualified tab, exact untracked providers, the complete Spotlight route matrix, project-keyed displaced/outstanding flush collection, the true 30-second race, and exactly-once shutdown remain production-source inspection. No build, test, app, or process was run during this documentation reconciliation.

## Change History

- 2026-10-23: Added canonical SSH parent/per-project migration design, prior raw full alias support, live/unresolved/parked canonical loading, dormant-state preservation, and exact final build/test-build evidence.
- 2026-10-23: Added project-qualified source-control/Spotlight/shortcut architecture, project-keyed displaced/outstanding flush tracking, and the true flush-vs-30-second-timeout exactly-once shutdown race; corrected stale immediate-shutdown ordering and narrowed verification.
- 2026-10-23: Added F021-R30–R31 lifecycle design; corrected browser query/persist keys, deferred shutdown/30-second watchdog, unpinned preview and per-tab flush handling, eager VibeSpace pruning, and compile/static-only verification.
- 2026-10-20: Documented F021-R25–R29 automatic board cleanup: frozen ownership evidence, one normalized/persisted multi-surface mutation, host-qualified migration and fail-closed legacy handling, managed-window closure, and ownership-preserving browser/terminal restoration. Static sources only; no test pass is claimed.

- 2026-10-20: Corrected fallback-refocus ordering and publication-boundary semantics; the 2026-10-23 entry supersedes the earlier immediate-shutdown description with file-flush-aware deferred shutdown.
