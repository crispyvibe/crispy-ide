# Terminal Inline Triggers — Technical Design

## Overview

Terminal Inline Triggers add one shared typed-trigger controller layer across terminal-adjacent input surfaces. The feature watches the active draft or terminal input stream, detects the active trigger token, resolves context-aware results, and presents a picker that can replace only that token with a reviewed insertion.

The current implementation spans direct terminal input, terminal spotlight compose, ACP compose, VibeCast compose, and one board-scoped overlay used when those surfaces live inside dense board layouts.

## Architecture

### Core Responsibilities

1. Detect the active trigger token from the current input buffer.
2. Resolve the owning terminal or project context for that token.
3. Build a unified picker model from path results, shortcut matches, and built-in actions.
4. Present the picker inline or through the shared board popup.
5. Replace only the active token on confirm and return focus to the source surface.
6. Tear down picker-scoped work immediately on dismiss or context loss.

### Main Components

| Component | Responsibility |
|-----------|----------------|
| `TerminalInlineTriggerController` | Incremental trigger parsing and insertion for direct terminal-style input streams |
| `SpotlightComposeInlineResultProvider` | Builds the result model for compose-driven surfaces |
| `SpotlightComposePathSearchController` | Owns picker-scoped local path-search lifecycle and publishes path results |
| `SpotlightComposeInlinePromptService` | Runs the built-in generate-command action |
| `TerminalComposeInputView` | Captures picker keyboard commands and routes buffer updates from compose surfaces |
| `BoardInlinePickerOverlayController` | Publishes one shared board-scoped popup model and routes confirm/cancel back to the origin |
| `ACPStandalonePaneContentView` / ACP compose views | Bind full-buffer text editing into the shared trigger model |
| `VibeCastView` | Hosts the same trigger model in agent compose surfaces |

### Presentation Modes

| Mode | Used By | Notes |
|------|---------|------|
| Inline panel | Direct terminal and compact compose surfaces | Anchored to the owning input surface |
| Shared board popup | Board-hosted terminal, ACP, and VibeCast surfaces | Centered overlay that avoids tile clipping and layout shifts |

## Data Flow

### Trigger Detection

1. The owning surface reports text updates through incremental input handling or a full-buffer sync path.
2. The trigger controller identifies the active whitespace-delimited token containing the configured trigger.
3. If no active token exists, picker state is cleared and search resources are released.
4. If an active token exists, the controller extracts:
   - the visible query text
   - the token replacement range
   - the owning terminal or project context

### Result Assembly

1. Path results are requested when the current context can resolve filesystem candidates.
2. Saved terminal shortcuts are filtered against the same query.
3. One built-in `Generate Command` action is added.
4. `Manage Shortcuts…` is added when the source surface exposes a callback.
5. The composed result model is published to the active presenter.

### Confirmation

1. The presenter returns the selected result to the source controller.
2. The controller replaces only the active trigger token.
3. Focus is returned to the originating input surface.
4. No command or message is auto-submitted as part of the replacement.

### Dismissal

1. `Escape`, close button, token removal, or source-surface teardown dismisses the picker.
2. The controller suppresses reopening for the same token instance.
3. Search tasks, helper processes, observers, and published board-popup state are released.

## API / Command Contracts

### Source Surface Contract

Each participating surface must provide:

- current text buffer or incremental terminal input events
- cursor or replacement-range support
- terminal or project context needed for path resolution
- callbacks for confirm, dismiss, and optional shortcut management

### Presenter Contract

Presenters consume a view model containing:

- active query text
- ordered file and directory results
- ordered shortcut results
- built-in action rows
- selected pane and selected row
- footer hints and optional result count

Presenters must support:

- selection movement (`Up`, `Down`, `Right Arrow`)
- confirm (`Tab`, `Enter`)
- dismiss (`Escape`, close button)

## State Management

### Query State

The active query is derived from the current trigger token and is rendered back into the popup chrome so users can see and edit what is being matched. Query updates must replace the existing visible query state rather than append duplicate text.

### Focus Routing

The source surface remains the canonical focus owner. The popup can own selection state, but confirmation and dismissal both route focus back to the originating compose field or terminal input target.

### Board Popup Ownership

`BoardInlinePickerOverlayController` holds the currently presented popup model for the active board. Individual tiles do not permanently own popup view state. This prevents duplicate popups and avoids tile-local clipping.

## Dependencies

- SwiftUI and AppKit event routing for keyboard handling
- terminal session models and spotlight coordinators for context resolution
- shortcut/settings infrastructure for trigger configuration and shortcut management
- bundled local path-search helper for local filesystem search

## Platform Considerations

- The local path-search helper must ship inside the app bundle and launch from an executable location appropriate for macOS app sandboxing rules.
- Helper lifecycle must be picker-scoped. Inline triggers must not keep a helper alive after the picker closes.
- Remote SSH terminals require a different backend contract than local path search because the remote filesystem is not directly available to the app process.

## Performance Constraints

- Trigger detection must remain on the active editing path without causing visible typing lag.
- Picker updates must not reflow terminal board layout.
- Query updates must avoid repeated full-tree Swift-side crawls on the main actor.
- Picker dismissal must stop search work promptly enough to avoid orphan background activity.

## Migration / Rollout Notes

- The canonical product definition now lives under `specs/features/terminal/inline-triggers/`.
- Existing terminal spotlight, ACP, VibeCast, and board specs may still reference inline-trigger behavior where it intersects their feature boundaries, but F038 owns the shared behavior model.
- Remote SSH path-result parity remains planned work. The interaction model is specified now so later backend work can plug into the same presenter contract.
