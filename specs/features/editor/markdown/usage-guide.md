---
title: "Markdown Editor"
feature: "F008"
domain: "editor"
audience: "user"
version: "1.0"
sidebar:
  label: "Markdown"
  order: 1
---

# Markdown Editor

## Overview

The Markdown Editor provides a rich editing experience for `.md`, `.markdown`, and `.mdx` files. It renders markdown in an editable WYSIWYG view powered by WKWebView, with a formatting toolbar, guided authoring for links/images/tables, find and replace, and a source view toggle. Theme tokens are injected as CSS custom properties so rendered content matches your active theme.

## Getting Started

1. Open any `.md`, `.markdown`, or `.mdx` file from the file explorer.
2. The file opens in the rendered rich editing mode by default.
3. Use the formatting toolbar to apply bold, italic, headings, and other formatting.
4. Save with ⌘S — edits are converted back to canonical markdown via Turndown.

## Workflows

### Editing in Rich Mode

1. Open a markdown file — it renders in the WYSIWYG editor.
2. Click anywhere in the rendered content to begin editing.
3. Use the formatting toolbar or standard keyboard shortcuts for formatting.
4. Code blocks are automatically syntax-highlighted.
5. Save (⌘S) to persist changes as canonical markdown.

### Switching to Source View

1. Click the view mode toggle in the editor toolbar.
2. The editor switches to raw markdown source view.
3. Edit the raw markdown directly.
4. Toggle back to rich view — content state is preserved across toggles.

### Inserting or Editing a Link

1. Select the text you want to linkify.
2. Click the **Link** button in the formatting toolbar.
3. Enter a section (`#installation`), relative file (`../guide.md#setup`), file URL, HTTP(S) URL, or email destination.
4. Confirm to wrap the selection as Markdown link syntax.
5. If no text is selected, a notification appears: "Select text first to add a link."
6. To edit an existing link, right-click it (or open its web-link popover), choose **Edit**, update the prefilled destination, and confirm.

### Navigating Links in Rich Mode

- Click `#section` links to jump immediately to the matching heading. The destination briefly highlights; press **⌘[** to return to the previous document position.
- Click a relative Markdown link such as `../guide.md#setup` to open that file in the current Crispy editor group and jump to its heading after rendering.
- Click another local file link to open it in Crispy. Right-click to choose the system default app instead.
- Click an HTTP(S) link to show an anchored action popover when your preference is **Ask Each Time**. Choose **Open in Crispy** or **Default Browser**.
- Right-click any link for the complete action set. Web links offer open destinations plus **Edit**, **Copy**, and **Remove**; Remove keeps the visible link text.
- **Option-click** a link when you want to place the caret and edit its visible text without navigating.
- Focus a link with the keyboard and press **Enter** to activate it. Press **Escape** to dismiss the action popover.

Crispy blocks executable/unknown schemes, protocol-relative links, web URLs with embedded credentials, malformed destinations, and unavailable local files. Source mode always treats links as editable Markdown text and does not activate them.

### Inserting an Image

1. Click the **Image** button in the formatting toolbar.
2. A searchable image picker opens with case-insensitive filename filtering.
3. Search for and select the desired image.
4. Confirm insertion — the editor inserts `![alt](path)` with a resolved relative path.
5. The alt text defaults to the filename and can be edited before insertion.

### Inserting a Table

1. Click the **Table** button in the formatting toolbar.
2. A table-size prompt appears with row and column inputs (default: 3×3).
3. Enter desired dimensions and confirm.
4. A markdown table is inserted with header row, separator row, and body rows.

### Using Find and Replace

1. Press **⌘F** to open the find and replace bar.
2. Type your search query — matches are highlighted in the active view.
3. Use the replace field to substitute matches.
4. Works in both rich view and source view modes.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Save | ⌘S |
| Find | ⌘F |
| Replace | ⌘⇧H |
| Bold | ⌘B |
| Italic | ⌘I |

## Settings

- **Theme**: The active application theme is injected into the markdown renderer as ~50 CSS custom properties. Changing themes updates the rendered appearance immediately.
- **Font Size**: Controlled via the global font size shortcuts (⌘+, ⌘-, ⌘0).
- **Markdown Web Links**: In General settings, choose **Ask Each Time**, **Crispy Browser**, or **Default Browser**. This affects normal HTTP(S) clicks; right-click always exposes both destinations.

## Tips

- MDX files (`.mdx`) open in the same markdown editor with identical behavior.
- Content sync uses Turndown to convert HTML back to markdown — formatting is preserved as canonical markdown syntax.
- Tables remain GFM markdown pipe tables after rich-mode edits, including column alignment and escaped pipe characters.
- Ordinary currency such as `$8M`, `$2M`, and `$16,655.00` remains editable text rather than math. For an equation that intentionally begins with a number, use `\\(…\\)` in Markdown source; Crispy preserves that explicit delimiter form when saving so it remains math when reopened.
- The editor automatically recovers from WKWebView crashes by re-rendering content with no data loss.
- Code blocks within markdown receive syntax highlighting based on the specified language fence.
- The formatting toolbar provides: Bold, Italic, Headings (H1–H6), Ordered List, Unordered List, Blockquote, Code Block, and Horizontal Rule.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Editor shows blank content | The WKWebView may have crashed. The editor should auto-recover. If not, close and reopen the file. |
| Link button does nothing | Ensure text is selected before clicking Link. The editor requires a selection to create a link. |
| Theme not applying | Close and reopen the file to force theme token re-injection. |
| Table dimensions rejected | Ensure row and column values are valid positive integers. |
| Table changed to HTML | Reopen the file after updating Crispy. Rich-mode table edits are stored as GFM markdown instead of HTML. |
| Source view out of sync | Toggle back to rich view — content state is preserved. If issues persist, save and reopen. |
| A section link says the section was not found | Ensure the fragment matches the generated lowercase heading slug; spaces become hyphens and duplicate headings use `-2`, `-3`, and later suffixes. |
| A web link is blocked | Use a complete HTTP(S) address without embedded username/password credentials. Executable and unknown schemes are intentionally rejected. |
| A relative file link does not open | Verify the target exists relative to the current Markdown file and points to a file rather than a directory. |
| Clicking a link navigates when I want to edit | Hold Option while clicking, or right-click and choose **Edit**. |
