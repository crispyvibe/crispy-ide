---
title: "Document Render Previews"
feature: "F058"
domain: "editor"
audience: "user"
version: "1.1"
sidebar:
  label: "Render Previews"
  order: 12
---

# Document Render Previews

## Overview

Crispy gives three more document formats a live, rendered preview right next to their source — each rendered **locally and offline** by a command-line tool you install once. Every one of these is a **render-only** preview: you edit the text in the **Source** tab, and the **Preview** shows the result.

| Format | Extensions | Rendered with | Output | Install |
|--------|-----------|---------------|--------|---------|
| **Typst** | `.typ` | `typst compile` | PDF | `brew install typst` (~v0.15) |
| **AsciiDoc** | `.adoc`, `.asciidoc`, `.asc` | `asciidoctor` | HTML | `brew install asciidoctor` (~v2.0) |
| **Graphviz** | `.dot`, `.gv` | `dot -Tpdf` | PDF | `brew install graphviz` (~v15) |

Each file opens with a **Preview / Source** toggle in the editor toolbar. **Preview** shows the rendered output and updates as you edit; **Source** is the editable text. You edit in Source; the preview is read-only.

There's **no account, no cloud, and no internet** involved — Crispy just runs the command-line tool on your machine and shows you the result. Renders are debounced (rapid edits batch into a single re-render) and bounded by a timeout, so a long or runaway render won't hang the app.

## Getting Started

1. Install the tool for the format you want to preview (once):
   - **Typst:** `brew install typst`
   - **AsciiDoc:** `brew install asciidoctor` (or `gem install asciidoctor`)
   - **Graphviz:** `brew install graphviz`
2. Open a `.typ`, `.adoc`/`.asciidoc`/`.asc`, or `.dot`/`.gv` file from the file explorer.
3. It opens in **Preview** mode and renders.
4. Use the toolbar's **Preview / Source** toggle to switch to the editable text. Crispy remembers your choice per file.
5. Edits autosave — there is no Save button.

Crispy looks for these tools in the standard install locations (`/opt/homebrew/bin`, `/usr/local/bin`, `/Library/TeX/texbin`, `/usr/bin`), so a Homebrew install is found automatically — there's nothing to configure. Crispy was validated against **typst 0.15.0**, **asciidoctor 2.0.26**, and **graphviz / dot 15.0.0**, but recent releases work.

## Document types

### Typst (`.typ`)

A modern typesetting system, fast and friendly for documents and reports. Crispy runs `typst compile` and shows the resulting **PDF**. Edit the source and the PDF re-renders; your current page and scroll position are preserved across re-renders so the view doesn't jump.

- Needs the `typst` binary — `brew install typst` (validated ~v0.15).

### AsciiDoc (`.adoc`, `.asciidoc`, `.asc`)

A rich plain-text documentation format. Crispy runs `asciidoctor` and shows the formatted **HTML** with AsciiDoctor's default styling (the standalone document with its embedded stylesheet). Edit the source and the HTML re-renders.

- Needs the `asciidoctor` binary — `brew install asciidoctor` (validated ~v2.0).

### Graphviz (`.dot`, `.gv`)

The DOT graph-description language for diagrams (flowcharts, dependency graphs, state machines). Crispy runs `dot -Tpdf` and shows the rendered graph as a **PDF**. Edit the source and the diagram re-renders; page and scroll position are preserved.

- Needs the `dot` binary from Graphviz — `brew install graphviz` (validated ~v15).

## Workflows

### Edit and watch the preview

Switch to **Source**, edit the document text, and the **Preview** updates shortly after you stop typing (rapid edits are batched into a single re-render). For the PDF previews (Typst, Graphviz) your current page and scroll position are kept across re-renders, so the view doesn't jump.

### Preview a Typst document

Open a `.typ` file. Crispy runs `typst compile` and shows the resulting PDF. Edit the source and the PDF re-renders.

### Preview an AsciiDoc document

Open an `.adoc`/`.asciidoc`/`.asc` file. Crispy runs `asciidoctor` and shows the formatted HTML (with AsciiDoctor's default styling).

### Preview a Graphviz diagram

Open a `.dot` or `.gv` file. Crispy runs `dot -Tpdf` and shows the rendered graph as a PDF.

## When a tool is installed vs not installed

- **Installed:** the file opens in **Preview** and renders. Edits in **Source** re-render the preview automatically.
- **Not installed:** the **preview is unavailable** — instead of a rendered page you'll see a message indicating the required tool wasn't found. Install the matching tool (see the table above) and reopen the file. There's no guided installer for these three formats; the message points you at the missing command.

## Keyboard Shortcuts

This feature adds no format-specific global shortcuts. Standard editor shortcuts (undo/redo, find/replace, selection) work as usual in the **Source** tab.

## Settings / Configuration

- **Mode (Preview / Source):** chosen with the toolbar toggle; remembered per document. New documents open in **Preview**.
- **Tools:** Crispy looks for `typst`, `asciidoctor`, and `dot` in the standard install locations (`/opt/homebrew/bin`, `/usr/local/bin`, `/Library/TeX/texbin`, `/usr/bin`). There's nothing to configure — install the tool and reopen the file.
- There are no other settings for these formats.

## Troubleshooting

- **The preview shows a "not found" message:** the required command-line tool isn't installed (or isn't in a standard location). Install it (see Getting Started) and reopen the file.
- **The preview shows "Compilation failed":** there's an error in your document — the message includes the tool's error output so you can find it. Fix the source and the preview re-renders. (For the PDF previews — Typst and Graphviz — if you already had a good render, Crispy keeps showing it with a small "compilation failed" banner instead of clearing the page.)
- **A long render seems stuck:** Crispy stops a compile that runs too long and re-runs it on your next edit; it won't hang the app.
- **My edits aren't showing in the preview:** make sure you're editing in **Source** and viewing **Preview** — the preview itself is read-only.

## Known Limitations

- **Requires local tools** — Typst, AsciiDoc, and Graphviz previews each need the corresponding CLI installed on your Mac. Crispy doesn't bundle a renderer.
- **Render-only previews** — unlike Crispy's Markdown and LaTeX editors, these previews **can't be edited in place**: there's no click-to-edit and no commenting on the preview. Edit the text in **Source**.
- **No dedicated install prompt** — if a tool is missing you'll see a "not found" / compile-failure message rather than a guided installer (unlike the LaTeX PDF tab, which has an actionable install screen).
- **Offline and single-user** — rendering is local; there's no cloud rendering or collaboration (by design).

## Change History

- **1.1** — Added per-format detail (Typst / AsciiDoc / Graphviz with extensions, tools, output, and validated versions), the installed-vs-not-installed experience, and the offline/debounced/bounded render model.
- **1.0** — Initial Typst, Graphviz, and AsciiDoc render previews.
