# Document Render Previews — Spec

Status: implemented

## Overview

F058 makes three more text-backed document formats first-class in Crispy, each with a live rendered preview produced by the user's locally-installed command-line toolchain — fully **offline**, no bundled engine, no network:

- **Typst** (`.typ`) — rendered to a PDF via `typst compile`.
- **Graphviz** (`.dot`, `.gv`) — rendered to a PDF via `dot -Tpdf`.
- **AsciiDoc** (`.adoc`, `.asciidoc`, `.asc`) — rendered to standalone HTML via `asciidoctor`.

Each opens with the same two-mode toggle markdown and LaTeX use, but here the rendered side is **read-only**:

- **Preview** (default) — the compiled output. PDF formats (Typst, Graphviz) render in a `PDFView`; AsciiDoc renders its HTML in a `WKWebView` with JavaScript disabled. The preview recompiles, debounced, as the source changes.
- **Source** — the raw document text in Crispy's standard `CodeEditorView`. This is the only place the document is edited; all changes flow through the normal document-buffer + autosave path.

Unlike F057's LaTeX Edit mode and F008's markdown, these three are **render-only** previews: there is no in-place WYSIWYG editing, no click-to-edit, and no comment affordance on the preview. The user edits the source text and watches the rendered output update.

The formats share a small offline scaffold (`DocumentFormatPreviews.swift`): `ExternalTool` resolves and runs a CLI converter off the main thread with a watchdog timeout and task cancellation; `CompiledPDFPreviewView` is the generic debounced source→PDF host (reusing F057's `CompiledPreviewContainerView`); `HTMLDocPreviewView` is the generic source→HTML→`WKWebView` host.

## Dependencies

- F007 (Editing) — Source mode is the standard `CodeEditorView`; edits flow through the shared buffer + autosave pipeline.
- F039 (Document Buffer) — each document's source is held in `DocumentBuffer` and persisted by `AutosaveScheduler` like any text file.
- F006 (Content Viewer) — hosts each document as an editor tab and provides the markup view-mode toggle.
- F057 (LaTeX Editor) — reuses the external-toolchain discovery pattern and the `CompiledPreviewContainerView` PDF host first built for the full-TeX LaTeX preview. The Preview/Source toggle reuses the markup view-mode plumbing shared with markdown and LaTeX.

## Requirements

### F058-R01: Three render-preview document types
`.typ` MUST detect as `DocumentType.typst`; `.adoc`/`.asciidoc`/`.asc` as `DocumentType.asciidoc`; `.dot`/`.gv` as `DocumentType.diagram`. Detection MUST take precedence over the generic plain-text/code path so these extensions never fall back to a raw code view by accident.

### F058-R02: Source / Preview toggle
Each document MUST offer the markup view-mode toggle with a **Preview** segment and a **Source** segment. The default on open is **Preview**. The chosen mode MUST be remembered per open document.

### F058-R03: Offline local compilation
Previews MUST be produced by the user's locally-installed CLI tool (`typst`, `dot`, or `asciidoctor`), resolved from a fixed set of trusted directories, and MUST run with no network access. No rendering engine is bundled in the app.

### F058-R04: Typst → PDF preview
A Typst document's Preview MUST run `typst compile --root <dir> main.typ main.pdf` in a private scratch directory and display the resulting PDF.

### F058-R05: Graphviz → PDF preview
A Graphviz document's Preview MUST run `dot -Tpdf graph.dot -o graph.pdf` in a private scratch directory and display the resulting PDF.

### F058-R06: AsciiDoc → HTML preview
An AsciiDoc document's Preview MUST run `asciidoctor --base-dir <dir> -o - doc.adoc`, capture the standalone HTML from stdout, and render it in a `WKWebView` with content JavaScript **disabled**.

### F058-R07: Live, debounced recompile
The Preview MUST recompile as the source changes, debounced (0.5 s) to coalesce rapid edits. While loading the buffer no compile is triggered. PDF previews MUST preserve the reader's page and scroll position across recompiles.

### F058-R08: Read-only preview
The Preview MUST be read-only. Editing happens only in Source mode. There is no in-place editing, click-to-edit, or comment affordance on these previews.

### F058-R09: Bounded resource use
A compile MUST be terminated if it exceeds a watchdog timeout (30 s default) or if the surrounding task is cancelled (e.g. the source changed again, or the view was dismantled), so a runaway or looping compile cannot hang or pile up.

### F058-R10: Non-destructive compile failure
A compile failure MUST surface the converter's error log rather than crash or blank out. For a PDF preview that already has a successful render, the last good render MUST be kept and a dismissible "compilation failed" banner shown instead of discarding it.

### F058-R11: Graceful tool-missing behavior
When the required CLI tool is not installed, the Preview MUST not crash; it surfaces the converter-not-found condition through the same compile-failure path (a message in the PDF host / an error page in the HTML host). A dedicated "install the tool" empty-state (like LaTeX's toolchain prompt) is **not** built for these three formats.

### F058-R12: File-backed, autosaving
Each document is a real text file. Source edits MUST persist through the standard document buffer + autosave path. No separate database.

## Scenarios

### Scenario F058-S01: Open a Typst file (Given / When / Then)
- **Given** a `.typ` file and `typst` installed, **when** the user opens it, **then** it opens in Preview mode, Crispy runs `typst compile` in a scratch directory, and the resulting PDF is shown.

### Scenario F058-S02: Open a Graphviz file
- **Given** a `.dot`/`.gv` file and `dot` installed, **when** the user opens it, **then** Crispy runs `dot -Tpdf` and shows the rendered graph as a PDF.

### Scenario F058-S03: Open an AsciiDoc file
- **Given** an `.adoc`/`.asciidoc`/`.asc` file and `asciidoctor` installed, **when** the user opens it, **then** Crispy runs `asciidoctor -o -` and renders the standalone HTML in a `WKWebView` with JavaScript disabled.

### Scenario F058-S04: Toggle to Source and edit
- **Given** an open document in Preview, **when** the user switches to Source, edits the text, and the buffer changes, **then** the Preview (after the debounce) recompiles and updates; the mode choice is remembered per document.

### Scenario F058-S05: Live preview while editing source
- **Given** the document is in Preview and the user is typing in Source (or the buffer otherwise changes), **when** edits stop, **then** the preview recompiles once (rapid edits coalesced by the 0.5 s debounce) and a PDF preview keeps the prior page/scroll position.

### Scenario F058-S06: Compile error
- **Given** a syntax error in the source, **when** the Preview recompiles, **then** the converter's error log is shown; if a previous successful PDF render exists it is kept with a dismissible "compilation failed" banner instead of being discarded.

### Scenario F058-S07: Required tool not installed
- **Given** the format's CLI tool is not on disk, **when** the document opens in Preview, **then** the preview shows a converter-not-found / compile-failed message rather than crashing or blanking (no dedicated install prompt).

### Scenario F058-S08: Runaway compile is bounded
- **Given** a compile that loops or hangs, **when** the watchdog timeout elapses or the task is cancelled (new edit or view dismantled), **then** the external process is terminated and does not accumulate.

### Scenario F058-S09: Offline guarantee
- **Given** no network connectivity, **when** any of the three formats is opened and edited, **then** the local toolchain renders the preview normally with no network access.

## Acceptance Criteria

- `.typ`/`.adoc`/`.asciidoc`/`.asc`/`.dot`/`.gv` detect to `typst`/`asciidoc`/`diagram` ahead of the generic code path (S01–S03).
- The Source/Preview toggle defaults to Preview and is remembered per document (S04).
- Typst and Graphviz render via `typst compile` / `dot -Tpdf` to a `PDFView`; AsciiDoc renders via `asciidoctor -o -` to a JavaScript-disabled `WKWebView` (S01–S03, R04–R06).
- Previews recompile debounced on source change and PDF page/scroll position is preserved across recompiles (S05).
- Compile failures show the tool log non-destructively; a prior PDF render is retained behind a banner (S06).
- A missing tool degrades to a compile-failure message, not a crash (S07).
- Compiles are terminated on timeout or cancellation; scratch directories are cleaned up (S08).
- All three render with networking disabled (S09).

## Open Questions

1. Should the three formats get a shared, dependency-aware **install empty-state** (like F057 LaTeX's "install BasicTeX" prompt) that detects the missing CLI and links to install instructions, instead of surfacing a raw compile-failure message? (Recommended follow-up; not yet built.)
2. Should the AsciiDoc render run `asciidoctor` in a restricted **safe mode** (`--safe-mode`) in addition to `--base-dir`, to constrain `include::` / file-read directives? (See threat-model F058-T02.)
3. Should the rendered AsciiDoc HTML carry a content-security policy to block remote resource (e.g. image) loads in addition to disabling JavaScript? (See threat-model F058-T03.)
4. Should successful renders be cached so toggling Source↔Preview without edits avoids a recompile?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-06-20 | Initial implementation: Typst (`.typ`), AsciiDoc (`.adoc/.asciidoc/.asc`), and Graphviz (`.dot/.gv`) document types with a read-only Source/Preview toggle, rendered offline by the user's local `typst` / `asciidoctor` / `dot` toolchains via a shared `ExternalTool` + `CompiledPDFPreviewView` / `HTMLDocPreviewView` scaffold. | — |
