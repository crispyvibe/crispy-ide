# GPU Acceleration and UI Responsiveness Audit

Status: Reviewed static audit
Last Updated: 2026-03-13
Owner: Engineering
Scope: `crispyvibes-ide/projects/crispyvibes/crispyvibes`

Fact-check note: the code references and implementation claims below were rechecked against the current repository on 2026-03-13. The prioritization and impact estimates are still static-analysis judgments, not runtime measurements from Instruments.

## Executive Summary

The app is not missing a single "enable GPU" switch. Large parts of the UI already benefit from macOS compositor acceleration through SwiftUI/AppKit/Core Animation, and the embedded Ghostty terminal is explicitly Metal-backed through `CAMetalLayer` in `projects/crispyvibes/crispyvibes/Features/Terminal/Services/GhosttyTerminalEngine.swift:416-419`.

The largest code-visible reason the app may not feel "GPU-native fast" is that most non-terminal surfaces still use stock AppKit/WebKit text and view pipelines, with several full-document or full-tree CPU paths on the main thread. In other words:

- Terminal rendering is already GPU-accelerated.
- Explorer, editor, markdown conversion, image editing, and parts of the vibespace shell are primarily CPU-bound.
- The biggest wins will come from reducing main-thread work and invalidation breadth before introducing more GPU code.
- If you want GPU-native responsiveness in the editor specifically, the long-term path is a custom incremental text/rendering pipeline, not just "Swift instead of Electron."

## Bottom-Line Assessment

| Area | Current bottleneck type | Does more GPU help? | Priority |
|---|---|---:|---:|
| Terminal rendering | Mostly already GPU-backed | Low | Medium |
| Terminal board interactions | View invalidation / state churn | Low-Medium | High |
| Code editor | Main-thread regex highlighting + full attributed-string passes | Low for now | Critical |
| Rich markdown/html editor | DOM parse/serialize + WebKit bridge churn | Medium | Critical |
| Raster image preview/editor | Decode/composite/draw work on CPU and main thread | High | Critical |
| File explorer | Tree refresh/reload churn, worker refresh, git refresh coupling | Low | High |
| Detailed vibespace shell | Broad SwiftUI invalidation + host rebuilds | Low | High |
| Settings | Mostly form UI, already scoped/lazy | Very low | Low |

## What Is Already GPU-Accelerated

### Terminal surface

- `GhosttyTerminalView` creates a `CAMetalLayer` in `projects/crispyvibes/crispyvibes/Features/Terminal/Services/GhosttyTerminalEngine.swift:416-419`.
- This is the clearest GPU-backed surface in the app today.
- Conclusion: terminal rendering speed issues are not caused by a lack of GPU acceleration at the draw layer.

### System compositor-backed surfaces

- SwiftUI/AppKit/WKWebView/PDFKit all render through Core Animation backed surfaces by default.
- That means normal scrolling, clipping, opacity, rounded corners, and layer compositing are already using the OS graphics stack.
- Conclusion: for most panes, "GPU acceleration" is already present in the compositor; the bigger issue is how much work reaches the compositor.

### Board divider overlay

- The terminal board divider chrome is drawn with `Canvas` in `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardInteractionDecorations.swift:72-79`.
- This is fine. It is not the main responsiveness problem.

## Area-by-Area Findings

### 1. Global shell and detailed vibespace view

#### Finding

The root shell still owns a large amount of state in `projects/crispyvibes/crispyvibes/ContentView.swift:34-80`, and the detailed vibespace composition mounts multiple expensive panes at once in `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/Canvas/ContentViewProjectCanvas.swift:94-135`.

#### Why it matters

- Any broad `ContentView` invalidation can re-run layout and body generation for heavy surfaces.
- The detailed view keeps a focused terminal plus the content viewer alive together.
- `NativeSplitView` replaces both hosted roots on every update through `updateHostedContent` in `projects/crispyvibes/crispyvibes/Shared/Components/NativeSplitView.swift:194-201`.

#### Bottleneck type

CPU/layout invalidation. This is not a missing-GPU problem.

#### Recommendation

- Split root state further so explorer, content viewer, and terminal regions observe smaller models.
- Make the heavy pane hosts more identity-stable. Right now `NativeSplitView` always reassigns `AnyView` roots in `projects/crispyvibes/crispyvibes/Shared/Components/NativeSplitView.swift:112-113` and `:194-201`.
- Prefer dedicated pane view models or `Equatable` wrappers around non-changing props for the detailed shell.

#### Expected impact

High for perceived responsiveness during file switching, project switching, and layout changes.

### 2. File explorer and source control sidebar

#### What is already good

- The explorer avoids a pure-SwiftUI row tree and uses `NSOutlineView` in `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/Explorer/AppKitTreeView.swift:21-68`.
- Search filtering is already debounced and pushed off the main thread in `projects/crispyvibes/crispyvibes/Features/VibeSpace/ViewModels/Explorer/FolderExplorerViewModel.swift:84-118`.

#### Main hotspots

1. `AppKitTreeView.updateNSView` still performs broad reconciliation work on most updates in `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/Explorer/AppKitTreeView.swift:71-145`.
2. `refreshNodeCache(with:)` walks the full tree recursively in `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/Explorer/AppKitTreeView.swift:297-304`.
3. `reloadExpandedNodes()` reloads every expanded node in `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/Explorer/AppKitTreeView.swift:581-589`.
4. Visible-row updates loop all visible rows in `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/Explorer/AppKitTreeView.swift:115-129`.
5. Watcher-triggered refreshes can still fall back to full tree reload plus git refresh in `projects/crispyvibes/crispyvibes/Features/VibeSpace/ViewModels/Explorer/FolderExplorerViewModelTreeLifecycle.swift:68-123`, `:222-238`, `:269-310`.

#### Bottleneck type

CPU, worker churn, and UI reload breadth. GPU will not materially improve this area.

#### Recommendation

- Move from "reload expanded subtrees" toward targeted node diffs by changed path.
- Separate tree refresh cadence from git refresh cadence. Today `refreshGitStateIfNeeded` can follow tree refreshes in `projects/crispyvibes/crispyvibes/Features/VibeSpace/ViewModels/Explorer/FolderExplorerViewModelTreeLifecycle.swift:306-310`.
- Keep watcher bursts coalesced longer when many filesystem events arrive quickly.
- Preserve and update a more granular item index so changed directories can patch only affected branches.

#### Expected impact

High in large repositories and multi-project vibespaces.

### 3. Code editor and plain text editor

#### Code editor hotspots

The code editor is still fundamentally an `NSTextView` wrapper in `projects/crispyvibes/crispyvibes/Features/Editor/Views/CodeEditorView.swift:17-45`.

The expensive work is:

1. Full syntax highlighting over the whole document on the main thread in `projects/crispyvibes/crispyvibes/Features/Editor/Languages/LanguageDefinition.swift:37-74`.
2. A second full attributed-string scan in `enforceVisibleForeground` in `projects/crispyvibes/crispyvibes/Features/Editor/Views/CodeEditorView.swift:169-190`.
3. Debounced re-highlighting after every edit in `projects/crispyvibes/crispyvibes/Features/Editor/Views/CodeEditorView.swift:228-245`.
4. Full-string replacement plus deferred highlight on external changes in `projects/crispyvibes/crispyvibes/Features/Editor/Views/CodeEditorView.swift:61-88`.

#### Plain text editor

`PlainTextEditor` is much simpler in `projects/crispyvibes/crispyvibes/Features/Editor/Views/PlainTextEditor.swift:19-147`. Its main cost is standard TextKit layout, not rendering.

#### Bottleneck type

Main-thread CPU and text layout. More GPU does not solve the core issue here.

#### Recommendation

- Replace regex-over-entire-document highlighting with incremental tokenization.
- Limit highlight work to visible ranges plus a small prefetch margin.
- Push tokenization off the main thread and apply attribute deltas back on the main thread.
- Evaluate TextKit 2 or a custom text surface if editor responsiveness is a strategic differentiator.

#### Strategic note

From the code, this looks like the biggest gap versus GPU-native responsiveness. A custom GPU-backed renderer only becomes worth it after the app stops doing full-document CPU work for each edit.

### 4. Rich markdown and HTML editor

#### Swift-side hotspots

`MarkupRenderedEditor` avoids redundant sync better than before, but it still drives a full web-editor update model:

- JS injection for content/theme commands happens in `projects/crispyvibes/crispyvibes/Features/Editor/Views/MarkupRenderedEditor.swift:61-99`.
- `updateNSView` always evaluates sync paths in `projects/crispyvibes/crispyvibes/Features/Editor/Views/MarkupRenderedEditor.swift:223-227`.

#### Web-side hotspots

The bundled editor runtime performs full-document transforms:

- Markdown render does `marked.parse(...)`, assigns `innerHTML`, resolves images, then highlights all code blocks in `projects/crispyvibes/crispyvibes/Resources/MarkdownRuntime/editor.html:418-427`.
- Native sync converts the full edited DOM back to markdown with Turndown in `projects/crispyvibes/crispyvibes/Resources/MarkdownRuntime/editor.html:456-465`.
- Every input schedules that sync in `projects/crispyvibes/crispyvibes/Resources/MarkdownRuntime/editor.html:468-472`, plus listeners in `:520-523` and `:1701-1705`.

#### Bottleneck type

CPU and bridge churn, not raw compositing.

#### Recommendation

- Avoid full DOM-to-markdown serialization on normal typing paths.
- Use a model that preserves markdown source incrementally instead of regenerating it from `editor.innerHTML`.
- Highlight only newly inserted or visible code blocks rather than running `querySelectorAll("pre code")` over the entire document every render.
- For HTML mode, avoid full iframe document rewrites when only local edits changed small regions.

#### Does GPU help?

Only indirectly. `WKWebView` is already composited. The bottleneck is parsing and serialization.

### 5. Raster image preview and editing

#### Main hotspots

This is the strongest code-visible GPU opportunity outside the terminal.

Hot paths:

- File observation and reload are handled on the main queue in `projects/crispyvibes/crispyvibes/Features/Editor/Support/RasterImageFilePreview.swift:92-103`.
- Image loading/thumbnail generation still runs synchronously inside preview refresh in `projects/crispyvibes/crispyvibes/Features/Editor/Support/RasterImageFilePreview.swift:151-176` and `:199-248`.
- Preview refresh is driven directly from `updateNSView` in `projects/crispyvibes/crispyvibes/Features/Editor/Support/RasterImageFilePreview.swift:355-419`.
- Custom drawing is CPU-side AppKit drawing in `projects/crispyvibes/crispyvibes/Features/Editor/Support/EditableRasterImageCanvasView.swift:183-191`.
- Final compositing still uses `NSImage.lockFocus()` in `projects/crispyvibes/crispyvibes/Features/Editor/Support/EditableRasterImageCanvasViewRendering.swift:78-95`.

#### Bottleneck type

Mixed main-thread CPU, image decode, and software compositing.

#### Recommendation

- Move preview decode/downsample work off the main thread.
- Use tiled rendering for very large images instead of redrawing a full bitmap view.
- Replace software compositing with Core Image or Metal for crop/draw/annotation composition.
- Consider `CATiledLayer` for zoom-heavy image work and `MTKView` if annotation becomes a major workflow.

#### Does GPU help?

Yes. This is the clearest place where additional GPU work can materially improve responsiveness.

### 6. PDF and SVG previews

#### Findings

- PDF preview uses `PDFView` in `projects/crispyvibes/crispyvibes/Features/Editor/Support/PDFFilePreview.swift:13-29`.
- SVG preview uses `WKWebView` in `projects/crispyvibes/crispyvibes/Features/Editor/Support/SVGFilePreview.swift:15-35`.

#### Bottleneck type

Mostly document load/decode, not frame rendering.

#### Recommendation

- Cache already-open documents/previews when users switch tabs frequently.
- For very large PDFs, validate whether document reloading on file change is causing visible stalls before investing in custom rendering.

#### Does GPU help?

Low incremental value. These surfaces already rely on mature OS/web rendering stacks.

### 7. Content viewer web pages

#### Findings

`ContentViewerView` uses a simple `WKWebView` wrapper in `projects/crispyvibes/crispyvibes/Features/ContentViewer/Views/ContentViewerView.swift:153-162`.

#### Bottleneck type

Mostly web-content dependent.

#### Recommendation

- This is not a high-priority GPU target.
- If web page tabs become numerous, add lifecycle management so inactive web tabs can suspend or unload.

### 8. Terminal host and terminal board

#### What is already good

- The actual terminal surface is Metal-backed, so GPU rendering is already present.
- Board chrome is relatively lightweight.

#### Main hotspots

1. `VibeSpaceTerminalOnlyView` mutates `@State` during body evaluation through `currentBoardMetrics = baseMetrics` in `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalOnlyView.swift:75-85`.
2. The board recomputes metrics, hit-test context, and cursor regions inside `GeometryReader` every render in `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalOnlyView.swift:75-83`.
3. Each tile mounts a full `TerminalSessionHostView` in `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardTileCard.swift:93-105`.
4. `TerminalContainerView` listens to `NSWindow.didUpdateNotification` and rescans the terminal subtree for scrollers in `projects/crispyvibes/crispyvibes/Features/Terminal/Views/TerminalSessionHostView.swift:453-500` and `:527-539`.
5. Scroller configuration work runs repeatedly in `projects/crispyvibes/crispyvibes/Features/Terminal/Views/TerminalSessionHostView.swift:432-445` and `:519-524`.

#### Bottleneck type

Mostly invalidation churn and repeated AppKit host work around the already-fast terminal renderer.

#### Recommendation

- Remove state mutation from `VibeSpaceTerminalOnlyView.body`; derive board metrics via preferences, a local computed cache, or controller-owned ephemeral state.
- Cache scroller references after attach instead of recursively searching the terminal subtree on every window update.
- Throttle or narrow scroller visibility refresh triggers; `didUpdateNotification` is too broad.
- Keep terminal tiles alive only when visible/active if board tile count grows.

#### Does GPU help?

Only a little. The terminal already uses the GPU. The remaining work is orchestration overhead.

### 9. Settings and terminal board settings surfaces

#### Findings

- General settings are mostly standard SwiftUI form controls in `projects/crispyvibes/crispyvibes/Features/Settings/Views/AppSettingsSheetViewGeneral.swift:4-220`.
- This is not a hot rendering path relative to editors, explorer, or terminal surfaces.

#### Recommendation

- Do not spend GPU effort here.
- Keep these views lazy and category-scoped, which the app already does elsewhere.

## Recommended Optimization Roadmap

### Phase 1: High-ROI fixes without renderer rewrites

1. Stop state mutation during terminal board body evaluation.
2. Remove broad window-update-driven terminal scroller rescans.
3. Narrow explorer refreshes to changed branches instead of reloading expanded nodes.
4. Decouple git refresh from every watcher-driven tree refresh.
5. Push raster image reload/decode work fully off the main thread.

### Phase 2: Editor pipeline improvements

1. Replace full-document regex highlighting with incremental tokenization.
2. Reduce or eliminate DOM-to-markdown full serialization on every rich-editor edit.
3. Highlight only visible or changed markdown code blocks.
4. Keep editor host identity stable across split-view/layout changes.

### Phase 3: Targeted GPU work

1. Introduce Core Image or Metal for raster-image compositing and annotation.
2. Add tiled rendering for very large raster content.
3. Consider a GPU-backed custom editor surface only if editor latency remains a product-level problem after Phase 2.

## Recommended Instrumentation Plan

Use Instruments before and after each phase:

1. Time Profiler
2. Core Animation
3. Metal System Trace
4. Allocations
5. Points of Interest / signposts around file switch, explorer refresh, and terminal board drag

Suggested benchmark flows:

1. Open a large code file and type continuously for 10 seconds.
2. Switch between 5 to 10 editor tabs rapidly.
3. Expand/collapse deep repository trees with active filesystem changes.
4. Open a large image and zoom/crop/annotate repeatedly.
5. Run 4 to 8 live terminals in the board and resize/move tiles.

## Final Conclusions

The app already uses GPU acceleration where the platform naturally provides it, and the terminal is explicitly Metal-backed. The main opportunity is not "make the whole app GPU accelerated"; it is to stop feeding too much main-thread CPU work into otherwise capable native rendering stacks.

If the goal is "feel much closer to GPU-native performance," the near-term path is:

1. Reduce invalidation breadth in the shell and board.
2. Make explorer refresh incremental.
3. Rebuild the editor pipeline around incremental text/markup updates.
4. Add GPU work only where the workload is actually image or terminal-surface rendering.

Based on the current implementation, the best GPU candidate today is the raster image editor. The best responsiveness candidate overall is the editor pipeline.
