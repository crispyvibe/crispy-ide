# F049 File Comments — Spec

**Domain:** Editor
Status: draft

---

## Overview

File-level commenting system that lets users (and agents via the CLI) attach comments to specific character ranges in any file opened in the content viewer. Comments are persistent per vibespace, support full threading, and survive file edits via fuzzy anchor relocation. The UI surfaces comments as gutter indicators, content highlights, and a per-pane side panel docked inside the file viewer. Agents can read and write comments via the existing `crispy` CLI for code-review workflows.

## Dependencies

- F006 (Content Viewer) — required: comments panel docks inside the content viewer pane
- F007 (Editing) — required: comment anchoring needs editor coordinates and selection
- F044 (Agent CLI) — required: `comments.*` commands route through the existing JSON-RPC over Unix socket
- F040 (Agent Conversation Store) — required: comments share the same encrypted libSQL helper subprocess

---

## Requirements

### F049-R01: Supported File Types

Comments MUST be supported on all files openable in the content viewer (text, markdown, code, config). For non-text content viewers (images, PDF, office documents, HTML preview), only file-level comments are supported (see F049-R14).

### F049-R02: Comment Storage

Comments MUST be stored in the existing encrypted libSQL store (`conversations.db`), exposed via the Rust persistence helper. Comment rows are scoped by `vibespace_id` so the UI and CLI access the same data through a single Rust layer.

### F049-R03: CLI Operations

The CLI MUST expose:

- `comments.add` — add a comment at a file anchor
- `comments.list` — list comments for a file (filterable by status)
- `comments.reply` — append a reply to a thread
- `comments.resolve` — mark a thread resolved
- `comments.delete` — delete a comment (cascades replies — see R10)
- `comments.update` — update comment content

### F049-R04: Threading

Comments MUST support nested replies via a `parent_comment_id` reference. Top-level comments have a null parent. Maximum thread depth is 50 (R17).

### F049-R05: Comment Anchoring

Comments MUST be anchored using `(start_line, start_column, end_line, end_column)` plus a content snapshot containing:

- SHA-256 hash of the anchored substring (`anchor_hash`)
- The literal anchored text (`anchor_text`, capped at 4 KB)
- A small surrounding context window (`leading_context`, `trailing_context`, 64 chars each)

When the file changes, the system MUST attempt anchor relocation in this order:

1. Hash match at the original line range — accept silently
2. Fuzzy match on `anchor_text` within ±50 lines — accept and update position
3. Wider scan with `leading_context`/`trailing_context` corroboration — accept and update
4. None match — set `is_stale = true` and preserve the last-known position

### F049-R06: Comment Visibility in UI

Comments MUST be visible in the content viewer UI:

- Gutter indicators for lines containing comments
- Comment panel docked to the right edge of the file viewer pane (NOT app-level, NOT workspace sidebar). Per-pane scope: each split pane has its own panel state for its own file.
  - Toggleable (toolbar button + keyboard shortcut)
  - Resizable
- Visual distinction between active, resolved, and stale comments
- Content highlight overlay on the anchored character range:
  - Passive: subtle theme-token underline / background tint
  - Active (selected in panel or gutter clicked): intensified background
  - Stale: dashed underline / faded highlight at last-known position
- Bidirectional linking: clicking a highlight scrolls panel to the thread; clicking a thread scrolls the editor and activates the highlight

The cross-file workspace view (R15) is a separate surface and does NOT replace the per-pane panel.

### F049-R07: Agent Interaction

Agents MUST be able to read all comments on a file, add comments, reply, and resolve via the CLI. Comments authored via the CLI MUST be tagged with the calling agent identity (`author_kind = "agent"`, `author_label` from the calling channel client tag, e.g., `"acpchat.<uuid>"`).

### F049-R08: Comment Metadata

Each comment MUST include:

- `created_at`, `updated_at` (ISO 8601, UTC)
- `resolved_at` (null when unresolved)
- An "edited" indicator surfaced in the UI when `updated_at > created_at`

Full edit history is NOT required.

### F049-R09: Comment Content Format

Comment content MUST support a safe subset of markdown (bold, italic, inline code, fenced code blocks, links, lists). Raw HTML and inline scripts MUST be stripped during rendering. Plain text MUST render correctly without markdown processing.

### F049-R10: Delete Semantics

Comments are hard-deleted (no soft delete or recovery). Deleting a parent comment MUST cascade-delete the entire reply subtree atomically. The UI MUST warn before deleting a thread that has replies.

### F049-R11: CLI/UI Synchronization

When the CLI writes a comment, the app UI MUST reflect the change without manual refresh. The Rust layer MUST broadcast a change event consumed by the Swift UI; UI updates MUST appear within 500ms.

### F049-R12: Concurrency Semantics

The Rust layer MUST serialize writes through a single transaction queue. Conflicting updates to the same comment follow last-write-wins by `updated_at`.

### F049-R13: File Lifecycle Handling

When a file with comments is renamed or moved within the vibespace, comments MUST follow the file (anchor by canonical path; rename detection via the existing file watcher). When a file is deleted, comments MUST be retained as orphaned (file unavailable) and surfaced via the cross-file view (R15) only.

### F049-R14: Supported Anchor Targets

Character-range anchoring (R05) applies only to text-based content viewers. For non-text viewers, comments attach at file level only.

### F049-R15: Cross-File View

The UI MUST provide a workspace-wide comment view showing all comments across the active vibespace. Supports grouping by file, filtering by status, and click-to-navigate.

### F049-R16: Search & Filtering

UI and CLI MUST support filtering by status, file/folder, date range, and full-text content.

### F049-R17: Practical Limits

The system MUST enforce:

- Max 1,000 active comments per file
- Max 10,000 characters per comment
- Max thread depth of 50 levels (replies beyond depth 50 attach to depth 50)

Limit violations surface as structured errors via CLI and a non-blocking notification in the UI.

### F049-R18: Observability Events

The Rust layer MUST emit structured events for `comment.created`, `comment.updated`, `comment.resolved`, `comment.deleted`, `anchor.relocated` (with confidence score), `anchor.stale`, and `limit.exceeded`. Events include comment ID, file path, agent identity (when applicable), and timestamp.

### F049-R19: HTML Preview & Browser Surface Anchoring (v2)

Comments anchored to HTML preview iframes and browser windows MUST use a CSS-selector-based anchor in addition to the line-based anchor:

- The persistence helper stores `dom_selector` (≤1 KB), `dom_text_offset`, `dom_text_length`, and `dom_fingerprint` (SHA-256 of the containing block's `textContent` at capture time) on `comment_anchors`.
- The `comments` table gains a `surface_kind` column (`'file'` or `'browser'`) discriminating the anchor target.
- For browser surfaces, the `file_path` column stores a canonical URL produced by the URL normalizer (lowercased scheme/host, default ports stripped, fragment dropped, tracking + sensitive query params removed).
- Re-anchoring on render uses `document.querySelector(selector)` first; on miss, the relocator falls back to text-fingerprint search using `anchorText` within the surface body. Selectors are bounded to ≤6 ancestor segments and prefer `#id` tokens to break the chain at stable identifiers.

### F049-R20: Comment Surface Bridge Protocol

The app MUST expose a `CommentSurfaceBridge` protocol implemented by every surface (NSTextView code editor, WKWebView markdown/HTML preview, browser-window WKWebView). The protocol contract is `captureSelectionAnchor`, `scrollAndSelect`, `syncDecorations`, and `geometryTick`. Per-pane state (`CommentsPanelStore`) and the cross-file workspace view interact only with the protocol — they never depend on a specific bridge implementation.

### F049-R21: Cross-Surface "All Comments" View

The workspace-wide comments view MUST group threads by surface kind (Files / Browsers) and route navigation correctly:

- Clicking a file row posts `commentsNavigateToThread` with the file path.
- Clicking a browser row posts `commentsNavigateToBrowserURL` with the canonical URL; subscribed browser panes match against their own canonical URL and either scroll-to-anchor (match) or navigate first then scroll (mismatch).

### F049-R22: Inline Comment Composer

When the user clicks "Add Comment" on a selection in rich preview or browser surfaces, the system MUST show an inline text composer at the selection location (not open the side panel). The composer:

- Appears at the same position as the "Add Comment" button
- Shows a preview of the selected/anchored text
- Contains a text field (auto-focused), Cancel and Comment buttons
- Supports ⌘↩ to submit, Escape to cancel
- On submit, persists the comment directly without opening the panel
- Provides an "expand to panel" action for users who want the full panel

For code-mode (NSTextView), the "Add Comment" context menu action opens the panel composer (no inline JS available).

### F049-R23: Anchor Context in Panel

Each thread in the comments panel MUST display the anchored text above the comment body:

- File comments: line number badge + monospace code excerpt (up to 2-3 lines)
- Browser comments: italic quoted text excerpt with the CSS selector
- Visual: accent-colored left border (orange when stale)
- Stale indicator badge ("⚠ modified") when the anchor has drifted
- Clicking the context block navigates to the source location

### F049-R24: Compact Thread Layout

The comments panel MUST use a compact layout optimized for the 280-320px panel width:

- 20px circular avatars with tinted background
- Single-line headers: avatar + author name (semibold) + relative timestamp
- Same-author message grouping: consecutive messages from the same author within 5 minutes collapse (hide avatar/name, minimal gap)
- Always-visible action buttons (Reply, Resolve/Reopen, Delete) with hover highlight and press feedback
- Thread cards with subtle background, no heavy borders
- Resolved threads at reduced opacity

### F049-R25: Bulk Operations

The comments panel MUST provide bulk operations accessible from the panel toolbar:

- **Copy All**: copies all threads to clipboard as formatted markdown
- **Copy Unresolved**: copies only active/stale threads
- **Delete Resolved**: bulk-deletes all resolved threads
- **Delete All**: bulk-deletes all threads for the current file/URL

The copy format MUST be optimized for sharing with AI agents:
- File comments: `## #N L{line}` heading, blockquoted anchor text, threaded replies
- Browser comments: `## #N {url}` heading, CSS selector, blockquoted text, replies
- Replies indented under root comments

### F049-R26: Panel Resize

The comments panel MUST be resizable via a drag handle on its left edge:

- Drag handle shows a resize cursor on hover
- Width clamps between 20% and 50% of the parent pane width
- Width persists per pane across panel open/close cycles

---

## Scenarios

### F049-S01: Add a comment to a code file

Given a file `src/foo.swift` is open in the content viewer
When the user selects characters at lines 10–12 and clicks "Add Comment"
Then a composer appears in the side panel
And on submit, a new top-level thread is created with `anchor_hash`, `anchor_text`, and `(10, c1, 12, c2)`
And a gutter indicator appears at line 10
And the highlighted range shows the passive content highlight

### F049-S02: Reply to a thread

Given an active comment thread is selected in the panel
When the user types a reply and submits
Then the reply is appended with `parent_comment_id` set
And the thread depth increments by one
And the panel scrolls to the new reply

### F049-S03: Resolve a thread

Given an active comment thread
When the user clicks "Resolve"
Then `resolved_at` is set on the root comment
And the thread is filtered out of the active list
And the gutter indicator switches to the resolved style

### F049-S04: Anchor relocation after silent file change

Given a comment anchored at line 10 of `foo.swift`
When the user inserts 5 new lines above line 10 and saves
Then on next render, the anchor relocates to line 15 (fuzzy match on `anchor_text`)
And the gutter indicator follows
And `is_stale` remains false

### F049-S05: Anchor goes stale

Given a comment anchored at line 10
When the user replaces the anchored text with unrelated content (no fuzzy match within ±50 lines or context corroboration)
Then `is_stale` is set to true
And the comment shows the dashed-underline stale style at last-known position
And `anchor.stale` event is emitted

### F049-S06: CLI add reflects in UI

Given the app is running with a vibespace open
When an agent runs `crispy comments add --file foo.swift --line 10 --comment "needs error handling"`
Then within 500ms the gutter and panel update without manual refresh
And the comment shows the agent identity badge

### F049-S07: Cascade delete a thread with replies

Given a thread with 3 replies
When the user clicks "Delete" on the parent
Then a confirmation dialog appears warning about replies
And on confirm, the parent and all replies are deleted in one transaction
And the gutter indicator and highlight disappear

### F049-S08: Open the cross-file view

Given multiple files have comments in the active vibespace
When the user opens the cross-file comments view
Then all comments across all files are listed, grouped by file
And clicking a comment navigates to that file and pane

### F049-S09: Resize and toggle the per-pane panel

Given a file is open in a content viewer pane
When the user toggles the comments panel button
Then the panel slides in from the right edge of the pane
And the editor reflows to make room
And dragging the divider resizes the panel
And the second pane in a split layout has its own independent panel state

### F049-S10: Limit enforcement

Given a file already has 1,000 active comments
When the CLI attempts `comments.add` for that file
Then the call returns `limit_exceeded` with a structured error
And the UI surfaces a non-blocking notification

---

## Acceptance Criteria

- All scenarios above are covered by automated tests (Rust unit + Swift unit + behavioral)
- Anchor relocation completes within 100 ms for files under 10,000 lines (PERF-3)
- All UI elements have accessibility identifiers per A11Y-6
- Gutter, highlight, and panel are operable via keyboard (A11Y-2)
- All user-facing strings live in `AppStrings.Comments`

## Open Questions

None at this stage.

## Change History

- 2026-05-26: Initial spec.
