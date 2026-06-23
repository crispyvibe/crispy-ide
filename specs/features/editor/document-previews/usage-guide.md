---
title: "Document Render Previews"
feature: "F058"
domain: "editor"
audience: "user"
version: "1.0"
sidebar:
  label: "Render Previews"
  order: 12
---

# Document Render Previews

## Overview

Crispy gives three more document formats a live, rendered preview right next to their source — all rendered **locally and offline** by tools you already have installed:

- **Typst** (`.typ`) — rendered to a PDF with `typst`.
- **Graphviz** (`.dot`, `.gv`) — rendered to a PDF with `dot`.
- **AsciiDoc** (`.adoc`, `.asciidoc`, `.asc`) — rendered to formatted HTML with `asciidoctor`.

Each file opens with a **Preview / Source** toggle in the editor toolbar. **Preview** shows the rendered output and updates as you edit; **Source** is the editable text. You edit in Source; the preview is read-only.

There's no account, no cloud, and no internet involved — Crispy just runs the command-line tool on your machine and shows you the result.

## Getting Started

1. Install the tool for the format you want to preview (once):
   - Typst: `brew install typst`
   - Graphviz: `brew install graphviz`
   - AsciiDoc: `brew install asciidoctor` (or `gem install asciidoctor`)
2. Open a `.typ`, `.dot`/`.gv`, or `.adoc`/`.asciidoc`/`.asc` file from the file explorer.
3. It opens in **Preview** mode and renders.
4. Use the toolbar's **Preview / Source** toggle to switch to the editable text. Crispy remembers your choice per file.
5. Edits autosave — there is no Save button.

## Workflows

### Edit and watch the preview
Switch to **Source**, edit the document text, and the **Preview** updates shortly after you stop typing (rapid edits are batched into a single re-render). For PDF previews (Typst, Graphviz) your current page and scroll position are kept across re-renders, so the view doesn't jump.

### Preview a Typst document
Open a `.typ` file. Crispy runs `typst compile` and shows the resulting PDF. Edit the source and the PDF re-renders.

### Preview a Graphviz diagram
Open a `.dot` or `.gv` file. Crispy runs `dot -Tpdf` and shows the rendered graph as a PDF.

### Preview an AsciiDoc document
Open an `.adoc`/`.asciidoc`/`.asc` file. Crispy runs `asciidoctor` and shows the formatted HTML (with AsciiDoctor's default styling).

## Keyboard Shortcuts

This feature adds no format-specific global shortcuts. Standard editor shortcuts (undo/redo, find/replace, selection) work as usual in **Source** mode.

## Settings / Configuration

- **Mode (Preview / Source):** chosen with the toolbar toggle; remembered per document. New documents open in Preview.
- **Tools:** Crispy looks for `typst`, `dot`, and `asciidoctor` in the standard install locations (`/opt/homebrew/bin`, `/usr/local/bin`, `/Library/TeX/texbin`, `/usr/bin`). There's nothing to configure — install the tool and reopen the file.
- There are no other settings for these formats.

## Troubleshooting

- **The preview shows "Compilation failed":** there's an error in your document — the message includes the tool's error output so you can find it. Fix the source and the preview re-renders. (If you already had a good render, Crispy keeps showing it with a small "compilation failed" banner instead of clearing the page.)
- **The preview shows a "not found" message:** the required command-line tool isn't installed (or isn't in a standard location). Install it (see Getting Started) and reopen the file.
- **A long render seems stuck:** Crispy stops a compile that runs too long and re-runs it on your next edit; it won't hang the app.
- **My edits aren't showing in the preview:** make sure you're editing in **Source** and that you're viewing **Preview** — the preview itself is read-only.

## Known Limitations

- **Requires local tools** — Typst, Graphviz, and AsciiDoc previews each need the corresponding CLI installed on your Mac. Crispy doesn't bundle a renderer.
- **Render-only previews** — unlike Crispy's Markdown and LaTeX editors, these previews can't be edited in place; there's no click-to-edit and no commenting on the preview. Edit the text in **Source**.
- **No dedicated install prompt** — if a tool is missing you'll see a compile-failure message rather than a guided installer.
- **Offline and single-user** — rendering is local; there's no cloud rendering or collaboration (by design).
