# Agent CLI — File Commands

This document specifies the `file.*` commands. See [spec.md](spec.md) for cross-cutting requirements.

## Commands

- `file.open` — open a file in the editor

The CLI does not expose `read`, `write`, `edit`, `list`, `stat`, `delete`, or `rename`. Agents that need those use their model's built-in file tools or the shell (via `terminal.send`). The CLI's value here is the IDE-integration side-effect: showing the file in a tab where the user can see it.

---

## `file.open`

Opens a file in the Crispy editor. The file appears in a tab exactly as if the user had double-clicked it in the explorer.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | File path. Absolute, or relative to caller's `CRISPY_PROJECT_PATH`. |
| `line` | integer | no | 1-based line number to scroll to and place the caret. |
| `column` | integer | no | 1-based column to place the caret. Requires `line`. |
| `vibespace_id` | string | no | Vibespace to open the editor in. Defaults to caller's `CRISPY_VIBESPACE`. |

### Result

| Field | Type | Description |
|---|---|---|
| `tab_id` | string | UUID of the editor tab |
| `path` | string | Resolved absolute path |
| `line` | integer \| null | Caret line if `line` was provided |

### Requirements

#### F044-R40: Open routes through ContentViewer

`file.open` MUST go through the same code path used by the explorer's open-file action so that the file appears in the content viewer, gets added to recent files, and persists in session restore. The server posts the existing internal open-file notification observed by `ContentView`.

#### F044-R41: Path resolution and boundary

`file.open` MUST resolve relative paths against `CRISPY_PROJECT_PATH`. After symlink resolution, the path MUST remain within the project root. Paths escaping the project return `permission_denied`. (Path-resolution logic is shared with `ACPFileSystemHandler.resolvedPath(from:)`.)

#### F044-R42: Line and column validation

`line` MUST be a positive integer. `column` requires `line` and MUST be a positive integer. Out-of-range values are not validated against file content (the editor clamps to the actual extent).

#### F044-R43: Missing file

If `path` does not exist, the response is `file_not_found`. The CLI MUST NOT create the file as a side effect of `file.open`.

### Scenarios

#### Scenario F044-S100: Open file with absolute path

**Given** the agent's project is `/projects/foo` with file `/projects/foo/src/main.rs`
**When** the agent invokes `file.open` with `path: "/projects/foo/src/main.rs"`
**Then** the file opens in the editor in the agent's vibespace
**And** the response includes `tab_id` and the resolved absolute path

#### Scenario F044-S101: Open file with relative path

**When** the agent invokes `file.open` with `path: "src/main.rs"`
**Then** the path resolves to `/projects/foo/src/main.rs`
**And** the file opens in the editor

#### Scenario F044-S102: Open file at line and column

**When** the agent invokes `file.open` with `path: "src/main.rs"`, `line: 42`, `column: 8`
**Then** the file opens with the caret on line 42, column 8
**And** the editor scrolls to make that line visible

#### Scenario F044-S103: Open path escaping project

**Given** the project root is `/projects/foo`
**When** the agent invokes `file.open` with `path: "../bar/secret.txt"`
**Then** the response is `permission_denied`

#### Scenario F044-S104: Open path through symlink that escapes project

**Given** `/projects/foo/link` is a symlink to `/etc/passwd`
**When** the agent invokes `file.open` with `path: "link"`
**Then** the response is `permission_denied` after symlink resolution detects the escape

#### Scenario F044-S105: Open non-existent file

**When** the agent invokes `file.open` with `path: "missing.txt"`
**Then** the response is `file_not_found`
