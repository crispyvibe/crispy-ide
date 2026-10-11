# 012: NativeSplitView Stale Mouse-Drag Hang

Date: 2026-10-07
Area: App shell / shared split-view infrastructure
Trigger: The installed Crispy application became unresponsive while consuming one CPU core and several gigabytes of memory
Status: Implemented — P0 and independent P1/P2 audit fixes complete; final unit/build validation passed without a runner restart; local UI automation remains unexecuted after an earlier automation-initialization blocker; 60-second CPU/memory stress acceptance remains manual
Severity: Critical (proposed P0)

## Problem

The production Crispy application entered a persistent UI hang. The window stopped responding normally, the main process consumed approximately 100% of one CPU core, and its physical memory footprint reached 4.3–4.4 GB. The explorer, source-control, terminal, and persistence helper processes remained idle, localizing the failure to the main UI process.

Observed application and system:

- Executable: `/Applications/Crispy.app/Contents/MacOS/Crispy`
- Bundle identifier: `com.crispyvibe.app`
- Version: `0.1` (build `32`)
- Process: PID `32137`
- Launch time: 2026-10-04 23:04:07 -0500
- Observation time: 2026-10-07 11:20–11:22 -0500
- Operating system: macOS 26.6.2 (25G83), Apple silicon
- CPU: 99–100% during inspection
- Physical footprint: 4.3 GB in the first sample and 4.4 GB in the second

This is a full application-availability failure. Affected users cannot safely continue editing and may need to quit and relaunch Crispy, risking unsaved in-memory work.

## Live Evidence

Two independent, non-invasive stack samples captured the same main-thread state.

The first sample collected 1,546 main-thread samples over five seconds. All 1,546 followed this path:

```text
NSApplication.sendEvent
└── NSWindow._handleMouseDownEvent
    └── TrackingSplitView.mouseDown(with:)
        └── NSSplitView.mouseDown
            └── nextEventMatchingMask
                └── nested run loop
                    └── SwiftUI flushObservers
                        └── GraphHost.flushTransactions
                            └── AttributeGraph update
```

A second three-second sample collected 269 main-thread samples. All 269 again remained in `TrackingSplitView.mouseDown(with:)` at `NativeSplitView.swift:37`, inside `NSSplitView.mouseDown`.

At the same time, CoreGraphics reported that neither mouse button was held:

```text
left=false right=false
```

This rules out an ordinary active divider drag. The process was trapped in stale mouse tracking after the terminating release event had already occurred or was no longer represented by the current global button state.

Relevant runtime commands were:

```bash
ps -p 32137 -o pid,state,%cpu,%mem,rss,vsz,etime,time,command
sample 32137 5 1
sample 32137 3 10
xcrun swift -e 'import CoreGraphics; print("left=\(CGEventSource.buttonState(.combinedSessionState, button: .left)) right=\(CGEventSource.buttonState(.combinedSessionState, button: .right))")'
```

No process was killed, signaled, or otherwise modified during diagnosis.

## Root Cause

The immediate root cause was an orphaned synchronous AppKit divider-drag loop in the incident-era `TrackingSplitView`.

At the incident revision, `projects/crispyvibes/crispyvibes/Shared/Components/NativeSplitView.swift:33-42` wrapped AppKit's blocking `NSSplitView.mouseDown(with:)` implementation:

```swift
override func mouseDown(with event: NSEvent) {
    let pointInSplitView = convert(event.locationInWindow, from: nil)
    if isPointNearDivider(pointInSplitView) {
        onDividerDragStarted?()
        super.mouseDown(with: event)
        onDividerDragEnded?()
        return
    }
    super.mouseDown(with: event)
}
```

For a divider click, `super.mouseDown(with:)` ran a synchronous AppKit tracking loop and did not return until tracking terminated. Crispy's only drag-end cleanup was after that blocking call. If AppKit did not receive the matching mouse-up event—for example, after an interrupted gesture, focus transition, window/app deactivation, or another event-routing edge case—the following failures became permanent:

1. `super.mouseDown(with:)` never returned.
2. `onDividerDragEnded` was never called.
3. `Coordinator.endDividerDrag()` was never called.
4. `isUserDraggingDivider` remained `true`.
5. Crispy had no cancellation, timeout, app-deactivation, window-deactivation, or global-button-state recovery path.

The live stack and global button state confirmed this failure state. They did not identify which interruption originally caused AppKit to miss or stop recognizing the terminating event.

### CPU and memory amplification

The stale AppKit tracking loop alone explained why the main event handler did not complete. `NativeSplitView` then amplified the failure into sustained CPU and allocation pressure.

Every SwiftUI update invoked `NativeSplitView.updateNSView` (`NativeSplitView.swift:121-131`), which called `updateHostedContent`. That method recreated `AnyView` wrappers and assigned both `NSHostingView.rootView` values every time (`NativeSplitView.swift:213-222`), whether or not pane identity or content changed. While AppKit's nested tracking run loop remained active, SwiftUI observers continued flushing transactions, repeatedly rebuilding and reconciling the hosted view graphs.

This matched the live samples: the stack below `NSSplitView.mouseDown` repeatedly entered SwiftUI transaction flushing and AttributeGraph updates. It also matched the prior finding in `specs/learnings/004-gpu-ui-responsiveness-audit.md`, which had identified unconditional `NativeSplitView` hosted-root replacement as a high-impact CPU/layout invalidation path.

The complete failure was therefore:

- **Primary fault:** stale `NSSplitView` synchronous mouse tracking with no interrupted-drag recovery.
- **Amplifier:** unconditional reconstruction of both SwiftUI hosting roots during nested event-loop updates.
- **Result:** unresponsive UI, one saturated CPU core, continued allocation/layout churn, and multi-gigabyte memory pressure.

## Historical Reproduction Guidance

At the time of the incident, a deterministic reproduction sequence had not been confirmed. The incident indicated the following high-probability test matrix:

1. Open a surface backed by `NativeSplitView`, such as the app sidebar, detailed terminal/content split, multi-project rail, or content-viewer split.
2. Begin dragging a divider.
3. While the mouse is down, exercise interruption cases independently:
   - switch applications with Command-Tab;
   - deactivate or minimize the Crispy window;
   - release the mouse outside the window or on another display;
   - disconnect or reconnect a mouse/trackpad;
   - change Spaces or displays;
   - trigger a SwiftUI state change that replaces or hides the containing surface;
   - collapse the pane or change canvas mode;
   - close the containing window or project surface.
4. Release the mouse.
5. Check whether Crispy remains responsive and whether the main process becomes CPU-bound.
6. If it hangs, capture `sample <pid> 3 10` and verify whether the main thread is in `TrackingSplitView.mouseDown` while `CGEventSource.buttonState` reports `false`.

Testing should use the `crispyvibes-local` scheme and `CrispyLocal.app`; repository guidance prohibits killing or disrupting the main production `Crispy.app` during development.

## Proposed Fix (Historical Plan)

### 1. Remove indefinite drag lifetime from the blocking `mouseDown` wrapper

Do not make application drag state depend solely on code after synchronous `super.mouseDown(with:)` returning. Prefer a cancellable interaction design, such as a dedicated divider drag recognizer or explicit event-tracking state machine that handles `.ended` and `.cancelled` and checks app/window activity.

If native `NSSplitView` tracking must remain, add a separate recovery mechanism that can observe interruption independently of the blocked call. Recovery must cover:

- application resignation/deactivation;
- window resignation, ordering out, or teardown;
- view removal from its window;
- mouse-up observed outside the local view;
- global button state becoming up while Crispy still considers a drag active;
- an upper bound/watchdog for implausibly long divider drags.

A `defer` around `super.mouseDown(with:)` is insufficient by itself because it still cannot run while the blocking call remains stuck.

### 2. Make drag cleanup idempotent

Centralize cleanup so normal end, cancellation, deactivation, teardown, and watchdog recovery all invoke the same idempotent operation. It should clear drag state, remove monitors/observers, and reconcile the persisted divider position once.

### 3. Stop unconditional hosting-root replacement

`updateNSView` should not recreate and reassign both `AnyView` roots on every update. Preserve stable pane hosts and update only when the represented pane identity or relevant content changes. At minimum, suppress root reassignment during an active divider drag and avoid setting `needsDisplay` when the divider appearance is unchanged.

This optimization is independently justified by the existing responsiveness audit and limits the impact of any future nested-loop failure.

### 4. Add diagnostics

Add signposts or structured diagnostics for:

- divider drag begin, end, and cancellation;
- drag duration;
- app/window deactivation during drag;
- stale-drag watchdog recovery;
- hosted-root replacements during a drag.

Avoid logging raw project paths or document contents.

## Pre-Fix Acceptance Criteria

1. Starting and normally completing a divider drag updates and persists the requested size.
2. Every interruption case ends or cancels divider tracking without hanging the main thread.
3. No drag can remain active after CoreGraphics reports the initiating button is up.
4. App/window deactivation and view teardown clear drag state and event monitors.
5. `NativeSplitView` does not replace unchanged hosting roots during divider movement.
6. A 60-second automated interruption stress test leaves `CrispyLocal.app` responsive and near idle CPU after input stops.
7. Repeated interrupted drags do not cause monotonic memory growth.
8. Existing split-size constraints, pane orientation, sidebar placement, and persisted dimensions continue to work.

## Planned Regression Tests (Historical)

Add coverage near the shared component and its major consumers:

- coordinator tests for begin, normal end, cancellation, duplicate cancellation, and teardown;
- an AppKit-level test that starts divider tracking, simulates deactivation/cancellation, and verifies the handler returns;
- UI tests that interrupt drags by changing focus, canvas mode, and pane visibility;
- a test or instrumentation assertion that unchanged SwiftUI updates do not replace both hosted roots;
- a performance test that measures post-interaction CPU and memory stabilization.

Because AppKit event tracking and real window activation are central to this bug, unit tests alone are not sufficient. At least one regression must run against an actual test window in the UI-test target.

## Implementation (2026-10-08)

`NativeSplitView` now uses an explicit, main-actor divider-drag state machine. Divider mouse-down events are consumed without calling `NSSplitView.mouseDown(with:)`; only non-divider mouse-down events are forwarded to AppKit. Local dragged/up monitoring, global mouse-up monitoring, and `mouseDragged`/`mouseUp` overrides feed manual divider positioning through the existing delegate constraint path, preserving orientation, `primaryAtEnd`, minimum/maximum sizing, minimum secondary sizing, and binding persistence.

Each drag receives a monotonically increasing generation. Local/global monitors, lifecycle observers, queued global callbacks, and watchdog timers capture that generation; callbacks from an earlier drag cannot move or finish its replacement. Programmatic reconciliation is also blocked while any drag is active, so a queued final apply from drag A cannot move drag B. Monitor, observer, and timer cleanup remains centralized and idempotent.

Configuration comparison now occurs before replacing the coordinator's parent and covers orientation, `primaryAtEnd`, `minPrimary`, `maxPrimary`, and `minSecondary`. The new parent is installed before one `.configurationChanged` cancellation, so deferred reconciliation uses the new constraints while the next coalesced hosted-content update replaces any content ordered under the old configuration before publication.

Invalid divider geometry no longer recursively schedules itself. Non-finite geometry or a total dimension no larger than the divider stops immediately and waits for a real representable update or `TrackingSplitView` frame-size change. A changed frame schedules one coalesced apply on the next main turn; programmatic divider movement does not recursively trigger the split view's frame-size callback.

Pane hosts retain stable `NSHostingView` roots backed by observable content holders. Ordinary updates and drag-end flushes are coalesced onto the next main-loop turn, so neither `updateNSView`, normal/cancel finish, nor dismantle synchronously publishes holder content. Shutdown invalidates the scheduled publication generation and discards pending content. Divider color invalidation still occurs only when the resolved color changes.

All normal and interrupted endings converge on the same final structured reason/duration event. Global mouse-up is classified as normal completion. Watchdog branches no longer emit a duplicate error before the final cancellation event. Diagnostics contain orientation, placement, reason, duration, and counters but no project or document paths.

The app sidebar split retains the stable accessibility identifier `app.sidebar.split`; the independent audit did not require broader accessibility lifecycle changes. The UI regression now throws `XCTSkip` before fixture creation or launch unless `UITestAppTarget.current == .local`. UI teardown matching explicitly rejects `/Applications/Crispy.app/Contents/MacOS/Crispy` even for `.main`, while still matching DerivedData `Crispy.app` executables. `UITestAppTarget` remains internal to and compiled in the UI-test target. A pure matcher test and a unit-level static source/order audit cover these guards.

## Validation (2026-10-11)

Validation used the isolated `crispyvibes-local` scheme and `DebugLocal` configuration for the unsigned application build; unit tests used the repository's `crispyvibes` test scheme without launching an installed app. The installed production process remained PID 45388 at `/Applications/Crispy.app/Contents/MacOS/Crispy` throughout final validation; no command launched, terminated, or signaled it.

- Final complete unit target: 1,953 tests executed with 0 skipped and 0 failures. The complete run finished without restarting the test runner.
- `NativeSplitViewTests`: 24 tests passed with 0 failures in the focused validation. Coverage holds zero geometry across three run-loop turns without scheduling or applying, then verifies one frame-change request and one successful apply; rejects stale global, local, observer, and queued-reconciliation effects across drag replacement; directly verifies `primaryAtEnd` and constraint configuration changes; verifies deferred single content publication after cancellation and no publication after dismantle; classifies global mouse-up as normal; and statically verifies UI launch/teardown safety.
- Existing split regressions: 51 tests passed with 0 failures in focused validation: 18 `ContentViewerMemoryLifecycleTests`, 18 `ContentViewerStoreTests`, 9 `SplitLayoutEngineTests`, and 6 `SplitPaneLayoutTests`. The combined focused run executed 75 tests with 0 failures.
- UI-test source compilation: `UITestSupport.swift` and `ChromeAndSettingsUITests.swift` compiled in the local test build, including the accessible `UITestAppTarget`, pre-launch local-only skip, installed-production exclusion, and pure DerivedData matcher test.
- Final unsigned `DebugLocal` build: passed with `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, and an empty code-sign identity. Build warnings were pre-existing and outside the NativeSplitView audit files.
- Changed-file language-server diagnostics and project/Info plist validation passed during integrated validation; final documentation checks are recorded separately by the worktree finalization.
- Local UI automation: unexecuted. An earlier isolated `crispyvibes-local` attempt on this host timed out while macOS automation initialized before the test body. No main-target UI test was invoked. The local-only regression remains an acceptance step on an automation-healthy host.

Residual manual acceptance gaps are an actual outside-window interrupted drag in `CrispyLocal.app`, live focus and paint behavior, the 60-second interruption stress/idle-CPU check, and repeated-drag memory stabilization. These require healthy macOS UI automation or manual Instruments/Activity Monitor observation and are not represented as completed by the unit/build evidence.

## Operational Recovery

For an already affected process, quitting and relaunching Crispy is the safest current recovery. If normal Quit is unresponsive, users may need to force quit, with the associated risk of losing unsaved in-memory edits. Development tooling should not attempt to manipulate the production process automatically.

## Lessons

1. Synchronous framework tracking APIs require explicit interruption and cancellation design when application state is coupled to their return.
2. Cleanup placed only after a blocking call is not a recovery mechanism.
3. Global input state is a useful independent check for detecting stale local interaction state.
4. Nested AppKit run loops can continue processing SwiftUI transactions even while the original event handler is stuck.
5. Unconditional representable-host reconstruction turns a recoverable input defect into a CPU and memory incident.
6. Hang diagnosis should combine process resource data, repeated stack samples, independent input-state checks, and source correlation before assigning a root cause.

## Related Files

- `projects/crispyvibes/crispyvibes/Shared/Components/NativeSplitView.swift`
- `projects/crispyvibes/crispyvibes/Features/Home/Views/ContentViewToolbar.swift`
- `projects/crispyvibes/crispyvibes/Features/VibeSpace/Canvas/Views/ContentViewProjectCanvas.swift`
- `projects/crispyvibes/crispyvibes/Features/ContentViewer/Views/SplitContainerView.swift`
- `specs/learnings/004-gpu-ui-responsiveness-audit.md`
