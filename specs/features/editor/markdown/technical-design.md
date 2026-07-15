# Markdown — Technical Design

## Overview

Markdown editing uses a dual-mode architecture: a rich rendered view (default) backed by `MarkupRenderedEditor` in a `WKWebView`, and a source mode using the native code editor with Markdown language definition. Content round-trips through Turndown (HTML → Markdown) for canonical storage.

## Architecture

### Supported Extensions

`.md`, `.markdown`, `.mdx` — all route to the markdown editor with identical behavior.

### Rendering Pipeline

1. Markdown source loaded from disk.
2. Rich mode: source injected into `WKWebView` via `MarkupRenderedEditor` in markdown mode.
3. User edits in rich mode produce HTML.
4. The live editor DOM is converted back to canonical markdown via **Turndown**.
   - Tables use a dedicated GFM serializer that emits header, alignment separator, and body rows.
   - Editor-only comment gutter controls are removed from serialized output.
   - Passing the DOM node directly avoids creating and reparsing a second full `innerHTML` string.
5. Canonical markdown sent to native `MarkdownViewModel` as `rawContent`.
6. Autosave writes `rawContent` to disk.

### Rich Mode Features

Formatting toolbar actions:

- Bold, Italic
- H1, H2
- Bullet List, Numbered List
- Quote, Code Block
- Link, Image, Table
- Horizontal Rule

Code blocks within markdown receive syntax highlighting during rendering.

### Source Mode

Displayed in the code editor with Markdown language definition. No formatting toolbar; a label ("Markdown Source") is shown instead.

### View Mode Toggle

Segmented control switches between Rich and Source. Mode stored per document keyed by file path. Rich is default. Content state preserved across toggles.

## Data Flow

### Content Sync

- Rich mode edits → Turndown converts HTML to markdown → `rawContent` updated in view model.
- Source mode edits → direct `rawContent` update.
- Content injection and format commands deferred until `WKWebView` signals readiness via `editorReady`.
- Browser-to-native values are recorded before publishing through SwiftUI, preventing a synchronous native echo from rerendering the editing DOM.
- Unchanged native echoes are ignored. Unavoidable rerenders snapshot and restore the document-wide text selection offsets.
- Comment bridge registration and decoration payloads are idempotent, preventing observable update loops and DOM churn while typing.

### Guided Authoring

- **Link** — requires selected text; prompts for URL; wraps selection in markdown link syntax.
- **Image** — opens searchable image picker (case-insensitive filename filtering, scans project directory for `.png`, `.jpg`, `.jpeg`, `.gif`, `.bmp`, `.tif`, `.tiff`, `.webp`, `.heic`, `.heif`, `.svg`, `.apng`, `.avif`); inserts markdown image syntax with resolved path and editable alt text.
  > **Note:** The image picker scanner (`MarkdownImageCandidateScannerService`) includes `apng` and `avif` extensions, but the file type detection (`MarkdownViewModelDetection`) does not. The two extension sets differ.
- **Table** — prompts for row and column counts; inserts markdown table with header and separator rows.

## State Management

- View mode preference stored per file path (rich = default, source = explicit preference).
- `rawContent` is the single source of truth for document content.
- Dirty state tracked via `hasUnsavedTextChanges`.

## API / Command Contracts

### WKWebView Bridge

- `editorReady` — signal from web runtime that content injection can proceed.
- Format command payloads sent to web editor (one per unique request ID).
- Content sync runs after each formatting mutation.

## Dependencies (frameworks, libraries)

- `WKWebView` — rich rendering host
- Turndown — HTML-to-Markdown conversion
- `MarkupRenderedEditor` — markdown rendering mode
- Code editor — source mode with Markdown language definition

## Platform Considerations

- `WKWebView` crash recovery: editor detects web process crash and re-renders content automatically with no data loss.
- ~50 CSS custom properties injected into `WKWebView` to reflect the active theme.
- JavaScript disabled for SVG rendering but enabled for markdown editing.

## Performance Constraints

- Autosave debounce: 0.45 seconds.
- Content injection deferred until `editorReady` to avoid race conditions.
- Rich-editor synchronization is debounced and deduplicated.
- Markdown serialization operates on a cloned DOM node instead of an `innerHTML` string parse, reducing peak memory for table-heavy documents.
