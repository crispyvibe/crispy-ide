# Document Render Previews — Technical Design

## Overview

F058 adds three editable `DocumentType`s — `.typst`, `.asciidoc`, `.diagram` — each bound to Crispy's document buffer like markdown and LaTeX, and each shown in one of two panes selected by the markup view-mode toggle:

- **Source** → the standard `CodeEditorView` with a per-format `GenericCodeLanguage`. Edits flow `onContentChange → viewModel.userDidEdit → DocumentBuffer → AutosaveScheduler`.
- **Preview** (default, the `.rich` mode) → a **read-only** rendered host that compiles the buffer's current text with the user's local CLI tool and displays the result.

All rendering is performed by external command-line tools the user has installed (`typst`, `dot`, `asciidoctor`); nothing is bundled. The app is **not sandboxed** (entitlements grant only `get-task-allow`), so it can spawn these helpers directly.

The format-specific code lives in `Features/Editor/Views/DocumentFormatPreviews.swift`; routing lives in `MarkdownEditorPlugins.swift` and `MarkdownViewModelDetection.swift`.

## Architecture

```
Open .typ / .adoc|.asciidoc|.asc / .dot|.gv
  └─ MarkdownViewModelDetection.detectDocumentType → .typst / .asciidoc / .diagram   (before plainText/code)
        └─ MarkdownViewModel → DocumentBuffer → AutosaveScheduler                    (buffer holds raw source)
              └─ EditorPluginRegistry → TypstEditorPlugin / AsciiDocEditorPlugin / DiagramEditorPlugin
                    │
   currentMarkupViewMode == .source ───────────┐        currentMarkupViewMode == .rich (Preview) ──┐
                    ▼                            │                          ▼                         │
         CodeEditorView (per-format language)    │     PDF formats: CompiledPDFPreviewView           │
         content get: displayContent             │       → compile() → PDFDocument → PDFView          │
         onContentChange → userDidEdit           │       (reuses CompiledPreviewContainerView)         │
                                                 │     AsciiDoc:    HTMLDocPreviewView                 │
                                                 │       → render() → HTML string → WKWebView (JS off) │
                                                 └──────────────────────────────────────────────────────┘

Shared scaffold (DocumentFormatPreviews.swift):
  ExternalTool.resolve(name)  → first executable in /opt/homebrew/bin, /usr/local/bin,
                                 /Library/TeX/texbin, /usr/bin
  ExternalTool.run(tool,args,cwd,timeout:30) → Process off main (global qos:.userInitiated),
                                 args as an array (no shell), watchdog terminate + Task-cancel terminate,
                                 returns (status, stdout Data, merged stderr log)
  ExternalTool.makeScratchDir() → <temp>/crispyvibes-preview/<uuid>/

Toolbar (MarkdownEditorView.markupToolbar, isRenderPreviewFormat):
  shows a static format label ("Typst"/"AsciiDoc"/"Graphviz") + the [Preview | Source] toggle.
  (No formatting buttons / no palette — these previews are render-only.)
```

## Data Flow

**Detection & routing.** `detectDocumentType(for:)` checks `typstExtensions` (`typ`), then `asciidocExtensions` (`adoc`, `asciidoc`, `asc`), then `diagramExtensions` (`dot`, `gv`) — all ahead of the plain-text/code fallbacks — and returns the matching `DocumentType`. `EditorPluginRegistry` maps each type to its plugin; the three plugins share a `formatPreviewView(...)` helper that returns the `CodeEditorView` in `.source` mode and the format's preview view in `.rich` mode.

**Compile (PDF formats).** `CompiledPDFPreviewView` is an `NSViewRepresentable` over `CompiledPreviewContainerView` (the same PDF host F057 uses). On appearance and on every buffer change it calls `scheduleCompile`: a 0.5 s debounced `DispatchWorkItem` that, unless `isBufferLoading`, cancels any in-flight `Task` and starts a new one calling the injected `compile: (String, URL?) async -> (URL?, String)` closure. On success it loads the PDF (`PDFDocument(url:)`) into the container — preserving the previous page index and scroll point so a re-render doesn't jump the reader — and deletes the previous render's scratch directory. On failure it shows the tool log (last 40 lines); if a prior PDF exists the container keeps it behind a dismissible banner.

- **Typst** (`TypstPreviewCompiler`): writes the source to `<scratch>/main.typ`, runs `typst compile --root <scratch> main.typ main.pdf` with `cwd = <scratch>`, returns `main.pdf` on exit 0; removes the scratch dir on failure.
- **Graphviz** (`GraphvizPreviewCompiler`): writes `<scratch>/graph.dot`, runs `dot -Tpdf graph.dot -o graph.pdf` with `cwd = <scratch>`, returns `graph.pdf` on exit 0; removes the scratch dir on failure.

**Render (AsciiDoc).** `HTMLDocPreviewView` is an `NSViewRepresentable` over a `WKWebView` configured with `defaultWebpagePreferences.allowsContentJavaScript = false` and `drawsBackground = false`. Its debounced `scheduleRender` calls `AsciiDoctorPreviewCompiler.compile`, which writes `<scratch>/doc.adoc` and runs `asciidoctor --base-dir <baseDir> -o - doc.adoc` (`baseDir` = the document's own directory if known, else the scratch dir), capturing the standalone HTML from **stdout**. The HTML is loaded with `loadHTMLString(_:baseURL:)` (baseURL = the document's directory). On non-zero exit the coordinator loads a small inline error page built from the escaped tool log. The scratch dir is always removed (`defer`) since the output is stdout, not a file.

**Lifecycle.** Both hosts cancel the pending debounce and in-flight task in `dismantleNSView`; the PDF host additionally deletes its last scratch directory on shutdown and whenever it swaps in a newer render.

## API / Command Contracts

**External converter invocations** (arguments passed as an **array** to `Process`, never a shell string):

| Format | Command | Output |
|--------|---------|--------|
| Typst | `typst compile --root <scratch> <scratch>/main.typ <scratch>/main.pdf` | PDF file |
| Graphviz | `dot -Tpdf <scratch>/graph.dot -o <scratch>/graph.pdf` | PDF file |
| AsciiDoc | `asciidoctor --base-dir <docDir|scratch> -o - <scratch>/doc.adoc` | standalone HTML on stdout |

`ExternalTool.run` augments the child `PATH` with the search directories, runs on a background queue, and returns `Output { status, stdout: Data, log: String }` where `log` is captured stderr.

**Plugin → preview closures (Swift):** each plugin injects a format-specific closure into the generic host — `CompiledPDFPreviewView(compile:)` for Typst/Graphviz, `HTMLDocPreviewView(render:)` for AsciiDoc — so the hosts stay format-agnostic.

## State Management

- `MarkdownViewModel.DocumentType.{typst, asciidoc, diagram}` — editable types routed through the buffer/autosave path; included in `isEditableDocumentType`.
- `MarkupViewMode { rich, source, compiled }`; `supportsMarkupViewModeToggle` includes the three formats; `defaultMarkupViewMode == .rich` for them (Preview); the chosen mode is stored per document in `markupViewModeByDocumentID` and cleared on close. The toggle's `.rich` segment is labelled **"Preview"** (`richModeLabel` via `isRenderPreviewFormat`); the `.compiled` segment exists only for LaTeX.
- `CompiledPDFPreviewView.Coordinator` — `lastContent` (change guard), `pending` (debounce), `task` (in-flight compile), `currentPDFURL` (for scratch cleanup).
- `HTMLDocPreviewView.Coordinator` — `lastContent`, `pending`, `task`.

## Dependencies (frameworks, libraries)

- `AppKit`, `PDFKit` (`PDFView`/`PDFDocument` via `CompiledPreviewContainerView`), `WebKit` (`WKWebView`), `Foundation` (`Process`, `Pipe`), `OSLog`. No new Swift package dependencies and **no vendored runtime**.
- Runtime tools are the **user's** local installs: `typst`, Graphviz (`dot`), `asciidoctor`. Resolved at run time from `/opt/homebrew/bin`, `/usr/local/bin`, `/Library/TeX/texbin`, `/usr/bin`.

## Platform Considerations

- macOS only. The app is **not sandboxed** (`get-task-allow` only), which is what permits spawning the external CLI converters and reading their output.
- The AsciiDoc `WKWebView` runs with content JavaScript disabled and a transparent background; PDF formats render in an AppKit `PDFView`.
- The shared `CompiledPreviewContainerView` (from F057) carries SyncTeX/block-edit/comment affordances for the LaTeX native compiler; F058's `CompiledPDFPreviewView` does **not** wire up `onPageClick`, so those affordances are inert here — the preview is strictly read-only.

## Performance Constraints

- Compiles are debounced at 0.5 s and the prior in-flight `Task` is cancelled before a new one starts, so rapid edits collapse to a single render.
- A 30 s watchdog terminates a runaway/looping compile; task cancellation terminates the child process when the source changes again or the view is dismantled.
- Each compile runs off the main thread on a `.userInitiated` global queue; results are applied back on the main actor.
- PDF previews preserve page + scroll position across recompiles to avoid reflow jank.

## Migration / Rollout Notes

- No persistence migration: the three are plain text files on the existing buffer; the Source/Preview preference reuses the markdown/LaTeX `markupViewModeByDocumentID` map.
- No feature flag — shipped on by default. Previews are simply unavailable (compile-failure message) when the corresponding CLI tool is not installed.
- Verification: `xcodebuild -scheme crispyvibes-local` builds.

## Known Gaps / Follow-ups

- No shared install/empty-state for a missing CLI tool (unlike F057's LaTeX toolchain prompt); a missing tool currently surfaces as a compile-failure message. Recommended follow-up.
- The AsciiDoc render sets `--base-dir` but not `--safe-mode`; constraining `include::`/file-read further is an open question (threat-model F058-T02).
- The rendered AsciiDoc HTML has no CSP; JavaScript is disabled but remote resource (e.g. image) loads are not blocked (threat-model F058-T03).
- Previews are render-only — no in-place editing, click-to-edit, or comments for these three formats (by design).
