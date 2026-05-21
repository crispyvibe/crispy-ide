# F039 Document Buffer — Technical Design

## Overview

This document describes the architecture for replacing the shared `rawContent` model in `MarkdownViewModel` with per-document `DocumentBuffer` instances governed by a lifecycle state machine. The design eliminates file content erasure by making "save during loading" structurally unreachable.

## Architecture

### Type Inventory

| Type | Role | Location |
|------|------|----------|
| `BufferState` | Lifecycle state enum | `Features/Editor/Models/BufferState.swift` |
| `SaveToken` | Correlates save completion with in-flight save | `Features/Editor/Models/BufferState.swift` |
| `DocumentBuffer` | Per-file content + state machine + load task | `Features/Editor/Models/DocumentBuffer.swift` |
| `DocumentBufferStore` | Buffer registry + active buffer | `Features/Editor/ViewModels/DocumentBufferStore.swift` |
| `AutosaveScheduler` | Debounced save scheduling with flush | `Features/Editor/Services/AutosaveScheduler.swift` |

### Buffer Identity and Sharing

One `DocumentBuffer` exists per file identity (keyed by `FileDocumentReference.documentIdentity`). If the same file is open in two split panes, both `EditorGroupStore` instances observe the same buffer. The buffer is the single source of truth for that file's content — this prevents conflicting writes to the same path.

Reference counting: `DocumentBufferStore` tracks an open count per buffer. `openBuffer` increments, `closeBuffer` decrements. The buffer is disposed only when the count reaches zero.

### Dependency Graph

```
EditorGroupStore (1 per pane)
  └── MarkdownViewModel (1 per pane, existing, refactored)
        └── DocumentBufferStore (1 per vibespace, shared)
              ├── [String: DocumentBuffer] (1 per open file identity)
              └── AutosaveScheduler
                    └── PaneWorkerExecuting / FileContentProviding (existing)
```

### BufferState

The state machine is the load-bearing invariant. All content mutations flow through it.

```swift
@MainActor
enum BufferState: Equatable {
    case loading
    case clean(content: String)
    case dirty(content: String, baseline: String)
    case saving(content: String, baseline: String, token: SaveToken)
    case failed(message: String)
}
```

`SaveToken` correlates a save completion with the specific save that produced it:

```swift
struct SaveToken: Equatable {
    let id: UUID
    let content: String
}
```

State transition diagram:

```
                    ┌─────────────────────────────────────────────┐
                    │                                             │
                    ▼                                             │
  ┌─────────┐  read ok   ┌───────────┐  user edit  ┌──────────┐ │
  │ loading ├────────────►│   clean   ├────────────►│  dirty   │ │
  └────┬────┘             └─────┬─────┘             └────┬─────┘ │
       │                        │                        │       │
       │ read fail              │ external change        │ begin save
       ▼                        │ (reload)               ▼       │
  ┌─────────┐                   │                  ┌──────────┐  │
  │ failed  │                   └──────────────┐   │  saving  ├──┘
  └─────────┘                                  │   └────┬─────┘  save ok
                                               │        │        (no edits
                                               │        │ edit    during save)
                                               │        │ during
                                               │        │ save
                                               │        ▼
                                               │   ┌──────────┐
                                               └──►│  dirty   │
                                                   └──────────┘
```

Transition rules:

| From | Event | To | Guard |
|------|-------|----|-------|
| `loading` | read succeeded | `clean(content)` | — |
| `loading` | read failed | `failed(message)` | — |
| `loading` | user edit | **rejected** | edits blocked |
| `loading` | save requested | **rejected** | saves blocked |
| `clean(c)` | user edit `e` where `e ≠ c` | `dirty(e, baseline: c)` | — |
| `clean(c)` | user edit `e` where `e = c` | `clean(c)` (no-op) | — |
| `clean(c)` | external change `c'` | `clean(c')` | — |
| `dirty(c, b)` | user edit `e` where `e = b` | `clean(b)` | undo to baseline |
| `dirty(c, b)` | user edit `e` where `e ≠ b` | `dirty(e, b)` | — |
| `dirty(c, b)` | begin save | `saving(c, b, token)` | token minted |
| `dirty(c, b)` | external change | **rejected** | user edits preserved |
| `saving(c, b, t)` | save succeeded with token `t` (no edits during save) | `clean(c)` | state still `.saving` |
| `saving(c, b, t)` | user edit `e` during save | `dirty(e, b)` | token `t` remains valid (not stale) |
| `dirty(e, b)` | save succeeded with token `t` (edits arrived during save) | `dirty(e, t.content)` | baseline updated to saved content |
| `saving(c, b, t)` | save failed with token `t` | `dirty(c, b)` | retry on next cycle |
| `dirty(e, b)` | save failed with token `t` | `dirty(e, b)` | no baseline change |
| any state | `didSave`/`didFailSave` with non-matching token | **ignored** | stale token from superseded save cycle |
| `failed` | retry / reopen | `loading` | — |

Token lifecycle: a token becomes stale only when `beginSave()` mints a new token (a new save cycle starts). An edit arriving during save does NOT invalidate the token — the in-flight save is still writing valid content to disk, and its completion must update the baseline.

### DocumentBuffer

Each buffer owns its load task and enforces all state transitions.

```swift
@MainActor
final class DocumentBuffer: ObservableObject, Identifiable {
    let id: String                          // documentIdentity
    let fileURL: URL
    let documentReference: FileDocumentReference

    @Published private(set) var state: BufferState = .loading
    private var loadTask: Task<Void, Never>?
    private var activeSaveToken: SaveToken?

    // MARK: - Computed properties

    /// Content for view binding. Returns "" during loading/failed — but the view
    /// layer MUST NOT push this to NSTextView during loading (see "Editor Surface
    /// Contract" below). This value is only meaningful in clean/dirty/saving states.
    var displayContent: String

    var isDirty: Bool
    var isLoading: Bool
    var isFailed: Bool

    /// Last known disk content. Nil during loading/failed.
    var baseline: String?

    // MARK: - Load task management

    /// Starts an async file read. Cancels any in-flight load task first.
    /// The caller provides the read closure; the buffer owns the Task.
    func beginLoad(read: @escaping () async throws -> String)

    /// Cancels the in-flight load task. Called on close or reopen.
    func cancelLoad()

    // MARK: - State transitions

    /// Called when file read completes. Only accepted if still in .loading.
    func didLoad(content: String)

    /// Called when file read fails. Only accepted if still in .loading.
    func didFailLoad(message: String)

    /// Called when the user edits content. No-op in loading/failed.
    func applyEdit(_ content: String)

    /// Mints a SaveToken and transitions to .saving. Returns nil if not dirty.
    func beginSave() -> SaveToken?

    /// Called when save succeeds. Token must match activeSaveToken.
    func didSave(token: SaveToken)

    /// Called when save fails. Token must match activeSaveToken.
    func didFailSave(token: SaveToken)

    /// Called on external file change. Only accepted in .clean state.
    func externalContentChanged(_ content: String)

    /// User-initiated revert. Cancels load task, transitions to .loading.
    func beginReload(read: @escaping () async throws -> String)
}
```

`beginLoad` implementation sketch:

```swift
func beginLoad(read: @escaping () async throws -> String) {
    cancelLoad()
    state = .loading
    loadTask = Task { [weak self] in
        do {
            let content = try await read()
            guard !Task.isCancelled else { return }
            self?.didLoad(content: content)
        } catch {
            guard !Task.isCancelled else { return }
            self?.didFailLoad(message: error.localizedDescription)
        }
    }
}

func cancelLoad() {
    loadTask?.cancel()
    loadTask = nil
}
```

`beginSave` / `didSave` with token correlation:

```swift
func beginSave() -> SaveToken? {
    guard case .dirty(let content, let baseline) = state else { return nil }
    let token = SaveToken(id: UUID(), content: content)
    activeSaveToken = token
    state = .saving(content: content, baseline: baseline, token: token)
    return token
}

func applyEdit(_ content: String) {
    switch state {
    case .clean(let baseline):
        if content != baseline {
            state = .dirty(content: content, baseline: baseline)
        }
    case .dirty(_, let baseline):
        if content == baseline {
            state = .clean(content: baseline)
        } else {
            state = .dirty(content: content, baseline: baseline)
        }
    case .saving(_, let baseline, _):
        // Edit during save — exit .saving but keep activeSaveToken valid.
        // The in-flight save is still writing valid content to disk.
        state = .dirty(content: content, baseline: baseline)
    case .loading, .failed:
        return
    }
}

func didSave(token: SaveToken) {
    guard token == activeSaveToken else { return }  // stale token from superseded save
    activeSaveToken = nil
    switch state {
    case .saving(let current, _, _):
        // No edits arrived during save — content on disk matches buffer
        state = .clean(content: current)
    case .dirty(let current, _):
        // Edits arrived during save — update baseline to what was saved
        state = .dirty(content: current, baseline: token.content)
    default:
        break
    }
}

func didFailSave(token: SaveToken) {
    guard token == activeSaveToken else { return }  // stale token
    activeSaveToken = nil
    switch state {
    case .saving(let content, let baseline, _):
        state = .dirty(content: content, baseline: baseline)
    case .dirty:
        break  // already dirty from edit-during-save, baseline unchanged
    default:
        break
    }
}
```

### DocumentBufferStore

Manages buffer lifecycle with reference counting for shared-buffer-across-panes.

```swift
@MainActor
final class DocumentBufferStore: ObservableObject {
    @Published private(set) var buffers: [String: DocumentBuffer] = [:]
    private var refCounts: [String: Int] = [:]

    /// Returns existing buffer (incrementing refCount) or creates a new one in .loading state.
    /// If the buffer already exists and is not in .failed state, the existing buffer is returned
    /// as-is — no load restart. If the buffer is in .failed state, the caller may retry via
    /// buffer.beginReload().
    ///
    /// This means a second pane opening the same file attaches to the existing buffer and its
    /// in-flight load task. Only explicit user actions (revert, retry) cancel and restart loads.
    func openBuffer(for reference: FileDocumentReference) -> DocumentBuffer

    /// Decrements reference count. When count reaches zero:
    /// - If dirty, flushes via the provided writer before disposal.
    /// - Cancels any in-flight load task.
    /// - Removes buffer from registry.
    /// Returns a Task that completes when disposal (including flush) is done.
    /// If flush fails, the buffer is still disposed (best-effort save) and the error
    /// is returned to the caller via the task.
    @discardableResult
    func closeBuffer(
        id: String,
        writer: ((URL, SaveToken) async throws -> Void)? = nil
    ) -> Task<Error?, Never>?

    func buffer(for id: String) -> DocumentBuffer?
}
```

`closeBuffer` returns an optional `Task<Error?, Never>` so callers that need to know whether the flush succeeded can inspect the result. The buffer stays alive until the flush completes. If the write throws, `didFailSave` is called and the error is returned — but the buffer is still disposed (the tab is already gone from the UI, keeping a phantom buffer alive is worse).

```swift
@discardableResult
func closeBuffer(
    id: String,
    writer: ((URL, SaveToken) async throws -> Void)? = nil
) -> Task<Error?, Never>? {
    guard let count = refCounts[id] else { return nil }
    let newCount = count - 1
    if newCount > 0 {
        refCounts[id] = newCount
        return nil
    }

    // Last reference — dispose
    guard let buffer = buffers[id] else {
        refCounts.removeValue(forKey: id)
        return nil
    }

    buffer.cancelLoad()

    if buffer.isDirty, let writer {
        return Task {
            var flushError: Error? = nil
            if let token = buffer.beginSave() {
                do {
                    try await writer(buffer.fileURL, token)
                    buffer.didSave(token: token)
                } catch {
                    buffer.didFailSave(token: token)
                    flushError = error
                }
            }
            self.buffers.removeValue(forKey: id)
            self.refCounts.removeValue(forKey: id)
            return flushError
        }
    }

    buffers.removeValue(forKey: id)
    refCounts.removeValue(forKey: id)
    return nil
}
```

### AutosaveScheduler

Extracted from `MarkdownViewModel`. Independently testable. Operates only on dirty buffers.

```swift
@MainActor
final class AutosaveScheduler {
    private var pendingWork: [String: DispatchWorkItem] = [:]
    private let delay: TimeInterval
    private let writer: (URL, SaveToken) async throws -> Void

    init(
        delay: TimeInterval = 0.45,
        writer: @escaping (URL, SaveToken) async throws -> Void
    )

    /// Schedules a debounced save. No-op if buffer is not dirty.
    func scheduleSave(for buffer: DocumentBuffer)

    /// Cancels a pending debounced save without executing it.
    func cancel(for bufferID: String)

    func cancelAll()
}
```

`scheduleSave` with token and content integrity guard:

```swift
func scheduleSave(for buffer: DocumentBuffer) {
    guard buffer.isDirty else { return }
    cancel(for: buffer.id)
    let workItem = DispatchWorkItem { [weak self, weak buffer] in
        guard let self, let buffer else { return }
        Task { @MainActor in
            guard let token = buffer.beginSave() else { return }
            // F039-R04: Content integrity guard
            guard !token.content.isEmpty || (buffer.baseline?.isEmpty ?? true) else {
                buffer.didFailSave(token: token)
                return
            }
            do {
                try await self.writer(buffer.fileURL, token)
                buffer.didSave(token: token)
            } catch {
                buffer.didFailSave(token: token)
            }
        }
    }
    pendingWork[buffer.id] = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
}
```

## Editor Surface Contract

This section resolves the interaction between `displayContent`, the NSTextView/WKWebView, and the loading state. The rule is:

> **The editor surface MUST NOT assign content to `NSTextView.string` or inject content into `WKWebView` when the active buffer is in `.loading` or `.failed` state.**

The view layer enforces this, not the buffer. The buffer's `displayContent` returns `""` during loading as a safe default for SwiftUI views that render non-editable UI (loading indicators, error messages). But the `NSViewRepresentable.updateNSView` implementations must check `isLoading`/`isFailed` and skip the content assignment:

```swift
// CodeEditorView.updateNSView
func updateNSView(_ nsView: NSScrollView, context: Context) {
    guard let textView = nsView.documentView as? ContentViewerDropAwareTextView else { return }

    // CRITICAL: Do not push content during loading — prevents empty-content feedback loop
    guard !isBufferLoading else {
        textView.isEditable = false
        return
    }
    textView.isEditable = true

    if textView.string != content {
        textView.string = content
        // ... selection restore, highlighting, etc.
    }
}
```

For `MarkupRenderedEditor.syncContentToEditor`:

```swift
func syncContentToEditor(force: Bool = false) {
    guard isEditorReady, let webView else { return }
    guard !parent.isBufferLoading else { return }  // don't inject during loading
    // ... existing injection logic
}
```

What the user sees during loading:
- The NSTextView/WKWebView retains whatever content it had before (stale content from previous tab, or empty from initial creation).
- An overlay loading indicator is shown (driven by `workerStatus = .busy("Opening file")`).
- The editor is not editable (`textView.isEditable = false`).
- When the buffer transitions to `.clean`, `updateNSView` fires again, pushes the real content, and enables editing.

This is consistent with the current behavior where `workerStatus = .busy("Opening file")` is already set during file reads. The only change is that the NSTextView content assignment is gated on buffer state.

## Data Flow

### File Open (replaces current `openFile`)

```
User clicks file B
  │
  ├── EditorGroupStore.openFileInTab(at: urlB)
  │     ├── bufferStore.openBuffer(for: referenceB)
  │     │     ├── If buffer exists: increment refCount, return existing buffer
  │     │     └── If new: create DocumentBuffer in .loading, store, refCount = 1
  │     ├── viewModel.activateBuffer(referenceB.documentIdentity)
  │     └── buffer.beginLoad(read: { try await worker.readFile(...) })
  │           ├── Cancels any previous load task on this buffer
  │           └── Stores new Task in buffer.loadTask
  │
  ├── SwiftUI observes activeBuffer change
  │     ├── updateNSView checks buffer.isLoading → true
  │     ├── textView.isEditable = false (no content assignment)
  │     ├── Loading overlay shown via workerStatus
  │     └── No textDidChange fires — NSTextView content untouched
  │
  └── Async read completes
        ├── Task checks !Task.isCancelled (guards stale reads)
        ├── buffer.didLoad(content: fileContent)
        │     └── Only accepted if buffer is still in .loading
        ├── buffer.state → .clean(content: fileContent)
        ├── SwiftUI observes state change
        ├── updateNSView checks buffer.isLoading → false
        ├── textView.string = fileContent (real content assigned)
        ├── textView.isEditable = true
        └── Loading overlay dismissed
```

### Rapid Tab Switching / Close-Reopen

```
User opens file B, then immediately switches to file C
  │
  ├── buffer B created, beginLoad starts Task-B
  ├── User switches to C → buffer C created, beginLoad starts Task-C
  │     └── activeBufferID changes to C; B's buffer and Task-B still alive
  │
  ├── Task-B completes → buffer B.didLoad(content)
  │     └── B is now .clean but not active — no view update
  │
  ├── Task-C completes → buffer C.didLoad(content)
  │     └── C is active — view updates with C's content
  │
  └── If user closes C before Task-C completes:
        ├── closeBuffer(C) → cancelLoad() cancels Task-C
        ├── Buffer C removed (refCount 0, not dirty, no flush needed)
        └── Task-C's guard (!Task.isCancelled) prevents didLoad on dead buffer
```

### User Edit

```
User types in editor
  │
  ├── textDidChange / contentChanged fires
  │     └── viewModel.userDidEdit(newContent)
  │           ├── activeBuffer.applyEdit(newContent)
  │           │     ├── .clean → .dirty(newContent, baseline)
  │           │     ├── .loading → rejected (no-op)
  │           │     └── .saving → .dirty(newContent, baseline) — exits saving
  │           └── autosave.scheduleSave(for: activeBuffer)
  │                 └── Only proceeds if buffer.isDirty
  │
  └── After 0.45s debounce
        ├── token = buffer.beginSave() → mints SaveToken, state → .saving
        ├── Content integrity check (token.content not empty or baseline was empty)
        ├── Write to disk via worker/fileContentProvider
        ├── buffer.didSave(token: token)
        │     ├── Token matches activeSaveToken → accepted
        │     ├── State was .saving (no edits during save) → .clean
        │     └── State was .dirty (edits during save) → .dirty with updated baseline
        └── If token doesn't match → completion ignored (stale save)
```

### Tab Close with Dirty Buffer

```
User closes tab for file A (dirty buffer)
  │
  ├── EditorGroupStore.closeTab(tabA.id)
  │     └── bufferStore.closeBuffer(id: bufferA.id, writer: { url, token in
  │               try await worker.writeFile(at: url.path, contents: token.content)
  │           })
  │
  ├── closeBuffer decrements refCount
  │     ├── If refCount > 0 (file open in another pane): no disposal, return nil
  │     └── If refCount == 0:
  │           ├── buffer.cancelLoad()
  │           ├── buffer.isDirty → true → flush via writer
  │           ├── Returns Task<Error?, Never> that:
  │           │     ├── Calls beginSave → gets token
  │           │     ├── Calls writer(url, token) — may throw
  │           │     ├── On success: calls didSave(token:), removes buffer
  │           │     └── On failure: calls didFailSave(token:), removes buffer, returns error
  │           └── Buffer stays alive until Task completes
  │
  └── Tab removed from UI immediately; flush happens in background
```

### WKWebView Crash Recovery

```
WebContent process terminates
  │
  ├── webViewWebContentProcessDidTerminate fires
  │     ├── Reloads editor HTML
  │     └── Does NOT touch the buffer — buffer retains its state
  │
  ├── editorReady fires
  │     ├── Checks buffer.isLoading → false (buffer is clean or dirty)
  │     ├── syncContentToEditor injects buffer.displayContent (real content)
  │     └── Buffer content was never lost
  │
  └── contentChanged fires with the re-injected content
        └── applyEdit detects content == baseline → no-op (stays clean)
           OR content matches current dirty content → no state change
```

### External File Change

```
File watcher detects change
  │
  ├── Check buffer state
  │     ├── .clean → buffer.externalContentChanged(newDiskContent)
  │     │            State stays .clean with updated content
  │     ├── .dirty → rejected (user edits preserved)
  │     ├── .saving → rejected (save in flight)
  │     └── .loading → rejected (load in progress)
  │
  └── If reloaded, SwiftUI observes content change → editor updates
```

## State Management

### MarkdownViewModel Changes

`MarkdownViewModel` retains its role as the view-facing coordinator but delegates content management to `DocumentBufferStore`. Properties that move into `DocumentBuffer`:

| Current property | Moves to |
|-----------------|----------|
| `rawContent` | `DocumentBuffer.state` (via `displayContent`) |
| `lastSavedContent` | `DocumentBuffer.state` (via `baseline`) |
| `hasUnsavedTextChanges` | `DocumentBuffer.isDirty` |
| `autosaveWorkItem` | `AutosaveScheduler.pendingWork` |
| `openRequestID` | Replaced by `DocumentBuffer.loadTask` + `Task.isCancelled` |
| `openFileTask` | `DocumentBuffer.loadTask` (per-buffer, owned by buffer) |
| `lastSaveDate` | `DocumentBuffer` (per-buffer) |

Properties that stay on `MarkdownViewModel`:

| Property | Reason |
|----------|--------|
| `documentType` | View-layer concern (determines which editor plugin renders) |
| `fileURL` | Convenience accessor (delegates to active buffer) |
| `editorTabs` | Tab strip model (unchanged) |
| `activeEditorTabID` | Tab selection (synced with active buffer) |
| `workerStatus` | View-layer loading/error indicator |
| `markupViewModeByDocumentID` | Per-document view preference (not content) |
| `pendingSourceSelection` | View-layer cursor positioning |
| `imageFileURL`, `pdfFileURL` | Non-editable preview state |
| `hasUnsavedImageEdits` | Raster image editing (separate from text buffer) |

### View Binding Changes

Current:
```swift
// MarkdownEditorPlugins.swift — rich editor
content: Binding(
    get: { viewModel.rawContent },
    set: { viewModel.updateEditableContentFromRenderer($0) }
)

// MarkdownEditorPlugins.swift — source editor
content: Binding(
    get: { viewModel.rawContent },
    set: { _ in }
),
onContentChange: { newContent in
    viewModel.updateEditableContentFromRenderer(newContent)
}
```

After migration:
```swift
// Rich editor
content: Binding(
    get: { viewModel.displayContent },
    set: { viewModel.userDidEdit($0) }
)

// Source editor
content: Binding(
    get: { viewModel.displayContent },
    set: { _ in }
),
onContentChange: { newContent in
    viewModel.userDidEdit(newContent)
}
```

The view model exposes thin forwarding properties:

```swift
extension MarkdownViewModel {
    var displayContent: String {
        bufferStore.activeBuffer?.displayContent ?? ""
    }

    var isBufferLoading: Bool {
        bufferStore.activeBuffer?.isLoading ?? false
    }

    func userDidEdit(_ content: String) {
        guard let buffer = bufferStore.activeBuffer else { return }
        buffer.applyEdit(content)
        if buffer.isDirty {
            autosave.scheduleSave(for: buffer)
        }
    }
}
```

## API / Command Contracts

No new pane worker commands. File read/write operations are unchanged:

| Command | Timeout | Used by |
|---------|---------|---------|
| `.readFile` | 10 s | `DocumentBuffer.beginLoad` (buffer load) |
| `.writeFile` | 10 s | `AutosaveScheduler` / flush (buffer save) |
| `FileContentProviding.readFile` | — | Remote file read (SSH) |
| `FileContentProviding.writeFile` | — | Remote file write (SSH) |

## Dependencies (frameworks, libraries)

No new external dependencies. All new types are pure Swift with `@MainActor` isolation.

## Platform Considerations

- `NSTextView.string` assignment triggers `textDidChange` in the delegate. The `updateNSView` implementations MUST check `isBufferLoading` and skip content assignment during loading (see "Editor Surface Contract" above).
- `WKWebView` content injection via `syncContentToEditor` MUST check `isBufferLoading` and skip injection during loading.
- `WKWebView` crash recovery (`webViewWebContentProcessDidTerminate`) MUST NOT reset buffer state — the buffer is the source of truth, not the web view.

## Performance Constraints

- Buffer creation is synchronous and lightweight (no file I/O).
- Per-buffer memory: one `String` for content + one `String` for baseline. For a 1 MB file, this is ~2 MB per buffer. Acceptable for typical editor usage (< 20 open files).
- Autosave debounce remains 0.45 s.
- No change to file read/write timeouts (10 s).
- Reference counting adds negligible overhead (dictionary lookup per open/close).

## Migration Plan

The migration is designed to be incremental — new types are built alongside existing code, and `MarkdownViewModel` is migrated method by method.

### Phase 1: New Types (additive, no existing code changes)

1. Create `BufferState.swift` and `SaveToken` — enum with `Equatable` conformance.
2. Create `DocumentBuffer.swift` — state machine with all transition methods, load task ownership.
3. Create `AutosaveScheduler.swift` — extracted autosave logic with `scheduleSave`, `cancel`, `flush`.
4. Create `DocumentBufferStore.swift` — buffer registry with reference counting.
5. Write unit tests for `DocumentBuffer` state transitions (all paths, including token correlation).
6. Write unit tests for `AutosaveScheduler` (scheduling, cancellation, flush, integrity guard).
7. Write property-based tests: "save is unreachable from loading" invariant.
8. Write unit tests for `DocumentBufferStore` reference counting and flush-on-dispose.

### Phase 2: Integration (modify MarkdownViewModel internals)

9. Add `DocumentBufferStore` (shared) and `AutosaveScheduler` as dependencies. Update `AppContainer`.
10. Migrate `openFile()` — use `bufferStore.openBuffer` + `buffer.beginLoad`. Remove `rawContent = ""` reset.
11. Migrate `openFileIfNeeded()` — check buffer existence instead of `currentDocumentID` comparison.
12. Migrate `updateEditableContentFromRenderer()` → delegate to `buffer.applyEdit()` + `autosave.scheduleSave()`.
13. Migrate `save()` → delegate to `autosave.flush()` or direct `buffer.beginSave()` + write + `buffer.didSave(token:)`.
14. Migrate `reloadCurrentEditableFile()` → `buffer.beginReload(read:)`.
15. Migrate `reloadIfFileChanged()` → `buffer.externalContentChanged()` with state guard.
16. Migrate `clearCurrentDocument()` → `bufferStore.closeBuffer()` with writer.
17. Migrate `closeEditorTab()` → `bufferStore.closeBuffer()` with writer.

### Phase 3: View Layer (update bindings)

18. Replace `rawContent` reads in `MarkdownEditorPlugins.swift` with `displayContent`.
19. Replace `updateEditableContentFromRenderer` calls with `userDidEdit`.
20. Add loading guard to `CodeEditorView.updateNSView` — skip `textView.string` assignment and disable editing when `isBufferLoading`.
21. Add loading guard to `PlainTextEditor.updateNSView` — same.
22. Add loading guard to `MarkupRenderedEditor.syncContentToEditor`.
23. Update `MarkupRenderedEditor.webViewWebContentProcessDidTerminate` — do not touch buffer state.

### Phase 4: Cleanup

24. Remove `rawContent`, `lastSavedContent`, `hasUnsavedTextChanges`, `autosaveWorkItem`, `openRequestID`, `openFileTask` from `MarkdownViewModel`.
25. Remove `scheduleAutosave()`, `updateEditableContentFromRenderer()`, `updateText()` methods.
26. Update `EditorGroupStore.syncMarkdownViewModelToTab` to use buffer activation instead of `openFileIfNeeded`.
27. Run full test suite — unit, behavioral, integration.
28. Manual testing: rapid tab switching, SSH file open, WKWebView crash (simulate via Activity Monitor), concurrent edit during save, same file in two split panes, close tab with dirty buffer.

### Phase Boundaries

- **Phase 1 can be merged independently.** No existing code is modified. New types + tests only.
- **Phase 2 + 3 are one atomic change.** The internal migration and view binding updates must ship together.
- **Phase 4 is cleanup.** Can be a separate PR after Phase 2+3 is validated.
