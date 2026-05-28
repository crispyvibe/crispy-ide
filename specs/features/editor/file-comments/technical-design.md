# File Comments — Technical Design

## Overview

F049 adds comment storage, CLI commands, and UI affordances for inline file comments. The design extends the existing `crispyvibes-persistence` Rust helper with new tables and RPC methods, adds a Swift `VibeSpaceCommentStore` that wraps the existing helper subprocess, and introduces UI components that dock inside the per-pane content viewer.

## Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│  Crispy.app (Swift)                                                    │
│  ┌──────────────────┐  ┌──────────────────────┐  ┌─────────────────┐   │
│  │ ContentViewer    │  │ CommentsPanelView    │  │ CrossFileView   │   │
│  │  + Gutter        │◄─┤  (per-pane)          │  │ (workspace)     │   │
│  │  + Highlights    │  └────────┬─────────────┘  └────────┬────────┘   │
│  └────────┬─────────┘           │                          │            │
│           │                     ▼                          ▼            │
│           │    ┌────────────────────────────────────────────────────┐   │
│           │    │  VibeSpaceCommentStore (@MainActor)                │   │
│           │    │  - reactive @Published threadsByFile               │   │
│           │    │  - reads/writes via AgentConversationStore.send    │   │
│           │    │  - drives anchor relocation on file changes        │   │
│           │    └────────────┬───────────────────────────────────────┘   │
│           │                 │                                            │
│           │    ┌────────────▼─────────────────┐                          │
│           │    │  AgentConversationStore       │                         │
│           │    │  (existing — owns subprocess) │                         │
│           │    └────────────┬─────────────────┘                          │
│           │                 │ JSON-RPC over stdio                        │
│           ▼                 ▼                                            │
│  ┌──────────────────────────────────────────┐                            │
│  │  CLISocketServer ─► CLICommandRouter ─►  │                            │
│  │  CLICommandRouterCommentsHandlers (ext)  │                            │
│  └──────────────────────┬───────────────────┘                            │
└─────────────────────────┼────────────────────────────────────────────────┘
                          │
            ┌─────────────▼──────────────┐
            │  crispy CLI (Rust binary)  │  ← invoked by agents in terminals
            └─────────────┬──────────────┘
                          │ Unix domain socket
                          ▼
              ┌────────────────────────────────┐
              │ crispyvibes-persistence-helper │  (Rust subprocess)
              │  ┌──────────────────────────┐  │
              │  │  handlers_comments.rs    │  │
              │  │  - comment.add           │  │
              │  │  - comment.list          │  │
              │  │  - comment.reply         │  │
              │  │  - comment.update        │  │
              │  │  - comment.resolve       │  │
              │  │  - comment.delete        │  │
              │  │  - comment.relocate      │  │
              │  │  - comment.search        │  │
              │  └──────────────────────────┘  │
              │  schema v2: comments,          │
              │             comment_anchors    │
              │  encrypted libSQL (AES-256-CBC)│
              └────────────────────────────────┘
```

## Data Flow

### Add comment (UI path)

1. User selects text in `MarkdownEditorView` and triggers "Add Comment".
2. `EditorGroupStore` captures the selection and asks `VibeSpaceCommentStore` to open a composer in the side panel for the active file.
3. Composer submit calls `VibeSpaceCommentStore.add(file:, anchor:, body:)`.
4. The store calls `agentConversationStore.send(method: "comment.add", params: …)`.
5. Persistence helper writes the comment in a single transaction, returns the new row.
6. Store emits a `commentsChanged(file:)` event consumed by views; gutter, highlight, and panel re-render.

### Add comment (CLI path)

1. Agent runs `crispy comments add --file foo.swift --line 10 --comment "..."` in a terminal.
2. CLI binary connects to the Crispy app's Unix socket, sends `comments.add` JSON-RPC.
3. `CLICommandRouter` dispatches to `handleCommentsAdd(_:)` (in `CLICommandRouterCommentsHandlers`).
4. Handler resolves the active vibespace + project from the channel client `_env`, validates the file path lies inside the vibespace, computes the anchor hash from the current file content, and calls `VibeSpaceCommentStore.add(...)`.
5. Same as step 4–6 above.
6. The store's `@Published` change triggers UI updates within the 500ms target.

### Anchor relocation

Triggered when a file is reloaded (file watcher fires) or first opened after the app launches:

1. `VibeSpaceCommentStore.relocateAnchors(file:, content:)` is called.
2. For each comment on the file, the relocator runs the strategy from F049-R05:
   - Hash check at original line range
   - Fuzzy line search ±50 lines
   - Context corroboration scan
3. Successful relocations call `comment.relocate` to persist the new range.
4. Failures set `is_stale = true`.
5. `anchor.relocated` / `anchor.stale` observability events are emitted.

## API / Command Contracts

### CLI Commands (JSON-RPC method names)

| Method | Params | Result |
|---|---|---|
| `comments.add` | `file` (str, required), `start_line`, `start_col`, `end_line`, `end_col` (ints, required), `body` (str, required), `parent_id` (str, optional) | `{id, vibespace_id, file_path, ...}` |
| `comments.list` | `file` (str, optional), `status` (`active`/`resolved`/`stale`/`all`) | `{comments: [...]}` |
| `comments.reply` | `parent_id` (str, required), `body` (str, required) | `{id, parent_id, ...}` |
| `comments.update` | `id` (str, required), `body` (str, required) | `{id, ...}` |
| `comments.resolve` | `id` (str, required) | `{id, resolved_at}` |
| `comments.delete` | `id` (str, required) | `{id, deleted_count}` |

### Persistence helper RPC (internal)

Same set, plus:

- `comment.relocate` — `{id, start_line, start_col, end_line, end_col, is_stale, anchor_hash, anchor_text}`
- `comment.search` — `{vibespace_id, query, status, file_prefix, since, until}`

## State Management

`VibeSpaceCommentStore` (@MainActor, ObservableObject) owns:

- `@Published var threadsByFile: [FileKey: [CommentThread]]`
- `@Published var orphanedComments: [CommentThread]`
- `@Published var lastChangeID: UUID` — bumps on every write so views observe coalesced refreshes

Per-pane state lives in a small `CommentsPanelState` struct stored on each `EditorGroupStore`:

- `isOpen: Bool`
- `widthFraction: CGFloat` (default 0.30)
- `selectedThreadID: String?`
- `composerSelection: SelectionRange?` (active when composing)
- `filter: CommentStatusFilter`

This honors R06's per-pane independence requirement.

## Schema

### Migration v2 (new tables)

```sql
CREATE TABLE comments (
  id              TEXT PRIMARY KEY,
  vibespace_id    TEXT NOT NULL,
  file_path       TEXT NOT NULL,
  parent_id       TEXT REFERENCES comments(id) ON DELETE CASCADE,
  body            TEXT NOT NULL,
  author_kind     TEXT NOT NULL CHECK (author_kind IN ('user','agent')),
  author_label    TEXT,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  resolved_at     TEXT,
  is_stale        INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_comments_vs_file ON comments(vibespace_id, file_path, created_at);
CREATE INDEX idx_comments_parent  ON comments(parent_id);

CREATE TABLE comment_anchors (
  comment_id        TEXT PRIMARY KEY REFERENCES comments(id) ON DELETE CASCADE,
  start_line        INTEGER NOT NULL,
  start_column      INTEGER NOT NULL,
  end_line          INTEGER NOT NULL,
  end_column        INTEGER NOT NULL,
  anchor_hash       TEXT NOT NULL,
  anchor_text       TEXT NOT NULL,
  leading_context   TEXT NOT NULL,
  trailing_context  TEXT NOT NULL
);

CREATE VIRTUAL TABLE comment_fts USING fts5(body, content='comments', content_rowid='rowid');
CREATE TRIGGER comments_ai AFTER INSERT ON comments
  BEGIN INSERT INTO comment_fts(rowid, body) VALUES (new.rowid, new.body); END;
CREATE TRIGGER comments_ad AFTER DELETE ON comments
  BEGIN INSERT INTO comment_fts(comment_fts, rowid, body) VALUES ('delete', old.rowid, old.body); END;
CREATE TRIGGER comments_au AFTER UPDATE OF body ON comments
  BEGIN INSERT INTO comment_fts(comment_fts, rowid, body) VALUES ('delete', old.rowid, old.body);
        INSERT INTO comment_fts(rowid, body) VALUES (new.rowid, new.body); END;
```

The migration is additive — no changes to v1 tables.

## Dependencies

- libSQL (already used) for storage + FTS5 search
- SHA-256 (Apple `CryptoKit` on Swift; already-vendored crate `sha2` on Rust side via existing `crispyvibes-persistence` deps; if not present we add it)
- Existing JSON-RPC plumbing in `AgentConversationStore`, `CLISocketServer`, `CLICommandRouter`

## Platform Considerations

- macOS-only; uses Foundation `Process` for the helper (existing pattern)
- Per-pane panel uses SwiftUI `HSplitView`-style layout via a custom resizable divider for fine control over snapping and persistence

## Performance Constraints

- Anchor relocation < 100 ms for files ≤ 10,000 lines (R05 / NFR PERF-3) — the relocator scans only ±50 lines + context windows, O(N) over comments, O(window) per comment
- UI updates from CLI writes < 500 ms (R11) — `@Published` round-trip on the main actor

## Migration / Rollout Notes

- Schema migration v2 runs automatically on next launch
- Existing vibespaces simply gain an empty comments table — no data backfill
- No feature flag; ships directly per planning doc

## UI Architecture — UX Layer

### Inline Composer (JS-based)

For WKWebView surfaces (markdown preview, HTML preview, browser windows), the "Add Comment" button expands into an inline composer rendered entirely in JavaScript within the page:

```
User selects text
  → JS `repositionButton()` shows "💬 Add Comment" at selection rect
  → User clicks button
  → Button hides, inline composer div appears at same position
  → Composer contains: anchor text preview, textarea, Cancel/Comment buttons
  → User types + submits (click or ⌘↩)
  → JS posts to `window.webkit.messageHandlers.commentsRichRequestAdd`
    with `{ ...anchorFields, body: "user's comment" }`
  → Native handler detects `body` field → calls store.add() directly
  → No panel open needed
```

The composer is styled with `!important` inline styles and `all: initial` to resist host page CSS (same defensive pattern as the element picker).

For code-mode (NSTextView), the context menu "Add Comment to Selection" posts a notification that opens the panel composer — no JS layer available.

### Panel Thread Layout

`CommentThreadView` renders each thread as a card:

```
┌─────────────────────────────────────────┐
│ ┃ L42                                   │  ← Anchor context (accent left border)
│ ┃ guard let config = self.cfg           │
│                                         │
│ [●] Alice · 2h ago                      │  ← 20px avatar + header
│ Should we throw here?                   │  ← Body (13px)
│                                         │
│ [●] Bob · 30m ago                       │  ← Reply
│ Agreed, silent returns hide bugs.       │
│                                         │
│ [Reply] [✓ Resolve] ··········· [🗑]    │  ← Always-visible action pills
└─────────────────────────────────────────┘
```

Action pills use `ActionPill` — a custom button with:
- Hover: tinted background (10% of button color)
- Press: darker background (18%) + scale-down (0.94×)
- Animated transitions (120ms hover, 80ms press)

Same-author grouping: consecutive messages from the same author within 5 minutes hide the avatar/name row and use 2px vertical gap.

### Panel Resize

`FileContentWithCommentsPanel` and `BrowserContentWithCommentsPanel` include a 6px drag handle between the editor and panel. The handle:
- Shows `NSCursor.resizeLeftRight` on hover
- Updates `panel.widthFraction` on drag (clamped to 0.20–0.50)
- Uses `DragGesture(minimumDistance: 1)` for immediate response

### Bulk Operations

`CommentsPanelView.bulkActionsRow` provides two menus:
- **Copy**: formats threads as markdown via `copyToClipboard(threads:)`, writes to `NSPasteboard.general`
- **Delete**: iterates threads and calls `panel.deleteThread(_:store:)` for each

Copy format differentiates by `surfaceKind`:
- File: `## #N L{line}` + blockquoted anchor text
- Browser: `## #N {url}` + `Selector: \`{css}\`` + blockquoted text

