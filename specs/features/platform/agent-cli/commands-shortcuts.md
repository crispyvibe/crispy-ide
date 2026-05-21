# Agent CLI — Shortcut Commands

This document specifies the `shortcut.*` commands. See [spec.md](spec.md) for cross-cutting requirements.

## Commands

- `shortcut.list` — list saved terminal shortcuts in scope
- `shortcut.add` — register a new terminal shortcut

The CLI deliberately omits `shortcut.run` — agents that want to execute a shortcut's command should use `terminal.send` directly. The CLI's role here is shortcut **catalog management**: agents can discover existing shortcuts (to understand the project's build/test/lint conventions) and propose new ones (e.g. "I noticed you keep running `npm run e2e` — saved it as a shortcut").

These commands operate on Crispy's terminal-shortcut model defined in [F001 Terminal Sessions & Tabs](../../terminal/sessions-and-tabs/spec.md), specifically `F001-R28`/`F001-R29`. Shortcuts are scoped to a vibespace or to a specific project within a vibespace.

---

## `shortcut.list`

Lists all terminal shortcuts visible from the channel client's context. Returns vibespace-scoped shortcuts and project-scoped shortcuts for the channel client's project.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `vibespace_id` | string | no | Defaults to caller's `CRISPY_VIBESPACE`. |
| `scope` | string | no | One of `"vibespace"`, `"project"`, `"all"`. Default `"all"`. |

### Result

| Field | Type | Description |
|---|---|---|
| `shortcuts` | array of ShortcutDescriptor | Shortcuts matching the requested scope |

`ShortcutDescriptor`:

| Field | Type | Description |
|---|---|---|
| `id` | string | Stable identifier |
| `name` | string | Display name |
| `command` | string | The command line that will be sent to a terminal |
| `launch_behavior` | string | `"currentTerminal"`, `"newPermanentTerminal"`, or `"newTemporaryTerminal"` |
| `scope` | string | `"vibespace"` or `"project"` |
| `project_path` | string \| null | Absolute project path if scope is `"project"`, else null |

### Requirements

#### F044-R80: List reflects vibespace and project shortcut stores

`shortcut.list` MUST return entries from the same data the VibeSpace Settings UI shows: vibespace-level shortcuts plus project-level shortcuts for the resolved project. Order matches the UI sidebar order.

#### F044-R81: Scope filtering

If `scope` is `"vibespace"`, only vibespace-scoped shortcuts are returned. If `scope` is `"project"`, only project-scoped shortcuts for the channel client's project are returned. `"all"` (the default) returns both, vibespace-scoped first.

### Scenarios

#### Scenario F044-S200: List with mixed shortcuts

**Given** the vibespace has 2 vibespace-scoped shortcuts and the channel client's project has 3 project-scoped shortcuts
**When** the agent invokes `shortcut.list`
**Then** the response contains 5 entries
**And** vibespace-scoped entries appear before project-scoped ones
**And** the project-scoped entries have `project_path` set to the channel client's project path

#### Scenario F044-S201: List filtered to project scope

**When** the agent invokes `shortcut.list` with `scope: "project"`
**Then** only the 3 project-scoped shortcuts are returned

#### Scenario F044-S202: List with no shortcuts

**When** the vibespace and project have no shortcuts
**Then** the response is `shortcuts: []`

---

## `shortcut.add`

Registers a new terminal shortcut. The shortcut appears in the VibeSpace Settings UI immediately and persists across app restarts.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Display name. Must be non-empty after trimming whitespace. |
| `command` | string | yes | The command line to run. Must be non-empty after trimming whitespace. |
| `launch_behavior` | string | no | One of `"currentTerminal"`, `"newPermanentTerminal"`, `"newTemporaryTerminal"`. Default `"newPermanentTerminal"`. |
| `scope` | string | no | `"vibespace"` or `"project"`. Default `"project"`. |
| `vibespace_id` | string | no | Defaults to caller's `CRISPY_VIBESPACE`. |
| `project_path` | string | no | Required when `scope: "project"`. Defaults to caller's `CRISPY_PROJECT_PATH`. Ignored when `scope: "vibespace"`. |

### Result

| Field | Type | Description |
|---|---|---|
| `id` | string | Identifier of the new shortcut |
| `name` | string | Resolved name (trimmed) |
| `scope` | string | Resolved scope |

### Requirements

#### F044-R82: Add routes through existing shortcut store

`shortcut.add` MUST go through the same code path used by VibeSpace Settings → Shortcuts → "Add Shortcut" so the new entry is persisted, surfaces in the UI, and behaves identically to user-created shortcuts.

#### F044-R83: Validation

Both `name` and `command` MUST be non-empty after whitespace trimming. Empty values return `invalid_params`. `launch_behavior` MUST be one of the three documented values; other values return `invalid_params`.

#### F044-R84: Project-scope project resolution

When `scope: "project"`, the resolved project path MUST belong to the resolved vibespace. If the project path is not part of the vibespace's projects, the response is `vibespace_not_found` (the project, not the vibespace, is the missing referent — but we surface a single error code for this case to keep the API simple).

#### F044-R85: Duplicate names allowed

Two shortcuts MAY share the same name. Uniqueness is enforced only by `id`. If an agent wants to dedupe, it should call `shortcut.list` first.

### Scenarios

#### Scenario F044-S210: Add project-scoped shortcut with defaults

**Given** an agent runs in a project at `/projects/foo`
**When** the agent invokes `shortcut.add` with `name: "Run tests"` and `command: "npm test"`
**Then** a new shortcut is created with `scope: "project"`, `project_path: "/projects/foo"`, and `launch_behavior: "newPermanentTerminal"`
**And** the shortcut appears in VibeSpace Settings → Shortcuts under the foo project
**And** the response includes the new `id`

#### Scenario F044-S211: Add vibespace-scoped shortcut

**When** the agent invokes `shortcut.add` with `name: "Open docs"`, `command: "open https://docs.example.com"`, `scope: "vibespace"`, `launch_behavior: "newTemporaryTerminal"`
**Then** a vibespace-scoped shortcut is created
**And** the response includes `scope: "vibespace"`

#### Scenario F044-S212: Empty command rejected

**When** the agent invokes `shortcut.add` with `name: "noop"` and `command: "   "`
**Then** the response is `invalid_params` with message about empty command

#### Scenario F044-S213: Invalid launch behavior

**When** the agent invokes `shortcut.add` with `launch_behavior: "background"`
**Then** the response is `invalid_params` listing the allowed values

#### Scenario F044-S214: Persist across app restart

**Given** the agent has added a shortcut via `shortcut.add`
**When** the user quits and relaunches the app
**Then** the shortcut still appears in VibeSpace Settings and via `shortcut.list`
