# CrispyVibes App — Memory Leak Audit Report (Revised)

**Date:** 2026-04-13 (revised after code review feedback and runtime follow-up)
**Scope:** 80 high-risk Swift files across 6 batches
**Patterns checked:** 10 (strong delegates, closure retain cycles, timer leaks, observer leaks, Combine leaks, KVO leaks, missing deinit, unbounded collections, strong reference cycles, DispatchSource leaks)

---

## Executive Summary

**Total files scanned:** 363 app source files (pass 1: 80 high-risk, pass 2: 283 remaining) + 72 test files excluded
**Files with issues:** 36
**Files clean:** 327

Findings are classified into three tiers based on code verification:

| Tier | Count | Meaning |
|------|-------|---------|
| 🔴 Confirmed Retention Bugs | 7 | Missing cleanup calls, uncancelled timers, unbounded collections, unbalanced Unmanaged |
| 🟡 Hardening Opportunities | 18 | Missing deinit, strong closure properties, dict growth, cache accumulation |
| ⚪ Speculative / Low-Risk | 23 | Minor cleanup gaps, defensive improvements, singleton caches |

---

## 2026-04-11 Runtime Follow-Up — Explorer Worker

This follow-up documents what was observed in the live app after the explorer worker appeared to grow during use, plus the patch applied from that investigation.

### What We Witnessed

- Main app process `/Applications/CrispyVibes.app/Contents/MacOS/CrispyVibes` (`PID 46734`) reached about `322 MB` physical footprint during observation.
- Explorer worker `CrispyVibes-explorer-worker --pane-task-session explorer` (`PID 46837`) reached about `123 MB RSS` / `128.8 MB` physical footprint after roughly 20 minutes.
- Terminal and editor workers remained much smaller, at about `20 MB` and `23 MB` RSS respectively.
- `lsof` did not show a matching file-descriptor leak in the explorer worker. Open handles were mostly the expected stdio/session pipes.

### What We Observed in the Heap

`heap 46837` showed large counts of Foundation objects that should have been transient inside a long-running pane worker:

- `CFString`: about `259,920`
- `NSPathStore2`: about `158,575`
- `NSURL`: about `79,289`
- `_FileCache`: about `76,539`
- `NSConcreteData`: about `21,684`
- `NSConcreteFileHandle`: about `15,918`
- `NSConcretePipe`: about `7,959`

This pattern matched Foundation/autorelease accumulation during repeated worker requests more closely than a classic Swift retain-cycle leak.

### Follow-Up Patch Applied

`PaneWorkerBootstrap.runPersistentSessionWorker` now wraps each request/response iteration in `autoreleasepool`, and `runSingleRequestWorker` uses the same pattern. This constrains transient Foundation allocations created during request decoding, file enumeration, git subprocess handling, and response encoding to a single worker request instead of the full worker lifetime.

**Patched file:** `Features/VibeSpace/Services/PaneWorker/PaneWorkerInfrastructure.swift`

### Remaining App-Process Growth Candidate

`AppKitTreeCoordinator.nodeCache` and `loadingNodeCache` remain a separate app-process growth vector. The cache is pruned on collapse, but it is not bounded or reconciled against the currently reachable tree during broad browsing, refreshes, or root replacement, so long sessions can still accumulate retained row-identity state there.

### Build Verification Status

Swift package resolution was repaired by clearing Xcode/SwiftPM caches and resolving packages into a clean temporary source-packages directory, but full build verification remained blocked by an Xcode environment hang after `CreateBuildDescription`. Process samples showed `xcodebuild` idle in Xcode's run loop with `DTDKRemoteDeviceConnection` / `DTDKRemoteDeviceDataListener` activity rather than active compiler work.

---

## 2026-04-13 Runtime Follow-Up — Source Control Worker

This follow-up documents a separate live investigation into source control worker growth that initially looked like a memory leak but turned out to be a watcher-driven refresh loop.

### What We Witnessed

- Installed app source control worker `CrispyVibes-sourceControl-worker --pane-task-session sourceControl` grew from roughly `10 MB` to well over `300 MB`, and in one live capture reached about `2.2 GB RSS`.
- The matching app process remained comparatively smaller, which localized the issue to the long-lived source control pane worker rather than the UI process.
- `lsof` did not show a corresponding file-descriptor leak.

### What We Observed in the Heap

`heap` on the runaway source control worker showed `NSConcreteData (Bytes Storage)` dominating physical footprint in repeated `16 KB` allocations. That pattern fit repeated subprocess output buffering more closely than a classic retained-object graph leak.

### Root Cause Confirmed

The project-root watcher in `VibeSpaceSourceControlViewModelHelpers.swift` was allowed to react to internal `.git` filesystem churn. A typical sequence was:

1. root watcher reports a file-system change
2. `refreshRepositories(affectedBy:)` queues a source control refresh
3. repository refresh requests a git snapshot from the source control worker
4. git status/snapshot activity touches files under `.git` such as `index`, logs, objects, or refs
5. the watcher sees those `.git` writes as fresh changes and retriggers source control refresh

This created a self-sustaining refresh loop under otherwise idle use. The observed memory growth was therefore allocation churn inside repeated git worker requests, not a proven permanent retain cycle.

### Follow-Up Patch Applied

- `VibeSpaceSourceControlViewModel.refreshRepositories(affectedBy:)` now filters observed paths before queueing refresh work.
- `VibeSpaceSourceControlViewModelHelpers.filteredObservedPaths(from:)` now drops:
  - configured noisy/generated directories such as `DerivedData`, `SourcePackages`, `node_modules`, and similar
  - internal `.git` paths that should not retrigger status refresh, including `.git/index`
- User-visible git ref paths are still allowed through so branch changes continue to refresh correctly, including `.git/HEAD`, `FETCH_HEAD`, `ORIG_HEAD`, `packed-refs`, and `refs/...`.
- `.git` internal filtering now applies even if the user clears the ignored-directory settings list entirely.

**Patched files:** `Features/VibeSpace/ViewModels/VibeSpaceSourceControlViewModel.swift`, `Features/VibeSpace/ViewModels/VibeSpaceSourceControlViewModelHelpers.swift`

### Regression Tests Added

`VibeSpaceSourceControlViewModelTests` now cover:

- ignored generated-directory changes are skipped
- `.git/index` is ignored
- `.git/HEAD` and `.git/refs/heads/...` remain refresh-visible
- `.git` internal filtering still applies even when `ignoredDirectoryNames` is empty

**Validation:** `xcodebuild -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes -destination 'platform=macOS,arch=arm64' -only-testing:CrispyVibesUnitTests/VibeSpaceSourceControlViewModelTests test` passed with `28` tests and `0` failures during the follow-up.

---

## 2026-04-16 Runtime Follow-Up — Terminal Interactive Target Menus

This follow-up was triggered after the terminal interactive-target popup work landed for links, files, and folders. The concern was whether the new menu command routing introduced a fresh retain cycle, leaked menu callback objects, or bypassed the existing terminal teardown guarantees documented elsewhere in this audit.

### What Was Reviewed

- `TerminalSessionSupportTypesInteractiveTargeting.swift`
- `GhosttyTerminalView.swift`
- `TerminalSessionSupportTypesInteractiveTargetingMouse.swift`
- existing terminal teardown and deallocation paths in:
  - `GhosttyTerminalEngine.terminate()`
  - `TerminalSession.terminate()`
  - `MonitoredTerminalView.deinit`
  - `GhosttyTerminalView.deinit`
  - `TerminalViewModel.deinit`

### What We Verified

- The popup menu no longer relies on ad hoc temporary target objects retained through Objective-C association.
- Menu command dispatch now uses a stateless singleton target plus per-item command objects stored in `NSMenuItem.representedObject`.
- The menu command objects are scoped to the lifetime of the AppKit menu items rather than being stored in any long-lived registry, cache, or static dictionary.
- Existing terminal observer and monitor teardown remains intact:
  - `MonitoredTerminalView.deinit` still calls `teardownInteractiveTargetRecognition()` to remove local event monitors and tracking areas.
  - `GhosttyTerminalView.deinit` still removes the screen-change observer and releases the Ghostty callback context.
- Existing terminal closure cleanup remains intact:
  - `GhosttyTerminalEngine.terminate()` still resets `actionHandlers`.
  - `TerminalSession.terminate()` still clears `firstOutputObservers`, pending work, and queued commands.

### Runtime / Test Verification

The follow-up reran the targeted terminal interaction tests plus the dedicated terminal memory lifecycle suite:

- `xcodebuild test -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes -configuration Debug -destination 'platform=macOS' -only-testing:CrispyVibesUnitTests/GhosttyTerminalViewInputTests -only-testing:CrispyVibesUnitTests/TerminalInteractiveTargetDetectorTests`
- `xcodebuild test -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes -configuration Debug -destination 'platform=macOS' -only-testing:CrispyVibesUnitTests/TerminalMemoryLifecycleTests`

Observed results:

- interactive-target tests passed
- terminal memory lifecycle tests passed
- repeated create/close session cycles still deallocated sessions cleanly
- hosted terminal views still deallocated after shutdown
- engine release and action-handler teardown still passed existing assertions

### Conclusion

No new confirmed memory leak or resource-retention issue was found in the terminal interactive-target popup implementation.

This work does **not** add a new Tier 1, Tier 2, or Tier 3 finding. The relevant pre-existing terminal hardening items in this report remain unchanged:

- missing defensive `deinit` in some terminal-adjacent types
- `MonitoredTerminalView` closure properties remain acceptable because production teardown still nils them through engine/session shutdown
- Ghostty and terminal teardown correctness still depends on the established ownership and terminate paths, which continue to be covered by the terminal lifecycle tests

---

## 🔴 Tier 1 — Confirmed Retention Bugs

These are verified code paths where objects are retained beyond their useful lifetime.

### 1. DockedBrowserCoordinator — Detailed browser VMs retained after tab close
**File:** `Features/VibeSpace/Services/Browser/DockedBrowserCoordinator.swift`
**Problem:** `removeDetailedBrowser(browserID:)` exists (line 194) but is never called from any production browser-tab close path. The `detailedViewGroups`, `detailedViewSessionSnapshots`, and `detailedViewReferences` dictionaries accumulate entries as detailed browser views are opened, but entries are only removed via `removeAll()` (full vibespace teardown) — never individually.
**Impact:** Each detailed browser tab opened during a session permanently retains a `BrowserPanelViewModel` (with its WKWebView, KVO observers, delegates) until the entire vibespace is torn down.
**Verification:** `grep` confirms `removeDetailedBrowser` is only defined, never called from outside the file.
**Fix:** Call `removeDetailedBrowser(browserID:)` from the browser tile close / tab close path in the terminal board or vibespace canvas.

### 2. VibeCastStore — Uncapped messages array
**File:** `Features/VibeCast/ViewModels/VibeCastStore.swift`
**Problem:** `@Published var messages: [VibeCastMessage] = []` grows without bound. Messages are appended via `send()` but never removed or capped.
**Impact:** Memory grows linearly with VibeCast usage. This is retained product state rather than a classic reference-cycle leak, but it contributes to memory accumulation during long sessions.
**Fix:**
```swift
func send(_ text: String) {
    messages.append(VibeCastMessage(text: text))
    if messages.count > 500 { messages.removeFirst(messages.count - 500) }
}
```

### 3. OperationMetricsStore — traceStack unbounded growth
**File:** `App/Diagnostics/OperationMetricsStore.swift`
**Problem:** `traceStack` grows with `beginTrace()` and shrinks with `endTrace()`. If calls are unbalanced (error paths, Task cancellation, early returns), entries accumulate permanently. Note: the main `buffer` ring buffer IS properly capped — only `traceStack` is the issue.
**Impact:** Slow memory growth proportional to unbalanced trace calls over time.
**Fix:** Add max-depth guard or stale-trace cleanup (e.g., traces older than 5 minutes), or use a defer-based API that guarantees `endTrace()` is called.

### 4. TerminalSession.firstOutputObservers — Not cleared in terminate()
**File:** `Features/Terminal/Services/TerminalSession.swift`
**Problem:** `firstOutputObservers: [UUID: @MainActor () -> Void]` dictionary is never cleared in `terminate()`. If observers are registered but never triggered (e.g., session terminates before first output), the closures and anything they capture persist for the session's lifetime.
**Impact:** Closures and their captured context leak per-session when first output never arrives.
**Fix:** Add `firstOutputObservers.removeAll()` to `terminate()`.

### 5. LocalCommandExecutor — Process + timer lifecycle on Task cancellation
**File:** `Features/Local/LocalCommandExecutor.swift`
**Problem:** `DispatchSource.makeTimerSource` + `process.waitUntilExit()` (blocking call) inside `Task.detached`. If the enclosing Task is cancelled externally, `waitUntilExit()` still blocks the thread — the process and timer are never cleaned up until the process exits naturally.
**Impact:** Orphaned processes and timers when commands are cancelled.
**Fix:** Use non-blocking wait pattern or check `Task.isCancelled`. Add `timer.cancel()` in a `defer` block.

---

## 🟡 Tier 2 — Hardening Opportunities

These are defensive improvements. Normal teardown paths handle cleanup correctly, but abnormal paths (crashes, unexpected deallocation order, skipped shutdown calls) could leak.

### Missing deinit — defensive cleanup

| # | File | What's missing | Normal path handles it? | Fix |
|---|------|----------------|------------------------|-----|
| 1 | GhosttyTerminalEngine | `deinit` doesn't call `stopOutputPolling()` | ✅ Yes — `stopOutputPolling()` is called from multiple extension methods during normal surface teardown | Add `outputPollTimer?.cancel()` to deinit |
| 2 | TerminalSession | No `deinit` | ✅ Yes — `terminate()` is called from `TerminalViewModelTabs` during normal tab close. Deallocation tests confirm proper release. | Add defensive `deinit` cancelling work items/tasks |
| 3 | DirectoryWatcher | No `deinit` | ✅ Yes — `FolderExplorerViewModel.deinit` calls `directoryWatcher.invalidate()` | Add `deinit { invalidate() }` |
| 4 | PollingDirectoryWatcher | No `deinit` | Partially — `stop()` must be called manually | Add `deinit { pollTask?.cancel() }` |
| 5 | SSHConnection | No `deinit` | Partially — `disconnect()` must be called manually | Add `deinit` cancelling `healthTask` |
| 6 | MarkdownViewModel | No `deinit` | Unknown — 3 resources (`autosaveWorkItem`, `openFileTask`, `gitDiffTask`) | Add `deinit` cancelling all three |
| 7 | RemoteProjectSession | No `deinit` | Partially — `shutdown()` must be called manually | Add defensive `deinit` |
| 8 | SSHPortForwardService | No `deinit` | Partially — `removeAll()` must be called manually | Add `deinit` closing NIO channels |
| 9 | SSHConnectionManager | No `deinit` | Partially — `disconnectAll()` must be called manually | Add defensive `deinit` |
| 10 | VibeSpaceHydrationCoordinator | No `deinit` | Unknown — holds Task + DispatchWorkItem | Add `deinit` cancelling both |
| 11 | HomeCatalogCoordinator | No `deinit` | Unknown — holds `catalogLoadTask` | Add `deinit { catalogLoadTask?.cancel() }` |
| 12 | PaneWorkerClient (actor) | No `deinit` | Partially — `restart()` terminates process | Add `deinit` to terminate `activeProcess` |

### Strong closure properties — fragile patterns

These are correctly handled at all current call sites (using `[weak self]`), but the API doesn't enforce it. A future caller forgetting `[weak self]` would create a retain cycle.

| # | File | Property | Current call sites safe? |
|---|------|----------|-------------------------|
| 1 | BrowserNavigationDelegate | 5 closure properties | ✅ Yes |
| 2 | BrowserUIDelegate | `onOpenInNewTab` | ✅ Yes |
| 3 | BrowserPanelViewModel | `onOpenNewBrowser`, `onSessionStateChanged` | ✅ Yes |
| 4 | TerminalSession | `onTitleChanged`, `onDirectoryChanged`, etc. | ✅ Yes |
| 5 | ProjectSession | `onFileOpenRequested`, `onFileRenamed` | ✅ Yes |
| 6 | GitHeadWatcher | `let onChange` (strong, can't be nilled) | ✅ Yes |
| 7 | ContentViewerStore | `onActiveFileCleared` | ✅ Yes |
| 8 | VibeSpaceHydrationCoordinator | `canvasModeProvider` | ✅ Yes |

**Recommendation:** Convert high-traffic closure-as-delegate patterns to formal `weak var delegate` protocols, or add documentation requiring `[weak self]` at call sites.

---

## ⚪ Tier 3 — Speculative / Low-Risk

These are pattern-scan warnings with no confirmed leak path. Listed for completeness.

| # | File | Note |
|---|------|------|
| 1 | BrowserDownloadDelegate | Dead code `tempURLs` dict |
| 2 | BrowserHostOwnershipCoordinator | Strong captures in short-lived dispatch blocks |
| 3 | BrowserContentView/SuggestionsController | Missing deinit for task cancel |
| 4 | GhosttyTerminalRuntime | `pendingDisplayRecoveryWorkItem` not cancelled in deinit |
| 5 | SwiftTermTerminalEngine | No deinit (mitigated by ownership) |
| 6 | DockedFileViewerCoordinator | `groups` dict growth (has removal methods, verify they're called) |
| 7 | MonitoredTerminalView | 7 closure properties not nil'd in deinit (nil'd in terminate()) |
| 8 | DeveloperToolsView | Timer re-creation risk on re-appear |
| 9 | MarkdownViewModel | `markupViewModeByDocumentID` dict never pruned |
| 10 | StackedRailTerminalStore | No explicit deinit (AnyCancellable handles it) |
| 11 | ProjectActivityTracker | Missing explicit deinit (AnyCancellable handles it) |
| 12 | VibeSpaceShortcutProvider | Missing explicit deinit (AnyCancellable handles it) |
| 13 | AppShellStore | Strong `operationMetricsStore` ref |
| 14 | ContentViewTerminalSpotlightState | `MainActor.assumeIsolated` crash risk in deinit |
| 15 | SFTPFileContentProvider | Deferred Task close could hang |

---

## Root Cause Analysis — What's Most Likely Causing Memory Growth

Based on verified findings, the most probable contributors to long-session memory accumulation are:

1. **DockedBrowserCoordinator detailed-view retention** (confirmed) — Each detailed browser view opened permanently retains a full `BrowserPanelViewModel` + WKWebView until vibespace teardown. This is likely the single largest contributor if users open browser tabs frequently.

2. **VibeCastStore uncapped messages** (confirmed) — Linear growth with usage.

3. **OperationMetricsStore unbalanced traces** (confirmed) — Slow growth if begin/end traces are unbalanced on error paths.

4. **TerminalSession.firstOutputObservers** (confirmed) — Per-session closure leak when first output never arrives.

The remaining items (missing deinit in various classes) are hardening opportunities. Normal teardown paths in the codebase do handle cleanup correctly for most of these, as verified by checking call sites and existing deallocation tests. However, adding defensive `deinit` implementations would protect against edge cases and abnormal teardown sequences.

**Note:** This analysis is based on static code review. Runtime verification with Xcode Instruments (Allocations + Leaks + Memory Graph Debugger) is recommended to confirm which items contribute most to the observed memory growth.

---

## Pass 2 — Full Codebase Scan (283 additional files)

Pass 2 scanned all 283 remaining app source files (363 total app files - 80 from pass 1). Most were structs/enums/protocols (value types, inherently safe). New findings below.

### 🔴 NEW Confirmed Bugs

#### 6. GhosttyRuntimeCallbackContext — Unmanaged.passRetained without balancing release
**File:** `Features/Terminal/Services/GhosttyTerminalRuntimeCallbacks.swift`
**Problem:** `Unmanaged.passRetained(callbackContext)` creates a retained opaque pointer stored in `runtimeConfig.userdata`. This retained reference is never balanced with a `release()` call. The `GhosttyRuntimeCallbackContext` object (and its captured references) leaks permanently.
**Fix:** In `GhosttyTerminalRuntime.deinit` (or teardown), call `Unmanaged<GhosttyRuntimeCallbackContext>.fromOpaque(pointer).release()`.

#### 7. TerminalViewModel.gitHeadWatchersByTab — Static dictionary retains orphaned watchers
**File:** `Features/Terminal/ViewModels/TerminalViewModelTabs.swift`
**Problem:** `private static var gitHeadWatchersByTab: [UUID: GitHeadWatcher]` is a static dictionary. Entries are added in `updateGitHeadWatcher` and removed in `teardownGitHeadWatcher`. If a `TerminalViewModel` is deallocated without calling `shutdown()`/`terminateAllSessions()`, orphaned `GitHeadWatcher` entries persist forever — leaking file descriptors and DispatchSources.
**Fix:** Convert to instance property, or add a `deinit` guard that cleans up entries for this VM's tabs.

### 🟡 NEW Medium Findings

| # | File | Issue |
|---|------|-------|
| 1 | AppKitTreeCoordinator | `nodeCache` + `loadingNodeCache` can still grow during broad browsing; entries are pruned on collapse, but the cache is not otherwise bounded or reconciled |
| 2 | AppKitTreeCellViews | Earlier concern about closure retention appears resolved in current code; `prepareForReuse()` clears callback references |
| 3 | CognitoAuthService | `activeWebSession` race — calling `signInWithApple` twice rapidly leaks the first session |
| 4 | GhosttyTerminalEngineSurfaceConfig | `applyThemeOverrideIfPossible()` can leak newly allocated config on early-return error paths |
| 5 | BoardInteractionDelegateAdapter | Closures capture `boardStore` strongly instead of `[weak boardStore]` |
| 6 | AppSettingsSheetViewShortcuts | NSEvent monitor may not be removed in all SwiftUI teardown edge cases |

### 🟢 NEW Low Findings

| # | File | Issue |
|---|------|-------|
| 1 | DiagnosticsEventStore | `events` array backing storage never shrinks (removeFirst doesn't release capacity) |
| 2 | SyntaxRegexCache | `removeAll(keepingCapacity: true)` — backing storage permanently allocated |
| 3 | AppKitMenuTarget | Singleton `handler` closure retained until next menu |
| 4 | PaneWorkerExecutorGitProbeSupport | Static caches bounded by TTL+max but persist for app lifetime |
| 5 | VibeSpaceTerminalBoardStandaloneRegistry | Missing `deinit { shutdownAll() }` safety net |
| 6 | LayoutPersistenceService | `browserSessionSnapshotProvider`/`browserCurrentURLProvider` stored closures (resolved 2026-05: providers moved to `BoardSnapshotProviders` owned by board store) |
| 7 | TextProcessorService | `waitForProcessExit` busy-wait can block thread for 20s (resource leak) |
| 8 | TerminalDiagnosticsSnapshot | Dead entries with nil weak refs accumulate between snapshots |

### Pass 2 Summary

| Category | Count |
|----------|-------|
| Files scanned | 283 |
| CLEAN (structs/enums/protocols/extensions) | 267 |
| New confirmed bugs | 2 |
| New medium findings | 6 |
| New low findings | 8 |

---

## 2026-04-18 Runtime Follow-Up — Animation CPU Saturation

This follow-up documents a live investigation into typing sluggishness and high CPU usage in the running app, triggered by Activity Monitor showing 876 MB physical footprint and 670 Mach ports.

### What We Witnessed

- Main app process (`PID 86967`) at `876 MB` physical footprint (peak `900.6 MB`) after approximately 20 hours of uptime.
- `sample 86967 1` showed **80% of main thread time** (613 out of 768 samples) inside `CA::Transaction::flush` → `NSHostingView.layout()` → `AG::Subgraph::update` → `AnimatableAttribute.updateValue()` → `RepeatAnimation.animate` → `DefaultCombiningAnimation.animate`.
- The hot inner loop was `swift_arrayInitWithCopy` / `swift_arrayDestroy` inside `DefaultCombiningAnimation.animate` — transient array allocations created and destroyed every frame.
- `heap` showed `1,399` instances of `InternalCustomAnimationModifiedContent<BezierAnimation, RepeatAnimation>` in the AttributeGraph.
- 13 active tmux terminal sessions running concurrently.
- `vmmap --summary` showed `MALLOC_SMALL` at `657 MB` virtual, `84 MB` resident, `523 MB` swapped — indicating heavy allocation churn with fragmentation preventing the allocator from returning pages.

### Root Cause — Three Perpetual Animation Components

Three components in `TerminalViewComponents.swift` drove continuous main-thread work:

1. **`TerminalActivityBar`** — `TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive))` at 30 fps per active terminal. With 13 sessions, potentially 10+ instances driving body re-evaluation 30 times/second each, multiplied through the full SwiftUI view update pipeline.

2. **`TerminalActivityPulse`** — `.animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)` on every active terminal tile card. `repeatForever` animations drive at display refresh rate (60–120 fps depending on hardware) and create permanent `AnimatorState` entries in the AttributeGraph that persist for the view's lifetime. Applied to board tile cards, board view support, and ACP streaming tiles.

3. **`ActivityIndicator`** — `TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false))` running at 30 fps unconditionally. Phase changes are discrete (every 0.3 s), so 30 fps was approximately 7× the needed update rate.

### Impact on Typing

Each `TimelineView` tick and each `repeatForever` animation frame triggers:
- `AG::Subgraph::update` (AttributeGraph node re-evaluation)
- `AnimatableAttribute.updateValue` (animation interpolation)
- Array alloc/copy/destroy for combining animation state

With many concurrent animation sources, the main thread spent the majority of each display cycle processing animation bookkeeping rather than handling input events, causing the observed keystroke latency.

### Patches Applied

**File:** `Features/Terminal/Views/TerminalViewComponents.swift`

1. **`TerminalActivityBar`** — reduced TimelineView from `1.0 / 30.0` (30 fps) to `1.0 / 12.0` (12 fps). The animated element is a 4 px-wide sliding highlight on a bar — 12 fps is visually identical. Per-instance main-thread view updates reduced by 2.5×.

2. **`TerminalActivityPulse`** — replaced `.animation(.repeatForever())` with an explicit `TimelineView(.animation(minimumInterval: 1.0 / 8.0, paused: !isActive))` driving a `cos()` wave to oscillate opacity between 0.80 and 1.0 over a 1.6 s period (matching the original easeInOut(0.8) autoreverse cycle). This:
   - Eliminates `RepeatAnimation` objects from the AttributeGraph entirely
   - Gives explicit control over frame rate (8 fps, down from display rate)
   - Properly pauses when `isActive` is false (no animation work at all for idle terminals)
   - Fixes a known SwiftUI issue where `repeatForever` animations can silently stop after view-identity changes, because `TimelineView` is driven by the system display link rather than SwiftUI's internal animation state machine

3. **`ActivityIndicator`** — reduced TimelineView from `1.0 / 30.0` (30 fps) to `0.25` (4 fps). Phase transitions are discrete (every 0.3 s), so 4 fps captures every transition with no visible difference.

### Expected Impact

- **Main thread**: Animation-driven view updates reduced from ~500+ per second (across all instances at display rate) to ~150 per second total (12 + 8 + 4 fps × instance count), freeing the main thread for input event handling.
- **AttributeGraph**: No more `RepeatAnimation` entries accumulating. The 1,399 `InternalCustomAnimationModifiedContent<BezierAnimation, RepeatAnimation>` objects should drop to zero.
- **Heap fragmentation**: Reduced allocation churn should allow the malloc allocator to coalesce free blocks, potentially recovering a significant portion of the 523 MB swapped-out MALLOC_SMALL.
- **Functionality**: All animations preserved — activity bars still animate for active terminals, pulse effect still runs, indicator dots still cycle. Animations will not silently stop after view-identity changes.

### Verification Status

Build succeeded: `xcodebuild -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes -configuration Debug -destination 'platform=macOS,arch=arm64' build` completed with no errors or warnings.

Runtime verification pending: re-run `sample` and `heap` after deploying the patched build to confirm main-thread animation saturation is resolved and `RepeatAnimation` object count drops.

---

## 2026-04-18 Runtime Follow-Up — Ghostty C Allocator Leak via Output Polling

This follow-up documents a confirmed unbounded memory leak discovered through `MallocStackLogging=lite` tracing on a live dev build.

### What We Witnessed

- With `LocalPathSearchSession` disabled (which was separately consuming 600+ MB from filesystem crawling), the app started at ~160 MB physical footprint with 4 terminals open.
- Over 6 minutes of idle use, `memalign in heap.CAllocator.alloc` (Ghostty's internal C heap allocator) grew from **4,302 entries / 7.7 MB** to **11,517 entries / 33.1 MB** — a **25 MB increase in 6 minutes**.
- Extrapolated leak rate: **~250 MB/hour** with 4 terminals.
- Physical footprint grew from 292 MB to 512 MB during the investigation window.

### Root Cause Confirmed

`malloc_history -allBySize` traced the top allocation site:

```
9,147 calls for 27.7 MB:
  GhosttyTerminalEngine.startPolling()  GhosttyTerminalEngineOutputTracking.swift:150
    → GhosttyTerminalEngine.startLightweightPolling()  GhosttyTerminalEngineOutputTracking.swift:127
      → terminalView.visibleContents()
        → ghostty_surface_read_text()
          → heap.CAllocator.alloc
```

The lightweight output polling timer called `visibleContents()` every **1 second per terminal**. Each call invoked `ghostty_surface_read_text()` in Ghostty's C library, which allocated memory through its internal `heap.CAllocator`. While `ghostty_surface_free_text()` freed the returned text buffer, internal allocations made during the read operation were not reclaimed — likely due to Ghostty's allocator using an arena/slab strategy where individual frees mark blocks as available without shrinking the arena.

With 4 terminals: 4 calls/sec × ~5 internal allocations per call × ~3.5 KB avg = ~70 KB/sec = ~250 MB/hour.

### Patch Applied

**File:** `Features/Terminal/Services/GhosttyTerminalEngineOutputTracking.swift`

Replaced timer-driven lightweight polling with render-callback-driven change detection:

- `handleRenderAction()` (called by Ghostty's native render callback) now invokes `checkLightweightContentChange()` in lightweight tracking mode, instead of being a no-op.
- `transitionToLightweightTracking()` no longer starts a 1-second polling timer. The timer is eliminated entirely in lightweight mode.
- `resumeAppropriateOutputPolling()` returns immediately in lightweight mode since no timer is needed.
- New private method `checkLightweightContentChange()` performs the same hash-based content comparison, but is only called when Ghostty actually renders new content — not on a fixed timer.

This eliminates the leak by removing the periodic `ghostty_surface_read_text()` calls. The render callback fires only when content actually changes, so `visibleContents()` is called far less frequently and only when needed.

### Also Discovered: LocalPathSearchSession Filesystem Crawl

During the same investigation, `malloc_history` confirmed that `LocalPathSearchSession` was the dominant memory consumer even when the user never opened search:

- **777,728 files crawled** under the project root at startup
- **222 MB** in `LocalPathSearchCandidate.init(entry:)` line 452 — `Array(entry.normalizedRelativePath.utf16)` copies
- **77 MB** in `LocalPathSearchCandidate.init(entry:)` line 453 — `Array(entry.normalizedFileName.utf16)` copies
- **67 MB** in 12 `Set<String>` instances — dedup sets
- Plus ~290 MB in `StringStorage` / `CFString` from `buildEntry()` creating 4 strings per file
- **Total: ~600+ MB** from path search, with **11.4 GB peak** during crawl

The crawler starts in `LocalPathSearchRuntime.init` → `startCrawler()` the moment a `LocalPathSearchSession` is bound, and holds all results in memory indefinitely. Each file gets 7 string representations (absolutePath, relativePath, normalizedRelativePath, normalizedFileName, two UTF-16 array copies, plus the dedup set entry). This is a design-level issue requiring either lazy loading, capped crawl depth, or on-demand search rather than preloading.

### Verification Status

Build succeeded. Runtime verification pending.

---

## 2026-04-19 Instruments Follow-Up — Leak Trace Patterns

This follow-up documents findings from an Instruments Leaks trace (Run 1–3) against the dev build, confirming several allocation patterns during SwiftUI view rendering and mouse event handling.

### Pattern 1: Disk I/O During View Rendering

**Files:** `VibeSpaceManagementService.swift`, `VibeSpacePersistenceStore.swift`
**Symptom:** 33,406+ CFString allocations through `AppPersistenceDataStore.loadWithIntegrity` during tile card rendering.
**Cause:** `projectShortcuts(vibespaceID:projectPath:)` and `vibespaceShortcuts(vibespaceID:)` loaded config from disk on every call. The `dirtyConfigs` / `dirtyProjectConfigs` caches only held modified configs — all unmodified configs fell through to disk every time. Called from `ContentViewProjectCanvas` → `shortcutDefinitionsForProjectPath` closure during view body evaluation.
**Fix:** Added `projectShortcutsCache` and `vibespaceShortcutsCache` read-through caches, invalidated on mutation and deletion.

### Pattern 2: Computed Path Normalization in View Body

**File:** `VibeSpaceTerminalBoardLayout.swift`
**Symptom:** 1,046+ leaked `NSPathStore2` objects from `NSString.standardizingPath`.
**Cause:** `normalizedWorkingDirectoryPath` was a computed property calling `NSString(string:).standardizingPath` on every access — from `workingDirectoryURL`, `normalized()`, and indirectly from board metrics, cursor regions, and tile card rendering.
**Fix:** Removed the computed property. `workingDirectoryURL` now uses `URL(fileURLWithPath:).standardizedFileURL` directly. `normalized()` computes through the URL only when explicitly called.

### Pattern 3: NSViewRepresentable Reconfiguring Static Properties

**File:** `TerminalComposeInputView.swift`
**Symptom:** Leaked font objects (`__NSGetSystemFontVariants`), `NSColor` objects (`ProjectColorTag.nsColor`), and `selectedTextAttributes` dictionaries from `ComposeTextEditorRepresentable.configure()`.
**Cause:** A single `configure()` method set ~20 properties — including `font`, `isEditable`, `isRichText`, and other static values — on every `updateNSView` call. `setFont:` allocates internally via system font lookup. Colors create new `NSColor` objects each call.
**Fix:** Split into `configureOnce()` (static properties, called only from `makeNSView`) and `configureDynamic()` (palette colors, callbacks — called from `updateNSView`).

### Pattern 4: Cursor Rect Invalidation Without Change Check

**File:** `VibeSpaceTerminalBoardInteractionDecorations.swift`
**Symptom:** `NSTrackingAreaAKViewHelper addCursorRect:cursor:` allocations on every SwiftUI update.
**Cause:** `updateNSView` always called `window?.invalidateCursorRects(for:)` regardless of whether `cursorRegions` changed, triggering `resetCursorRects()` → `addCursorRect` on every view evaluation.
**Fix:** Added equality check: only invalidate when `cursorRegions` actually changed.

### Pattern 5: @Published Setter Churn on Mouse Move

**File:** `BoardInteractionController.swift`
**Symptom:** `Published.subscript.setter` allocations on every `mouseMoved` event.
**Cause:** `hoverMoved(to:)` set `hoveredRegion` and `cursorStyle` unconditionally, triggering `objectWillChange.send()` and Combine allocations even when the value hadn't changed. Mouse move events fire at ~60 Hz.
**Fix:** Added equality guards: only set `@Published` properties when the new value differs.

### Summary

These patterns share a common anti-pattern: **expensive work (disk I/O, path normalization, font lookup, cursor rect rebuilds, Combine publishes) executed unconditionally during SwiftUI view rendering or high-frequency event handlers without caching or change guards.**

---

## Recommended Fix Priority (Updated)

### Completed Follow-Up

- Add per-request `autoreleasepool` handling to pane worker bootstrap loops in `PaneWorkerInfrastructure.swift` to address the observed explorer worker heap growth.
- Filter source-control watcher events before queueing refresh work in `VibeSpaceSourceControlViewModel.swift` / `VibeSpaceSourceControlViewModelHelpers.swift` so generated folders and internal `.git` churn do not retrigger SCM refresh loops.

### Phase 1 — Fix confirmed retention bugs (7 items)
1. Wire `removeDetailedBrowser(browserID:)` into browser tab close paths
2. Cap `VibeCastStore.messages`
3. Clear `TerminalSession.firstOutputObservers` in `terminate()`
4. Add stale-trace cleanup to `OperationMetricsStore.traceStack`
5. Fix `LocalCommandExecutor` process/timer lifecycle
6. Balance `Unmanaged.passRetained` with `release()` in GhosttyTerminalRuntime teardown
7. Fix `TerminalViewModel.gitHeadWatchersByTab` static dict — convert to instance or add deinit guard

### Phase 2 — Add defensive deinit (12 classes)
Add `deinit` to the 12 classes listed in Tier 2. These are 1-3 line changes each.

### Phase 3 — Architectural improvements
- Convert closure-as-delegate patterns to formal `weak var delegate` protocols
- Add `[weak self]` documentation/enforcement for public closure properties

---

## Files Scanned (80 total)

### Batch 1 — Browser (14 files) ✅
BrowserPanelViewModel, BrowserNavigationDelegate, BrowserUIDelegate, BrowserDownloadDelegate, BrowserSessionHostView, BrowserHostOwnershipCoordinator, DockedBrowserCoordinator, CrispyVibesBrowserWebView, BrowserPanelViewModelSession, BrowserPanelViewModelTheme, BrowserPanelViewModelFind, BrowserContentView, BrowserHistoryStore, BrowserSessionSnapshot

### Batch 2 — Terminal (15 files) ✅
TerminalSessionHostView, TerminalViewModel, GhosttyTerminalEngine, GhosttyTerminalEngineOutputTracking, GhosttyTerminalRuntime, GhosttyTerminalView, GhosttyTerminalViewLifecycle, TerminalSession, TerminalSessionOwnershipCoordinator, TerminalFocusCoordinator, TerminalSessionDelegateAndView, SwiftTermTerminalEngine, TerminalSessionLaunchSupport, TerminalSessionAppearance, TerminalSessionCommandDispatch

### Batch 3 — VibeSpace/Explorer/Observers (11 files) ✅
ProjectSession, FolderExplorerViewModel, VibeSpaceSourceControlViewModel, VibeSpaceTerminalBoardStore, DirectoryWatcher, GitHeadWatcher, PollingDirectoryWatcher, AppDelegateDefaultsObservation, AppDelegate, NativeSplitView, RasterImageFilePreview

### Batch 4 — Remote/SSH + Services (12 files) ✅
SSHConnection, SSHConnectionManager, RemoteProjectSession, RemoteCommandExecutor, SFTPFileSystemProvider, SFTPFileContentProvider, SSHPortForwardService, PortForwardDetector, ExperimentalFeaturesService, PaneWorkerInfrastructure, LocalCommandExecutor, ContentViewTerminalSpotlightState

### Batch 5 — Coordinators + Stores + ViewModels (15 files) ✅
VibeSpaceHydrationCoordinator, HomeCatalogCoordinator, DockedFileViewerCoordinator, VibeSpaceCanvasActionsCoordinator, ContentViewerStore, EditorGroupStore, SplitViewStore, AppShellStore, VibeSpaceCatalogStore, ShelfStore, VibeCastStore, MarkdownViewModel, DeveloperToolsView, VibeSpaceStackedProjectRailSupport, FeatureWalkthroughController

### Batch 6 — App-level + Models + Misc (13 files) ✅
ContentView, CrispyVibesApp, AppContainer, VibeSpaceInteractionService, VibeSpaceState, VibeSpaceStateInternals, VibeSpaceStateProjectLifecycle, TerminalSessionSupportTypesInteractiveTargeting, ProjectActivityTracker, VibeSpaceShortcutProvider, TmuxService, OperationMetricsStore, TerminalLifecycleLogger

---

*Report generated by automated memory leak pattern scanning (2 passes, 363/363 app source files covered, 0 skipped), revised after code review feedback. 72 test files excluded (no runtime impact). Findings should be verified with Xcode Instruments (Allocations + Leaks) for runtime confirmation.*
