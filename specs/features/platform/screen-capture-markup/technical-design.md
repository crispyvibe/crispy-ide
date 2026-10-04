# Screen Capture & Screenshot Studio — Technical Design

## Overview
F062 is a single state machine from explicit command to visible selection, acquisition, and Screenshot Studio. Selection/TCC/geometry remain transient. Studio owns memory editing and delegates ordered clipboard/history output. Automatic delivery and secondary Copy keep Studio open. Primary Copy & Dismiss records the selected item/revision and dismisses only after guarded clipboard plus flattened-history publication. Local history is bounded, flattened, privacy-whitelisted, and race-safe.

## Architecture
```text
File menu / app toolbar / Carbon ⇧⌘2
                 │
                 ▼
      ScreenCaptureCoordinator.beginCapture()
        ├─ ScreenCaptureTCCAuthorizer
        ├─ ScreenCaptureKitStillProvider
        ├─ ScreenCaptureOverlayController
        ├─ ScreenCaptureSurfaceRegistry
        ├─ OriginFocusTracking (cancel/failure only)
        └─ ScreenshotStudioCoordinator
             1. ScreenshotStudioViewModel.installNewCapture
             2. ScreenshotStudioWindowController.presentOrFocus
             3. ScreenshotStudioViewModel.deliverCurrentCapture
                    └─ ScreenCaptureDeliveryCoordinator
                       ├─ RasterImageExporting
                       ├─ ScreenCaptureOutputEncoding
                       ├─ ScreenCaptureClipboardDelivering
                       └─ ScreenCaptureHistoryRepository
```

`AppContainer+ScreenCapture.swift` is the sole concrete root. It derives exactly one history URL from injected `AppPersistenceDataStore`, constructs one repository/store, and injects factories for delivery, Studio view models, and the panel. No F062 type discovers Application Support or creates a concrete repository outside the composition root.

`ScreenCaptureServices` owns startup and shutdown: history load, Carbon binding, coordinator-state recovery observation, selection, Studio, output callbacks, history store, and registration teardown.

## Data Flow
1. All three entry surfaces call `beginCapture()` with no intent parameter.
2. Coordinator captures ephemeral origin focus, then explicitly checks/requests TCC.
3. Provider returns a privacy-minimized catalog: display geometry plus window IDs/frames only, no app/window names.
4. Selection commits one generation/topology-bound target and updates remembered mode.
5. F062 UI is dismissed/filtered, a compositor barrier passes, and ScreenCaptureKit acquires immutable pixels.
6. Coordinator creates `AcquiredScreenCapture`, calls the one Studio route, and clears origin.
7. Studio installs Current and fresh F009 Markup/Pen state; the controller creates/focuses one utility panel without ordering the main IDE.
8. Only after presentation, delivery eagerly encodes raw PNG/TIFF, replaces the clipboard, and queues flattened PNG history add.
9. Genuine edits debounce 250 ms. Export → eager encode → clipboard → serialized item update refreshes flattened source, thumbnail, and rail metadata. Secondary Copy cancels debounce and starts this pipeline immediately without dismissing.
10. Primary Copy & Dismiss records item ID plus current session revision, cancels debounce through `copyNow`, and waits for `deliveryCompleted(itemID, revision)`. Delivery emits completion only after successful full-resolution render/encode, clipboard commit, flattened add/update commit, and guarded entries/thumbnail publication.
11. History selection decodes off-main and installs only when request UUID/generation is current.

## API / Command Contracts
- `AppShortcutAction.captureScreen` and `GlobalCaptureShortcutCommand.captureScreen` are the only screenshot actions.
- `ScreenCaptureCoordinator.beginCapture()` has no route parameter.
- `ScreenCaptureStudioRouting.present(_:)` is the only success route.
- `AcquiredScreenCapture` contains only ID and immutable image/placement facts.
- `ScreenCaptureHistoryRepository` exposes load/add/update/thumbnail/source/delete/clear.
- `ScreenshotStudioViewModel` exposes named install, delivery, selection, copy, delete, clear, retry, refresh, close, and shutdown methods.

## State Management
Coordinator state is `idle → checkingPermission → preparingCatalog → selecting → capturing → presentingStudio`, with permission/failure/shutdown branches. Session generations reject stale acquisition completions. Success clears origin immediately after Studio routing; cancel/failure restores then clears it.

Studio has one current item, recent metadata, presentation thumbnails, latest selection request, editor session/baseline, working status, structured failure, and optional pending-dismiss item/revision. It never stores origin identity. Copy & Dismiss disables duplicate delivery actions while pending. A different selection/install or matching failure clears pending ownership. Only matching `deliveryCompleted` for the same current item and a revision at least requested consumes and nils `onClose` before invoking it once.

Delivery uses a global clipboard token, per-item generations, per-item serialized persistence tails, cancellable debounce/output/render handles, and active-item checks. Clipboard is committed before history work for each successful output; older item/revision completions cannot replace the active clipboard. Revision and `clipboardCommitted` travel with persistence. An `.add` that receives only `itemAlreadyExists` rechecks cancellation/generation/token and retries as `.update`; other failures remain typed. Completion follows guarded history-store, entries, and thumbnail publication and is suppressed after any clipboard/history/publication failure.

Repository uses clear epochs, generations, tombstones, staging, private trash, immutable version filenames, and atomic current metadata replacement. Clear retires the entire visible items directory before recreating it.

## Persistence and Migration
Canonical preference v3 JSON keys are `schemaVersion`, `mode`, `delay`, and `includesPointer`. Decoder reads legacy nested `options` fields independently and ignores unknown `postCaptureBehavior`; store immediately writes v3.

Shortcut override migration runs in `AppContainer+ScreenCapture` before preferences, shortcut settings, or Carbon manager construction. Existing `captureScreen` override/disabled state wins. Otherwise first enabled `captureAndMarkup`, then `captureToClipboard`, is copied. All three obsolete keys, including `repeatLastArea`, are removed. Repeated execution is idempotent.

History root:
```swift
appPersistenceStore.appFileURL(
  relativePath: "ScreenCapture/History",
  isDirectory: true
)
```
The root must be local/non-ubiquitous and excluded from backup. Each item contains exact-whitelist `current.json`, one current flattened canonical metadata-free PNG, and one <=320 px aspect-fit thumbnail. Retention is maximum 50 and 30 days.

## Failure and Lifecycle
Permission/acquisition failure restores origin and never enters Studio delivery. Permission Recheck and Cancel first dismiss the active recovery surface, then respectively begin a new capture or cancel to idle. Any subsequent non-recovery coordinator state also dismisses an active recovery surface, so recovery cannot coexist with selection or Studio. Studio output/history failures preserve Current, clear pending dismissal, and provide Copy retry or history refresh. Plain Copy never closes. Copy & Dismiss closes only from guarded completion, after required clipboard and history commits/publication; controller shutdown therefore cannot cancel those required commits early. Delete/clear invalidate presentation and output tokens before repository mutation. Shutdown cancels selection, selection decode, thumbnails, debounce, render, encode, persistence/mutation tasks, clears callbacks, closes the panel, unregisters Carbon, and clears published store state. Cancellation checks prevent work that has not reached its atomic disk commit and all token/generation checks suppress late clipboard, history-store, thumbnail, event, and UI publication. Cancellation is not rollback: if repository `add` or `update` completed its atomic disk commit before cancellation was observed, the flattened version may remain on disk; startup/next load discovers it and applies ordinary validation and retention pruning without publishing to the shut-down UI.

## Dependencies
- ScreenCaptureKit, CoreGraphics/ImageIO, AppKit/SwiftUI, Carbon hot keys.
- Existing F009 memory editor/exporter and app persistence root.
- No network, cloud, Accessibility API, event tap, CoreData, or SwiftData dependency.

## Platform Considerations
Screen Recording TCC and actual ScreenCaptureKit pixels require a signed interactive macOS run. Hardware UI tests remain gated by `CRISPY_F062_HARDWARE_UI=1`. Universal Clipboard and third-party clipboard managers are external macOS behavior.

## Performance Constraints
- Reject capture work above 64 megapixels or estimated 512 MiB working set.
- Thumbnail maximum dimension 320 px.
- Edit output debounce 250 ms and coalescing.
- Maximum 50 history entries / 30 days.
- Heavy image/file work runs off the main actor; published UI state returns to main.

## Migration / Rollout Notes
The old Quick Access, post-capture router, HUD, file promise, explicit Save As, dirty decision, Last Capture, Repeat/Reopen, Copy & Return, and optional command rows are removed rather than deprecated. Studio-local Copy & Dismiss is restored as a post-commit close action and never returns to the origin application. Existing raw preferences and overrides migrate at startup; pixels are never migrated from the old transient product because it had no history.

## Change History
| Date | Change | Author |
|---|---|---|
| 2026-10-04 | Restored Studio-local Copy & Dismiss with revision-bound post-clipboard/history completion and add-collision fallback. | — |
| 2026-10-04 | Added dismiss-first permission recovery actions and non-recovery-state stale-panel teardown. | — |
| 2026-10-04 | Documented the cancellation versus completed atomic disk commit boundary and guaranteed suppression of late publication. | — |
