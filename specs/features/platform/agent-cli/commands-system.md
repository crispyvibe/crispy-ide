# Agent CLI — System Commands

This document specifies the universal system commands. They use bare names (no namespace prefix) because they are meta commands that exist on every agent, not domain-specific operations. See [spec.md](spec.md) for cross-cutting requirements.

## Commands

- `ping` — connectivity check
- `whoami` — return the channel client's resolved context
- `help` — list supported methods, or describe one in detail

---

## `ping`

Health check. Returns app metadata. Used by agents to verify the socket connection works before issuing real commands.

### Parameters

None.

### Result

| Field | Type | Description |
|---|---|---|
| `version` | string | App version (`CFBundleShortVersionString`) |
| `build` | string | App build number (`CFBundleVersion`) |
| `app` | string | App display name (e.g. `"Crispy"` or `"CrispyLocal"`) |
| `protocol_version` | integer | Agent CLI protocol version, currently `1` |

### Requirements

#### F044-R20: Ping always succeeds

`ping` MUST succeed for any connection that passes the ancestry check, even when no other subsystem is initialized.

### Scenarios

#### Scenario F044-S20: Successful ping

**Given** an agent runs inside a Crispy terminal
**When** the agent invokes `crispy ping`
**Then** the response contains `ok: true`, `version`, `build`, `app`, and `protocol_version`

#### Scenario F044-S21: Distinct app reports its identity

**Given** the channel client is connected to a `CrispyLocal.app` instance
**When** `ping` is invoked
**Then** the response `app` field equals `"CrispyLocal"`

---

## `whoami`

Returns the channel client's full context: which terminal, vibespace, and project it inherits from environment variables, and what the server resolves those to.

### Parameters

None.

### Result

| Field | Type | Description |
|---|---|---|
| `terminal_id` | string \| null | UUID of the caller's terminal, or null if not running inside a Crispy terminal |
| `vibespace_id` | string | UUID of the vibespace, falling back to focused vibespace if env var unset |
| `vibespace_name` | string | Display name of the vibespace |
| `project_path` | string | Absolute path to the project root |
| `project_name` | string | Display name of the project |
| `stale_env` | array \| null | Names of env vars whose values were ignored because they no longer match running state |

### Requirements

#### F044-R21: whoami reflects channel client environment first

`whoami` MUST read `CRISPY_CONTEXT`, `CRISPY_VIBESPACE`, and `CRISPY_PROJECT_PATH` from the channel client's environment (passed by the CLI in request params under a reserved `_env` field) and resolve them. If any env var is missing or invalid, the field returned MUST be null OR fall back to the app's currently-focused equivalent — see F044-R22.

#### F044-R22: whoami fallback to focused state

If `CRISPY_VIBESPACE` is missing or invalid, `vibespace` MUST fall back to the app's currently-focused vibespace tag. The `vibespace` field MUST never be null when the app has at least one open vibespace.

### Scenarios

#### Scenario F044-S30: Identify from inside a terminal

**Given** an agent runs inside a terminal
**And** all `CRISPY_*` env vars are set correctly
**When** `whoami` is invoked
**Then** the response includes `context: "terminal.<uuid>"`, `context_kind: "terminal"`, `vibespace`, `vibespace_name`, `project_path`, and `project_name`

#### Scenario F044-S31: Identify from an ACP-spawned agent

**Given** an agent process was spawned by Crispy through ACP (no terminal)
**And** the spawn injected `CRISPY_CONTEXT=acpchat.<uuid>` and the vibespace/project env
**When** `whoami` is invoked
**Then** the response includes `context: "acpchat.<uuid>"`, `context_kind: "acpchat"`, and the resolved vibespace and project

#### Scenario F044-S32: Identify with stale CRISPY_VIBESPACE

**Given** the user has switched vibespaces since the agent process was spawned
**And** the channel client's `CRISPY_VIBESPACE` env var refers to a vibespace that has since been closed
**When** `whoami` is invoked
**Then** the response `vibespace` falls back to the currently-focused vibespace tag
**And** a `stale_env` field is included with value `["vibespace"]` to inform the agent

#### Scenario F044-S33: whoami with no context env var

**Given** the channel client lacks `CRISPY_CONTEXT` (e.g. unset by a wrapper script)
**When** `whoami` is invoked
**Then** the response `context` and `context_kind` are both null
**And** `vibespace`, `project_path`, and `project_name` still resolve from the focused state

---

## `help`

Lists supported methods (compact mode), or describes a single method in full detail. Agents use this for self-discovery: a single `help` call gives the menu; a follow-up `help shelf.add` gives the full schema for that one command.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `method` | string | no | When provided, returns the full descriptor for just that method. Omit to get a compact list. |

### Result (no `method` param)

Discovery mode. Returns a top-level overview of the app, a glossary of
core concepts, and the command list grouped by domain — so an agent can
orient itself with one call.

| Field | Type | Description |
|---|---|---|
| `protocol_version` | integer | Agent CLI protocol version |
| `app` | string | App display name (e.g. `"Crispy"` or `"CrispyLocal"`) |
| `summary` | string | Multi-sentence overview of what Crispy is and what the CLI exposes |
| `concepts` | array of ConceptDefinition | Glossary of the top concepts an agent will encounter |
| `domains` | array of DomainGroup | Domains in display order, each with its commands |

`ConceptDefinition`:

| Field | Type | Description |
|---|---|---|
| `term` | string | Concept name (e.g. `"vibespace"`, `"pane"`) |
| `definition` | string | One-sentence definition |

`DomainGroup`:

| Field | Type | Description |
|---|---|---|
| `name` | string | Domain name (`core`, `shelf`, `terminal`, `browser`, …) |
| `description` | string | What the domain represents |
| `commands` | array of `{method, summary}` | Methods in this domain |

### Result (with `method` param)

Detailed mode — the response wraps a single full descriptor in `commands` for shape consistency.

| Field | Type | Description |
|---|---|---|
| `protocol_version` | integer | Agent CLI protocol version |
| `commands` | array of one CommandDescriptor | Full descriptor for the requested method |

`CommandDescriptor`:

| Field | Type | Description |
|---|---|---|
| `method` | string | Dotted method name |
| `summary` | string | One-line description |
| `params` | array of ParamDescriptor | Input parameters |
| `result_fields` | array of ResultFieldDescriptor | Output fields |
| `errors` | array of string | Possible error codes |

`ParamDescriptor`:

| Field | Type | Description |
|---|---|---|
| `name` | string | Parameter name |
| `type` | string | `"string"`, `"integer"`, `"boolean"`, `"array"`, `"object"` |
| `required` | boolean | Whether the parameter is required |
| `description` | string | Human-readable description |
| `default` | any | Optional default value when not required |

`ResultFieldDescriptor`:

| Field | Type | Description |
|---|---|---|
| `name` | string | Field name |
| `type` | string | Same set as `ParamDescriptor.type` |
| `description` | string | Human-readable description |
| `nullable` | boolean | Whether the field may be null |

### Requirements

#### F044-R24: Help is the source of truth

`help` MUST emit every method the server is willing to dispatch. Method names listed MUST match the wire methods exactly. Adding a new command without registering it in `help` is a defect.

#### F044-R25: help reflects feature flags

If a command is gated behind a feature flag or build configuration (e.g. browser commands disabled in a build that excludes `WebKit`), it MUST NOT appear in `help` output for that build.

#### F044-R26: help with unknown method returns unknown_method

If `method` is provided but does not match any registered method, the response MUST be `unknown_method` with the requested name in the message.

### Scenarios

#### Scenario F044-S40: Compact list grouped by domain

**Given** the app is running with all subsystems enabled
**When** `help` is invoked with no parameters
**Then** the response `domains` array contains one entry per registered domain
**And** each domain has a `name`, a `description` explaining the concept, and a `commands` array of `{method, summary}` entries
**And** every method in the registry appears under exactly one domain

#### Scenario F044-S41: Detail for a known method

**When** `help` is invoked with `method: "shelf.add"`
**Then** the response `commands` array contains exactly one CommandDescriptor for `shelf.add`
**And** that descriptor includes `params`, `result_fields`, and `errors`

#### Scenario F044-S42: Detail for unknown method

**When** `help` is invoked with `method: "shelf.fly"`
**Then** the response is `ok: false` with code `unknown_method`

#### Scenario F044-S43: Disabled subsystem omitted

**Given** the app is running in a build configuration where browser support is disabled
**When** `help` is invoked
**Then** no `browser.*` commands appear in the response
