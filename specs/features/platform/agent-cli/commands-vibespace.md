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

## Open Questions

### Should agents be able to create or close vibespaces?

Currently NOT in scope. Agents that need a fresh vibespace must rely on the user creating one via the UI. Future work could add `vibespace.create` and `vibespace.close`, but doing so introduces semantics around persistence (does it appear in recents?), focus stealing (should creation steal user focus?), and project assignment (which directory becomes the project?).

### Should `pane.list` include layout geometry?

Currently NO — `pane.list` returns only the structural pane/surface tree, not pane sizes or split orientations. If agents need geometry to make layout decisions, this can be added as additional fields without breaking the existing shape.
