# Whiteboarding — Technical Design

## Overview

F052 hosts an offline [Excalidraw](https://excalidraw.com) build in a `WKWebView` and binds its scene JSON to Crispy's document buffer. It plugs into the existing editor plugin system as a new `DocumentType`, so `.excalidraw` files flow through the same open → buffer → autosave pipeline as markdown/code. Creation and relocation reuse the Shelf and its move-to-project plumbing.

## Architecture

```
Toolbar "New Whiteboard"  ──.newWhiteboard──▶ ContentView
                                               └─ createNewWhiteboardInShelf()
                                                    ├─ WhiteboardDocument.createUntitled(in: <AppSupport>/Whiteboards)
                                                    └─ openFilesInShelf([url])  (ShelfStore.addFiles + reveal + open)

Open .excalidraw ─▶ MarkdownViewModel (DocumentType.whiteboard) ─▶ DocumentBuffer ─▶ AutosaveScheduler
                          │
                          ▼  EditorPluginRegistry → WhiteboardEditorPlugin
                    WhiteboardEditorView (NSViewRepresentable)
                          │   binds viewModel.displayContent ⇄ userDidEdit
                          ▼
                    WKWebView  ◀── app-excalidraw://local/* ── ExcalidrawSchemeHandler ── Resources/ExcalidrawRuntime/
                          │   index.html → config.js, react, react-dom, excalidraw UMD, bridge.js
                          ▼
                    Excalidraw canvas  (onChange → debounced serialize → whiteboardChanged → content)

Shelf row drag ──ShelfItemDrag type──▶ AppKitTreeView (NSOutlineView) acceptDrop
                                          └──.shelfFileMoveToProjectRequested──▶ ContentView
                                                └─ moveShelfItemToProject(): flush → moveItem → retarget tab → remove from Shelf
```

## Data Flow

**Open / edit:** `MarkdownViewModelFileLifecycle.openFile` detects `.excalidraw` (→ `DocumentType.whiteboard`) and loads the file text into a `DocumentBuffer`. `WhiteboardEditorPlugin` makes a `WhiteboardEditorView` bound to `viewModel.displayContent` (get) / `viewModel.userDidEdit` (set). On `whiteboardReady`, Swift pushes the scene JSON into the canvas via `crispyvibesSetScene`. On every canvas edit, `bridge.js` debounces (600 ms), serializes with `ExcalidrawLib.serializeAsJSON`, and posts `whiteboardChanged`; the coordinator writes it to `content` → `userDidEdit` → buffer dirty → `AutosaveScheduler` writes the file. An echo guard (`lastInjectedScene` / `suppressChange`) prevents Swift-pushed scenes from being re-sent as edits.

**Create:** `createNewWhiteboardInShelf` writes `WhiteboardDocument.emptyScene` to `<AppSupport>/Whiteboards/Untitled Whiteboard[ N].excalidraw`, adds it to `ShelfStore`, and opens it.

**Move to project:** the Shelf row is a drag source carrying a private `com.crispyvibe.app.shelf-item` pasteboard type (the path is stashed in a main-actor `ShelfItemDrag.draggingPath` because custom-type data is unreliable to read back on an AppKit drop). The project tree's `NSOutlineView` accepts that type as a `.move` and posts `.shelfFileMoveToProjectRequested`. `moveShelfItemToProject` then: validates the target is inside an open project, flushes unsaved buffer edits to the source file, `moveItem`s it (uniquifying on collision), retargets the open tab via `contentViewerStore.retargetFileSystemLocation`, and removes the Shelf entry.

## API / Command Contracts

**Swift → JS** (`evaluateJavaScript`): `window.crispyvibesSetScene(jsonString)`, `window.crispyvibesSetTheme("light"|"dark")`.

**JS → Swift** (`WKScriptMessageHandler`): `whiteboardReady` (canvas mounted), `whiteboardChanged` (debounced scene JSON string), `whiteboardLog` (diagnostics).

**Local resource scheme:** `app-excalidraw://local/<path>` served by `ExcalidrawSchemeHandler` from `Resources/ExcalidrawRuntime/`, with symlink-resolved path containment, per-extension MIME types, and `X-Content-Type-Options: nosniff`. No agent CLI surface (deferred).

## State Management

- `MarkdownViewModel.DocumentType.whiteboard` — editable type; `isEditableDocumentType` includes it so autosave applies.
- `DocumentBuffer` holds the scene JSON; `flushUnsavedEdits(forFileURL:)` synchronously writes a dirty local buffer before a move.
- `ShelfItemDrag.draggingPath` — `@MainActor` drag holder, set at drag start, read+cleared on drop.
- Notifications: `.newWhiteboard`, `.shelfFileMoveToProjectRequested` (observed on `ContentView.body`).

## Dependencies (frameworks, libraries)

- `WebKit` (`WKWebView`, `WKURLSchemeHandler`).
- Vendored, pinned: `@excalidraw/excalidraw` 0.17.6 (MIT), `react`/`react-dom` 18.3.1. No Swift package dependencies added.
- Build: `projects/crispyvibes/web/excalidraw-runtime/{package.json, package-lock.json, build.sh}`; `build.sh` runs `npm ci` and copies the UMD bundle + `excalidraw-assets/` (fonts, locales, vendor chunk) into `Resources/ExcalidrawRuntime/`. `index.html`, `config.js`, `bridge.js` are hand-authored and not overwritten by the build. The runtime folder is bundled as an Xcode **folder reference** to preserve the `excalidraw-assets/` subtree.

## Platform Considerations

- macOS only; the canvas is an AppKit-hosted `WKWebView`.
- A custom URL scheme is used instead of `file://` because WebKit blocks `fetch()` of `file://` resources, which Excalidraw uses to load locale chunks.
- The project file tree is an AppKit `NSOutlineView` (`AppKitTreeView`); the shelf drop is handled in its `validateDrop`/`acceptDrop`, not the SwiftUI container `onDrop`.

## Performance Constraints

- Bundle adds ~5.5 MB (UMD ~1.1 MB + assets ~4.2 MB), comparable to the existing mermaid bundle. Loaded lazily only when a whiteboard opens.
- Autosave is debounced (600 ms in JS) to coalesce rapid edits.

## Migration / Rollout Notes

- No persistence migration: whiteboards are plain files; the Shelf already persists arbitrary file paths.
- No feature flag — shipped on by default (the experimental gate discussed in planning was dropped per product decision).
- Verification: `xcodebuild -scheme crispyvibes-local` builds; runtime reproducibility via `web/excalidraw-runtime/build.sh`.

## Known Gaps / Follow-ups

- Residual data-loss window: the pre-move flush covers buffered edits; a sub-second JS debounce window (edits not yet posted to Swift) remains — negligible during a manual drag.
- Moving relocates the editor tab via a path-based view identity, causing a brief canvas remount (content preserved, not lost).
- No `whiteboard.*` agent CLI yet.
- Multi-surface concurrent editing of one whiteboard reloads per surface (no shared live-canvas arbiter).
