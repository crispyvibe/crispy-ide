# F039 Document Buffer — Spec

**Domain:** D4 (Editor)
Status: draft

---

## Overview

The document buffer system replaces the shared `rawContent` model in `MarkdownViewModel` with per-document `DocumentBuffer` instances governed by a lifecycle state machine. This is an infrastructure feature — it changes how the editor manages file content internally, with no user-facing behavior changes except the elimination of file content erasure bugs.

## Dependencies

- F006 Content Viewer — tab management, split panes, `EditorGroupStore`
- F007 Editing — autosave, save, dirty tracking, find-and-replace
- F008 Markdown — rich/source mode toggle, WKWebView rendering
- F009 Previews — image, PDF, git diff preview (non-editable, excluded from buffer system)

## Requirements

### F039-R01: Per-Document Content Isolation
Each open editable file MUST have its own content buffer. Switching tabs or opening a new file MUST NOT mutate another document's content.

### F039-R02: Lifecycle State Machine
Each document buffer MUST track its lifecycle phase. Valid phases: `loading`, `clean`, `dirty`, `saving`, `failed`. Transitions MUST be enforced — saves are only reachable from `dirty`.

### F039-R03: Save Gating
The autosave and manual save paths MUST be blocked when a buffer is in `loading` or `failed` state. No write operation may proceed unless the buffer is `dirty`.

### F039-R04: Content Integrity Guard
A save MUST NOT write empty content to a file whose baseline (last known disk content) was non-empty. This is a defense-in-depth check independent of the state machine.

### F039-R05: Edit Rejection During Loading
User edits arriving while a buffer is in `loading` state MUST be discarded. The editor surface MUST NOT be editable until the buffer transitions to `clean`. The view layer MUST NOT assign content to `NSTextView.string` or inject content into `WKWebView` while the buffer is in `loading` state — the editor surface retains its previous content and is overlaid with a loading indicator.

### F039-R06: Concurrent Edit During Save
If the user edits content while a save is in flight, the buffer MUST transition to `dirty` with the new content and the successfully-saved content as the new baseline. No edits are lost.

### F039-R07: External Change Handling
When a file watcher detects an external change to a `clean` buffer, the buffer MUST reload. When the buffer is `dirty` or `saving`, external changes MUST NOT overwrite user edits.

### F039-R08: WKWebView Crash Recovery
When the WKWebView WebContent process terminates, the buffer's content MUST be preserved. The recovered editor MUST re-inject the buffer's current content, not an empty string.

### F039-R09: Autosave Scheduler Isolation
Autosave scheduling MUST be a separate, testable component. It MUST NOT be embedded in the view model. It MUST only schedule saves for buffers in `dirty` state.

### F039-R10: Buffer Disposal
When a tab is closed, its buffer's reference count MUST be decremented. When the reference count reaches zero and the buffer is `dirty`, the buffer MUST attempt a flush (save to disk) before disposal. The buffer MUST remain alive until the flush completes or fails. If the flush fails, the buffer is still disposed (best-effort save) and the error MUST be surfaced to the caller. Any in-flight load task MUST be cancelled on disposal.

### F039-R11: Shared Buffer Across Panes
If the same file is open in multiple split panes, all panes MUST share a single buffer (keyed by file identity). The buffer is only disposed when the last pane referencing it is closed.

### F039-R12: View API Compatibility
The migration MUST preserve the existing view-layer API surface. Views that currently read `rawContent` MUST be able to read equivalent content from the active buffer without structural changes to the view hierarchy. The `NSViewRepresentable.updateNSView` implementations MUST add a loading guard (check `isBufferLoading`, skip content assignment, disable editing).

### F039-R13: Session Restore Compatibility
Buffer state MUST be compatible with the existing `EditorSessionState` persistence. Open tabs, active tab, and split layout MUST restore correctly through the new buffer system.

### F039-R14: Save Token Correlation
Each save operation MUST be identified by a unique token minted at `beginSave()`. Save completion (`didSave`, `didFailSave`) MUST only be accepted if the token matches the currently in-flight save. Stale completions from superseded saves MUST be ignored.

### F039-R15: Load Task Ownership and Cancellation
Each buffer MUST own its in-flight load task. `beginReload()` (user-initiated revert or retry after failure) MUST cancel the previous load task before starting a new one. Load completion MUST be rejected if the task was cancelled (stale read guard). When a second pane opens a file that already has a buffer in `.loading` state, it MUST attach to the existing buffer and its in-flight load — it MUST NOT cancel and restart the load.

---

## Scenarios

### F039-S01: File open does not erase content via autosave race
Given file A is open and clean
When the user opens file B (local or remote)
Then file B's buffer enters `loading` state
And no autosave is scheduled for file B during loading
And file A's buffer content is unchanged
And file B's buffer transitions to `clean` when the read completes

### F039-S02: Remote file open with slow read does not erase content
Given the user opens a file over SSH
When the file read takes longer than the autosave debounce (0.45 s)
Then no save occurs because the buffer is in `loading` state
And the file on disk is unchanged until the user makes an edit

### F039-S03: Tab switch preserves both documents
Given file A has unsaved edits (buffer is `dirty`)
And file B is open and `clean`
When the user switches from tab A to tab B
Then file A's buffer retains its dirty content
And file B's buffer provides its content to the editor
And switching back to tab A restores file A's dirty content

### F039-S04: Autosave blocked during loading
Given a new file is being opened (buffer in `loading` state)
When the SwiftUI render cycle pushes empty content to the editor surface
And `textDidChange` fires with empty string
Then `applyEdit("")` is rejected because the buffer is in `loading`
And no autosave is scheduled

### F039-S05: WKWebView crash preserves content
Given a markdown file is open in rich mode with unsaved edits
When the WKWebView WebContent process terminates
Then the buffer retains its `dirty` content
And the recovered editor re-injects the buffer's current content
And the user can continue editing without data loss

### F039-S06: Empty content save blocked by integrity guard
Given a file with 500 lines of content is open
When a code path attempts to save empty content (baseline was non-empty)
Then the save is rejected by the content integrity guard
And the file on disk is unchanged

### F039-S07: Concurrent edit during save
Given the user has unsaved edits and autosave begins (buffer enters `saving`)
When the user continues typing during the save
Then the buffer transitions to `dirty` with the new content
And when the save completes, the baseline updates to the saved content
And a new autosave cycle begins for the remaining unsaved edits

### F039-S08: External file change on clean buffer
Given a file is open with no unsaved edits (buffer is `clean`)
When an external tool modifies the file on disk
And the file watcher fires
Then the buffer reloads with the new disk content
And the editor displays the updated content

### F039-S09: External file change on dirty buffer
Given a file is open with unsaved edits (buffer is `dirty`)
When an external tool modifies the file on disk
And the file watcher fires
Then the buffer retains the user's edits
And the external change does not overwrite user content

### F039-S10: Tab close with dirty buffer saves content
Given a file has unsaved edits (buffer is `dirty`)
When the user closes the tab
Then the buffer's content is saved to disk before disposal
And the pending autosave is cancelled

### F039-S11: Session restore through buffer system
Given a vibespace session was persisted with 3 open file tabs
When the vibespace is restored
Then 3 document buffers are created in `loading` state
And each buffer loads its file content independently
And the active tab's buffer content is displayed when ready

### F039-S12: File open failure leaves buffer in failed state
Given the user opens a file that cannot be read (permissions, missing, network error)
When the file read fails
Then the buffer transitions to `failed` with the error
And no save is possible from `failed` state
And the error is displayed to the user

---

## Acceptance Criteria

- All F039-S01 through F039-S12 scenarios pass as behavioral tests.
- No file content erasure is reproducible under: rapid tab switching, SSH file open, WKWebView crash, concurrent edit during save, external file modification, same file in two split panes, close tab with dirty buffer.
- Existing F007 (Editing) and F006 (Content Viewer) behavioral tests continue to pass without modification.
- Autosave scheduler has independent unit tests covering all state transitions and flush.
- `DocumentBuffer` state machine has property-based tests verifying that `save` is unreachable from `loading`.
- `DocumentBuffer` save token correlation has unit tests verifying stale completions are ignored.
- `DocumentBufferStore` reference counting has unit tests verifying flush-on-dispose and shared-buffer-across-panes.

## Open Questions

1. Should dirty buffers prompt the user on tab close, or always auto-save? (Current behavior: always auto-save.)
2. Should external file changes on dirty buffers show a notification/conflict UI, or silently preserve user edits? (Proposed: silently preserve, revisit in future.)
3. Should buffer content be kept in memory for closed tabs (LRU cache) to speed up re-opening? (Proposed: no, out of scope for F039.)

## Change History

| Date | Change |
|------|--------|
| 2026-04-22 | Initial draft |
