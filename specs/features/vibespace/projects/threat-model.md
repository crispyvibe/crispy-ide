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

- **Vector:** A bug in the orchestration order (close browsers before mutating state vs. after) could cause `ProjectSession.shutdown()` to terminate before browsers receive their close requests, leaving orphan WebView instances.
- **Impact:** Memory leak; browsers may continue background activity (e.g., timers, network) for the parked project.
- **Likelihood:** Low — the close pipeline goes through `.closeBrowserRequested` which removes both board tiles and content-viewer tabs in the existing `ContentView` handler with an explicit "orphan VM" defensive cleanup branch.
- **Mitigation:** `VibeSpaceCanvasActionsCoordinator.parkProject(id:)` strictly orders: snapshot → close → setProjectParked → state mutation. Tests cover the close-fired-once invariant. Linked NFR: REL-2 (Reliability).

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

## NFR Compliance

| NFR | Coverage |
|---|---|
| SEC-2 (Data Integrity) | All `ProjectConfigFile` writes are integrity-signed via HMAC-SHA256 (existing infra). New fields `isParked` and `browserSessionEntries` are part of the signed payload. |
| REL-2 (Reliability) | Park/unpark uses atomic file writes (existing). Lifecycle ordering tested in `VibeSpaceStateParkingTests`. |
| PERF-3 (UI Responsiveness) | Park terminates terminals via existing `ProjectSession.shutdown()` which is non-blocking. Click-to-select is idempotent. |
| TEST-2 (Testability) | New behavior is covered by unit tests in `tests/unit/Models/VibeSpaceStateParkingTests.swift` and behavioral tests against the actions coordinator. |
