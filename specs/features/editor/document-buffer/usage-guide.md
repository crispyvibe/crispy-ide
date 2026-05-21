---
title: Document Buffer System
description: Internal architecture for per-document content buffers with lifecycle state machine.
audience: developer
---

# F039 Document Buffer — Usage Guide

> This is an internal infrastructure feature. There are no user-facing workflows. This guide is for developers working on the editor subsystem.

## When to Use DocumentBuffer

Any code that reads or writes file content in the editor must go through the `DocumentBuffer` API. Direct mutation of content strings is not allowed.

### Opening a File

```swift
// Do this:
let buffer = bufferStore.openBuffer(for: reference)
// buffer starts in .loading — editor shows loading state
// async read completes → buffer.didLoad(content:) → editor shows content

// Don't do this:
rawContent = ""  // ← NEVER reset content directly
```

### Handling User Edits

```swift
// In view model, called by editor surface callbacks:
func userDidEdit(_ content: String) {
    guard let buffer = bufferStore.activeBuffer else { return }
    buffer.applyEdit(content)
    if buffer.isDirty {
        autosave.scheduleSave(for: buffer)
    }
}
```

`applyEdit` is safe to call in any state — it's a no-op during `loading` and `failed`.

### Saving

Never call file write operations directly. Use the autosave scheduler or manual save path:

```swift
// Autosave (debounced) — scheduler handles beginSave/didSave/didFailSave internally:
autosave.scheduleSave(for: buffer)

// Manual save (Cmd+S):
guard let token = buffer.beginSave() else { return }
do {
    try await writer(buffer.fileURL, token)
    buffer.didSave(token: token)
} catch {
    buffer.didFailSave(token: token)
}
```

`beginSave()` returns `nil` if the buffer isn't dirty — this is the gating mechanism. The `SaveToken` correlates the completion with the specific save — a token becomes stale only when `beginSave()` mints a new one (a new save cycle starts), not when an edit arrives during save.

### Checking Buffer State

```swift
buffer.isLoading    // true during file read
buffer.isDirty      // true when user has unsaved edits
buffer.displayContent  // safe to read in any state
buffer.baseline     // last known disk content (nil during loading)
```

## State Machine Rules

1. **Saves are only reachable from `dirty`.** If `beginSave()` returns `nil`, don't write.
2. **Edits are rejected during `loading`.** The editor surface must not be editable until `didLoad` is called.
3. **External changes are rejected during `dirty`/`saving`.** User edits always win.
4. **Save failure returns to `dirty`.** The autosave scheduler will retry on the next cycle.
5. **Save completions are token-correlated.** A token becomes stale only when `beginSave()` mints a new token (a new save cycle). An edit during save does NOT invalidate the token — the in-flight write is still valid, and its completion updates the baseline. `didSave(token:)` and `didFailSave(token:)` are ignored only if the token doesn't match `activeSaveToken`.
6. **The view layer must not push content during loading.** `updateNSView` checks `isBufferLoading` and skips `textView.string` assignment. This prevents the empty-content feedback loop.
7. **Buffers are reference-counted.** Same file in two panes shares one buffer. Disposal only happens when refCount hits zero, after flushing dirty content.

## Testing

### Unit Testing a Buffer

```swift
func test_editDuringLoading_isRejected() {
    let buffer = DocumentBuffer(reference: makeReference())
    // buffer starts in .loading
    buffer.applyEdit("should be ignored")
    XCTAssertTrue(buffer.isLoading)
    XCTAssertEqual(buffer.displayContent, "")
}

func test_saveBlockedDuringLoading() {
    let buffer = DocumentBuffer(reference: makeReference())
    XCTAssertNil(buffer.beginSave())
}

func test_dirtyToSavingToClean() {
    let buffer = DocumentBuffer(reference: makeReference())
    buffer.didLoad(content: "hello")
    buffer.applyEdit("hello world")
    XCTAssertTrue(buffer.isDirty)

    let token = buffer.beginSave()!
    XCTAssertEqual(token.content, "hello world")

    buffer.didSave(token: token)
    XCTAssertFalse(buffer.isDirty)
    XCTAssertEqual(buffer.displayContent, "hello world")
}

func test_staleSaveTokenIsIgnored() {
    let buffer = DocumentBuffer(reference: makeReference())
    buffer.didLoad(content: "hello")
    buffer.applyEdit("v1")

    let token1 = buffer.beginSave()!
    // User edits during save — buffer exits .saving to .dirty,
    // but token1 is still valid (the save is still writing "v1" to disk)
    buffer.applyEdit("v2")
    XCTAssertTrue(buffer.isDirty)

    // Save completes — baseline updates to "v1" (what was written to disk)
    buffer.didSave(token: token1)
    XCTAssertTrue(buffer.isDirty)  // still dirty because "v2" ≠ "v1"
    XCTAssertEqual(buffer.displayContent, "v2")
    XCTAssertEqual(buffer.baseline, "v1")  // baseline updated
}

func test_trulyStaleSaveTokenIsIgnored() {
    let buffer = DocumentBuffer(reference: makeReference())
    buffer.didLoad(content: "hello")
    buffer.applyEdit("v1")

    let token1 = buffer.beginSave()!
    buffer.didSave(token: token1)  // save 1 completes → clean

    buffer.applyEdit("v2")
    let token2 = buffer.beginSave()!  // new save cycle → token1 is now stale

    // Phantom completion from token1 arrives (should not happen, but defensive)
    buffer.didSave(token: token1)
    // Must be ignored — token2 is the active token
    XCTAssertEqual(buffer.baseline, "v1")  // not updated by stale token
}
```

### Testing the Autosave Scheduler

Inject a mock save handler to verify scheduling behavior without disk I/O:

```swift
func test_autosaveOnlyFiresForDirtyBuffers() {
    var savedBufferIDs: [String] = []
    let scheduler = AutosaveScheduler(delay: 0.01) { buffer in
        savedBufferIDs.append(buffer.id)
    }

    let buffer = DocumentBuffer(reference: makeReference())
    buffer.didLoad(content: "hello")
    // buffer is clean — scheduleSave should be a no-op
    scheduler.scheduleSave(for: buffer)

    // wait for debounce...
    XCTAssertTrue(savedBufferIDs.isEmpty)
}
```

## Common Mistakes

| Mistake | Why it's wrong | Correct approach |
|---------|---------------|-----------------|
| Setting `rawContent = ""` before async read | Creates autosave race — empty content can be saved to disk | Create buffer in `.loading` state; content is never empty-assigned |
| Calling `save()` without checking buffer state | Can write stale/empty content | Use `beginSave()` which returns `nil` if not dirty |
| Reading `rawContent` directly in views | Bypasses state machine, sees transitional empty state | Read `displayContent` which is safe in all states |
| Pushing content to `NSTextView` during loading | Triggers `textDidChange` with empty string | Check `isBufferLoading` in `updateNSView`, skip content push and disable editing |
| Ignoring `SaveToken` on completion | Stale save completion could corrupt state | Always pass token to `didSave(token:)` / `didFailSave(token:)` |
| Disposing buffer without flushing | Dirty content lost on tab close | Use `closeBuffer(id:, writer:)` which flushes before disposal; inspect returned `Task<Error?, Never>` if you need to know whether the flush succeeded |
