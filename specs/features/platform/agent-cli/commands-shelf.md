# Agent CLI — Shelf Commands

This document specifies the `shelf.*` commands. See [spec.md](spec.md) for cross-cutting requirements.

## Commands

- `shelf.add` — add a file or folder to the shelf
- `shelf.list` — list all shelf items
- `shelf.remove` — remove an item from the shelf

The shelf is a persistent collection of file and folder paths surfaced in the vibespace sidebar. Shelf state survives app restarts and is identical whether the user or an agent adds items. See [F033 Shelf](../shelf/spec.md) for the underlying feature.

---

## `shelf.add`

Adds a file or folder to the shelf. Adding an existing path is a no-op (deduplicated).

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | Absolute or project-relative path to a file or directory. |
| `select` | boolean | no | If true, makes this the selected shelf item. Default false. |

### Result

| Field | Type | Description |
|---|---|---|
| `path` | string | Resolved absolute path |
| `kind` | string | `"file"` or `"folder"` |
| `added` | boolean | True if the item was newly added; false if it was already in the shelf |
| `selected` | boolean | True if this is now the selected shelf item |

### Requirements

#### F044-R50: Add routes through ShelfStore

`shelf.add` MUST call `ShelfStore.addFiles([url])` so the addition persists to `shelf-state.json` and triggers the same UI updates user clicks produce.

#### F044-R51: Path validation

The path MUST exist on disk. If it does not, the response is `file_not_found`. Project boundary is NOT enforced — the shelf intentionally allows paths anywhere on disk (matching user-clicked behavior).

#### F044-R52: Deduplication

If the resolved absolute path is already in the shelf, `shelf.add` MUST return `added: false` without modifying state. The position in the list MUST NOT change.

#### F044-R53: Kind detection

The `kind` field MUST be `"folder"` if the path is a directory, `"file"` otherwise. Symlinks are followed; `kind` reflects the link target.

### Scenarios

#### Scenario F044-S120: Add new file

**Given** the shelf does not contain `/projects/foo/notes.md`
**When** the agent invokes `shelf.add` with `path: "notes.md"`
**Then** the file is added to the shelf
**And** the response is `added: true, kind: "file", selected: false`
**And** the shelf sidebar shows the new entry

#### Scenario F044-S121: Add folder

**When** the agent invokes `shelf.add` with `path: "/projects/foo/docs"`
**Then** the folder appears in the shelf as expandable
**And** the response is `kind: "folder"`

#### Scenario F044-S122: Add already-shelved item

**Given** `/projects/foo/notes.md` is already in the shelf
**When** the agent invokes `shelf.add` with `path: "notes.md"`
**Then** the response is `added: false`
**And** the shelf is unchanged

#### Scenario F044-S123: Add with select

**When** the agent invokes `shelf.add` with `path: "plan.md"` and `select: true`
**Then** the file is added and immediately selected (highlighted in the sidebar)
**And** the response is `selected: true`

#### Scenario F044-S124: Add non-existent path

**When** the agent invokes `shelf.add` with `path: "missing.txt"`
**Then** the response is `file_not_found`
**And** the shelf is unchanged

#### Scenario F044-S125: Add path outside project (allowed)

**Given** the agent's project is `/projects/foo`
**When** the agent invokes `shelf.add` with `path: "/Users/manu/Desktop/reference.pdf"`
**Then** the file is added to the shelf
**And** no `permission_denied` is returned (shelf is not project-scoped)

#### Scenario F044-S126: Persist across restart

**Given** the agent has added `notes.md` and `docs/` to the shelf
**When** the user quits and relaunches the app
**Then** both items reappear in the shelf in the same order

---

## `shelf.list`

Lists all items in the shelf.

### Parameters

None.

### Result

| Field | Type | Description |
|---|---|---|
| `items` | array of ShelfItem | All items in shelf order (most-recently-added first) |
| `selected_path` | string \| null | Path of the currently selected item, or null |

`ShelfItem`:

| Field | Type | Description |
|---|---|---|
| `path` | string | Absolute path |
| `kind` | string | `"file"` or `"folder"` |
| `exists` | boolean | True if the path currently exists on disk |
| `selected` | boolean | True if this is the selected item |

### Requirements

#### F044-R54: List reflects ShelfStore state

`shelf.list` MUST return entries from `ShelfStore.filePaths` in the same order they appear in the UI sidebar.

#### F044-R55: Stale entries reported, not filtered

If a shelf entry's path no longer exists (deleted on disk), the entry MUST still appear with `exists: false`. The shelf does not auto-remove stale entries; the agent or user can call `shelf.remove` if desired.

### Scenarios

#### Scenario F044-S130: List with multiple items

**Given** the shelf has 3 items
**When** the agent invokes `shelf.list`
**Then** the response includes 3 entries in shelf order
**And** at most one entry has `selected: true`

#### Scenario F044-S131: List with stale entry

**Given** the shelf contains `/projects/foo/old.md` which has been deleted from disk
**When** the agent invokes `shelf.list`
**Then** the entry appears with `exists: false`

#### Scenario F044-S132: List with no items

**When** the shelf is empty and the agent invokes `shelf.list`
**Then** the response is `items: [], selected_path: null`

---

## `shelf.remove`

Removes an item from the shelf. The file/folder on disk is not affected; only the shelf entry is removed.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | Path to remove. Must match an existing shelf entry exactly (after path resolution). |

### Result

| Field | Type | Description |
|---|---|---|
| `removed` | boolean | True if an entry was removed; false if no matching entry was found |

### Requirements

#### F044-R56: Remove routes through ShelfStore

`shelf.remove` MUST call `ShelfStore.removeFile(at:)` with the resolved absolute path.

#### F044-R57: No-op for missing entries

If the path is not currently in the shelf, the response MUST be `removed: false` with `ok: true`. This allows agents to safely call `remove` without first checking via `list`.

#### F044-R58: Disk preservation

The file or folder on disk MUST NOT be deleted, modified, or moved as a side effect of `shelf.remove`. Only the shelf reference is cleared.

### Scenarios

#### Scenario F044-S135: Remove existing entry

**Given** the shelf contains `/projects/foo/notes.md`
**When** the agent invokes `shelf.remove` with `path: "notes.md"`
**Then** the entry is removed from the shelf
**And** the response is `removed: true`
**And** the file `notes.md` still exists on disk

#### Scenario F044-S136: Remove non-shelved entry

**When** the agent invokes `shelf.remove` with `path: "not-in-shelf.txt"`
**Then** the response is `ok: true, removed: false`

#### Scenario F044-S137: Remove selected entry

**Given** `notes.md` is the selected shelf item
**When** the agent invokes `shelf.remove` with that path
**Then** the entry is removed
**And** selection falls back to the next item (matching the sidebar UI behavior)
