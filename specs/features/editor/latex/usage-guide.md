---
title: "LaTeX Editor"
feature: "F055"
domain: "editor"
audience: "user"
version: "1.0"
sidebar:
  label: "LaTeX"
  order: 11
---

# LaTeX Editor

## Overview

Crispy opens LaTeX documents (`.tex`, `.latex`, `.ltx`) in a dedicated editor with two ways to work:

- **Edit** — a live, rendered view where your headings, paragraphs, and lists look like the finished document and your math is typeset by [KaTeX](https://katex.org). You type prose directly and click any equation to edit it visually. This is the default when you open a file.
- **Source** — the raw LaTeX in Crispy's code editor, with a math-symbol palette for inserting snippets at the cursor.

You can switch between them at any time with the mode toggle in the editor's toolbar — Crispy remembers your choice per document. Everything renders **locally and offline**: no LaTeX installation, no internet, no account needed. Crispy renders the math for preview; it does not run a full LaTeX compiler, so your `.tex` file stays the source of truth and Crispy preserves the parts it doesn't render (your preamble, packages, comments, and any environments it doesn't model) exactly as you wrote them.

Crispy also renders inline math in **Markdown** documents: `$E = mc^2$` and `$$…$$` blocks now typeset automatically in the markdown rich view and save back to their original `$` / `$$` form.

## Getting Started

1. Open any `.tex` / `.latex` / `.ltx` file from the file explorer (or create one and start typing).
2. It opens in **Edit** mode with the body rendered. Your `\documentclass`, packages, and title block are kept but the editing surface shows the readable document.
3. Type to edit prose. Click an equation to edit it. Use the **mode toggle** to drop into **Source** when you want the raw LaTeX.
4. Changes autosave — there is no Save button.

## Workflows

### Edit prose, headings, and lists
In **Edit** mode, click into a paragraph and type. Press Enter for a new paragraph. Use the toolbar for **bold**, *italic*, `code`, headings, and bullet/numbered lists — they apply to your selection and are written back as the matching LaTeX commands (`\textbf{…}`, `\section{…}`, `\begin{itemize}…`, and so on).

### Edit an equation visually
Click any equation (inline or a displayed block). A popup opens with:
- a **live preview** that updates as you build the math,
- a grid of **symbol and template buttons** (fractions, roots, sums, integrals, Greek letters, matrices, …) so you can build math without remembering the LaTeX, and
- the raw **TeX** in a text box for when you'd rather type it.

Click **Done** (or click away) to commit, **Cancel** (or Escape) to discard. The equation re-renders in place.

### Insert math from the palette
The toolbar's math palette inserts common templates and symbols. In **Source** mode the LaTeX snippet drops in at your cursor (with `{}` placeholders where the next value goes). In **Edit** mode the snippet is inserted and rendered immediately — a bare fragment becomes inline `$…$`, a matrix/environment becomes a displayed block.

### Work in raw LaTeX
Switch to **Source** for full control: the complete `.tex`, including the preamble and any package or environment Crispy doesn't render visually. Anything Crispy can't show in Edit mode is still right here, untouched.

### Math in Markdown
In a `.md` file, write `$inline$` or a `$$displayed$$` block. In the markdown rich view they typeset via KaTeX; when you save, they're written back as the same `$…$` / `$$…$$` you wrote.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Commit the equation popup | `⌘↩` (or click away) |
| Cancel the equation popup | `Esc` |
| New paragraph (Edit mode) | `↩` |

Standard editor shortcuts (undo/redo, find/replace, selection) work as usual in Source mode. Crispy adds no other LaTeX-specific global shortcuts in this version.

## Settings / Configuration

- **Mode (Edit / Source):** chosen with the toolbar toggle; remembered per document. New documents open in Edit.
- **Appearance:** the Edit-mode surface follows the app's light/dark theme automatically — nothing to configure.
- There are no other LaTeX-specific settings.

## Troubleshooting

- **An equation shows red text instead of math:** the LaTeX in that equation has a syntax error. Click it to open the popup and fix the TeX; the preview shows where it breaks. (Crispy never stops rendering the rest of the document over one bad equation.)
- **Something in my document shows as a grey read-only block:** that's an environment Crispy doesn't render visually (e.g. a TikZ picture or a custom environment). It's preserved exactly — switch to **Source** to edit it.
- **"The LaTeX preview runtime is unavailable":** the app build is missing its bundled KaTeX assets — rebuild/reinstall the app.
- **My preamble/packages seem to vanish in Edit mode:** they're intentionally hidden (they don't render as visible content) but fully preserved. Switch to **Source** to see and edit them.
- **Markdown math isn't rendering:** make sure you're in the markdown rich (rendered) view, not the markdown source view, and that the math is wrapped in `$…$` or `$$…$$`.

## Known Limitations

- **Preview, not compilation** — Crispy renders math and common document structure with KaTeX; it does not run a full LaTeX engine, so packages, custom macros, and complex layout are preserved but not visually rendered.
- **Modeled subset** — only prose, sections, `itemize`/`enumerate` lists, inline/display math, and `\maketitle` are editable in place in Edit mode. Tables, figures, TikZ, and custom environments appear as preserved read-only blocks; edit them in Source mode.
- **Single-user, offline** — there is no collaboration or cloud rendering (by design).
- **No command-line interface** for LaTeX documents yet.
