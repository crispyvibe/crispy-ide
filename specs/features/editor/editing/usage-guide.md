---
title: Editing
domain: Editor
feature: F007
audience: user
version: "1.0"
sidebar:
  label: Editing
  order: 2
---

# F007 Editing — Usage Guide

CrispyVibes provides code editing with syntax highlighting, autosave, and find & replace across a wide range of languages and file types.

> **Terminology:** A *VibeSpace* is Crispy's name for a vibespace. *VibeCast* is a tool for sending commands to terminals. *ACP Pane* is a chat window for AI coding assistants.

## Getting Started

Open any code file from the sidebar. CrispyVibes automatically detects the language and applies syntax highlighting.

## Code Editing

Open any supported code or config file and it loads in a monospaced editor with language-aware syntax highlighting. The editor detects the language from the file extension automatically.

### Supported Languages

CrispyVibes highlights 20+ language families:

| Category | Languages |
|----------|-----------|
| Systems | Swift, C, C++, Objective-C, Rust, Go |
| JVM | Java, Kotlin |
| Web | JavaScript, TypeScript, JSX, TSX, HTML, CSS, Vue, Svelte |
| Scripting | Python, Ruby, R, Shell |
| Data/Config | JSON, JSONC, YAML, TOML, SQL |

### Syntax Highlighting Limits

Files over 180,000 characters open without syntax highlighting to keep the editor responsive. You can still edit and save them as plain text.

The editor enforces minimum contrast ratios on syntax tokens so code stays readable across themes.

## Plain Text Files

Recognized plain-text extensions (`.txt`, `.log`, `.env`, `.cfg`, `.ini`, `.conf`) open in the text editor with full save and autosave support.

If CrispyVibes doesn't recognize a file type but can read it as text, it falls back to plain-text editing. Files that can't be read at all show an "unavailable" message.

## JSON Editor

`.json` and `.jsonc` files open in a built-in JSON editor with formatting and validation features.

## R Files

`.r` and `.rmd` files route to a dedicated R editor mode with language-specific rendering.

## Saving

- **Autosave** — edits are saved automatically after about 0.45 seconds of inactivity. An "Unsaved" badge appears in the header whenever you have changes that haven't been written to disk yet.
- **Manual save** — press `Cmd+S` to save immediately.
- If a save fails, an error alert appears so you can retry.

If a file changes outside CrispyVibes while you are reading or editing it, CrispyVibes refreshes the open document in place. In source editors, your current selection and scroll position are kept when the same file stays active.

## Find & Replace

### In Code and Plain Text

Press `Cmd+F` to open the find bar. Search matches are highlighted in the editor. You can navigate between matches and use replace or replace-all.

### In Markdown and HTML (Rich Text)

Find and replace is also available for editable markdown and HTML documents:

- Matching is case-insensitive.
- Use **Next** to cycle through matches — the status shows "N of M".
- **Replace Next** replaces the current match and advances.
- **Replace All** replaces every match and reports the count.
- Press **Done** or `Escape` to close the find bar.

Find and replace is only available for editable text documents. Attempting it on images, PDFs, or unsupported files shows an informational message.

## Rich / Source Toggle

Markdown and HTML documents support switching between a rendered rich view and a raw source view. Your content is preserved when you toggle. In source mode, the formatting toolbar is replaced by a label indicating the source type (e.g., "Markdown Source" or "HTML Source").

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘S | Save |
| ⌘Z | Undo |
| ⌘⇧Z | Redo |
| ⌘F | Find |
| ⌘⇧H | Replace |

## Related Guides

- [Content Viewer](../content-viewer/usage-guide.md)
- [Markdown](../markdown/usage-guide.md)
- [Previews](../previews/usage-guide.md)
