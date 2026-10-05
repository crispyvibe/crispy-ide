# Screen Capture & Screenshot Studio — Threat Model

## Overview
F062 processes potentially sensitive screen pixels, automatically places output on the general clipboard, and retains bounded flattened local history. Security goals are visible intent, least metadata, local-only bounded persistence, correct pre-redaction replacement, atomic recovery, stale-completion rejection, post-delivery dismissal, and honest permission/failure behavior. Screenshot PNG pixels are user content; the persisted `current.json` pointer and its item/version/timestamp/dimension fields are application metadata and therefore fall under SEC-2.

## Trust Boundaries
- User command/visible selection ↔ macOS capture and Screen Recording permission services.
- Captured pixels ↔ in-memory Studio/F009 annotation session.
- Studio render/encoder ↔ general pasteboard.
- Delivery coordinator ↔ local history actor/filesystem.
- Exact-whitelist metadata/canonical PNG ↔ untrusted or corrupt on-disk history.
- Main-actor presentation ↔ async render/encode/decode/file tasks.
- Carbon callback/retained context ↔ live shortcut manager and coordinator.

## Attack Surfaces
System-wide hot key, capture overlay, permission recovery, display geometry, excluded windows, raw/annotated pixels, clipboard replacement, local history files and thumbnails, unsigned metadata pointer, metadata decoder, delete/clear, startup cleanup, retention, Studio selection, callback teardown, and shutdown callbacks.

## Threats
### F062-T01: Capture without visible user intent
- Vector: background registration or a stale command triggers acquisition.
- Impact: unintended disclosure.
- Likelihood: Medium.
- Mitigation: one typed command plus visible target commitment; no background/video capture; session generations reject stale requests. References SEC-3, TEST-2, TEST-3.

### F062-T02: Permission bypass or misleading recovery
- Vector: the provider runs before authorization or recovery UI implies permission was granted.
- Impact: privacy violation or confusing prompts.
- Likelihood: Low.
- Mitigation: permission probe/request only after explicit capture intent, typed denied/revoked/relaunch states, dismiss-first Recheck/Cancel actions, provider suppression on failure, labelled recovery UI, and signed hardware checks isolated behind the manual gate. References REL-3, A11Y-1, TEST-4.

### F062-T03: Geometry captures unintended pixels
- Vector: mixed scale, topology change, spanning-window clipping, or a cross-display Region produces invalid geometry.
- Impact: content outside the visible commitment is captured.
- Likelihood: Medium.
- Mitigation: topology/generation binding, validated native coordinates and target descriptors, visibly clamped single-display Region, desktop-independent Window capture, and fail-closed errors. References SEC-3a, REL-3, TEST-2.

### F062-T04: Capture UI leaks into pixels
- Vector: overlay, recovery, Studio, thumbnail, or toolbar remains composited.
- Impact: UI/privacy leakage and recursive thumbnails.
- Likelihood: Medium.
- Mitigation: central surface registry, capture exclusion filters, order-out plus compositor barrier, and a one-shot token that restores only surfaces visible before a failed/cancelled post-barrier acquisition. Empty/unmappable display catalogs fail before retaining selection work. References SEC-3, REL-5, TEST-4.

### F062-T05: Sensitive local history disclosure and unsigned application metadata
- Vector: another local process/user reads history, backup syncs it, excess identity metadata is stored, or an attacker modifies `current.json` without detection.
- Impact: durable screenshot disclosure or an undetected metadata-pointer substitution.
- Likelihood: Medium.
- Mitigation: app-local Application Support root, non-ubiquitous validation, backup exclusion, exact metadata whitelist, canonical metadata-free PNG, no app/window/origin names, no network/OCR/indexing, scoped regular-file/symlink checks, and delete/clear controls. These controls reduce disclosure and path abuse but do **not** satisfy SEC-2 integrity verification: the exact-key atomic `current.json` file is currently unsigned and has no HMAC. Screenshot PNG content is user content; `current.json` is persisted application state. References SEC-2 (Partial/noncompliant), SEC-6, SEC-7.

### F062-T06: Pre-redaction raw history remains durable
- Vector: an initial raw capture is saved and later Redact adds another version, leaving recoverable raw bytes.
- Impact: secrets remain recoverable despite visible redaction.
- Likelihood: High without replacement discipline.
- Mitigation: one current immutable version pointer per item; edited flattened output and `current.json` are replaced atomically, and old source/thumbnail versions are removed after the commit. UI guidance notes that clipboard/history may contain raw output before redaction finishes and recommends Clear for stronger removal. Atomic replacement and recovery address partial writes but cannot authenticate unsigned `current.json`. References SEC-2 (Partial/noncompliant), REL-2, REL-5.

### F062-T07: Stale resurrection after edit/delete/clear
- Vector: late encode/add/update/thumbnail/selection work finishes after item deletion, clear, replacement, or shutdown.
- Impact: deleted sensitive data or stale UI reappears.
- Likelihood: High without concurrency controls.
- Mitigation: active clipboard token, per-item generations, tombstones, clear epoch, request UUIDs, task cancellation, atomic publication, and checks immediately before mutation/publication. Cancellation prevents uncommitted work but is not rollback; a version whose atomic add/update commit already completed may remain for next-load discovery/pruning while late UI publication remains forbidden. References REL-2, REL-5, REL-6, TEST-2.

### F062-T08: Corrupt or malicious history
- Vector: malformed/modified JSON, symlink, mismatched ID/path, image bomb, interrupted staging, or orphan version.
- Impact: crash, path escape, resource exhaustion, or displaying wrong pixels.
- Likelihood: Medium.
- Mitigation: exact key set, identifier-derived relative names, regular non-symbolic file checks, decode/size validation, quarantine, startup staging/trash/orphan cleanup, and independent-item isolation. Corruption and symlink/image validation provide graceful recovery but do not detect all tampering because metadata lacks SEC-2 integrity verification. References SEC-2 (Partial/noncompliant), SEC-3a, SEC-7, REL-3, REL-5.

### F062-T09: Clear/add race exposes retired history
- Vector: add/update overlaps clear-directory retirement.
- Impact: partial clear or content published into the wrong epoch.
- Likelihood: Medium.
- Mitigation: actor serialization plus a clear epoch captured across async processing; clear atomically retires the items directory before creating a fresh one; stale work fails. References REL-2, REL-5, TEST-2.

### F062-T10: Thumbnail leakage or substitution
- Vector: a thumbnail retains metadata, references another item, survives delete/clear, or reinstalls the editor.
- Impact: a sensitive preview remains visible or the wrong image is edited.
- Likelihood: Medium.
- Mitigation: metadata-free generated thumbnail capped at 320 px, same item/version whitelist, presentation-only state, valid-ID pruning, delete/clear invalidation, and source decode required for editor installation. References SEC-3a, REL-5, TEST-2.

### F062-T11: Unbounded storage/resource exhaustion
- Vector: repeated huge captures or corrupt timestamps evade pruning.
- Impact: disk/memory exhaustion and UI denial of service.
- Likelihood: Medium.
- Mitigation: 64 MP/512 MiB pre-allocation limits, canonical image validation, maximum 50 entries/30 days, 320 px thumbnails, startup/add pruning, and off-main serialized image/file work. References PERF-2, PERF-3, REL-4.

### F062-T12: Clipboard ordering leaks the wrong item
- Vector: item A finishes after item B becomes active, or edit N finishes after N+1.
- Impact: the user pastes stale or sensitive pixels.
- Likelihood: High without ordering.
- Mitigation: one active item, global clipboard token, per-item generation/version checks, cancellation of superseded render/encode work, and complete PNG/TIFF preparation before one clipboard replacement. No synthetic paste occurs. References SEC-3, REL-5, TEST-2.

### F062-T13: Partial clipboard replacement
- Vector: lazy representation or a failure between clipboard declaration and data production.
- Impact: empty/partial clipboard and misleading status.
- Likelihood: Low.
- Mitigation: eagerly encode and validate complete PNG/TIFF before mutation; perform one synchronous write; preserve Studio and expose structured retry on failure. Cross-device clipboard behavior remains external. References REL-3, TEST-3, TEST-4.

### F062-T14: Origin identity retention or focus misuse
- Vector: the origin app name is shown/persisted or success returns/pastes into an unintended app.
- Impact: identity leak or wrong-target disclosure.
- Likelihood: Medium.
- Mitigation: an ephemeral capability contains no name, is used only for cancellation/failure restoration, and is cleared on Studio success; there is no Copy & Return or synthetic paste. Keyboard focus returns on cancel/failure. References SEC-3, A11Y-2.

### F062-T15: Shortcut migration changes user intent
- Vector: disabled/customized state is lost or an arbitrary legacy route wins.
- Impact: an unexpected global command is enabled.
- Likelihood: Medium.
- Mitigation: existing `captureScreen` always wins, including customized/disabled values across compiled-default changes; otherwise deterministic first-enabled legacy priority; obsolete keys are removed; migration is idempotent and tested before Carbon construction. The ⌃⇧4 default avoids the former Grammarly letter-chord conflict and leaves macOS ⇧⌘4 and standard ⇧⌘S unclaimed. References REL-5, TEST-2, TEST-3, TEST-4.

### F062-T16: Failure/shutdown publishes late UI or leaves work alive
- Vector: callbacks retain Studio/store after close or termination, or cancellation is mistaken for rollback after an atomic repository commit.
- Impact: crash, memory retention, stale clipboard/history status, or incorrect assumptions about durable removal.
- Likelihood: Medium.
- Mitigation: tracked tasks/handles, weak captures, callback disconnection, output cancellation, panel/store shutdown, terminal service state, atomic commit boundaries, and post-await generation/token checks suppress late clipboard, history-store, thumbnail, event, and UI publication. Same-owner attachment is a no-op; owner replacement shuts down the prior distinct service. References REL-2, REL-5, REL-6, TEST-2, TEST-3.

### F062-T17: Premature or stale Studio dismissal
- Vector: Copy & Dismiss closes optimistically, clipboard succeeds while history fails, or an older item/edit completion closes a replacement Studio session.
- Impact: the user believes the latest selected edit was copied and saved when delivery is incomplete or different content is current.
- Likelihood: High without explicit completion ownership.
- Mitigation: the ViewModel records pending item ID/version before immediate copy; delivery carries version and clipboard state through guarded persistence and signals completion only after full-resolution encode, clipboard replacement, atomic flattened add/update, and guarded entries/thumbnail update. Matching failure preserves Studio. Completion requires the same selected item and a sufficient version; close ownership is cleared before one callback. An add collision retries only `itemAlreadyExists` as update under unchanged guards. References REL-2, REL-3, REL-5, TEST-2, TEST-3.

### F062-T18: Global hot-key shadowing or contention
- Vector: another app owns the configured chord, Grammarly retains the prior letter chord, or local and production Crispy instances request the same default.
- Impact: capture appears unavailable, the wrong process receives the chord, or registration state is misleading.
- Likelihood: Medium.
- Mitigation: Carbon requests `kEventHotKeyExclusive`; registration success means one Crispy process owns the chord. Conflict/failure is actionable and fails closed rather than shadowing another owner. The default moved from the Grammarly-conflicting letter chord to ⌃⇧4. Local and production instances may both request that default: one can own it while the other reports conflict. Application activation retries reconciliation after the owner releases it, exact healthy state does not churn, and users can disable or choose another chord. F062 uses a typed Carbon hot-key handler and **no event tap**. References SEC-3, REL-3, REL-5, TEST-2, TEST-3, TEST-4.

### F062-T19: Retained callback context after handler-removal failure
- Vector: Carbon handler removal fails while a late callback still holds the original context pointer, creating a stale-callback/use-after-free vector.
- Impact: crash, callback into released manager state, or repeated stale command dispatch.
- Likelihood: Low, with high impact absent lifetime isolation.
- Mitigation: the callback context is retained independently of the manager and contains only a weak manager reference. If removal fails, it is intentionally retained; late callbacks find no manager and return `eventNotHandledErr`. Rebind/shutdown retries owned-resource removal, and retention is bounded to a tiny context for that manager rather than growing per callback. References REL-5, REL-6, PERF-2, TEST-2, TEST-3, TEST-4.

## Residual Risks
- The macOS clipboard can be read, synchronized, or retained by OS/third-party tools. Local users/processes with sufficient filesystem access can read screenshot history, and flash/storage may retain deleted blocks.
- **SEC-2 release gap:** `current.json` is exact-key and atomically replaced, but it is unsigned and has no HMAC. Corruption, symlink, path, and image validation narrow exploitation and permit recovery; they do not authenticate persisted application metadata or detect all same-user tampering. This is Partial/noncompliant with SEC-2. Before claiming SEC-2 compliance for F062, wrap/sign the metadata pointer with the app persistence integrity mechanism (HMAC-SHA256 or equivalent), verify before decode/use, define migration/quarantine behavior, and add tamper/integrity integration tests. Screenshot PNG pixels remain user content; the metadata pointer is application state.
- Global shortcut ownership is inherently process-wide. When local and production Crispy builds request the same chord, only one may own it; the other reports conflict until activation reconciliation succeeds or the user selects another chord.
- If Carbon refuses handler removal, one tiny independent weak-manager context can remain intentionally retained until process exit. This is safer than freeing a pointer Carbon may call, but it is still bounded residual memory retention.
- Protected content, mixed-display geometry, current-Space activation, and permission behavior are controlled partly by macOS and require release-time hardware validation.

## NFR Compliance
| NFR | Status | F062 evidence or gap |
|---|---|---|
| SEC-2 | **Partial / noncompliant** | History metadata is under Application Support and writes are atomic, but `current.json` has no HMAC/equivalent integrity verification. Release follow-up is mandatory before claiming compliance. |
| SEC-3 | Partial | Typed capture/hot-key commands and constrained rendering/delivery boundaries are present; screenshot pixels and clipboard remain sensitive user content. |
| SEC-3a | Partial | Catalog/geometry, metadata keys, paths, IDs, and decoded images are validated; integrity/authenticity remains the SEC-2 gap. |
| SEC-6 | Meets for F062 | Capture, Studio, clipboard, and history work offline with no F062 network path. |
| SEC-7 | Partial | History is rooted under the injected app directory with regular-file/symlink/path checks; release review must continue to verify permissions and temporary-file scope. |
| REL-2 | Meets for documented repository flow | Add/update/current-pointer and clear retirement use staging plus atomic replacement/rename boundaries. |
| REL-3 | Meets for documented failures | Permission, provider, clipboard, history, catalog, and shortcut failures preserve usable state and expose retry/conflict status. |
| REL-4 | Meets for feature bounds | Capture working set, history count/age, and thumbnail size are capped. |
| REL-5 | Meets for documented recovery flow | Migrations/reconciliation are idempotent; epochs, generations, tombstones, cleanup, and retries leave recoverable state. |
| REL-6 | Partial | Shutdown cancels owned work and releases UI/registration resources, but the five-second budget and pending-write behavior still require release validation; failed Carbon removal can retain one safe context until exit. |
| PERF-2 | Partial | Memory/image/history bounds prevent unbounded growth, but F062-specific profiling has not demonstrated the global 100 MB/20 MB budgets. |
| PERF-3 | Partial | Heavy image/file work is off-main and interactive selection is not timed, but hardware responsiveness remains manually validated. |
| A11Y-1 | Partial | Interactive controls have labels/states and recovery/status announcements; VoiceOver remains a manual release check. |
| A11Y-2 | Meets by design; manual verification required | Region/Window/Display selection, Studio actions, cancel, and focus restoration have keyboard routes. |
| A11Y-3 | Manual / not established by this threat model | Applies only to text/color contrast and non-color cues; thumbnail identity is not credited as A11Y-3 compliance. |
| A11Y-6 | Partial | Stable identifiers exist for key controls such as `screenCapture.studio.copyAndDismiss`; full interactive-element inventory remains an audit item. |
| A11Y-7 | Partial | Native macOS controls are used, but increased contrast, reduced transparency/motion, and font-setting behavior require manual checks. |
| TEST-2 | Meets for scenario mapping | F062-S01–S23 each map to at least one automated test, including both catalog and acquisition timeout coverage for S23. |
| TEST-3 | Meets | OS services, stage racing, filesystem/history, clipboard, scheduling, Carbon, and presentation boundaries are injected. |
| TEST-4 | Meets for automated suite | Deterministic doubles and temporary isolated stores avoid network, permission, and machine-state dependence; real hardware checks are separately gated. |

## Change History
| Date | Change | Author |
|---|---|---|
| 2026-10-04 | Corrected NFR semantics, disclosed unsigned `current.json` as a Partial/noncompliant SEC-2 integrity gap with release follow-up, added REL-2/REL-5 atomic-race references, corrected resource/accessibility mappings, and added T18–T19 plus residual risks. | — |
| 2026-10-04 | Hardened exclusive/coherent Carbon ownership and callback context lifetime; added terminal owner shutdown, zero-panel fail-closed behavior, and hidden-surface restoration. | — |
| 2026-10-04 | Changed the no-override default from ⌃⇧S to ⌃⇧4 to avoid a Grammarly Snippet conflict, while preserving customized/disabled intent and leaving macOS ⇧⌘4 plus ⇧⌘S Save As unclaimed. | — |
| 2026-10-04 | Added T17 for premature/stale dismissal and the guarded clipboard-plus-history completion contract. | — |
| 2026-10-04 | Added dismiss-first Recheck/Cancel and stale permission-panel teardown mitigation. | — |
| 2026-10-04 | Clarified that shutdown blocks late publication and uncommitted work but cannot roll back an add/update atomic disk commit completed before cancellation. | — |
| 2026-10-04 | Replaced multi-route threats with sensitive local history, raw replacement, stale resurrection, corruption, clear/add race, thumbnail leakage, bounds, and clipboard-ordering analysis. | — |
