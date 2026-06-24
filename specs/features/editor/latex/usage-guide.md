---
title: "LaTeX Editor"
feature: "F057"
domain: "editor"
audience: "user"
version: "1.2"
sidebar:
  label: "LaTeX"
  order: 11
---

# LaTeX Editor

## Overview

Crispy opens LaTeX documents (`.tex`, `.latex`, `.ltx`) in a dedicated editor with **three tabs**, chosen from the mode toggle in the toolbar. Each tab is a different way to work with the same file — your edits are the same document underneath, and you can switch tabs at any time.

| Tab | What it shows | Needs a TeX engine? |
|-----|---------------|---------------------|
| **Edit** | A live, WYSIWYG view: headings, paragraphs, lists, the abstract, keywords, and your math (typeset by [KaTeX](https://katex.org)) look like the finished document. You type prose directly and click any equation to edit it visually. | **No** — works everywhere, instantly, with nothing installed. |
| **Source** | The raw `.tex` code in Crispy's code editor, with a math-symbol palette for inserting snippets at the cursor. Nothing is hidden or transformed. | No. |
| **PDF** | The **real, fully compiled document** — Crispy runs LaTeX on your Mac and shows the actual typeset PDF: correct two-column layouts, author blocks, floats, tables, citations, and bibliography. Double-click the page to edit the source behind it; select text to leave a comment. | **Yes** — requires a local TeX engine (BasicTeX or MacTeX). |

Think of **Edit** as a fast, dependency-free draft view for prose and math, **Source** as the full raw code, and **PDF** as the ground-truth, fully-typeset output. The Edit view is great for writing and reviewing content quickly, but it intentionally renders a *subset* — math and common structure — and **cannot reproduce full page layout** (two-column formatting, exact float placement, custom document classes). For that, use the PDF tab.

When you open a `.tex` file, Crispy picks a **smart default**:

- If it detects a TeX engine on your Mac → opens in **PDF** (the fully compiled document).
- If no engine is found → opens in **Edit** (KaTeX), which needs no installation.

You can switch modes at any time, and Crispy remembers your choice per document.

Crispy also renders inline math in **Markdown** documents: `$E = mc^2$` and `$$…$$` blocks typeset automatically in the markdown rich view and save back to their original `$` / `$$` form.

### Everything is local and offline

The PDF tab compiles with **your own local TeX toolchain** — `pdflatex -synctex=1` run on your machine. There is **no account, no cloud, and no internet**: compilation works fully offline. Crispy runs LaTeX (and BibTeX) **multiple passes** automatically so cross-references and citations resolve instead of showing `??` / `[?]` placeholders. Long or runaway compiles are bounded by a timeout and cancelled when you keep typing, so the app never hangs.

## Getting Started

1. Open any `.tex` / `.latex` / `.ltx` file from the file explorer (or create one and start typing).
2. If you have a TeX engine installed, it opens in the **PDF** tab with the fully compiled document. Otherwise it opens in the **Edit** tab with the body rendered by KaTeX.
3. Use the **mode toggle** (Edit · Source · PDF) to switch tabs.
4. Changes autosave — there is no Save button.

### Installing a TeX engine (for the PDF tab)

The PDF tab needs a local LaTeX engine. Crispy doesn't bundle one — it uses whatever you have installed.

**Recommended: BasicTeX (~100 MB)** — a minimal TeX Live distribution, ideal for most documents:

```
brew install --cask basictex
```

**Full distribution: MacTeX (multi-GB)** — the complete TeX Live with every package preinstalled, if you'd rather not manage packages yourself:

```
brew install --cask mactex
```

Both install into **`/Library/TeX/texbin`**, which Crispy probes automatically (along with the standard TeX Live and Homebrew binary locations). **No app restart is needed** — after installing, just open the PDF tab and click **Recheck**, and the live PDF appears.

Crispy was validated against **TeX Live 2026 / pdfTeX 1.40.29**, but any recent TeX Live release works.

### Installing extra LaTeX packages (no admin password)

BasicTeX is intentionally minimal, so some documents need packages it doesn't ship with — for example `enumitem`, `titlesec`, `algorithms`, or `IEEEtran`. If a compile fails with a "File `…sty` not found" error, install the missing package **per-user, without `sudo`**:

```
tlmgr init-usertree
tlmgr --usermode install <package>
```

This installs into your personal tree at **`~/Library/texmf`** — no admin rights required. For example: `tlmgr --usermode install enumitem titlesec`. (MacTeX users rarely need this, since it ships with the full package set.)

## Workflows

### Write prose, headings, and lists (Edit tab)

In **Edit**, click into a paragraph and type. Press Enter for a new paragraph. Use the toolbar for **bold**, *italic*, `code`, headings, and bullet/numbered lists — they apply to your selection and are written back as the matching LaTeX commands (`\textbf{…}`, `\section{…}`, `\begin{itemize}…`, and so on). The abstract and keywords are editable too. Tables, figures, TikZ pictures, the reference list, and custom environments appear as rendered, **read-only blocks** — they're preserved exactly; edit them in **Source** or on the **PDF** page.

The round-trip is reversible: what you write in Edit is saved as clean LaTeX, and the preamble, packages, and anything Edit doesn't render visually are kept intact (just hidden from the rendered view). Switch to **Source** any time to see the full file.

### Edit an equation visually (Edit tab)

Click any equation (inline or a displayed block) in **Edit**. A popup opens with:

- a **live preview** that updates as you build the math,
- a grid of **symbol and template buttons** (fractions, roots, sums, integrals, Greek letters, matrices, …) so you can build math without remembering the LaTeX, and
- the raw **TeX** in a text box for when you'd rather type it.

Click **Done** (or click away) to commit, **Cancel** (or Escape) to discard. The equation re-renders in place. If an equation has a syntax error it shows as red text — click it to open the popup and fix it; Crispy keeps rendering the rest of the document.

### Insert math from the palette

The toolbar's math palette inserts common templates and symbols. In **Source** the LaTeX snippet drops in at your cursor (with `{}` placeholders where the next value goes). In **Edit** the snippet is inserted and rendered immediately — a bare fragment becomes inline `$…$`, a matrix/environment becomes a displayed block.

### Edit on the page (PDF tab)

This is the signature feature of the PDF tab. **Double-click** any text in the rendered document. Crispy uses SyncTeX to map that spot back to the exact source, and a small inline editor opens **right where you clicked**, prefilled with that block of source (a paragraph or environment) and labeled with which lines you're editing. The matching region on the page is **highlighted** so you can see exactly what your edit affects.

Make your change and press **Save** (or **⌘↩**); the document is rewritten and the page re-compiles. Press **Esc** or **Cancel** to discard. The first time you open a document in the PDF tab, a brief hint reminds you: *"Double-click any text to edit · ⌘↩ to save."*

### Comment on the PDF (PDF tab)

In the **PDF** tab, **select some text** — a **Comment** button appears just above the selection. Click it to start a comment anchored to that part of the document. Comments you add on the PDF live in the **same comment store** as comments added in the **Source** or **Edit** views (shared with Crispy's commenting feature), so a comment shows up consistently no matter which tab you're working in.

### Non-destructive errors (PDF tab)

If an edit doesn't compile, Crispy **keeps showing your last good PDF** and drops a small dismissible banner — *"Compilation failed — showing the last successful render."* You never lose your place or stare at a blank page over one typo. Switch to **Source** to find and fix the error, and the page recompiles. (Only when there's no previous PDF to fall back to — e.g. the very first compile fails — does Crispy show the error log in full.)

### Live recompile

In the PDF tab, the page **recompiles automatically** a moment after you stop typing (edits are debounced and batched). Your current page and scroll position are preserved across re-renders, so the view doesn't jump. Cross-references and citations are resolved across multiple passes, and BibTeX is run automatically when your document declares a bibliography (`\bibliography{…}` or `\addbibresource`).

### Work in raw LaTeX (Source tab)

Switch to **Source** for full control: the complete `.tex`, including the preamble and any package or environment Crispy doesn't render visually. Anything Crispy can't show in Edit is still right here, untouched. The math palette inserts snippets at your cursor here too.

### Math in Markdown

In a `.md` file, write `$inline$` or a `$$displayed$$` block. In the markdown rich view they typeset via KaTeX; when you save, they're written back as the same `$…$` / `$$…$$` you wrote.

## When LaTeX is installed vs not installed

### Installed (BasicTeX or MacTeX present)

- `.tex` files **open in the PDF tab** by default.
- The PDF tab shows the **full-fidelity, real compiled document**.
- **Double-click** a region to edit that source block in place; the affected page region is highlighted.
- **Select text** to add a comment (shared with the Edit and Source tabs).
- Errors are **non-destructive** — the last good PDF stays on screen.
- The page **recompiles live** as you edit, with multi-pass + BibTeX resolution.
- The **Edit** and **Source** tabs remain fully available.

### Not installed (no TeX engine found)

- `.tex` files **open in the Edit tab** (KaTeX) by default — fully usable, no install required.
- The **Source** tab is fully usable too.
- The **PDF** tab shows an **actionable empty state** titled *"Full LaTeX preview needs a TeX engine"* with:
  - the body text *"Install BasicTeX (~100 MB) or MacTeX to render the real PDF. The Edit and Source tabs work without it."*
  - the **install command** `brew install --cask basictex` shown in a selectable field,
  - a **Copy** button (copies the command to the clipboard),
  - a **Recheck** button — click it after installing and the live PDF appears, **no app restart**,
  - a **Use Edit Tab** button to switch straight to the dependency-free Edit view, and
  - a **Get BasicTeX** link to the TeX download page.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Commit the equation popup / on-page edit | `⌘↩` (or click Save / click away) |
| Cancel the equation popup / on-page edit | `Esc` |
| New paragraph (Edit tab) | `↩` |
| Open the on-page editor (PDF tab) | Double-click the text |

Standard editor shortcuts (undo/redo, find/replace, selection) work as usual in the Source tab. Crispy adds no other LaTeX-specific global shortcuts in this version.

## Settings / Configuration

- **Mode (Edit / Source / PDF):** chosen with the toolbar toggle; remembered per document. New documents open in **PDF** when a TeX engine is installed, otherwise in **Edit**.
- **TeX engine (PDF tab):** install BasicTeX or MacTeX locally; nothing to configure in Crispy beyond having it on your Mac. Crispy auto-detects engines in `/Library/TeX/texbin`, the TeX Live binary directories, `/opt/homebrew/bin`, and `/usr/local/bin`.
- **Extra packages:** install per-user with `tlmgr --usermode install <package>` (into `~/Library/texmf`) — no admin password.
- **Appearance:** the rendered surfaces follow the app's light/dark theme automatically — nothing to configure.
- There are no other LaTeX-specific settings.

## Troubleshooting

- **The PDF tab says it "needs a TeX engine":** install BasicTeX (`brew install --cask basictex`) — copy the command from that screen — then press **Recheck**. No restart needed. Until then, use the **Edit** or **Source** tabs, which need no install.
- **A compile fails with "File `…sty` not found":** your document needs a package BasicTeX doesn't include (e.g. `enumitem`, `titlesec`, `algorithms`, `IEEEtran`). Install it without admin rights: `tlmgr init-usertree` then `tlmgr --usermode install <package>`.
- **My PDF won't update / shows a "compilation failed" banner:** your latest edit has a LaTeX error. Crispy keeps showing your last good PDF; switch to **Source** to find and fix it, and the page recompiles. (If the very first compile fails, the full error log is shown instead.)
- **References or citations show `??` or `[?]`:** this usually resolves on its own — Crispy runs LaTeX (and BibTeX) multiple times until cross-references settle. If it persists, there's likely a missing label or bibliography entry; check in **Source**.
- **An equation shows red text instead of math (Edit tab):** the LaTeX in that equation has a syntax error. Click it to open the popup and fix the TeX; the preview shows where it breaks. Crispy never stops rendering the rest of the document over one bad equation.
- **Something in my document shows as a grey read-only block (Edit tab):** that's an environment Crispy doesn't edit visually (e.g. a TikZ picture, a table, or a custom environment). It's preserved exactly — switch to **Source**, or use the **PDF** tab to see it fully typeset.
- **"The full-TeX compiler runtime is unavailable" / "The LaTeX preview runtime is unavailable":** the app build is missing its bundled assets — rebuild/reinstall the app.
- **My preamble/packages seem to vanish in the Edit tab:** they're intentionally hidden (they don't render as visible content) but fully preserved. Switch to **Source** to see and edit them.
- **Markdown math isn't rendering:** make sure you're in the markdown rich (rendered) view, not the markdown source view, and that the math is wrapped in `$…$` or `$$…$$`.

## Known Limitations

- **The PDF tab needs a local TeX engine** — the full compiled preview requires BasicTeX or MacTeX installed on your Mac (Crispy doesn't bundle one). The Edit and Source tabs work without it.
- **The Edit tab renders math, not full layout** — the KaTeX-powered Edit view shows math and common structure (prose, sections, flat lists, the title, abstract, and keywords are editable in place) but **not** full document-class layout (two-column, exact float placement, custom classes). Tables, figures, TikZ, the bibliography, and custom environments appear as preserved read-only blocks (edit them in Source or on the PDF page). Use the **PDF** tab for true layout.
- **Trust your sources** — the PDF tab runs a real LaTeX engine on your machine; only compile `.tex` files you trust, just as you would with any program.
- **Single-user, offline** — there is no collaboration or cloud rendering (by design); compilation is entirely local.
- **No command-line interface** for LaTeX documents yet.

## Change History

- **1.2** — Documented the three tabs explicitly (Edit / Source / PDF), the installed-vs-not-installed experience, BasicTeX/MacTeX install (location, auto-detect, Recheck), per-user package installs via `tlmgr --usermode`, validated TeX Live 2026 / pdfTeX 1.40.29, and the offline multi-pass + BibTeX compile model.
- **1.1** — Initial PDF (full-TeX) tab, on-page editing, and comments.
