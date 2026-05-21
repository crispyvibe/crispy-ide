# Shortcuts — Technical Design

## Overview

Complete keyboard shortcut reference for CrispyVibes, covering app menu commands, file operations, find/replace, project and terminal navigation, canvas mode switching, VibeCast, font zoom, vibespace management, dismiss/cancel actions, and debug-only shortcuts.

## Architecture

Shortcuts are registered via SwiftUI `.keyboardShortcut()` modifiers and AppKit `NSMenuItem` key equivalents. Actions are dispatched via `NotificationCenter` posts or direct view model calls depending on context.

## Shortcut Reference

### App Menu

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘ , | Open Settings | Global — opens app settings panel |

### File Operations

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘ S | Save Document | Saves active markdown document |

### Find & Replace

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘ F | Find in Document | Opens find bar in active document |
| ⌘ ⇧ H | Replace in Document | Opens find-and-replace bar in active document |

### Project Navigation

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘ 1–9 | Focus Project by Number | Switches focus to project at sidebar position; in VibeCast, repeated presses cycle that project's terminals |
| ⌘ ⌥ ] | Next Project | Focus next project in vibespace |
| ⌘ ⌥ [ | Previous Project | Focus previous project in vibespace |

### Terminal Navigation

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘ ⌥ ↓ | Next Terminal in Project | Next terminal tab within current project |
| ⌘ ⌥ ↑ | Previous Terminal in Project | Previous terminal tab within current project |
| ⌘ ⌥ → | Navigate Right on Board | Next board column in terminal board |
| ⌘ ⌥ ← | Navigate Left on Board | Previous board column in terminal board |

### Canvas Mode

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘ D | Open Detailed View | Switch to detailed vibespace layout |
| ⌘ T | Open Terminal Board | Switch to terminal-only board layout |

### VibeCast

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘ ⇧ V | Toggle VibeCast | Open/close VibeCast panel |
| ⌘ ↩ | Send Message | Send compose text to targeted terminal |
| ⌘ B | Broadcast | Send compose text to all terminals |
| ⌘ R | Rephrase | AI-rephrase compose text (requires non-empty input) |
| ⌥ ↑ | Cycle Target Up | Select previous terminal target |
| ⌥ ↓ | Cycle Target Down | Select next terminal target |

### Font Size (Zoom)

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘ + | Increase Font Size | +1 pt code/terminal font |
| ⌘ - | Decrease Font Size | −1 pt code/terminal font |
| ⌘ 0 | Reset Font Size | Reset to default |

### VibeSpace Management

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘ ⇧ N | Open VibeSpace | Opens folder picker for new vibespace |

### Dismiss / Cancel

| Shortcut | Action | Context |
|----------|--------|---------|
| Escape | Dismiss Terminal Spotlight | Closes terminal spotlight overlay |
| Escape | Dismiss Link Preview | Closes terminal link preview panel |
| Escape | Close Find Bar | Closes find/replace bar |
| Escape | Cancel Terminal Create Sheet | Dismisses new-terminal creation sheet |

### Dialogs

| Shortcut | Action | Context |
|----------|--------|---------|
| ↩ (Return) | Confirm Create Terminal | Submits new-terminal creation sheet |

### Debug Only

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘ ⌥ ⇧ D | Terminal Diagnostics Snapshot | DEBUG builds only — exports diagnostics snapshot |

## State Management

- Shortcut mappings for ⌘ 1–9 are resolved from `projectShortcutByPath` dictionary in vibespace state
- Positional fallback applies when no explicit mapping exists
- Shortcuts are customizable via App Settings → Shortcuts category (persisted in app storage)

## Dependencies (frameworks, libraries)

- SwiftUI (`.keyboardShortcut()` modifiers)
- AppKit (`NSMenuItem` key equivalents, `NSEvent` monitoring)

## Platform Considerations

- macOS only — relies on AppKit menu system and `NSEvent` key monitoring
- Debug shortcuts gated behind `#if DEBUG` compilation flag

## Performance Constraints

- Shortcut dispatch is synchronous notification post; no measurable latency

## Migration / Rollout Notes

- Shortcut customization persists in app storage; no migration needed for defaults
