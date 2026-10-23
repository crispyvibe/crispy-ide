# F021 — VibeSpace Projects: Threat Model

## Overview

VibeSpace Projects governs project lifecycle within a vibespace: add, remove, focus, park, unpark. The trust boundary sits between user actions (Files-tab context menus, settings sheet) and the persistence layer (per-project `ProjectConfigFile`, vibespace `VibeSpaceConfigFile`, both integrity-signed via HMAC-SHA256 per SEC-2).

## Threats

### F021-T01: Stale parked-project state restored under a different project

- **Vector:** A path is parked, the directory is later replaced (e.g., a different repository is cloned to the same path), and the user then activates the parked entry. The persisted browser sessions, terminal entries, and color tag would be re-applied to a project whose contents differ.
- **Impact:** Browser tabs / terminal working directories surface paths that may no longer match the user's expectation. Privacy boundary blurs because URLs in the persisted browser snapshot may have been visited under a different repository.
- **Likelihood:** Low — typical usage parks-and-activates without the directory being reshuffled. Higher in workspace setups where path reuse is common.
- **Mitigation:** Path-keyed identity is intentional. `unparkProject(path:)` requires the directory to exist on disk before recreating a session. Future hardening may include a content-fingerprint check on critical fields. Linked NFR: SEC-Data-Protection.

### F021-T02: Browser session leakage via park snapshot serialization

- **Vector:** Browser session entries (URL, history stacks, theme) persist into `ProjectConfigFile.browserSessionEntries`. If the config file is exfiltrated or shared (e.g., committed to git), browsing history is exposed.
- **Impact:** Per-project browsing history disclosed.
- **Likelihood:** Low — config files live in app-support directories, not project directories.
- **Mitigation:** `ProjectConfigFile` is integrity-signed (HMAC-SHA256). Path validation ensures config files cannot be tricked into pointing outside the vibespace's app-support directory. Documenting that browser session entries contain visit history is a follow-up. Linked NFR: SEC-2 (Data Integrity), SEC-Data-Protection.

### F021-T03: Park/unpark flow leaves orphan view-models or browsers running

- **Vector:** A bug in park orchestration could close project browsers while the project is still live, allowing close-triggered fallback logic to refocus the project being parked, or could fail to close browser view models after state removal.
- **Impact:** Focus thrashing, an incorrectly refocused dormant project, or orphan browser activity.
- **Likelihood:** Low — the close pipeline removes board tiles and content-viewer tabs and retains an explicit orphan-view-model cleanup branch.
- **Mitigation:** The coordinator queries browser snapshots by qualified and unambiguous legacy keys, persists once under only the qualified key, marks parked, removes board/file presentations, removes live state with `shutdown:false`, closes browsers, collects project-keyed displaced/outstanding and returned flush tasks, and races their completion against a true 30-second timeout. The first result cancels the losing monitor and the retained session shuts down exactly once. State removal before browser close prevents fallback refocus; deferred shutdown keeps file providers alive until the race resolves. Linked NFR: REL-2 (Reliability).

### F021-T04: Click-to-select recursion or focus thrashing

- **Vector:** A `focusProject` call programmatically activates a tab, which posts `.contentViewerTabActivated`, which calls `focusProject` again, in a loop.
- **Impact:** UI freeze, observability log spam, project-switch metric inflation.
- **Likelihood:** Low — the listener short-circuits when the resolved owning project's id already matches the focused project's id.
- **Mitigation:** Idempotent comparison guards the focus call. Linked NFR: PERF-3 (UI Responsiveness), REL-2.

### F021-T05: Parked-path hydration via reconciliation race

- **Vector:** The reconciliation flow scans paths against the filesystem. If a parked path were inadvertently included, a stale parked project could be re-hydrated as a live session.
- **Impact:** Parked project resurrection without going through the unpark flow; persisted `isParked = true` flag would diverge from live state.
- **Likelihood:** Very low — `availabilityReconciliationPaths()` only returns `unresolvedProjectPaths + projects.map(...)`; parked paths are tracked separately in `parkedProjectPaths` and are not in either list.
- **Mitigation:** Three-way disjoint state (live / unresolved / parked) is enforced in lifecycle methods. Linked NFR: REL-2.

### F021-T06: Parked SSH URI discloses remote identity

- **Vector:** A parked row renders the persisted `ssh://user@host:port/path` literally in visible or accessibility text.
- **Impact:** Screen sharing, screenshots, or assistive-technology logs could disclose usernames or sensitive ancestor paths in addition to the host identity needed to distinguish the row.
- **Likelihood:** Medium without presentation minimization because no live session is available to supply other metadata.
- **Mitigation:** The row uses the shared SSH identifier parser and localized `AppStrings` formatting for its server/SSH presentation, literal host (plus a non-default port), `…/basename` detail, and accessibility sentence; it omits username and ancestor path components from visible/accessibility text. The accessibility identifier hashes the full persisted identifier with `AppDiagnostics.pathToken` instead of embedding it. Linked NFR: SEC-Data-Protection, A11Y.
- **Residual risk:** Hostname, non-default port, remote classification, and project basename remain intentionally visible and may identify infrastructure or project purpose.

### F021-T07: Dormant project actions bypass activation controls

- **Vector:** A parked row exposes Open in System, Download, terminal, or file-mutation commands despite lacking a live authenticated remote session.
- **Impact:** Operations could run against stale connection metadata or bypass the explicit activation lifecycle.
- **Likelihood:** Low after menu restriction.
- **Mitigation:** Parked rows expose only Activate Project and Remove Project. Activation recreates the session and connection boundary before any explorer or external action becomes available. Linked NFR: REL-2, SEC-Data-Protection.

### F021-T08: Cross-host project cleanup deletes another SSH project's panes

- **Vector:** Two remote projects use the same raw root path on different SSH hosts, and park/remove cleanup treats the raw root as a globally unique owner.
- **Impact:** Terminals, browsers, files, ACP panes, or Spotlight members belonging to the other host could be deleted.
- **Likelihood:** Medium for common roots such as `/workspace` or `/home/user/project` when multiple servers are open.
- **Mitigation:** Ownership capture and cleanup use the host-qualified `projectIdentifier`. Remote runtime terminal subscriptions, project context, reconciliation, and Spotlight identities use that same owner. Terminal tab evidence may identify legacy remote terminal tiles, but raw-root equality alone never proves ownership across hosts. Linked NFR: SEC-1, REL-2.
- **Residual risk:** Incorrectly stamped historical metadata could still misidentify a tile; cleanup can only be as accurate as uniquely established ownership evidence.

### F021-T09: Ambiguous legacy ownership is migrated to the wrong project

- **Vector:** `syncProjects` encounters an older tile without `projectIdentifier` whose raw remote root matches more than one host and guesses an owner during migration.
- **Impact:** A later park/remove could delete or restore the tile under the wrong project, crossing an SSH-host boundary.
- **Likelihood:** Medium for legacy multi-host layouts; low for newly stamped layouts.
- **Mitigation:** The optional Codable ownership field decodes absent values safely, and migration stamps a host-qualified owner only when evidence proves exactly one project. Legacy terminal tab membership is accepted as stronger evidence; ambiguous raw-root-only remote tiles are retained fail-closed and left unstamped. Linked NFR: SEC-1, SEC-3a, REL-2.
- **Residual risk:** Retained ambiguous tiles may require manual cleanup and may not follow project park/remove until ownership becomes provable.

### F021-T10: Cleanup leaves a stale detached board window

- **Vector:** Park/remove deletes the last project-owned tile from a detached surface but fails to remove the empty surface or close its managed AppKit window.
- **Impact:** A blank, stale window remains registered, confusing users and retaining window/focus resources.
- **Likelihood:** Low because cleanup and normalization share one mutation, but multi-window lifecycle regressions have visible impact.
- **Mitigation:** The board store removes visible, minimized, and Spotlight members in one normalized persistent mutation. Normalization drops empty detached surfaces, and the managed-window layer closes windows whose surface IDs disappear. Linked NFR: REL-2, REL-6.
- **Residual risk:** An unmanaged or already-desynchronized AppKit window could require manual closure; source inspection cannot validate mounted window behavior.

### F021-T11: Project teardown discards a dirty docked file

- **Vector:** Park/remove shuts down the remote provider or releases a docked group before its active/later save revision is flushed, or omits an unpinned owned preview.
- **Impact:** Unsaved content is lost or written through the wrong project's provider.
- **Likelihood:** Low after deferred teardown.
- **Mitigation:** Cleanup includes matching pinned groups and the unpinned preview, closes every tab with its own provider/strong worker writer, waits for returned flush tasks before session shutdown, retains failed dirty buffers, and applies a 30-second shutdown watchdog with diagnostics. Linked NFR: SEC-Data-Protection, REL-2.
- **Residual risk:** Watchdog expiry can terminate provider resources before a hung write finishes; failed retained buffers need a later recovery path.

### F021-T12: Legacy browser lookup creates duplicate or cross-host persistence

- **Vector:** Migration reads and writes both the qualified identifier and raw-root key, duplicating browser state or allowing a same-root host collision.
- **Impact:** Stale browser history reappears or is restored under the wrong SSH project.
- **Likelihood:** Low after canonical persistence.
- **Mitigation:** The raw-root key is queried only when unambiguous, results are deduplicated by browser ID, and the final list is persisted exactly once under the host-qualified `projectIdentifier`, including when empty. Linked NFR: SEC-Data-Protection, SEC-2.
- **Residual risk:** Previously persisted legacy entries remain readable for migration until separate cleanup removes them.

### F021-T13: Same-root remote source control crosses project boundaries

- **Vector:** Repository models attach by raw path overlap, tracked diffs use a non-owning backend, or untracked files open with a provider from another host.
- **Impact:** Commands, diffs, or file reads target the wrong SSH project.
- **Likelihood:** Medium for common remote roots.
- **Mitigation:** Repository IDs/models retain exact `projectIdentifier`; project-backed attachment returns only that project. Tracked diffs use its `gitExplorer` and a project-qualified preloaded tab; untracked/new files use its exact provider. Linked NFR: SEC-Data-Protection, REL-2.
- **Residual risk:** Full multi-host interaction remains production-source inspection rather than mounted test evidence.

### F021-T14: Spotlight or shortcut identity collapses same-root projects

- **Vector:** One of the many Spotlight routes or shortcut dictionaries keys by raw root instead of exact project identifier.
- **Impact:** A nested action executes or opens on the wrong host, or two projects receive the same shortcut slot/key.
- **Likelihood:** Medium without consistent propagation and normalization.
- **Mitigation:** Main/detached direct, temporary, shortcut, split, permanent, ACP, link, file, browser, editor-pane, restore, and detached-attachment routes retain exact `projectIdentifier`. Project and project-scoped shortcuts use that exact key; SSH identifiers remain verbatim and numeric slots are unique. Linked NFR: SEC-1, REL-2.
- **Residual risk:** Only detached attachment and shortcut normalization have direct static test source; the complete route matrix is production-source inspection.

### F021-T15: Teardown loses a displaced flush or shuts a project down twice

- **Vector:** Replacing a floating preview/group starts a close task that is not returned by later project cleanup, or independent flush and timeout completions each invoke shutdown.
- **Impact:** Unsaved content is lost, a provider is released too early, or duplicated shutdown mutates lifecycle state twice.
- **Likelihood:** Low after project-keyed task tracking and race arbitration.
- **Mitigation:** `DockedFileViewerCoordinator` tracks displaced and outstanding tasks by exact project identifier. Park/remove collects all matching tasks and uses `ProjectFileFlushRace` to resolve once between complete flush and a true 30-second timeout, cancels both monitors after resolution, and calls `project.shutdown()` exactly once. Linked NFR: SEC-Data-Protection, REL-2.
- **Residual risk:** Timeout intentionally permits shutdown while a hung flush has not succeeded; the dirty-buffer recovery path remains necessary.

### F021-T16: Canonical SSH migration drops or blesses dormant project state

- **Vector:** A legacy raw full SSH identifier, raw remote path, or malformed normalized key differs from the current percent-encoded identifier; validation or cleanup then prunes unresolved/parked settings, loads only live configs, leaves duplicate parked identities, or rewrites an untrusted parent payload as trusted.
- **Impact:** Terminal/browser state, color, startup/ACP/shell overrides, or shortcut slots disappear; one remote project can retain duplicate identities; or tampered configuration receives a valid signature.
- **Likelihood:** Medium during upgrades involving reserved characters in remote paths.
- **Mitigation:** Canonicalize live, unresolved, focused, and parked identifiers; deduplicate parked values and exclude live/unresolved collisions; save a changed parent immediately only when its existing signature verified. Per-project reads and mutations search canonical plus raw-path, prior raw-full, and malformed-normalization aliases, migrate the complete config to the canonical key, and delete the alias. `loadProjectConfigs` includes live, unresolved, and parked projects, while runtime pruning preserves dormant settings and shortcut slots. Linked NFR: SEC-2, SEC-Data-Protection, REL-2.
- **Residual risk:** If multiple aliases independently contain divergent data, first-resolved migration is authoritative; conflict-merging is not defined.

## Verification Status

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. `VibeSpaceManagementServiceTests.testCanonicalRemoteIdentifierMigratesPriorRawFullIdentifierAndAllProjectState` directly covers complete prior-raw-full alias migration, browser/shortcut reads, canonical load keys, parked deduplication, and immediate trusted-parent rewrite; raw-path and malformed-normalization alias tests also exist. Preservation of every unresolved/parked runtime settings dictionary remains production-source inspection. Static source covers close serialization/failure retention, per-tab provider lifetime, shortcut uniqueness, board identity, remote discovery/refresh plumbing, detached attachment, and narrow detached shortcut/permanent routes. Exact same-root repository attachment, non-empty staged-then-working preloaded diff routing, exact untracked providers, the complete Spotlight matrix, project-keyed displaced/outstanding flush collection, the true 30-second race, and exactly-once shutdown remain production-source inspection. Mounted coordinator/window behavior remains unverified.

## NFR Compliance

| NFR | Coverage |
|---|---|
| SEC-2 (Data Integrity) | All `ProjectConfigFile` writes are integrity-signed via HMAC-SHA256 (existing infra). New fields `isParked` and `browserSessionEntries` are part of the signed payload. |
| REL-2 (Reliability) | Park/unpark uses atomic file writes (existing). Static sources include project-state and multi-surface board-cleanup cases, but browser snapshot/close ordering and mounted managed-window closure remain unexecuted gaps. |
| PERF-3 (UI Responsiveness) | Park/remove remove live state promptly while project-keyed file flushes race a true 30-second timeout; exactly-once shutdown follows the winning result. Click-to-select is idempotent. |
| TEST-2 (Testability) | `VibeSpaceStateParkingTests.swift`, `CLICommandRouterVibeSpaceProjectTests.swift`, `VibeSpaceTerminalBoardStoreBulkMoveTests.swift`, and canonical migration cases exist as static sources. Final validation reached build/test-build only; no test case executed and no pass is claimed. |

## Change History

- 2026-10-23: Added F021-T16 for canonical SSH migration loss/trust risks and corrected direct static migration coverage versus runtime/source-only gaps.
- 2026-10-23: Added F021-T13–T15 for exact same-root remote source-control ownership, complete Spotlight/shortcut identity, project-keyed displaced/outstanding flushes, and exactly-once flush-vs-timeout shutdown; narrowed evidence to static/build-only source.
- 2026-10-23: Added F021-T11–T12 and corrected park/remove threat analysis for provider-safe deferred shutdown, unpinned previews, canonical browser persistence, eager switch pruning, and static-only verification.
- 2026-10-20: Added F021-T08–T10 for cross-host deletion, ambiguous legacy migration, and stale detached windows, including mitigations and residual risks. Static sources only; no test pass is claimed.

- 2026-10-20: Corrected park ordering/fallback-refocus analysis and removed unsupported coordinator-ordering and close-fired-once test claims; model tests remain static and unexecuted in the focused host-hang attempt.
