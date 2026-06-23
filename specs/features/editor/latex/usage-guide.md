---
title: "LaTeX Editor"
feature: "F057"
domain: "editor"
audience: "user"
version: "1.1"
sidebar:
  label: "LaTeX"
  order: 11
---

# LaTeX Editor

## Overview

Crispy opens LaTeX documents (`.tex`, `.latex`, `.ltx`) in a dedicated editor with three ways to work, chosen from the mode toggle in the toolbar:

- **Edit** — a live, rendered view where headings, paragraphs, lists, the abstract, and keywords look like the finished document and your math is typeset by [KaTeX](https://katex.org). You type prose directly and click any equation to edit it visually. This view works **completely offline with no LaTeX installation**.
- **PDF** — the **real, fully compiled document**. If you have a TeX engine installed (BasicTeX or MacTeX), Crispy compiles your `.tex` locally and shows the actual typeset PDF — correct two-column layouts, author blocks, tables, citations, and bibliography. You can **double-click anywhere on the page to edit** the text right there, and **select text to leave a comment**. Everything compiles **on your machine, offline** — no account, no cloud, no internet.
- **Source** — the raw LaTeX in Crispy's code editor, with a math-symbol palette for inserting snippets at the cursor.

When you open a `.tex` file, Crispy picks a smart default: the **PDF** view if it detects a TeX engine on your Mac, otherwise the dependency-free **Edit** view. You can switch modes at any time, and Crispy remembers your choice per document.

Crispy also renders inline math in **Markdown** documents: `$E = mc^2$` and `$$…$$` blocks typeset automatically in the markdown rich view and save back to their original `$` / `$$` form.

## Getting Started

1. Open any `.tex` / `.latex` / `.ltx` file from the file explorer (or create one and start typing).
2. If you have a TeX engine installed, it opens in the **PDF** view with the fully compiled document. Otherwise it opens in **Edit** with the body rendered by KaTeX.
3. Use the **mode toggle** (Edit · Source · PDF) to switch views. Type to edit prose in Edit, click an equation to edit it, double-click the PDF to edit on the page, or drop into **Source** for raw LaTeX.
4. Changes autosave — there is no Save button.

### Install a TeX engine for the PDF view (one time)
The PDF view needs a local LaTeX engine. The lightest option is **BasicTeX** (~100 MB):

```
brew install --cask basictex
```

In the PDF tab's "needs a TeX engine" screen you can copy this command with one click, then press **Recheck** once it's installed — the live PDF appears without reopening the file. You can also click **Get BasicTeX** for the download page, or **Use Edit Tab** to keep working without installing anything. If a document needs an extra package, install it without admin rights with `tlmgr --usermode install <package>`.

## Workflows

### Edit prose, headings, and lists
In **Edit** mode, click into a paragraph and type. Press Enter for a new paragraph. Use the toolbar for **bold**, *italic*, `code`, headings, and bullet/numbered lists — they apply to your selection and are written back as the matching LaTeX commands (`\textbf{…}`, `\section{…}`, `\begin{itemize}…`, and so on). The abstract and keywords are editable too; tables and the reference list show as rendered, read-only blocks (edit them in Source or the PDF view).

### Edit on the page (PDF view)
In the **PDF** view, **double-click** any text in the rendered document. A small editor opens right where you clicked, prefilled with that block of source and showing which lines you're editing; the matching area on the page is highlighted. Make your change and press **Save** (or **⌘↩**); the document updates and the page re-compiles. Press **Esc** or **Cancel** to discard. If a change doesn't compile, Crispy keeps showing your last good PDF with a dismissible "compilation failed" banner so you never lose your place.

### Comment on the PDF
In the **PDF** view, **select some text** — a **Comment** button appears just above it. Click it to start a comment anchored to that part of the document. Comments you add on the PDF live in the same place as comments added in the Source or Edit views.

### Edit an equation visually
Click any equation (inline or a displayed block) in the **Edit** view. A popup opens with:
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
| Commit the equation popup / on-page edit | `⌘↩` (or click Save / click away) |
| Cancel the equation popup / on-page edit | `Esc` |
| New paragraph (Edit mode) | `↩` |
| Open the on-page editor (PDF view) | Double-click the text |

Standard editor shortcuts (undo/redo, find/replace, selection) work as usual in Source mode. Crispy adds no other LaTeX-specific global shortcuts in this version.

## Settings / Configuration

- **Mode (Edit / Source / PDF):** chosen with the toolbar toggle; remembered per document. New documents open in PDF when a TeX engine is installed, otherwise in Edit.
- **TeX engine (PDF view):** install BasicTeX or MacTeX locally; nothing to configure in Crispy beyond having it on your Mac. Extra packages install per-user via `tlmgr --usermode install <package>`.
- **Appearance:** the rendered surfaces follow the app's light/dark theme automatically — nothing to configure.
- There are no other LaTeX-specific settings.

## Troubleshooting

- **The PDF tab says it "needs a TeX engine":** install BasicTeX (`brew install --cask basictex`) — copy the command from that screen — then press **Recheck**. Until then, use the **Edit** or **Source** tabs, which need no install.
- **My PDF won't update / shows a "compilation failed" banner:** your latest edit has a LaTeX error. Crispy keeps showing your last good PDF; switch to **Source** (or check the error log shown when there's no previous PDF) to find and fix it, and the page recompiles.
- **References or citations show `??` or `[?]`:** this resolves on its own — Crispy runs LaTeX (and BibTeX) multiple times until cross-references settle. If it persists, there's likely a missing label or bibliography entry; check in **Source**.
- **An equation shows red text instead of math:** the LaTeX in that equation has a syntax error. Click it (Edit view) to open the popup and fix the TeX; the preview shows where it breaks. (Crispy never stops rendering the rest of the document over one bad equation.)
- **Something in my document shows as a grey read-only block (Edit view):** that's an environment Crispy doesn't edit visually (e.g. a TikZ picture or a custom environment). It's preserved exactly — switch to **Source**, or use the **PDF** view to see it fully typeset.
- **"The LaTeX preview runtime is unavailable":** the app build is missing its bundled KaTeX assets — rebuild/reinstall the app.
- **My preamble/packages seem to vanish in Edit mode:** they're intentionally hidden (they don't render as visible content) but fully preserved. Switch to **Source** to see and edit them.
- **Markdown math isn't rendering:** make sure you're in the markdown rich (rendered) view, not the markdown source view, and that the math is wrapped in `$…$` or `$$…$$`.

## Known Limitations

- **PDF view needs a local TeX engine** — the full compiled preview requires BasicTeX or MacTeX installed on your Mac (Crispy doesn't bundle one). The Edit and Source views work without it.
- **Edit view renders math, not full layout** — the KaTeX-powered Edit view shows math and common structure but not full document-class layout; use the **PDF** view for that. In Edit mode, prose, sections, flat lists, math, the title, abstract, and keywords are editable in place; tables, figures, TikZ, the bibliography, and custom environments appear as preserved read-only blocks (edit them in Source or on the PDF page).
- **Trust your sources** — the PDF view runs a real LaTeX engine on your machine; only compile `.tex` files you trust, just as you would with any program.
- **Single-user, offline** — there is no collaboration or cloud rendering (by design); compilation is entirely local.
- **No command-line interface** for LaTeX documents yet.
