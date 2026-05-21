# ADR-002: Document Buffer Architecture

Status: proposed
Date: 2026-04-22
Deciders: Crispy Team

## Context

Users report file content erasure when editing in the markdown/code editor. Root cause analysis identified a class of race conditions in `MarkdownViewModel`:

1. **Shared mutable state.** A single `rawContent` property serves every open tab. Opening or switching files resets it to `""` synchronously, while the async file read is in flight.
2. **Autosave feedback loop.** The `rawContent = ""` reset triggers SwiftUI re-render → `NSTextView.string = ""` → `textDidChange` → `updateEditableContentFromRenderer("")` → `scheduleAutosave()`. If the file read takes longer than the 0.45 s autosave debounce (SSH, large files, busy worker), the autosave writes empty content to disk.
3. **No lifecycle gating.** `save()` has no guard against the document being in a loading/transitional state. It writes whatever `rawContent` holds.
4. **WKWebView crash recovery.** macOS can terminate the WebContent process. During recovery, empty content can propagate through the binding into the autosave path.

These are structural defects — the current architecture makes "save during loading" a valid code path. Patching individual call sites is insufficient; the invariant must be enforced by the type system.

## Decision

Replace the shared-content model in `MarkdownViewModel` with per-document `DocumentBuffer` instances governed by an explicit lifecycle state machine.

Key design choices:

- **Per-document isolation.** Each open file gets its own `DocumentBuffer` with independent content, dirty state, and lifecycle phase. Tab switching changes the active buffer pointer, not the content.
- **State machine gating.** `BufferState` enum (`loading → clean → dirty → saving`) enforces that saves are only reachable from the `dirty` state. The `loading` state blocks both edits and saves at the type level.
- **Separated autosave.** `AutosaveScheduler` is extracted from the view model into a standalone, testable type that only operates on dirty buffers and includes a content integrity guard (empty-content check against non-empty baseline).
- **Parallel implementation.** New types are built alongside the existing code. `MarkdownViewModel` is migrated incrementally by delegating to `DocumentBuffer` instances, preserving the existing view API surface during transition.

## Consequences

- File content erasure bugs are eliminated by construction — the state machine makes "save during loading" unreachable.
- Per-buffer isolation eliminates cross-tab content leakage.
- Autosave scheduling becomes independently testable.
- `MarkdownViewModel` shrinks from a god object to a thin coordinator.
- Migration requires updating all `rawContent` consumers to use the buffer's `displayContent`.
- The `EditorGroupStore` → `MarkdownViewModel` ownership model is preserved; only the internal content model changes.
- Feature documented as F039 under D4 (Editor domain).
