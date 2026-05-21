---
title: "Office Document Preview"
feature: "F045"
domain: "editor"
audience: "user"
version: "1.0"
sidebar:
  label: "Office Preview"
  order: 5
---

# Office Document Preview

## Overview

Crispy can render Microsoft Office documents — Word, PowerPoint, and Excel — directly in the editor area. Documents open as read-only previews in a tab, just like any other file.

## Getting Started

No setup is required. Office document preview uses macOS built-in Quick Look, which is available on all supported systems.

## Workflows

### Opening a Document

1. In the **File Explorer**, navigate to a `.docx`, `.pptx`, or `.xlsx` file.
2. Click the file to open it in a new tab.
3. The document renders inline as a read-only preview.

You can also open documents from the **Shelf** or by dragging them into the editor area.

### Supported Formats

| Format | Extensions |
|--------|-----------|
| Word | `.docx`, `.doc` |
| PowerPoint | `.pptx`, `.ppt` |
| Excel | `.xlsx`, `.xls` |

### Handling Unsupported Files

If a document cannot be rendered (corrupt or unsupported variant), Crispy shows an error message with two options:

- **Reveal in Finder** — opens the containing folder
- **Open with Default App** — launches the file in its associated application

## Keyboard Shortcuts

No feature-specific shortcuts. Standard tab navigation applies:

| Action | Shortcut |
|--------|----------|
| Close tab | `⌘W` |
| Next tab | `⌃⇥` |
| Previous tab | `⌃⇧⇥` |

## Settings / Configuration

No configuration is required. The feature activates automatically for supported file types.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Document shows error instead of preview | The file may be corrupt. Try opening it in Microsoft Office or Preview.app to verify. |
| Preview is slow to load | Large files (>50 MB) take longer. A loading indicator is shown during rendering. |
| Formatting looks different from Office | Quick Look rendering may differ slightly from Microsoft Office. For pixel-perfect viewing, open in the native app. |

## Known Limitations

- **Read-only** — editing is not supported. Use Microsoft Office or another editor for changes.
- **Rendering fidelity** — complex animations, transitions, and macros in PowerPoint are not rendered.
- **Embedded media** — audio/video embedded in documents will not play inline.
- **Requires macOS Quick Look** — rendering depends on Apple's built-in document parsers.
