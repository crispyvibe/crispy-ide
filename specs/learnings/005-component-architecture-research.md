# Component Architecture Research & Comparison

Status: Active
Last Updated: 2026-03-04
Owner: Engineering
Scope: `crispyvibes-ide/projects/crispyvibes/crispyvibes` — all major UI components

## Purpose

Compare CrispyVibes's component implementations against industry-leading editors and IDEs. Identify architectural gaps and prioritize improvements by impact.

Feedback triage log: (archived — all items completed)

## Dependency Footprint

The app is intentionally lean — only 3 external packages:

| Package | Version | Purpose |
|---|---|---|
| SwiftTerm | 1.11.2 | Terminal emulation and rendering |
| Sparkle | 2.9.0 | Auto-update framework |
| swift-argument-parser | 1.7.0 | CLI argument parsing (SwiftTerm dependency) |

Everything else is built on Apple frameworks: SwiftUI, AppKit, WebKit, PDFKit, Combine, CryptoKit, CoreGraphics.

## Component Analysis

---

### 1. Code Editor

**Current Implementation**:
- NSTextView (TextKit 1) wrapped in NSViewRepresentable
- Regex-based syntax highlighting via NSRegularExpression → NSAttributedString
- Full-document re-highlight on every keystroke
- No line numbers, no virtualization, no incremental parsing
- Protocol-based `LanguageDefinition` with `SyntaxPattern` arrays
- Supports Python, JavaScript, JSON, R, and a generic fallback

**Files**: `projects/crispyvibes/crispyvibes/Features/Editor/Views/CodeEditorView.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Languages/LanguageDefinition.swift`, `projects/crispyvibes/crispyvibes/Themes/SyntaxTheme.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Languages/PythonLanguage.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Languages/JavaScriptLanguage.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Languages/JSONLanguage.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Languages/RLanguage.swift`

#### Industry Comparison

| Capability | CrispyVibes | Editor A | Editor B | Editor C | Editor D |
|---|---|---|---|---|---|
| Text engine | NSTextView / TextKit 1 | Monaco (custom) | GPUI (custom Metal) | Custom engine | NSTextView + TextKit 2 |
| Syntax parsing | Regex (full doc) | TextMate grammars | Tree-sitter (incremental) | Custom (incremental) | Tree-sitter |
| Large file support | None | Virtualized | Virtualized + streaming | Virtualized | Virtualized |
| GPU rendering | ❌ | ❌ (DOM) | ✅ Metal | ❌ | ❌ |
| Incremental highlight | ❌ | ✅ | ✅ | ✅ | ✅ |
| Code folding | ❌ | ✅ | ✅ | ✅ | ✅ |
| Line numbers | ❌ | ✅ | ✅ | ✅ | ✅ |
| Minimap | ❌ | ✅ | ❌ | ✅ | ❌ |

#### Gaps (Ordered by Impact)

1. **Full-document regex re-highlighting on every keystroke** — O(n) per keystroke on document size. Every other editor does incremental highlighting (only changed lines + context).
2. **No virtualization** — entire document rendered in memory. Large files (>10K lines) will degrade.
3. **TextKit 1** — legacy text engine. TextKit 2 has better performance for large documents and supports non-contiguous layout.
4. **No Tree-sitter** — regex patterns can't express nested grammar (e.g., string interpolation, embedded languages). Tree-sitter provides incremental parsing, structural selection, and code folding for free.
5. **No line numbers** — expected feature for any code editor.

#### Recommendations

| Priority | Change | Effort | Impact |
|---|---|---|---|
| 1 | Incremental highlighting (re-highlight only changed lines + visible range) | Low | High — eliminates O(n) per keystroke |
| 2 | Add line number gutter | Low | High — basic expected feature |
| 3 | Tree-sitter integration via `SwiftTreeSitter` package | Medium | High — incremental parsing, folding, structural selection |
| 4 | TextKit 2 migration | Medium | Medium — better large-file performance, non-contiguous layout |
| 5 | Visible-range-only rendering for large files | Medium | Medium — prevents degradation on large files |

---

### 2. Markdown Editor & File Preview

**Current Implementation**:
- **Markdown WYSIWYG**: WKWebView + marked.js + highlight.js + turndown.js with contenteditable
- **Plain text editing**: NSTextView (TextKit 1) with syntax highlighting
- **Git diff**: Custom parser with structured data model, syntax-highlighted rendering, `LazyVStack` for large diffs
- **PDF**: Native PDFKit (`PDFView`) with single-page continuous mode
- **Autosave**: 450ms debounced via `DispatchWorkItem`, content comparison to skip no-ops
- **Web↔Native sync**: 220ms debounced with suppression flags to prevent loops
- **Plugin architecture**: `EditorPluginRegistry` with protocol-based plugins per file type

**Files**: `projects/crispyvibes/crispyvibes/Features/Editor/Views/MarkdownEditorView.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/ViewModels/MarkdownViewModel.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Views/MarkupRenderedEditor.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Views/PlainTextEditor.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Support/GitDiffPreview.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Support/PDFFilePreview.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Views/MarkdownEditorFormatting.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Views/MarkdownEditorPlugins.swift`

#### Industry Comparison

| Capability | CrispyVibes | Editor A | Editor E | Editor B |
|---|---|---|---|---|
| Markdown rendering | WKWebView + marked.js | markdown-it (webview) | CodeMirror 6 + custom | Tree-sitter + native |
| Text editing | NSTextView (TextKit 1) | Monaco | CodeMirror 6 | Custom GPUI |
| Live preview | In-place WYSIWYG | Side-by-side | In-place | Side-by-side |
| Autosave | ✅ 450ms debounce | ✅ configurable | ✅ | ✅ |
| Find/replace | ✅ regex | ✅ regex | ✅ regex | ✅ regex |
| Large doc handling | No virtualization | Virtualized | Virtualized | Virtualized |

#### Assessment

The markdown editor is the strongest component architecturally. The WKWebView + marked.js approach is industry-standard (Editor A and Editor E use similar patterns). The plugin-based editor registry is clean and extensible.

#### Gaps

1. **No virtualization for large documents** — loading entire document into WKWebView and NSTextView.
2. **Find/replace scans full document** without caching results (PERF-015).
3. **Large-document bridge pressure** — content transfer still scales with full document size, even though redundant sync calls are now gated.

Resolved baseline:
- PERF-014 is no longer an open item. WKWebView content/theme sync is now gated by cached last-injected values.

#### Recommendations

| Priority | Change | Effort | Impact |
|---|---|---|---|
| 1 | Cache find/replace match results (PERF-015) | Low | Medium — faster search on large docs |
| 2 | Lazy content loading for very large markdown files | Medium | Low — edge case for most users |
| 3 | Add chunked/streamed update strategy for very large markdown payloads | Medium | Low-Medium — reduces bridge pressure under very large files |

---

### 3. Folder Explorer

**Current Implementation**:
- Recursive `FileItem` struct tree with `children: [FileItem]?`
- SwiftUI `List` + `DisclosureGroup` for rendering
- `DispatchSourceFileSystemObject` (FSEvents) for file watching, 0.3s debounce
- Lazy directory loading — children loaded on expand only
- Seti SVG icons loaded via `NSImage`, cached in `NSCache<NSString, NSImage>`
- Client-side recursive search/filter
- Git-ignored entries are detected and de-emphasized, but exclusion policies/toggles are not implemented

**Files**: `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/FolderExplorerView.swift`, `projects/crispyvibes/crispyvibes/Features/VibeSpace/ViewModels/FolderExplorerViewModel.swift`, `projects/crispyvibes/crispyvibes/Features/VibeSpace/ViewModels/FolderExplorerTypes.swift`, `projects/crispyvibes/crispyvibes/Models/FileItem.swift`, `projects/crispyvibes/crispyvibes/Shared/Support/FileIconProvider.swift`, `projects/crispyvibes/crispyvibes/Shared/Components/SetiIconView.swift`

#### Industry Comparison

| Capability | CrispyVibes | Editor A | Editor B | System File Manager | Editor D |
|---|---|---|---|---|---|
| Data structure | Recursive struct tree | Flat virtual list | Worktree (background) | NSOutlineView | NSOutlineView |
| Rendering | SwiftUI List + DisclosureGroup | Virtual DOM list | GPUI list | NSOutlineView | NSOutlineView |
| Virtualization | ❌ | ✅ | ✅ | ✅ | ✅ |
| File watching | FSEvents per expanded dir | chokidar (FSEvents) | Background worktree | FSEvents | FSEvents |
| .gitignore support | ❌ | ✅ | ✅ | N/A | ✅ |
| Search | Client-side recursive | Ripgrep (background) | Ripgrep (background) | Spotlight | Background indexed |
| Large dir handling | No special handling | .gitignore + filtering | .gitignore + streaming | Lazy enumeration | Lazy enumeration |
| Tree indexing | ❌ (O(n²) search) | ✅ (flat indexed) | ✅ (indexed) | ✅ | ✅ |

#### Gaps (Ordered by Impact)

1. **O(n²) tree search and replacement** — `findItem(withID:in:)` and `replaceChildren(ofPath:with:in:)` are recursive linear scans (PERF-004, PERF-005). Every other file tree uses indexed lookup.
2. **No `.gitignore` exclusion policy** — ignored paths are visually de-emphasized but still loaded and rendered. Large ignored trees (`node_modules`, `.git`, `build/`) still consume traversal and rendering cost.
3. **No virtualization** — SwiftUI `List` renders all visible nodes. NSOutlineView (used by System File Manager, Editor D) virtualizes natively.
4. **Unbounded FSEvents watchers** — one `DispatchSource` per expanded directory with no cap (PERF-013).
5. **No background search** — client-side recursive filter blocks UI. Editor A and Editor B use ripgrep in a background process.

#### Recommendations

| Priority | Change | Effort | Impact |
|---|---|---|---|
| 1 | Add `.gitignore` exclusion policy (toggle or vibespace default) | Medium | Very High — biggest UX/perf improvement for large repos |
| 2 | Index tree with `Dictionary<String, FileItem>` (PERF-004/005) | Low | High — O(1) lookup replaces O(n²) |
| 3 | Add `Equatable` to `FileItem` (PERF-021) | Low | Medium — reduces SwiftUI re-renders |
| 4 | Cap FSEvents watchers (PERF-013) | Low | Medium — prevents FD exhaustion |
| 5 | Consider `NSOutlineView` via NSViewRepresentable for native virtualization | High | Medium — better large-repo performance |
| 6 | Background search via Process (ripgrep or custom) | High | Medium — non-blocking file search |

---

### 4. Image Canvas & Preview

**Current Implementation**:
- **Drawing canvas**: NSView with `draw()` override using Core Graphics
- **Strokes**: `[[CGPoint]]` arrays rendered via `NSBezierPath` (2.2pt, round caps/joins)
- **Annotations**: Custom `TextAnnotation` struct rendered via `NSAttributedString`
- **Compositing**: `NSImage.lockFocus()` / `unlockFocus()` (deprecated API)
- **Image loading**: `NSImage(contentsOf:)` — full resolution, no downsampling
- **Scroll/zoom**: NSScrollView with magnification (0.1x–10x)
- **SVG**: WKWebView-based rendering, JavaScript disabled
- **File watching**: `DispatchSource` for live reload with file state caching (size + mtime)
- **No GPU acceleration, no render caching, no dirty-region tracking**

**Files**: `projects/crispyvibes/crispyvibes/Features/Editor/Support/EditableRasterImageCanvasView.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Support/RasterImageFilePreview.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Support/RasterImagePreviewHost.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Support/ImageFilePreview.swift`, `projects/crispyvibes/crispyvibes/Features/Editor/Support/SVGFilePreview.swift`

#### Industry Comparison

| Capability | CrispyVibes | Preview.app | Pixelmator | Sketch |
|---|---|---|---|---|
| Rendering | Core Graphics (CPU) | Core Graphics | Metal | Metal |
| Stroke rendering | NSBezierPath per frame | N/A | GPU geometry | GPU geometry |
| Compositing | lockFocus (deprecated) | CGContext | Metal compute | Metal |
| Large images | Full resolution | Tiled rendering | Tiled + GPU | Tiled + GPU |
| Dirty regions | ❌ | ✅ | ✅ | ✅ |
| Render caching | ❌ | ✅ | ✅ | ✅ |

#### Gaps (Ordered by Impact)

1. **Full canvas redraw on every stroke point** — no dirty-region tracking, no cached layers. Frame drops during drawing.
2. **`NSImage.lockFocus()` is deprecated** — Apple recommends `CGContext`-based or `NSGraphicsContext.current` drawing.
3. **Full-resolution image loading** — no downsampling for display (PERF-006). Memory spikes on large images.
4. **No render caching** — completed strokes re-rendered from point arrays every frame.
5. **No GPU acceleration** — this is the component that would benefit most from Metal in the entire app.

#### Recommendations

| Priority | Change | Effort | Impact |
|---|---|---|---|
| 1 | Cache completed strokes as bitmap layer; only render active stroke live | Low | High — eliminates most redraw cost |
| 2 | Replace `lockFocus()` with `CGContext`-based compositing | Low | Medium — removes deprecated API, slightly faster |
| 3 | Add dirty-region tracking (only redraw stroke bounding box) | Low | Medium — reduces draw area per frame |
| 4 | Downsample images for display via `CGImageSource` (GPU-005) | Low | High — eliminates memory spikes |
| 5 | Enable `layer?.drawsAsynchronously` (GPU-001) | Low | Medium — offloads drawing |
| 6 | Metal canvas via `MTKView` (GPU-004) | High | High — eliminates frame drops entirely |

---

## Cross-Component Summary

### Strength / Gap Matrix

| Component | Architecture | Performance | Feature Parity | Priority |
|---|---|---|---|---|
| Terminal | ✅ Good (SwiftTerm) | 🟡 Adequate | ✅ Good | Medium |
| Code Editor | 🟡 Basic | 🔴 Poor (full-doc regex) | 🔴 Missing basics | **High** |
| Markdown Editor | ✅ Good (plugin arch) | 🟡 Adequate | ✅ Good | Low |
| Folder Explorer | 🟡 Functional | 🔴 Poor (O(n²), no virtualization) | 🔴 No exclusion policy | **High** |
| Image Canvas | 🔴 Legacy APIs | 🔴 Poor (CPU, full redraws) | 🟡 Functional | Medium |
| Persistence | ✅ Strong | ✅ Good | ✅ Good | None |
| App Shell | ✅ Good (post-refactor) | 🟡 Adequate | ✅ Good | Low |

### Recommended Investment Order

1. **Folder Explorer** — `.gitignore` support + tree indexing. Highest user-visible impact, moderate effort.
2. **Code Editor** — Incremental highlighting + line numbers. Currently the weakest component vs industry standard.
3. **Image Canvas** — Stroke caching + image downsampling. Low effort, high impact on drawing experience.
4. **Terminal** — Architectural fixes (PERF-001, PERF-002). Already tracked in performance doc.
5. **App Shell** — Startup optimization (PERF-007). Already tracked in performance doc.
6. **Markdown Editor** — Minor sync optimizations. Already good enough.

### Technology Adoption Roadmap

| Technology | Benefit | Components Affected | Effort | When |
|---|---|---|---|---|
| Tree-sitter (`SwiftTreeSitter`) | Incremental parsing, folding, structural ops | Code Editor | Medium | Next major editor iteration |
| TextKit 2 | Better large-file perf, non-contiguous layout | Code Editor, Plain Text Editor | Medium | When dropping macOS 12 support |
| `.gitignore` exclusion policy | Exclude or de-emphasize ignored/build dirs predictably | Folder Explorer | Low-Medium | Immediate |
| `CGImageSource` thumbnailing | GPU-decoded image previews | Image Canvas | Low | Immediate |
| Metal (`MTKView`) | GPU-accelerated drawing | Image Canvas (first), Terminal (later) | High | After CPU optimizations measured |
| `NSOutlineView` | Native virtualized tree | Folder Explorer | High | If SwiftUI List proves insufficient |

## References

- Editor A architecture documentation
- GPU-accelerated rendering approach used by Editor B
- [Tree-sitter](https://tree-sitter.github.io/tree-sitter/)
- [SwiftTreeSitter package](https://github.com/ChimeHQ/SwiftTreeSitter)
- [TextKit 2 WWDC](https://developer.apple.com/videos/play/wwdc2021/10061/)
- Terminal rendering research: (archived — Ghostty replaced SwiftTerm)
- Performance findings: (archived — all PERF items resolved)
