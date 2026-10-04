# Screen Capture & Screenshot Studio — Spec
Status: implemented

## Overview
F062 provides one system-wide still-screenshot command. A user visibly selects a Region, Window, or Display; the successful image is installed in Screenshot Studio, the Studio is presented or focused, and eager PNG/TIFF clipboard plus flattened local-history delivery begins. Screenshot Studio stays open for Markup/Pen annotation and history browsing. Automatic edited-output refresh remains active; secondary **Copy** manually refreshes the same pipeline and stays open, while primary **Copy & Dismiss** closes only after the selected revision reaches both clipboard and flattened history. There are no alternate post-capture routes, Quick Access, repeat/reopen commands, file promises, or return-to-origin delivery actions.

## Dependencies
- F009 Previews — memory-backed raster editing, rendering, and Markup tools.
- F016 Keyboard Shortcuts — configurable system-wide shortcut storage and conflict UI.
- F036 App Settings — capture preferences, TCC status, and history clearing.
- macOS ScreenCaptureKit, Screen Recording TCC, AppKit clipboard, and local Application Support storage.

## Requirements
### F062-R01: One capture command
Crispy MUST expose only `captureScreen`: **File > Capture Screenshot…**, one app-wide camera toolbar action, and one configurable system-wide shortcut. The default MUST be ⇧⌘2. All entry points MUST call the same `beginCapture()` workflow. Apple ⇧⌘3/4/5 remain reserved. No Repeat or Reopen menu surface is permitted.

### F062-R02: Early shortcut migration
Before shortcut-store or Carbon registration construction, an idempotent migration MUST preserve an existing `captureScreen` override, including disabled state. If absent, it MUST adopt the first enabled binding from legacy `captureAndMarkup`, then `captureToClipboard`; it MUST remove those keys and `repeatLastArea` in every case.

### F062-R03: Preference schema v3
Schema v3 MUST persist only schema version, remembered Region/Window/Display mode, delay, and pointer inclusion. V1/v2 MUST decode field-by-field, discard `postCaptureBehavior`, apply safe defaults to missing/invalid fields, and immediately persist canonical v3.

### F062-R04: Visible selection and cancellation
Region release or keyboard commit, Window click/Return, and Display click/Return MUST visibly commit one target. Escape/cancellation MUST stop the attempt and restore the origin focus context. Region selection is limited visibly to one display.

### F062-R05: Permission and failure recovery
TCC MUST be probed/requested only after explicit capture intent. Denied, revoked, relaunch-required, topology, protected-content, resource, and acquisition failures MUST present applicable recovery without clipboard/history mutation. Cancellation/failure MUST restore origin; a successful Studio route MUST clear origin.

### F062-R06: Pixel-accurate capture and exclusion
Window captures MUST support spanning windows, Display captures MUST use native backing dimensions, and Region coordinates MUST map to native pixels. Selection, recovery, Studio, and other F062 windows MUST be excluded or hidden behind the compositor barrier before acquisition.

### F062-R07: One successful route
On acquisition success, the coordinator MUST install the new current item in Screenshot Studio and present/focus its single panel before eager delivery starts. No persisted setting or command may branch the route.

### F062-R08: Screenshot Studio
Studio MUST be a separate utility panel on the captured display/current Space, no larger than 80% of the visible frame. It MUST focus itself without revealing or ordering the main IDE window. Repeated capture MUST reuse the open panel and reposition for a newly captured display. Native and explicit close MUST release Studio work.

### F062-R09: Initial editor state
Every newly captured or history-selected image MUST create a fresh memory-backed F009 session in **Markup** mode with **Pen** selected. Studio MUST keep the image open after Copy and annotation delivery.

### F062-R10: Eager clipboard delivery
After Studio is installed and presented, raw capture output MUST be eagerly encoded as complete PNG and TIFF representations before one general-pasteboard replacement. Crispy MUST never synthesize paste. Clipboard failure MUST preserve the current Studio image and expose retry.

### F062-R11: Automatic edited-output refresh
A genuine annotation revision MUST debounce 250 ms, render full-resolution flattened output once, eagerly encode once, refresh the clipboard, then update that item’s flattened PNG and thumbnail. Secondary **Copy** MUST cancel pending debounce, use the identical pipeline immediately as a manual refresh/retry, and leave Studio open. Installation/revision zero MUST not trigger a feedback loop.

### F062-R12: Current/recent history rail
Studio MUST display Current plus newest-first Recent items and presentation-only thumbnails. Latest requested history selection wins; cancellation/failure MUST preserve the current editor. Thumbnail loading MUST never reinstall the editor.

### F062-R13: Bounded local history
Flattened PNG history MUST remain under the AppContainer-injected local root, excluded from backup, with no cloud/network path. Startup MUST remove interrupted staging/trash/orphan/corrupt items. Retention MUST be newest-first, maximum 50 entries and 30 days.

### F062-R14: History privacy metadata
Persisted metadata MUST use an exact whitelist containing only item/version identifiers, timestamps, canvas/export dimensions, pixel dimensions, and opaque relative filenames. It MUST contain no source target, app/window title, origin application, path, annotation text/layers, clipboard data, or OCR/index data. PNG output MUST be canonical and metadata-free.

### F062-R15: Delete and clear
Studio MUST support per-item delete and clear-all; Settings MUST provide **Clear Screenshot History** with count/progress/failure status. Delete/clear MUST invalidate pending render/encode/persistence tokens before repository mutation and prevent stale resurrection.

### F062-R16: Atomic and race-safe history
Add MUST stage/validate/atomically publish one item. Update MUST publish immutable content versions via atomic `current.json` replacement. Delete MUST privately retire before removal. Clear MUST atomically retire the items directory. Generations, tombstones, and clear epochs MUST reject stale add/update/selection completions and clear/add races. Cancellation prevents work that has not reached its atomic disk commit; it is not rollback. An add/update version atomically committed before cancellation MAY remain on disk for normal discovery and retention pruning on the next load.

### F062-R17: Lifecycle and composition
`AppContainer+ScreenCapture` MUST be the sole concrete composition root and derive the root only from `appPersistenceStore.appFileURL(relativePath:"ScreenCapture/History", isDirectory:true)`. `ScreenCaptureServices` MUST own history load/start/shutdown, shortcut registration, recovery, coordinator, and Studio lifecycle. Shutdown/cancellation MUST suppress late clipboard, history-store, thumbnail, and event/UI publication and prevent work not yet atomically committed; it MUST NOT claim rollback of an add/update disk commit that already completed.

### F062-R18: Settings surface
Settings MUST show exactly one screenshot shortcut plus remembered mode, delay, pointer, permission actions, and Clear Screenshot History status/control. It MUST not show post-capture behavior or optional screenshot-command rows. Views MUST call view-model methods only.

### F062-R19: Copy & Dismiss delivery guarantee
Studio MUST expose localized primary **Copy & Dismiss** with stable identifier `screenCapture.studio.copyAndDismiss`, bordered-prominent style, and default Return shortcut, alongside secondary stay-open **Copy** and separate Close/Escape. The ViewModel MUST require a current item and installed session, record item ID and requested revision, prevent duplicate requests, and invoke immediate `copyNow` without optimistic close. Delivery MUST carry revision and clipboard-commit state through persistence and emit `deliveryCompleted(itemID, revision)` only after full-resolution output, successful clipboard commit, flattened history add/update commit, and guarded entries/thumbnail publication. A matching completion with revision at least requested and the same selected item MUST clear pending state, nil close ownership, and invoke it exactly once. Any matching failure MUST clear pending state, preserve Studio/current edits, and expose retry. Clipboard or history failure MUST NOT emit completion. A manual `.add` colliding with an already committed initial add MUST retry only `itemAlreadyExists` as `.update` under unchanged generation/token/cancellation guards; other errors MUST propagate.

## Scenarios
### Scenario F062-S01: Default shortcut (Given / When / Then)
Given no override, when Crispy starts, then ⇧⌘2 is registered for `captureScreen` and the shortcuts UI contains one screenshot row.

### Scenario F062-S02: Legacy shortcut migration (Given / When / Then)
Given old override keys, when composition starts, then existing `captureScreen` wins or the first enabled legacy binding is adopted, obsolete keys are removed, and rerunning migration changes nothing.

### Scenario F062-S03: Preference migration (Given / When / Then)
Given v1/v2 JSON with independent valid/invalid fields and post-capture behavior, when loaded, then valid mode/delay/pointer fields survive, invalid fields default, behavior is discarded, and canonical flat v3 is stored.

### Scenario F062-S04: Region cancellation (Given / When / Then)
Given capture began from another app, when the user presses Escape, then selection closes, origin is restored, and no Studio/clipboard/history side effect occurs.

### Scenario F062-S05: Window acquisition (Given / When / Then)
Given a spanning window, when clicked or committed with Return, then its complete desktop-independent bounds are captured and routed only to Studio.

### Scenario F062-S06: Display acquisition (Given / When / Then)
Given a Retina display, when committed, then native backing pixels are captured and Studio appears on that display.

### Scenario F062-S07: Successful unified route (Given / When / Then)
Given acquisition succeeds, when routing begins, then Current is installed, the sole Studio panel is visible/focused, and only afterward eager delivery starts.

### Scenario F062-S08: Initial raw delivery (Given / When / Then)
Given Studio is visible with a new capture, when encoding completes, then complete PNG/TIFF replace the clipboard once and one flattened history item appears.

### Scenario F062-S09: Markup edit refresh (Given / When / Then)
Given Studio starts in Markup/Pen, when edits settle for 250 ms, then one flattened render refreshes clipboard, source, thumbnail, and rail metadata while Studio stays open.

### Scenario F062-S10: Explicit Copy (Given / When / Then)
Given pending edits, when Copy is selected, then debounce is cancelled, the same full-resolution pipeline runs immediately, and Studio remains open.

### Scenario F062-S11: Latest history selection wins (Given / When / Then)
Given two delayed history selections, when the second completes first, then only the second is installed; stale/failing selection preserves the prior editor.

### Scenario F062-S12: Delete during output (Given / When / Then)
Given render/encode/update is pending, when that item is deleted, then output is invalidated first and no stale completion restores it or changes the active clipboard.

### Scenario F062-S13: Clear/add race (Given / When / Then)
Given persistence is pending, when clear-all retires history, then old generations cannot republish and later explicit captures may add only in the new epoch.

### Scenario F062-S14: Corrupt startup item (Given / When / Then)
Given corrupt metadata/image or interrupted staging, when history loads, then bad content is privately quarantined/removed and valid recent entries remain available.

### Scenario F062-S15: Retention (Given / When / Then)
Given more than 50 items or items older than 30 days, when loading/adding, then only the newest eligible 50 remain.

### Scenario F062-S16: Clipboard ordering (Given / When / Then)
Given output for item A is late and item B becomes active, when A completes, then it cannot overwrite B’s clipboard/status; B’s current generation wins.

### Scenario F062-S17: Permission failure (Given / When / Then)
Given TCC is denied/revoked/relaunch-required, when capture starts, then applicable recovery appears, origin is restored, and no provider/clipboard/history route runs.

### Scenario F062-S18: Shutdown (Given / When / Then)
Given selection, thumbnails, rendering, encoding, or persistence is pending, when F062 shuts down, then tasks, callbacks, panels, registrations, and published history are released; no late clipboard, history-store, thumbnail, event, or UI publication occurs, and work not yet atomically committed is prevented. Shutdown is not rollback: if an add/update disk commit completed first, that flattened local-history version may remain and is discovered/pruned normally on the next load.

### Scenario F062-S19: Copy & Dismiss latest revision (Given / When / Then)
Given a selected item with a pending annotation debounce, when Copy & Dismiss or Return is invoked, then debounce is cancelled, the current requested revision is rendered once, complete PNG/TIFF reaches the clipboard, flattened history and thumbnail publication complete, and only then Studio closes exactly once.

### Scenario F062-S20: Copy & Dismiss failure (Given / When / Then)
Given Copy & Dismiss is pending, when clipboard or flattened-history add/update fails, then no completion is emitted, pending state clears, Current and its edits remain open with structured retry, and a later retry can succeed. Clipboard failure may still persist flattened history but cannot close Studio.

### Scenario F062-S21: Manual flush races initial add (Given / When / Then)
Given initial auto-add is atomically committed but not yet registered/published, when Copy & Dismiss manually flushes the same item as add, then `itemAlreadyExists` is retried as update under the same guards, one item remains in history, latest output publishes, and Studio closes.

### Scenario F062-S22: Stale completion cannot close replacement (Given / When / Then)
Given pending Copy & Dismiss ownership, when completion has an older revision, another item becomes selected, shutdown occurs, or completion repeats, then it cannot close a replacement/current different item; a valid matching completion nils close ownership before invoking it exactly once.

## Test Coverage Mapping
| Scenario | Automated test method(s) | Hardware/manual coverage |
|---|---|---|
| F062-S01 | `test_onlyOneScreenCaptureDescriptorUsesEnabledShiftCommand2SystemWide` | Carbon registration is covered by the injected registration policy. |
| F062-S02 | `test_existingCaptureScreenDisabledOverrideWinsAndLegacyKeysAreRemoved` | Automated migration coverage. |
| F062-S03 | `test_schemaV1DecodesFieldByFieldDiscardsBehaviorAndPersistsCanonicalV3` | Automated persistence-policy coverage. |
| F062-S04 | `test_cancelledSelectionRestoresOriginAndDoesNotPresentStudio` | Hardware/manual keyboard route: `test_keyboardCancelRestoresWithoutPresentingStudio`. |
| F062-S05 | `test_F062_S05_spanningWindowUsesDesktopIndependentTargetWithoutDisplayClipping` | Hardware/manual ScreenCaptureKit route: `test_windowAndDisplayCaptureUseTheSingleStudioRoute`. |
| F062-S06 | `test_F062_S06_displayTargetUsesFullNativeBackingDimensions` | Hardware/manual native-pixel/current-display verification is gated by `CRISPY_F062_HARDWARE_UI=1`. |
| F062-S07 | `test_studioCoordinatorInstallsPresentsThenStartsEagerDelivery` | Hardware/manual panel focus and current-Space placement. |
| F062-S08 | `test_initialAutoCopyThenAnnotatedRevisionRefreshesClipboardAndHistory` | Hardware/manual general/Universal Clipboard behavior remains platform-dependent. |
| F062-S09 | `test_debounceCoalescesRevisionsAndRevisionZeroDoesNotLoop` | Hardware/manual Markup/Pen interaction: `test_studioStartsInMarkupWithPenAndExposesHistoryControls`. |
| F062-S10 | `test_manualCopyCancelsDebounceAndUsesSamePipeline` | Hardware/manual Copy control: `test_studioShowsCurrentAndRecentHistoryRailWithCopyRemainingOpen`. |
| F062-S11 | `test_historySelectionLatestWinsAndFailurePreservesCurrentEditor` | Automated view-model ordering coverage. |
| F062-S12 | `test_deleteAndClearInvalidatePendingOutputBeforeRepositoryMutation` | Automated delivery-policy coverage. |
| F062-S13 | `test_updateCannotResurrectEntryClearedWhileImageWorkWasPending` | Automated clear-epoch/repository policy coverage. |
| F062-S14 | `test_startupCleansInterruptedStagingOrphansAndIsolatesCorruptItems` | Automated repository recovery coverage. |
| F062-S15 | `test_retentionKeepsNewestFiftyEntries`<br>`test_retentionRemovesEntriesOlderThanThirtyDays` | Automated count/age policy coverage. |
| F062-S16 | `test_itemACompletionCannotOverwriteClipboardAfterItemBActivation` | Automated clipboard-token ordering coverage. |
| F062-S17 | `test_permissionRecoveryRecheckDismissesOnceBeforeStartingCapture` | Hardware/manual signed TCC behavior is gated by `CRISPY_F062_HARDWARE_UI=1`. |
| F062-S18 | `test_shutdownDuringPendingAddPublishesNoItemOrLateSideEffect` | Automated lifecycle coverage; interactive process termination remains manual. |
| F062-S19 | `test_copyAndDismissCancelsPendingDebounceCommitsRequestedRevisionAndClosesOnce`<br>`test_copyAndDismissProductionPixelsClosesPanelOnlyAfterClipboardAndHistoryPublication` | Production raster/PNG/TIFF, named pasteboard, temp repository, and panel timing are automated. |
| F062-S20 | `test_copyAndDismissClipboardFailurePersistsButStaysOpenAndRetryable`<br>`test_copyAndDismissHistoryAddFailureAfterClipboardStaysOpenWithRetry`<br>`test_copyAndDismissHistoryUpdateFailureAfterClipboardStaysOpen` | Automated clipboard/add/update failure coverage. |
| F062-S21 | `test_initialCommittedAddRaceFallsBackToUpdateAndCopyAndDismissClosesWithoutDuplicate` | Automated committed-add/publication race coverage. |
| F062-S22 | `test_staleCompletionDifferentSelectionAndShutdownCannotCloseReplacement`<br>`test_deliveryCompletionNilsCloseOwnershipBeforeExactlyOneCallback`<br>`test_plainCopyPersistsAndStaysOpen` | Automated stale/repeated completion, ownership, shutdown, and plain-Copy coverage. |

## Acceptance Criteria
- Automated unit/integration coverage maps F062-S01–S22, including repository concurrency/recovery, Studio delivery ordering, Copy & Dismiss failure/race handling, and one-shot close ownership.
- Hardware/TCC UI checks for real ScreenCaptureKit acquisition, native dimensions, current-Space panel placement, keyboard/VoiceOver routes, and TCC behavior remain manual-gated with `CRISPY_F062_HARDWARE_UI=1`.
- PBX, localization, build, dead-code, and route-string audits contain no obsolete production surface.

## Open Questions
None.

## Change History
| Date | Change | Author |
|---|---|---|
| 2026-10-04 | Restored primary Copy & Dismiss with post-clipboard/history completion, failure preservation, add-collision fallback, and S19–S22 coverage. | — |
| 2026-10-04 | Added concrete S01–S18 test coverage mapping and dismiss-first permission recovery behavior. | — |
| 2026-10-04 | Clarified S18/R16/R17 atomic disk commit boundaries: cancellation suppresses late publication and uncommitted work but does not roll back a completed add/update commit. | — |
| 2026-10-04 | Replaced the multi-route product with one Screenshot Studio route, eager clipboard delivery, bounded local history, schema v3, and one shortcut. | — |
