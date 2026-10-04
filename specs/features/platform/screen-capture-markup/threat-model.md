# Screen Capture & Screenshot Studio — Threat Model

## Overview
F062 processes potentially sensitive screen pixels, automatically places output on the general clipboard, and retains bounded flattened local history. Security goals are visible intent, least metadata, local-only bounded persistence, correct pre-redaction replacement, atomic recovery, stale-completion rejection, post-commit-only dismissal, and honest TCC/failure behavior.

## Trust Boundaries
- User command/visible selection ↔ ScreenCaptureKit and Screen Recording TCC.
- ScreenCaptureKit pixels ↔ in-memory Studio/F009 annotation session.
- Studio render/encoder ↔ general pasteboard.
- Delivery coordinator ↔ local history actor/filesystem.
- Exact-whitelist metadata/canonical PNG ↔ untrusted/corrupt on-disk history.
- Main actor presentation ↔ async render/encode/decode/file tasks.

## Attack Surfaces
System-wide hot key, capture overlay, TCC recovery, display geometry, excluded windows, raw/annotated pixels, clipboard replacement, local history files and thumbnails, metadata decoder, delete/clear, startup cleanup, retention, Studio selection, and shutdown callbacks.

## Threats
### F062-T01: Capture without visible user intent
- Vector: background registration or stale command triggers acquisition.
- Impact: unintended disclosure.
- Likelihood: Medium.
- Mitigation: one explicit command plus visible target commit; no background/video capture; generation checks cancel stale requests. References SEC-1, SEC-3.

### F062-T02: TCC bypass or misleading recovery
- Vector: provider called before authorization or settings imply permission was granted.
- Impact: privacy violation/confusing prompts.
- Likelihood: Low.
- Mitigation: explicit-action-only probe/request, typed denied/revoked/relaunch states, dismiss-first Recheck/Cancel actions, automatic recovery dismissal on every non-recovery coordinator state, provider never called on failure, and manual signed hardware tests. References SEC-1, A11Y-1.

### F062-T03: Geometry captures unintended pixels
- Vector: mixed scale, topology change, spanning window clipping, or cross-display Region.
- Impact: content outside the visible commitment is captured.
- Likelihood: Medium.
- Mitigation: topology/generation binding, native coordinate validation, visibly clamped single-display Region, desktop-independent Window capture, fail closed. References SEC-3, REL-1.

### F062-T04: Capture UI leaks into pixels
- Vector: overlay, recovery, Studio, thumbnail, or toolbar remains composited.
- Impact: UI/privacy leakage and recursive thumbnails.
- Likelihood: Medium.
- Mitigation: central surface registry, ScreenCaptureKit exclusion filters, order-out plus compositor barrier, hardware validation. References SEC-3.

### F062-T05: Sensitive local history disclosure
- Vector: another local process/user reads history, backup syncs it, or app stores excess identity metadata.
- Impact: durable disclosure of screenshots.
- Likelihood: Medium.
- Mitigation: app-private local Application Support root, non-ubiquitous validation, backup exclusion, exact metadata whitelist, canonical metadata-free PNG, no app/window/origin names, no network/OCR/indexing. Users can delete/clear. References SEC-1, SEC-3, DEP-1.

### F062-T06: Pre-redaction raw history remains durable
- Vector: initial raw capture is persisted and later Redact only adds another version, leaving recoverable raw bytes.
- Impact: secrets remain recoverable despite visible redaction.
- Likelihood: High without replacement discipline.
- Mitigation: history item has one current immutable version pointer; edited flattened output atomically replaces current and old source/thumbnail versions are removed after commit. UI guidance notes clipboard/history may contain raw output before redaction settles; use Clear for stronger removal. References SEC-3.

### F062-T07: Stale resurrection after edit/delete/clear
- Vector: late encode/add/update/thumbnail/selection completes after item deletion, clear, replacement, or shutdown.
- Impact: deleted sensitive data or stale UI reappears.
- Likelihood: High without concurrency controls.
- Mitigation: active clipboard token, per-item generations, tombstones, clear epoch, request UUIDs, task cancellation, and checks immediately before mutation/publication. Cancellation prevents uncommitted work but is not rollback; a version whose add/update atomic disk commit already completed may remain for normal next load discovery/pruning while late UI publication remains forbidden. References SEC-3, REL-1.

### F062-T08: Corrupt or malicious history
- Vector: malformed JSON, symlink, mismatched ID/path, image bomb, interrupted staging, orphan version.
- Impact: crash, path escape, resource exhaustion, or displaying wrong pixels.
- Likelihood: Medium.
- Mitigation: exact key set, identifier-derived relative names, regular non-symbolic file checks, decode/size validation, quarantine, startup staging/trash/orphan cleanup, independent-item isolation. References SEC-1, DEP-3, REL-1.

### F062-T09: Clear/add race exposes retired history
- Vector: add/update overlaps clear directory retirement.
- Impact: partial clear or content published into wrong epoch.
- Likelihood: Medium.
- Mitigation: actor serialization plus clear epoch captured across async processing; clear atomically retires items then creates a fresh directory; stale work fails. References SEC-3, REL-1.

### F062-T10: Thumbnail leakage or substitution
- Vector: thumbnail retains metadata, references another item, survives delete/clear, or reinstalls the editor.
- Impact: sensitive preview remains visible or wrong image is edited.
- Likelihood: Medium.
- Mitigation: metadata-free generated <=320 px PNG, same item/version whitelist, presentation-only thumbnail state, valid-ID pruning, delete/clear invalidation, source decode required for editor installation. References SEC-3, A11Y-3.

### F062-T11: Unbounded storage/resource exhaustion
- Vector: repeated huge captures or corrupt timestamps avoid pruning.
- Impact: disk/memory exhaustion and UI denial of service.
- Likelihood: Medium.
- Mitigation: 64 MP/512 MiB pre-allocation limits, canonical image validation, maximum 50 entries/30 days, 320 px thumbnails, startup/add pruning, off-main serial work. References PERF-1, REL-1.

### F062-T12: Clipboard ordering leaks wrong item
- Vector: item A finishes after item B becomes active, or edit revision N finishes after N+1.
- Impact: user pastes stale/sensitive pixels.
- Likelihood: High without ordering.
- Mitigation: one active item, global clipboard token, per-item generation and revision checks, cancel old render/encode, fully populate PNG/TIFF before one clear/write commit. No synthetic paste. References SEC-3, REL-1.

### F062-T13: Partial clipboard replacement
- Vector: lazy representation or failure between declaration and data production.
- Impact: empty/partial clipboard and misleading status.
- Likelihood: Low.
- Mitigation: eagerly encode and validate complete PNG/TIFF before mutation; one item/one synchronous write; structured failure preserves Studio for retry. Universal Clipboard remains external. References SEC-3.

### F062-T14: Origin identity retention or focus misuse
- Vector: origin app name is shown/persisted or success returns/pastes into an unintended app.
- Impact: identity leak or wrong-target disclosure.
- Likelihood: Medium.
- Mitigation: ephemeral capability has no name, is used only for cancellation/failure restoration, and is cleared on Studio success; no Copy & Return and no synthetic paste. References SEC-3, A11Y-2.

### F062-T15: Shortcut migration changes user intent
- Vector: disabled state is lost or arbitrary legacy route wins.
- Impact: unexpected global command.
- Likelihood: Medium.
- Mitigation: existing `captureScreen` always wins, including disabled; otherwise deterministic first enabled legacy priority; obsolete keys removed; idempotence tested before Carbon construction. References REL-1.

### F062-T16: Failure/shutdown publishes late UI
- Vector: callbacks retain Studio/store after close or app termination, or cancellation is mistaken for rollback after an atomic repository commit.
- Impact: crash, memory retention, stale clipboard/history status, or incorrect assumptions about durable data removal.
- Likelihood: Medium.
- Mitigation: tracked tasks/handles, weak captures, callback disconnection, output cancellation, panel/store shutdown, Carbon unregistration, and post-await token/generation checks suppress late clipboard, history-store, thumbnail, event, and UI publication. Work not atomically committed is prevented; completed add/update commits may remain for ordinary next-load discovery/pruning. References REL-1, TEST-1.

### F062-T17: Premature or stale Studio dismissal
- Vector: Copy & Dismiss closes optimistically, clipboard succeeds while history fails, or a late completion for an older revision/item closes a replacement Studio session.
- Impact: the user reasonably believes the latest selected edit was delivered when clipboard/history is incomplete or different content is current.
- Likelihood: High without explicit completion ownership.
- Mitigation: ViewModel records pending item ID and requested revision before `copyNow`; delivery carries revision and clipboard-commit state through guarded persistence and emits completion only after full-resolution encode, clipboard commit, flattened add/update commit, and entries/thumbnail publication. Matching failure clears pending dismissal and preserves Studio. Completion requires the same selected item and revision >= requested; close ownership is nilled before one callback. Add collision retries only `itemAlreadyExists` as update under unchanged generation/token guards. References SEC-3, REL-1, TEST-1.

## Residual Risks
The macOS clipboard can be read, synchronized, or retained by OS/third-party tools. Local users/processes with sufficient filesystem access can read app history. Flash/storage may retain deleted blocks. Protected content behavior and current-Space activation are controlled by macOS. Users handling secrets should redact before sharing and clear clipboard/history when necessary.

## NFR Compliance
- SEC-1 / SEC-3: explicit intent, minimal local data, no network, eager clipboard, atomic/stale-safe lifecycle.
- A11Y-1 / A11Y-2 / A11Y-3: keyboard/VoiceOver selection, labelled Studio/history actions, announced state/failure.
- PERF-1: resource limits, debounce, thumbnails, bounded retention.
- REL-1: typed failures, atomic files, recovery cleanup, generations/tombstones/epochs.
- TEST-1: injected clocks/processors/repositories/schedulers/presentation boundaries; manual hardware/TCC gate.

## Change History
| Date | Change | Author |
|---|---|---|
| 2026-10-04 | Added T17 for premature/stale dismissal and the guarded clipboard-plus-history completion contract. | — |
| 2026-10-04 | Added dismiss-first Recheck/Cancel and stale permission-panel teardown mitigation. | — |
| 2026-10-04 | Clarified that shutdown blocks late publication and uncommitted work but cannot roll back an add/update atomic disk commit completed before cancellation. | — |
| 2026-10-04 | Replaced multi-route threats with sensitive local history, raw replacement, stale resurrection, corruption, clear/add race, thumbnail leakage, bounds, and clipboard-ordering analysis. | — |
