# F039 Document Buffer — Threat Model

## Overview

The document buffer system manages file content in memory and writes it to disk via autosave. The primary threat is data loss — either through content erasure (writing empty/wrong content) or content leakage (writing one file's content to another file's path).

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Buffer ↔ Editor Surface | Content flows bidirectionally between `DocumentBuffer` and `NSTextView`/`WKWebView`. The editor surface is untrusted — it can send empty or malformed content via `textDidChange`/`contentChanged`. |
| Buffer ↔ Disk | Writes go through `PaneWorkerExecuting` or `FileContentProviding`. The worker is trusted but may fail (timeout, crash, permission error). |
| Buffer ↔ File Watcher | External file changes arrive via `NotificationCenter`. The notification is trusted (comes from the app's own file watcher), but the timing is adversarial (can arrive during any buffer state). |
| Buffer ↔ WKWebView Process | The WebContent process is untrusted — macOS can terminate it at any time. Recovery must not lose buffer content. |

## Attack Surfaces

### AS-1: Editor Surface Feedback Loop
The `NSTextView`/`WKWebView` can fire content-change callbacks with empty or stale content during view transitions (SwiftUI re-render, document switch, crash recovery).

### AS-2: Autosave Timing
The autosave debounce window (0.45 s) creates a race between content transitions and disk writes.

### AS-3: Concurrent State Mutation
Multiple async operations (file read, file write, user edit, external change) can arrive in any order on the main actor.

### AS-4: File Content Provider Failure
Remote file operations (SSH) can fail silently, return partial content, or timeout.

## Threats

### F039-T01: Empty Content Write During File Open
- Vector: `openFile` resets content → editor surface fires `textDidChange("")` → autosave writes empty content.
- Impact: Complete file content loss.
- Likelihood: High (deterministic for slow file reads, e.g., SSH).
- Mitigation: Buffer state machine blocks saves during `loading` state (F039-R03). Content integrity guard rejects empty writes against non-empty baseline (F039-R04).

### F039-T02: Cross-Tab Content Write
- Vector: Shared `rawContent` property means tab A's content could be written to tab B's file path if tab switch and save interleave.
- Impact: File corruption (wrong content in wrong file).
- Likelihood: Medium (requires specific timing of tab switch + autosave).
- Mitigation: Per-buffer isolation (F039-R01). Each buffer owns its own `fileURL` and content. `beginSave()` returns content from the specific buffer, and the save handler writes to that buffer's `fileURL`.

### F039-T03: WKWebView Crash Sends Empty Content
- Vector: WebContent process terminates → editor reloads → `contentChanged("")` fires before content is re-injected.
- Impact: Buffer transitions to dirty with empty content → autosave writes empty.
- Likelihood: Medium (depends on macOS memory pressure).
- Mitigation: Buffer content is preserved across WKWebView crashes (F039-R08). The `contentChanged` callback goes through `applyEdit`, which is a no-op if content matches baseline or if buffer is in `loading` state during recovery.

### F039-T04: External Change Overwrites User Edits
- Vector: File watcher fires while user has unsaved edits → reload overwrites `rawContent`.
- Impact: Loss of unsaved user edits.
- Likelihood: Medium (common with formatters, git operations).
- Mitigation: `externalContentChanged` is rejected when buffer is `dirty` or `saving` (F039-R07).

### F039-T05: Save Failure Leaves Buffer in Wrong State
- Vector: Disk write fails (permissions, full disk, SSH disconnect) → buffer state desyncs from disk.
- Impact: User believes content is saved but it isn't, or buffer gets stuck in `saving` state.
- Likelihood: Low-Medium.
- Mitigation: `didFailSave()` transitions back to `dirty` (retry on next cycle). `workerStatus` surfaces the error to the user.

### F039-T06: Partial Content from File Provider
- Vector: SSH file read returns partial content due to network interruption → buffer loads truncated content as baseline.
- Impact: Subsequent save writes truncated content to disk.
- Likelihood: Low.
- Mitigation: Content integrity guard (F039-R04) catches the case where loaded content is empty. For partial content (non-empty but truncated), this is harder to detect. Residual risk — mitigated by SSH transport layer checksums.

### F039-T07: Buffer Disposal Race
- Vector: Tab closed while autosave is in flight → buffer disposed → save completion handler accesses deallocated buffer.
- Impact: Crash or lost save.
- Likelihood: Low.
- Mitigation: `closeBuffer` flushes dirty buffers before disposal via a `writer` closure (F039-R10). The writer receives the `SaveToken` and the file URL — `closeBuffer` calls `beginSave`/`didSave`/`didFailSave` based on the result. The buffer stays alive until the flush task completes. If the flush throws, `didFailSave` is called, the error is returned via `Task<Error?, Never>`, and the buffer is disposed anyway (best-effort). `cancelLoad()` cancels in-flight reads.

## Residual Risks

1. **Partial content from network reads** (F039-T06): The content integrity guard only catches empty content, not truncated content. Full mitigation requires content checksums or length validation, which is out of scope for F039.
2. **Rapid buffer creation/disposal**: Opening and immediately closing many files could create memory pressure from buffer allocation. Mitigated by buffer disposal on tab close, but no LRU eviction is implemented.
3. **Undo history loss on tab switch**: The current architecture does not persist per-buffer undo history. Switching tabs and switching back loses undo state. This is a pre-existing limitation, not introduced by F039.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| REL (Reliability) | Addressed | State machine eliminates content erasure class of bugs |
| SEC (Security) | N/A | No new security boundaries introduced |
| PERF (Performance) | Acceptable | ~2 MB per buffer for 1 MB files, < 20 buffers typical |
| TEST (Testability) | Improved | State machine and autosave scheduler independently testable |
| A11Y (Accessibility) | N/A | No UI changes |
