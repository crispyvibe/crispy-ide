# Help Needed: Browser & HTML Preview Comments Not Working

## The Problem

We're building a file commenting system (F049) for CrispyVibes IDE (native macOS, Swift/SwiftUI). Comments on **code files work perfectly** — gutter icons, highlights, floating button, the whole thing. But we cannot get comments working on two surfaces:

1. **Browser windows** (WKWebView): Selecting text on any page does NOT show the "💬 Add Comment" floating button. No decorations appear on elements that have comments.

2. **HTML file preview** (rendered in an iframe inside a WKWebView): Same issue — no floating button on selection, no decorations on commented elements.

The maddening part: **the element picker feature in the exact same browser WKWebView works flawlessly**. It injects JS, draws hover overlays, captures DOM element info. Same webView instance, same injection mechanism. But our comments JS bundle appears to do nothing.

## What We Built

### Browser surface
- `BrowserSurfaceBridge.swift` — a `WKScriptMessageHandler` that:
  - Registers 4 message handlers (`commentsRichRequestAdd`, `commentsRichGutterClick`, `commentsRichSelectionCaptured`, `commentsRichURLChanged`) on the webView's userContentController
  - Contains a ~200-line JS bundle (IIFE) that adds a `selectionchange` listener, shows a floating "💬 Add Comment" button near the selection, injects CSS decorations on elements matching stored CSS selectors, and observes SPA route changes
  - The bundle is injected both as a `WKUserScript(.atDocumentEnd)` in `makeWebView()` AND via `evaluateJavaScript()` in `pageDidLoad()` as a fallback
- `BrowserPanelViewModel.swift` — owns the webView, calls `commentsBridge.attach(webView:)` in init, calls `commentsBridge.pageDidLoad(url:)` on every `onDidFinish` navigation callback, calls `refreshCommentsForCurrentPage()` which fetches threads from the store and pushes them to JS via `commentsBridge.syncDecorations()`
- `BrowserContentView.swift` — SwiftUI view that wraps the browser with a comments panel, sets `viewModel.commentsStore = commentStore` (from environment)

### HTML preview surface
- `editor.html` — contains a `crispyvibesHTMLAdapter` object that operates on `htmlFrame.contentDocument` (the iframe). It has `setComments(doc, threads, selectedID)` which does `doc.querySelector(th.selector)` and applies CSS classes + gutter buttons. Also has `captureSelection(doc)` which builds a CSS selector path for the selected element.
- `CodeEditorCommentBridge.swift` — `syncRichModeDecorations()` sends thread data (including `selector` field from `domSelector`) to the WKWebView via `evaluateJavaScript`
- `MarkupRenderedEditor.swift` — NSViewRepresentable coordinator subscribes to `store.changes` (Combine) and calls `syncCommentDecorationsIfNeeded()` which delegates to the bridge

### Persistence
- Rust schema v3 adds `comments.surface_kind` ('file'|'browser') and `comment_anchors.dom_selector/dom_text_offset/dom_text_length/dom_fingerprint`
- Comments are anchored by CSS selector path (bounded ≤6 ancestors, prefers `#id`, falls back to `nth-of-type`) + text offset within the element
- The `CommentAnchor` Swift struct carries optional `domSelector`, `domTextOffset`, `domTextLength`, `domFingerprint` fields
- Encoder/decoder/Rust handler all pass these through correctly

## What We've Tried

1. **Dual injection** — WKUserScript at document-end + evaluateJavaScript fallback after navigation finishes. Neither produces visible results.

2. **Store timing fixes** — Moved `commentsStore` assignment from `.onAppear` → `.task` → direct body-level assignment. Added `didSet` that triggers immediate `refreshCommentsForCurrentPage()`. Added Combine subscription retry in `updateNSView` for the HTML preview case.

3. **iframe lifecycle** — Cache the last thread list in `window.__crispyvibesLastThreads`; re-apply decorations + re-inject styles in `attachHTMLFrameListeners()` after every `frameDoc.write()` (which recreates the contentDocument).

4. **SPA resilience** — Route observer (`pushState`/`replaceState`/`popstate`) re-appends the floating button if it was removed by a body replacement.

5. **Rust response fix** — `insert_comment` now returns the full anchor (including `domSelector`) in its response so the immediate `Comment` object has correct data.

6. **Error logging** — Added completion handler to `evaluateJavaScript` in `injectBundleIfNeeded()` to log errors. Haven't been able to observe any errors firing (but also haven't confirmed the log appears).

7. **Environment propagation** — Added `vibespaceCommentStoreEnvironment` to detached board windows so browser tiles there get a non-nil store.

None of these fixed the issue. The floating button never appears on text selection in browser windows, and no decorations appear on either surface.

## Why the Element Picker Works (Our Best Clue)

The element picker (`BrowserPanelViewModel.elementPickerJS`) works because:
- It's injected **on-demand** via `evaluateJavaScript` when the user clicks the picker button — the page is guaranteed loaded
- It does NOT use `window.webkit.messageHandlers` — it writes to clipboard instead
- It does NOT depend on any external data (no store, no vibespace ID, no thread list)
- It's completely self-contained

Our comments bundle differs in that:
- It uses `window.webkit.messageHandlers.X.postMessage(...)` to communicate back to native
- It depends on `syncDecorations()` being called with thread data from the store
- Any nil in the chain (store, vibespace ID, thread list) causes a silent early return

We suspect the JS bundle either isn't executing at all, or it executes but the `window.webkit.messageHandlers` objects don't exist yet (handler registration timing), or `refreshCommentsForCurrentPage()` silently returns due to nil values. But we haven't been able to confirm which.

## Repo & Build

- **Path**: `/Users/manumishra/projects/crispyvibe/crispyvibes-ide-comments`
- **Build**: `xcodebuild build -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes-local -configuration DebugLocal -destination 'platform=macOS'`
- **Run**: `./scripts/run-local.sh`
- **Rust**: `cargo build --manifest-path projects/crispyvibes/rust/crispyvibes-persistence/Cargo.toml`
- The webView is inspectable (`webView.isInspectable = true`) so Safari Web Inspector can attach

## Key Files to Look At

- `Features/Editor/Comments/Services/BrowserSurfaceBridge.swift` — the JS bundle + native bridge
- `Features/VibeSpace/Services/Browser/BrowserPanelViewModel.swift` — webView owner, search for `attachCommentsBridge`, `refreshCommentsForCurrentPage`, `makeWebView`
- `Features/VibeSpace/Services/Browser/BrowserContentView.swift` — SwiftUI wrapper
- `Resources/MarkdownRuntime/editor.html` — search for `crispyvibesHTMLAdapter` and `editorMode === "html"`
- `Features/Editor/Views/MarkupRenderedEditor.swift` — search for `syncCommentDecorationsIfNeeded`
- `Features/Editor/Comments/Services/CodeEditorCommentBridge.swift` — search for `syncRichModeDecorations`

## Resolution: What Actually Fixed It

The root problem was not persistence, store timing, handler registration, or URL canonicalization. Those paths were mostly fine. The broken pieces were in the injected UI layer:

1. `selectionchange` alone is not a reliable trigger in WKWebView for these surfaces. The HTML preview iframe and browser page both needed fallback listeners on `mouseup`, `pointerup`, and `keyup`, with the reposition work deferred through `setTimeout(..., 0)` so WebKit had time to settle the selection.

2. The browser comments bundle was too eager to mark itself installed. It set `window.__crispyvibesCommentsBundleInstalled = true` before all setup had safely completed. If DOM setup failed or ran before the expected hosts were ready, later fallback injections would bail out forever. The marker now only gets set after the bundle finishes installing.

3. Browser-page UI cannot rely on page CSS behaving nicely. The floating add-comment button and the thread marker are injected into arbitrary host pages, so host resets like `button { ... }`, global fonts, layout styles, `appearance`, pseudo-element rules, and CSP/style behavior can distort or hide them. The fix was to style injected browser controls inline with `style.setProperty(..., "important")`, including `all: initial`, fixed dimensions, z-index, icon background, appearance reset, and box sizing.

4. Browser marker icons should not depend on `.crispyvibes-gutter-btn::before`. Pseudo-elements live in the host page's styling ecosystem and can be clobbered. The marker now uses an inline data-URI SVG as the button's own `background-image`.

5. `BrowserSurfaceBridge.scrollAndSelect(anchor:)` was incorrectly trying to encode a Swift `String` with `JSONSerialization.data(withJSONObject:)`, which is invalid for a top-level scalar. It now uses `JSONEncoder().encode(selector)` so selector strings are correctly escaped before interpolation into JS.

6. Relaunching mattered. `./scripts/run-local.sh` builds and then runs `open "$APP_PATH"`. If `CrispyLocal.app` is already running, macOS can focus the existing process instead of loading the newly built binary/resources. For validating injected JS changes, quit `CrispyLocal` first, then run the script.

### Files Changed for the Fix

- `projects/crispyvibes/crispyvibes/Features/Editor/Comments/Services/BrowserSurfaceBridge.swift`
  - Added `commentsRichDebug` message handler for install/selection breadcrumbs.
  - Made browser bundle installation retry-safe.
  - Added mouse/key/pointer selection fallbacks.
  - Added inline, `!important`, host-CSS-resistant styling for the floating add button.
  - Added inline, `!important`, host-CSS-resistant styling for browser thread markers.
  - Fixed selector JSON encoding for scroll-to-anchor.

- `projects/crispyvibes/crispyvibes/Resources/MarkdownRuntime/editor.html`
  - Added the same selection fallback strategy for rendered markdown and HTML iframe preview.
  - Re-attaches iframe selection fallbacks every time `frameDoc.write(...)` recreates the iframe document.

### Verification

- Extracted browser bundle JS and ran `node --check`.
- Extracted `editor.html` inline script and ran `node --check`.
- Built successfully with:

```bash
xcodebuild build -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes-local -configuration DebugLocal -destination 'platform=macOS'
```

- Confirmed manually:
  - HTML preview comments now show the floating add-comment button.
  - Browser comments now show the floating add-comment button.
  - Browser comment markers render without being visibly mangled by host page CSS after inline isolation.

### Candid Developer Note

The original implementation had a classic "works in our DOM, therefore it works in the web" mistake. Injecting UI into arbitrary browser pages is hostile territory. The host page is not a polite guesthouse for our tiny button; it is a CSS knife fight. Depending on a global stylesheet, a pseudo-element, and one `selectionchange` event was optimistic bordering on ceremonial.

The element picker was the clue because it did the unglamorous thing correctly: inject late, style inline, keep the UI self-contained, and avoid extra dependencies. The comments code should have copied that posture from the start instead of building a delicate little CSS garden in someone else's page.

## Follow-Up Review Findings

After the browser/HTML fix, I reviewed the full changed worktree. The branch still has several correctness issues that should be fixed before this ships.

### High Severity

1. Comments are scoped to the first vibespace, not the active vibespace.
   - `projects/crispyvibes/crispyvibes/App/AppContainer.swift:161`
   - `projects/crispyvibes/crispyvibes/Features/AgentCLI/CLICommandRouterCommentsHandlers.swift:120`
   - `projects/crispyvibes/crispyvibes/Features/AgentCLI/CLICommandRouterCommentsHandlers.swift:288`
   - The code comments say the store is bound to the focused/active vibespace, but the resolver uses `vibespaces.first`. In multi-vibespace sessions this can silently read and write comments against the wrong vibespace.

2. File rename handling does not migrate comments.
   - `projects/crispyvibes/crispyvibes/Features/Editor/Comments/Services/CommentLifecycleCoordinator.swift:98`
   - `projects/crispyvibes/rust/crispyvibes-persistence/src/handlers_comments.rs:685`
   - The lifecycle coordinator only refreshes the cache and says `comment.movePath` is future work. The helper already implements `comment.movePath`, so rename/move behavior currently does not satisfy the "comments follow file moves" requirement.

3. CLI replies to browser comments are persisted as file comments.
   - `projects/crispyvibes/crispyvibes/Features/AgentCLI/CLICommandRouterCommentsHandlers.swift:177`
   - The reply path inherits the parent path and anchor but omits `surfaceKind`, so `store.add` falls back to `.file`. Replies to browser/HTML comments can become mismatched records.

### Medium Severity

1. CLI comment output drops browser anchor metadata.
   - `projects/crispyvibes/crispyvibes/Features/AgentCLI/CLICommandRouterCommentsHandlers.swift:322`
   - `encodeComment` omits `surfaceKind`, DOM selector, DOM offsets, and fingerprint. Agents listing or searching comments cannot distinguish file comments from browser comments or round-trip browser anchors.

2. The sanitizer does not do what the comment claims.
   - `projects/crispyvibes/rust/crispyvibes-persistence/src/handlers_comments.rs:25`
   - `projects/crispyvibes/rust/crispyvibes-persistence/src/handlers_comments.rs:724`
   - The implementation removes only the opening dangerous tag, not the full tag pair/content. The test only checks that `<script` is absent, so `alert(1)</script>` still passes.

3. Unit tests are currently red.
   - `projects/crispyvibes/tests/unit/Features/ContentViewer/ViewModels/ContentViewerStoreTests.swift:333`
   - Command run:

```bash
xcodebuild test -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes -destination 'platform=macOS' -only-testing:CrispyVibesUnitTests
```

   - Result: 1086 tests executed, 1 failure.
   - Failing test: `ContentViewerStoreTests.testDeletedGitPreviewTabReactivatesViaGitContentInsteadOfDiskRead`.

### Low Severity / Cleanup

1. The branch deletes a large unrelated `.kiro` documentation tree.
   - `git status` shows 30 deleted `.kiro/...` files, roughly 5k removed lines.
   - This appears unrelated to F049 and should be restored unless it is intentionally part of this branch.

2. A user-facing context menu string bypasses `AppStrings`.
   - `projects/crispyvibes/crispyvibes/Features/Editor/Views/CodeEditorView.swift:374`
   - `"Add Comment to Selection"` should move through the localization string path used elsewhere.

3. Changed browser bridge code still emits actor-isolation warnings.
   - `projects/crispyvibes/crispyvibes/Features/Editor/Comments/Services/BrowserSurfaceBridge.swift`
   - The build currently succeeds, but these warnings are future Swift 6 errors and should be cleaned up while this code is fresh.

### Review Summary

The UI injection issue is fixed, but the broader F049 branch still has data-scoping, lifecycle, CLI API, and test-health problems. The most serious pattern is the implementation repeatedly saying "active vibespace" while using `vibespaces.first`; that is exactly the kind of bug that looks fine in a one-vibespace happy path and then quietly corrupts user expectations in real use.
