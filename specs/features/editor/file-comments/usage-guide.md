---
title: "File Comments"
feature: "F049"
domain: "editor"
audience: "user"
version: "1.0"
sidebar:
  label: "File Comments"
  order: 9
---

# File Comments

Crispy lets you attach comments to specific lines or character ranges in any file. Comments live with the vibespace, support replies, can be resolved, and are accessible to AI agents through the `crispy` CLI for code-review workflows.

## Overview

Comments are anchored to a character range in a file. They survive most edits — when you insert lines or rename code, the anchor relocates automatically. If the anchored text is replaced beyond recognition, the comment is marked **stale** so you can decide what to do with it.

Comments live in a side panel docked to the right of each file viewer pane. Each pane has its own panel state, so you can have one open in a split with another collapsed.

## Getting Started

1. Open a file in the content viewer.
2. Select the lines or characters you want to comment on.
3. Press **⌃⇧C** or click the comment button in the editor toolbar.
4. The comments panel opens on the right with a composer focused on your selection. Type your comment and submit.

A blue dot appears in the gutter at the start of the comment range, and a subtle highlight underlines the anchored text.

## Workflows

### Replying

Click a comment thread in the panel and type in the reply box at the bottom. Replies thread inline beneath the original.

### Resolving

Click the **Resolve** button on the thread header. Resolved threads disappear from the active list — you can show them again from the panel filter (**Active / Resolved / Stale / All**).

### Deleting

Click the trash icon. If the thread has replies, you'll be asked to confirm — deletion cascades through the entire reply chain.

### Editing

Click the edit (pencil) icon on a comment you authored. Submit to save. Edited comments show an "edited" badge with the latest update time.

### Stale comments

If you change the anchored text enough that Crispy can't relocate it, the comment is shown with a dashed underline at its last-known position and a warning icon in the panel. The original anchor text is preserved so you can read what the comment referred to. You can resolve, edit, or delete it.

### Cross-file view

Choose **View ▸ All Comments in Vibespace** (**⌃⇧⌘C**) to open the workspace-wide list. Comments are grouped by file. Click any comment to jump to it.

## Working with Agents

Agents (Claude, ChatGPT, etc.) running in a Crispy terminal can interact with comments through the `crispy` CLI:

```bash
# List all comments in a file
crispy comments list --file src/foo.swift

# Add a comment
crispy comments add --file src/foo.swift --line 42 --comment "consider using a guard here"

# Reply to an existing thread
crispy comments reply --id <comment-id> --comment "fixed in commit abc123"

# Resolve when done
crispy comments resolve --id <comment-id>
```

Comments authored by agents show an agent badge so you can tell at a glance which feedback came from a human review and which came from an AI pass.

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Add comment to selection | **⌃⇧C** |
| Toggle comments panel for active pane | **⌥⌘C** |
| Open cross-file comments view | **⌃⇧⌘C** |
| Jump to next comment in file | **⌘]** |
| Jump to previous comment in file | **⌘[** |
| Focus comment composer | **⌘↩** (when panel focused) |
| Resolve current thread | **⌘R** (when thread focused) |

## Settings / Configuration

The comments panel remembers its open state and width per pane, persisted with the vibespace layout. There is no global "comments off" setting — the panel is hidden by default and only appears when you toggle it for a pane.

## Troubleshooting

**The panel won't open.** Make sure the active pane has a file open (not a terminal or browser tab). The panel only attaches to file content.

**My comment shows as stale.** The anchored text was changed enough that Crispy couldn't find it again. The original text is preserved in the comment metadata. You can read what it referred to, then resolve or delete it.

**Comments don't appear after the agent added one.** The UI updates within half a second of the CLI write. If you don't see it, try toggling the panel closed and open. If still missing, check `crispy comments list --file <path>` to confirm the comment is stored — if it is, the UI watch path is the issue.

## Known Limitations

- Anchor relocation searches ±50 lines from the original position. If the anchored text moved further, the comment goes stale.
- No real-time multi-cursor collaboration. Comments are persistent but the app is single-user.
- Cross-origin iframes inside browser pages cannot be commented on (browser same-origin policy).

## Inline Commenting (Quick Comments)

In markdown preview and browser windows, clicking "💬 Add Comment" expands into a small inline composer right at the selection — no panel needed. Type your comment, press **⌘↩** to submit (or click "Comment"), and it's saved immediately. Press **Escape** or click "Cancel" to dismiss.

The inline composer shows a preview of the selected text so you can confirm you're commenting on the right thing. If you need the full panel (to browse threads, search, or reply), click the sidebar icon in the composer to expand.

In code mode (source view), right-click and choose "Add Comment to Selection" — this opens the panel composer since the code editor doesn't have an inline JS layer.

## Panel Layout

The comments panel shows each thread as a compact card:

- **Anchor context** at the top: the code or text you commented on, with a colored left border (blue = active, orange = stale). File comments show the line number; browser comments show the quoted text.
- **Author + timestamp** on one line (e.g., "You · 2h ago")
- **Comment body** below
- **Action buttons** always visible at the bottom: Reply (purple), Resolve (green), Delete (red). Buttons highlight on hover and compress slightly on click for clear feedback.

Replies appear below the root comment. If the same person posts multiple replies within 5 minutes, they're grouped (no repeated avatar/name).

## Resizing the Panel

Drag the left edge of the panel to resize it. The panel width ranges from 20% to 50% of the editor pane. Your preferred width is remembered per pane.

## Bulk Operations

At the top of the panel, two menus provide bulk actions:

**Copy** (clipboard icon):
- **Copy All** — copies every thread to your clipboard as formatted markdown
- **Copy Unresolved** — copies only active and stale threads

**Delete** (trash icon):
- **Delete Resolved** — removes all resolved threads at once
- **Delete All** — removes everything (use with caution)

### Copied Format

The copy format is designed for pasting into AI agent conversations:

```
# Comments: /path/to/file.swift

## #1 L42
> guard let config = self.cfg else { return }
- Comment: Should we throw here instead of silently returning?
  - Reply: Agreed, silent returns hide bugs.

## #2 L89 [STALE]
> let timeout = 30
- Comment: This timeout seems too aggressive
```

For browser comments, the format includes the URL and CSS selector:

```
## #1 https://example.com/settings
Selector: `#main > section:nth-of-type(2) > p`
> Enable notifications for all devices
- Comment: This copy is confusing for new users
```

## Commenting on HTML Previews

When you preview an HTML file (`.html` opened in the editor), comments anchor to **DOM elements** rather than source lines. Selecting text in the rendered preview shows the same "💬 Add Comment" button. The comment stores a CSS-selector path to the containing element plus the selected text — when the file re-renders, the comment finds its target via `querySelector`, falling back to text matching if the structure changed.

You can mix line-anchored comments (in source mode) and DOM-anchored comments (in rich preview) on the same HTML file. They appear together in the comments panel and the workspace-wide "All Comments" window.

## Commenting on Browser Windows

Browser windows opened via `crispy browser open` (or the dock) support the same commenting flow. Selecting text on any page shows the floating "Add Comment" button. Anchors use the canonical URL of the page plus a CSS-selector path inside the page's main frame.

The toolbar gains a `quote.bubble` toggle (next to the element-picker button) that opens the comments panel for the active page. Threads are scoped to the canonical URL — comments on `/dashboard` don't show on `/settings`.

URLs are canonicalized for storage stability:
- Tracking parameters (`utm_*`, `fbclid`, `gclid`, etc.) and sensitive query params (`token`, `session`, etc.) are stripped before persistence.
- Fragment identifiers (`#section`) are dropped.
- Default ports (`:80` / `:443`) are removed.
- Scheme and host are lowercased.

When the page navigates (link click, SPA route change, refresh), the comments panel re-queries against the new canonical URL — comments that don't match the active page are hidden until you navigate back.

In the workspace-wide "All Comments" window, browser comments live under a separate **Browsers** section. Clicking a browser thread navigates the most recently active browser pane to that URL and scrolls to the anchored element.
