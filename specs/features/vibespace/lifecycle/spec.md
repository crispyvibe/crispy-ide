# F020 — VibeSpace Lifecycle

Status: draft

Domain: **VibeSpace (D2)**.
Covers vibespace creation, catalog persistence, hydration/restore, dashboard,
unresolved-path reconciliation, view modes, vibespace identity, and file integrity signing.

> Many of these scenarios were originally in F014 (Navigation). Scenarios that are
> primarily about vibespace lifecycle live here; navigation-centric scenarios remain
> in F014 with cross-references.

---

## Dependencies

- F014 (Navigation) — title bar actions, canvas layout
- F023 (Project Color Coding) — color tags displayed in dashboard

---

## Scenarios

### F020-S01 · Dashboard summarizes active vibespace health and quick actions (APP-034)

```gherkin
Given a VibeSpace is active
When the Dashboard is shown
Then the header displays the active VibeSpace name
And summary chips show Project count and missing-path count when unresolved folders exist
And quick actions include `Create VibeSpace`, `Add Project`, and `VibeSpace Settings`
```

### F020-S02 · Creating a vibespace replaces the current active vibespace context (APP-035)

```gherkin
Given an active VibeSpace is open
When the user runs `Create VibeSpace` from the toolbar or Dashboard
Then selected folders become Projects in a new VibeSpace snapshot
And the new VibeSpace becomes the only active VibeSpace in memory
And catalog persistence stores only that active VibeSpace snapshot
```

### F020-S03 · Catalog hydration restores one active vibespace and reconciles paths (APP-036)

```gherkin
Given persisted vibespace catalog contains one or more VibeSpace snapshots
When the app hydrates the catalog on launch
Then one VibeSpace is selected as active for UI rendering
And existing folders load as Projects
And unavailable folders remain tracked as unresolved paths
```

### F020-S04 · User removes one unresolved folder path (APP-037)

```gherkin
Given a VibeSpace has unresolved paths
When user clicks `Remove` on a specific missing path
Then that missing path entry is removed from that VibeSpace
And the updated catalog is persisted
```

### F020-S05 · User relinks one unresolved folder path (APP-038)

```gherkin
Given a VibeSpace has unresolved paths
When user clicks `Relink` and chooses a replacement folder
Then the missing path entry is replaced by the chosen folder
And if the replacement folder exists it is loaded as a Project
And the updated catalog is persisted
```

### F020-S06 · VibeSpace maintenance can reindex project folders (APP-049)

```gherkin
Given VibeSpace settings are open
When user clicks `Reindex Project Folders`
Then VibeSpace availability reconciliation runs immediately
And recovered folders move from missing paths into live projects
And unavailable folders remain tracked as unresolved paths
```

### F020-S07 · Empty state is shown when no projects exist (APP-022)

```gherkin
Given no projects are open
When ContentView renders
Then an empty state panel is shown
And the primary call to action is `Add Project(s)`
And terminal-only vibespace mode also shows an `Add Project(s)` call to action instead of empty terminal panels
```

### F020-S08 · VibeSpace toggles between Detailed and Terminal Only modes on demand (APP-052)

```gherkin
Given a VibeSpace is open
When user switches vibespace view mode from toolbar picker or keyboard command
Then canvas mode updates between `Detailed` and `Terminal Only`
And switching mode does not restart terminal sessions
And selected mode is persisted per VibeSpace layout state
```

### F020-S09 · Terminal Only mode renders stable per-project terminal panes (APP-053)

```gherkin
Given Terminal Only mode is active
When vibespace canvas renders
Then each Project is shown in its own terminal pane
And selecting a pane does not move or reflow surrounding panes
And user can type directly in the selected terminal session
```

### F020-S10 · Terminal Only orientation is user-selectable per VibeSpace (APP-054)

```gherkin
Given Terminal Only mode is active
When user switches terminal-only orientation between `Vertical` and `Horizontal`
Then pane arrangement updates to the selected orientation
And selected orientation is persisted per VibeSpace
```

### F020-S11 · Active vibespace identity is shown as plain window title text (APP-060)

```gherkin
Given a VibeSpace is active
When the active VibeSpace changes
Then the macOS window title updates to the active VibeSpace name
And VibeSpace identity is not shown as a toolbar picker control
```

### F020-S12 · VibeSpace-only actions are hidden when no vibespace is active (APP-061)

```gherkin
Given no VibeSpace is active
When the title bar renders
Then VibeSpace action controls are hidden
And App actions and VibeSpace management actions remain visible
```

### F020-S13 · VibeSpace restore preserves remote project identifiers and degrades failed remotes (APP-072)

```gherkin
Given a saved VibeSpace contains one or more SSH-backed Projects identified by `ssh://user@host:port/path` URIs
When the VibeSpace is reopened
Then the remote project identifiers are restored exactly from vibespace persistence
And local projects remain available immediately
And remote projects begin reconnecting asynchronously before editor tab restore runs
And remote projects that fail to reconnect remain in the VibeSpace as degraded entries instead of being removed
```

### F020-S14 · VibeSpace and project config files are HMAC-SHA256 signed on save (APP-085)

```gherkin
Given a vibespace or project config file is saved
When the persistence layer writes the file
Then the file is signed with HMAC-SHA256 using a key stored in the macOS Keychain
And the signature is persisted alongside the file content
```

### F020-S15 · Tampered config files are detected on load (APP-086)

```gherkin
Given a vibespace or project config file has been modified outside the app
When the file is loaded
Then signature verification fails
And the file is treated as untrusted
```

### F020-S16 · Untrusted config files load for display but disable startup commands (APP-087)

```gherkin
Given a config file fails signature verification
When the vibespace is opened
Then vibespace name, project list, and color tags are displayed normally
And startup commands and preset launches are not auto-executed
And a non-dismissable alert identifies the affected vibespace and states that configuration was modified outside the app and startup commands are disabled for safety
```

### F020-S17 · Re-saving settings from the app restores trust (APP-088)

```gherkin
Given a vibespace config file is currently untrusted
When the user reviews and re-saves settings through the app UI
Then the file is re-signed with HMAC-SHA256
And startup command execution is re-enabled
```

### F020-S18 · Signing logic is centralized in AppPersistenceDataStore (APP-089)

```gherkin
Given any persistence service needs to save or load a signed config file
When it calls saveWithIntegrity or loadWithIntegrity on AppPersistenceDataStore
Then HMAC signing and verification are handled centrally
And no service duplicates crypto logic
```

### F020-S19 · Layout files are exempt from signing (APP-090)

```gherkin
Given a layout file (layout.json) is saved or loaded
When the persistence layer processes the file
Then no HMAC signing or verification is applied
And the file is treated as trusted by default
```

### F020-S20 · VibeSpace removal via App Settings is bulk-capable and confirmed

```gherkin
Given the user has multiple vibespaces on disk
When the user opens App Settings → VibeSpaces
And selects one or more rows and clicks `Delete`
Then a confirmation alert is shown with single/many message variants
And on confirm, every selected vibespace's persisted state is pruned
And any active session bound to a deleted vibespace is closed first
And the operation is irreversible
```

---

## Requirements

| ID | Requirement |
|----|-------------|
| F020-R01 | Dashboard shows vibespace name, project count, missing-path count, and quick actions |
| F020-R02 | Creating a vibespace replaces the active vibespace context and persists to catalog |
| F020-R03 | Catalog hydration restores one active vibespace and reconciles folder availability |
| F020-R04 | Unresolved paths support remove and relink operations with catalog persistence |
| F020-R05 | Reindex reconciles folder availability immediately |
| F020-R06 | Empty state shows `Add Project(s)` CTA in both canvas modes |
| F020-R07 | Canvas mode toggles between Detailed and Terminal Only without restarting sessions |
| F020-R08 | Terminal Only orientation is user-selectable and persisted per vibespace |
| F020-R09 | Window title reflects active vibespace name as plain text |
| F020-R10 | VibeSpace actions hide when no vibespace is active |
| F020-R11 | VibeSpace restore preserves remote project URIs and degrades failed remotes |
| F020-R12 | Config files are HMAC-SHA256 signed; tampered files disable startup commands |
| F020-R13 | Signing is centralized in AppPersistenceDataStore; layout files are exempt |
| F020-R14 | VibeSpaces are removable in bulk via App Settings → VibeSpaces (F036-R07); deletion closes the active session if matched, prunes persisted state, and requires explicit confirmation |

---

## Acceptance Criteria

- VibeSpace creation wizard produces a valid catalog entry
- App launch restores the last active vibespace from persisted catalog
- Unresolved paths are visible in dashboard and removable/relinkable
- View mode toggle preserves all terminal sessions
- File integrity signing blocks auto-execution of tampered configs

---

## Open Questions

- Should vibespace catalog support multiple saved vibespaces for quick switching?
- Should file integrity alerts offer a "trust anyway" escape hatch for power users?

---

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Initial draft — extracted from F014 Navigation | — |
| 2026-05-26 | Added F020-S20 + F020-R14 covering vibespace bulk removal via App Settings → VibeSpaces (cross-references F036-R07) | — |
