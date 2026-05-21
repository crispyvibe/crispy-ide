# VibeCast — Technical Design

## Overview

Technical design is still incomplete, but the current implementation already has one important architectural rule: all VibeCast compose surfaces share the same inline-trigger behavior model while adapting presentation to the hosting surface.

## Architecture

### Inline Trigger Integration

`VibeCastView` resolves a target terminal context and derives:

- search roots from the target tab working directory and owning project root
- shortcut rows from the target terminal view model
- one built-in generate action

The compose surface then runs one unified inline trigger flow that replaces only the active trigger token rather than sending immediately.

Presentation varies by host:

- content viewer and spotlight render the picker inline above the compose input
- terminal board tiles publish picker state into the shared board popup controller

The board popup is intentionally two-pane so that path results remain separate from action-oriented items such as generate, shortcuts, and `Manage Shortcuts…`.

## Data Flow

### Inline Trigger Data Flow

1. User types the configured trigger in the VibeCast compose input.
2. `VibeCastView` parses the active trigger token from the compose buffer.
3. Path search runs against the resolved target terminal context.
4. Results are merged into:
   - file and directory rows
   - shortcut rows
   - the generate action
5. Confirmation replaces only the active trigger token in the compose text.
6. Cancel restores focus to the same compose input without sending.

## API / Command Contracts

_Pending._

## State Management

_Pending._

## Dependencies (frameworks, libraries)

_Pending._

## Platform Considerations

_Pending._

## Performance Constraints

_Pending._

## Migration / Rollout Notes

_Pending._
