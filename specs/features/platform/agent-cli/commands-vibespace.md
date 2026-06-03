# Agent CLI — VibeSpace & Pane Commands

This document specifies the `vibespace.*` and `pane.*` commands. See [spec.md](spec.md) for cross-cutting requirements.

> **Status: deferred.** All commands in this category are spec'd but not yet implemented. Tracked under F044 future scope.

## Commands

- `vibespace.list` — list all open vibespaces
- `vibespace.current` — return the focused vibespace
- `pane.list` — list panes and surfaces in a vibespace

These commands give agents read-only awareness of the IDE's layout. They do NOT mutate state — agents cannot create or close vibespaces from the CLI in this version. (See [Open Questions](#open-questions) for future scope.)

---

## `vibespace.list`

Lists all currently-open vibespaces.

### Parameters

None.

### Result

| Field | Type | Description |
|---|---|---|
| `vibespaces` | array of VibeSpaceDescriptor | All open vibespaces |
| `focused_id` | string | UUID of the focused vibespace |

`VibeSpaceDescriptor`:

| Field | Type | Description |
|---|---|---|
| `vibespace_id` | string | UUID |
| `name` | string | Display name |
| `project_count` | integer | Number of projects in the vibespace |
| `focused_project_path` | string \| null | Absolute path of the focused project, or null if none |
| `focused` | boolean | True if this is the focused vibespace |

### Requirements

#### F044-R70: List reflects VibeSpaceCatalogStore

`vibespace.list` MUST return entries from `VibeSpaceCatalogStore.vibespaces` in the order the user sees them.

#### F044-R71: At most one focused

Exactly one entry MUST have `focused: true` whenever the response is non-empty. The focused entry's `vibespace_id` MUST equal the top-level `focused_id` field.

### Scenarios

#### Scenario F044-S180: List with multiple vibespaces

**Given** the user has 3 vibespaces open
**When** the agent invokes `vibespace.list`
**Then** the response contains 3 entries
**And** exactly one has `focused: true`
**And** `focused_id` matches that entry

#### Scenario F044-S181: List with one vibespace

**When** the agent invokes `vibespace.list` with only one vibespace open
**Then** the response contains 1 entry with `focused: true`

---

## `vibespace.current`

Returns the focused vibespace and the focused project within it.

### Parameters

None.

### Result

| Field | Type | Description |
|---|---|---|
| `vibespace_id` | string | UUID of the focused vibespace |
| `name` | string | Display name |
| `project_count` | integer | Number of projects in the vibespace |
| `focused_project_path` | string \| null | Absolute path of the focused project, or null |
| `focused_project_name` | string \| null | Display name of the focused project, or null |
| `is_caller_vibespace` | boolean | True if this matches the caller's `CRISPY_VIBESPACE` |

### Requirements

#### F044-R72: Reflects current focus

`vibespace.current` MUST return whatever vibespace is presently focused, regardless of where the channel client originated. This is distinct from `whoami` which prefers the channel client's env-var context.

### Scenarios

#### Scenario F044-S185: Current matches caller

**Given** the agent runs in the same vibespace that has UI focus
**When** the agent invokes `vibespace.current`
**Then** the response includes the focused vibespace
**And** `is_caller_vibespace: true`

#### Scenario F044-S186: User switched vibespaces

**Given** the agent's terminal is in vibespace A
**And** the user has clicked over to vibespace B
**When** the agent invokes `vibespace.current`
**Then** the response describes vibespace B
**And** `is_caller_vibespace: false`

---

## `pane.list`

Lists all panes and the surfaces inside each pane for a given vibespace.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `vibespace_id` | string | no | Defaults to caller's `CRISPY_VIBESPACE`. |

### Result

| Field | Type | Description |
|---|---|---|
| `panes` | array of PaneDescriptor | All panes in the vibespace |

`PaneDescriptor`:

| Field | Type | Description |
|---|---|---|
| `pane_id` | string | UUID |
| `surfaces` | array of PaneSurfaceDescriptor | Surfaces inside this pane |
| `focused` | boolean | True if this pane has focus |

`PaneSurfaceDescriptor`:

| Field | Type | Description |
|---|---|---|
| `terminal_id` | string | UUID |
| `kind` | string | `"terminal"` or `"browser"` or `"editor"` |
| `title` | string | Tab title |
| `focused` | boolean | True if this is the focused surface within the pane |
| `is_caller` | boolean | True if this is the caller's own surface |

### Requirements

#### F044-R73: Inclusive surface listing

`pane.list` MUST list ALL surface kinds (terminal, browser, editor) — distinct from `terminal.list` which is filtered to terminals only.

#### F044-R74: Exactly one focused pane

Exactly one pane MUST have `focused: true` per vibespace. Within that pane, exactly one surface MUST have `focused: true` (or the pane is empty).

### Scenarios

#### Scenario F044-S190: List in caller's vibespace

**Given** the caller's vibespace has 2 panes: one with a terminal surface and one with a browser surface
**When** the agent invokes `pane.list`
**Then** the response includes 2 panes with their respective surfaces

#### Scenario F044-S191: List with mixed surfaces

**Given** a pane contains both a terminal and a browser surface as tabs
**When** the agent invokes `pane.list`
**Then** the corresponding pane descriptor lists both surfaces in tab order

#### Scenario F044-S192: Empty pane edge case

**Given** the vibespace has just been created and no surfaces have been added yet
**When** the agent invokes `pane.list`
**Then** the response is `panes: []` or includes a single empty pane (whichever matches `VibeSpaceCatalogStore` reality)

---

## `vibespace.addProject`

Adds a project folder to the focused vibespace and focuses it.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | Absolute path to the project directory |

### Result

| Field | Type | Description |
|---|---|---|
| `project_path` | string | Resolved absolute path of the added project |
| `project_name` | string | Display name of the added project |
| `focused` | boolean | Always `true` — new project becomes focused per F021-S03 |

### Requirements

#### F044-R80: Add Project

`vibespace.addProject` MUST add a project to the focused vibespace via the same orchestration path used by the UI's "Add Project" flow (`VibeSpaceCanvasActionsCoordinator.addProjectsViaCLI`). Behavior MUST match F021-S03: the new project becomes focused, and an active terminal is ensured for the project root.

Validation:
- `path` MUST exist and be a directory; otherwise return `file_not_found`
- `path` MUST NOT already correspond to a live project in the vibespace; otherwise return `invalid_params`. (Parked projects with the same path auto-unpark — this is delegated to `VibeSpaceState.addProjects`.)

### Scenarios

#### Scenario F044-S200: Adds a new project and focuses it

**Given** the focused vibespace has 1 live project
**When** the agent invokes `vibespace.addProject` with a fresh directory path
**Then** the vibespace's `projects` count becomes 2
**And** the new project becomes focused (`focused_project_path` matches)
**And** the response result includes `project_path`, `project_name`, `focused: true`

#### Scenario F044-S201: Rejects nonexistent path

**Given** the agent invokes `vibespace.addProject` with a path that does not exist on disk
**Then** the response is an error with code `file_not_found`
**And** the vibespace is unmodified

#### Scenario F044-S202: Rejects duplicate live project

**Given** project `/foo` is already live in the vibespace
**When** the agent invokes `vibespace.addProject` with `/foo`
**Then** the response is an error with code `invalid_params`
**And** the vibespace is unmodified

---

## `vibespace.removeProject`

Removes a project from the focused vibespace and closes its artifacts.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | Absolute path of the project to remove |

### Result

| Field | Type | Description |
|---|---|---|
| `removed_project_path` | string | Resolved absolute path of the removed project |

### Requirements

#### F044-R81: Remove Project

`vibespace.removeProject` MUST resolve the live project at `path` and invoke `VibeSpaceCanvasActionsCoordinator.removeProject(id:)`, which:
- closes all browsers owned by the project (F012-R18)
- shuts down the project session (terminating terminals and watchers)
- applies focus fallback to the last remaining project (F021-S06)
- persists the catalog

Validation:
- `path` MUST correspond to a live project in the vibespace; otherwise return `file_not_found`

### Scenarios

#### Scenario F044-S203: Removes the project and applies focus fallback

**Given** the focused vibespace has projects `/a` (focused) and `/b`
**When** the agent invokes `vibespace.removeProject` with `/a`
**Then** the vibespace's `projects` count becomes 1
**And** `/b` becomes focused
**And** the response result includes `removed_project_path: "/a"`

---

## `vibespace.parkProject`

Parks a project in the focused vibespace, persisting state and terminating sessions.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | Absolute path of the project to park |

### Result

| Field | Type | Description |
|---|---|---|
| `parked_project_path` | string | Resolved absolute path of the parked project |

### Requirements

#### F044-R82: Park Project

`vibespace.parkProject` MUST invoke `VibeSpaceCanvasActionsCoordinator.parkProject(id:)`, which:
- captures browser session entries (F012-R20)
- closes browsers via the standard close pipeline
- marks `ProjectConfigFile.isParked = true`
- mutates state via `VibeSpaceState.parkProject(id:)` (terminates terminals, removes from `projects`, appends to `parkedProjectPaths`)
- persists the catalog

Validation:
- `path` MUST correspond to a live project in the vibespace; otherwise return `file_not_found`. Already-parked projects are NOT live, so re-parking returns `file_not_found` rather than a no-op.

### Scenarios

#### Scenario F044-S204: Parks the project, moving its path to parkedProjectPaths

**Given** the focused vibespace has live project `/foo`
**When** the agent invokes `vibespace.parkProject` with `/foo`
**Then** `/foo` is removed from `projects`
**And** `/foo` is appended to `parkedProjectPaths`
**And** the project's `ProjectConfigFile.isParked` becomes `true`
**And** the response result includes `parked_project_path: "/foo"`

---

## `vibespace.activateProject`

Activates (unparks) a parked project in the focused vibespace and focuses it.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | Absolute path of the parked project to activate |

### Result

| Field | Type | Description |
|---|---|---|
| `activated_project_path` | string | Resolved absolute path of the activated project |
| `focused` | boolean | Always `true` — the activated project becomes focused |

### Requirements

#### F044-R83: Activate Project

`vibespace.activateProject` MUST verify `path` is currently parked, then invoke `VibeSpaceCanvasActionsCoordinator.unparkProject(path:)`, which recreates the live `ProjectSession`, restores persisted browser sessions, clears `ProjectConfigFile.isParked`, focuses the project, and persists the catalog (mirrors the UI "Activate Project" flow, F021-R11).

Validation:
- `path` MUST currently be parked in the vibespace; otherwise return `file_not_found`
- if unpark yields no session (e.g. the directory is gone), return `internal_error`

### Scenarios

#### Scenario F044-S205: Activates a parked project and focuses it

**Given** project `/foo` is parked in the focused vibespace
**When** the agent invokes `vibespace.activateProject` with `/foo`
**Then** `/foo` is removed from `parkedProjectPaths` and appended to `projects`
**And** `/foo` becomes the focused project
**And** the response result includes `activated_project_path: "/foo"`, `focused: true`

#### Scenario F044-S206: Rejects a non-parked path

**Given** `/foo` is a live (not parked) project, or is unknown to the vibespace
**When** the agent invokes `vibespace.activateProject` with `/foo`
**Then** the response is an error with code `file_not_found`
**And** the vibespace is unmodified

---

## `vibespace.listProjects`

Lists the active, parked, and unresolved projects in the focused vibespace. Read-only.

### Parameters

None.

### Result

| Field | Type | Description |
|---|---|---|
| `active` | array of object | Live projects: `{ path, name, focused }` |
| `parked` | array of string | Parked project paths |
| `unresolved` | array of string | Unresolved (missing) project paths |

### Requirements

#### F044-R84: List Projects

`vibespace.listProjects` MUST return the focused vibespace's `projects` (with `focused` reflecting `focusedProjectID`), `parkedProjectPaths`, and `unresolvedProjectPaths`. It MUST be free of observable side effects (F044-R12) and require no actions coordinator (catalog read only).

### Scenarios

#### Scenario F044-S207: Lists active and parked projects

**Given** the focused vibespace has a live project `/a` and a parked project `/b`
**When** the agent invokes `vibespace.listProjects`
**Then** `active` contains one entry with `path: "/a"`
**And** `parked` equals `["/b"]`

---

## Test Coverage

| Scope | Test File |
|---|---|
| Handler-level: addProject / removeProject / parkProject / activateProject / listProjects success + validation paths; coordinator-not-attached fallback; coordinator-level parked-project removal | `tests/unit/Models/CLICommandRouterVibeSpaceProjectTests.swift` |
| Underlying state-layer behavior (park/unpark cycle, addProjects auto-unpark, remove parked project) | `tests/unit/Models/VibeSpaceStateParkingTests.swift` |

---

## Open Questions

### Should agents be able to create or close vibespaces?

Currently NOT in scope. Agents that need a fresh vibespace must rely on the user creating one via the UI. Future work could add `vibespace.create` and `vibespace.close`, but doing so introduces semantics around persistence (does it appear in recents?), focus stealing (should creation steal user focus?), and project assignment (which directory becomes the project?).

### Should `pane.list` include layout geometry?

Currently NO — `pane.list` returns only the structural pane/surface tree, not pane sizes or split orientations. If agents need geometry to make layout decisions, this can be added as additional fields without breaking the existing shape.
