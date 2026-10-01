# Markdown — Technical Design

## Overview

Markdown editing uses a dual-mode architecture: a rich rendered view (default) backed by `MarkupRenderedEditor` in a `WKWebView`, and a source mode using the native code editor with Markdown language definition. Content round-trips through Turndown (HTML → Markdown) for canonical storage.

## Architecture

### Supported Extensions

`.md`, `.markdown`, `.mdx` — all route to the markdown editor with identical behavior.

### Rendering Pipeline

1. Markdown source loaded from disk.
2. Rich mode: source injected into `WKWebView` via `MarkupRenderedEditor` in markdown mode.
3. Numeric currency tokens such as `$8M`, `$2M`, and `$16,655.00` are wrapped as editable literal prose before KaTeX auto-render, preventing separate currency values from being paired as one inline equation; symbolic `$E = mc^2$` math remains eligible for KaTeX.
4. User edits in rich mode produce HTML.
5. The live editor DOM is converted back to canonical markdown via **Turndown**.
   - Tables use a dedicated GFM serializer that emits header, alignment separator, and body rows.
   - Editor-only comment gutter controls are removed from serialized output.
   - Passing the DOM node directly avoids creating and reparsing a second full `innerHTML` string.
6. Canonical markdown sent to native `MarkdownViewModel` as `rawContent`.
7. Autosave writes `rawContent` to disk.

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

- **Link** — requires selected text; prompts for a section, file, HTTP(S), `mailto:`, or `file:` destination; validates the scheme before wrapping the selection.
- **Image** — opens searchable image picker (case-insensitive filename filtering, scans project directory for `.png`, `.jpg`, `.jpeg`, `.gif`, `.bmp`, `.tif`, `.tiff`, `.webp`, `.heic`, `.heif`, `.svg`, `.apng`, `.avif`); inserts markdown image syntax with resolved path and editable alt text.
  > **Note:** The image picker scanner (`MarkdownImageCandidateScannerService`) includes `apng` and `avif` extensions, but the file type detection (`MarkdownViewModelDetection`) does not. The two extension sets differ.
- **Table** — prompts for row and column counts; inserts markdown table with header and separator rows.

### Target-Aware Link Routing

`editor.html` assigns deterministic IDs to rendered headings using normalized heading text; duplicates receive `-2`, `-3`, and later suffixes. A delegated `a[href]` handler classifies each activation:

- `#fragment` → resolve within `#editor`, record the current scroll position, smooth-scroll, and flash-highlight the target. ⌘[ pops the document-local scroll history.
- relative/absolute `file:` target → resolve against `markdownBaseHref` and post `markdownLinkAction` with target kind `localFile`.
- HTTP(S) → either show the anchored action popover (`ask`) or post the saved direct action (`crispy` / `defaultBrowser`).
- `mailto:` → offer the default system app.
- unsupported schemes, protocol-relative targets, malformed URLs, and HTTP(S) URLs with embedded credentials → block and show a subtle notification.

The runtime popover owns user-gesture UI: Open in Crispy, Default Browser/App, Edit, Copy, and Remove. Option-click places the caret instead of activating. Enter activates a focused link; right-click always opens the full popover; Escape and scroll dismiss it. Editing reuses the guided link dialog with the current `href` prefilled. Removing unwraps the anchor so visible inline content remains.

`MarkupRenderedEditor.Coordinator` registers `markdownLinkAction`, strictly decodes it into `MarkdownLinkActionRequest`, and invokes the injected callback. Its `WKNavigationDelegate` cancels link-activated or targetless WebKit navigation as a defense-in-depth backstop. Native code never trusts WebView classification alone:

- `MarkdownViewModel` revalidates HTTP(S) scheme, host, and absence of credentials before invoking `MarkdownLinkRouter`.
- Crispy Browser actions post the existing `.openNewBrowserRequested` notification from `AppContainer`, preserving project ownership and current detailed/terminal-only placement.
- Default browser/app actions call the injected `VibeSpaceInteractionService`.
- Before posting a local-file action, the runtime calls `syncToNative()` so any debounced rich edit reaches the source document before its WebView can be replaced.
- Local links remove the fragment, standardize the file URL, require an existing non-directory local target for both Crispy and Default App actions, reject Default App for remote-provider paths, and confine local targets to the resolved owning project root when an absolute project identity is available. `MarkdownViewModel` registers the fragment request, then invokes its owner callback; `EditorGroupStore` opens the file through its own `openFileInTab`, preserving the visible pane tab list, provider registry, comments context, and persistence. Detached standalone editors use the view model's direct-tab fallback. Remote providers validate paths through their normal authenticated read/confinement flow.
- A linked Markdown fragment becomes a document-bound `MarkdownRichNavigationRequest`. After the target runtime renders, `MarkupRenderedEditor` invokes `window.crispyvibesNavigateToAnchor(fragment)` and consumes the one-shot request.

The preference is stored as `AppPreferences.markdownWebLinkPreferenceKey` with enum values `ask`, `crispy`, and `defaultBrowser`; `ask` is the default. `MarkdownEditorView` observes it with `@AppStorage` and synchronizes it into the runtime through `window.crispyvibesSetWebLinkPreference(...)`.

## State Management

- View mode preference stored per file path (rich = default, source = explicit preference).
- `rawContent` is the single source of truth for document content.
- Dirty state tracked via `hasUnsavedTextChanges`.

## API / Command Contracts

### WKWebView Bridge

- `editorReady` — signal from web runtime that content injection can proceed.
- `markdownLinkAction` — validated user action payload containing action, target kind, original `href`, resolved URL, and fragment.
- `window.crispyvibesSetWebLinkPreference(rawValue)` — synchronizes `ask` / `crispy` / `defaultBrowser` behavior.
- `window.crispyvibesNavigateToAnchor(fragment)` — applies a one-shot same-document or post-open heading navigation.
- Format command payloads sent to web editor (one per unique request ID).
- Content sync runs after each formatting or link mutation.

## Dependencies (frameworks, libraries)

- `WKWebView` — rich rendering host
- Turndown — HTML-to-Markdown conversion
- `MarkupRenderedEditor` — markdown rendering mode
- Code editor — source mode with Markdown language definition

## Platform Considerations

- `WKWebView` crash recovery: editor detects web process crash and re-renders content automatically with no data loss.
- ~50 CSS custom properties are injected into `WKWebView` to reflect the active theme.
- `MarkupRenderedEditor` reads `crispyvibesUIScale` and applies `WebViewPresentationScale` in both `makeNSView` and `updateNSView`. The adapter sets `pageZoom` from the 0.25×–5.0× clamped current/default code-size ratio, scaling Markdown runtime UI and nested authored HTML without DOM reconstruction.
- JavaScript disabled for SVG rendering but enabled for markdown editing.

## Performance Constraints

- Autosave debounce: 0.45 seconds.
- Content injection deferred until `editorReady` to avoid race conditions.
- Rich-editor synchronization is debounced and deduplicated.
- Markdown serialization operates on a cloned DOM node instead of an `innerHTML` string parse, reducing peak memory for table-heavy documents.
