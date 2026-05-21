# tmux Integration — Technical Design

## Overview

Technical design pending. This document will cover the architecture, data flow, and implementation details for tmux availability detection, session lifecycle, quit/close behavior policies, server option management, session manager UI, persistence, vibespace sessions browser integration, remote tmux support, and bulk cleanup.

## Architecture

_Pending._

## Data Flow

_Pending._

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

## External Integration

### tmux (Experimental)

Purpose:

- Terminal session persistence across app restarts
- Shell state, scrollback, and running processes survive quit and relaunch

Behavior:

- Enabled via Settings > Experimental > tmux Integration toggle
- Binary detected at `/opt/homebrew/bin/tmux`, `/usr/local/bin/tmux`, or `/usr/bin/tmux`
- Local terminal tabs get a unique tmux session named `crispyvibes-<id>`
- Remote project terminals seed a stable tmux session name from the SSH project identifier when no saved session name exists
- Sessions launch via `tmux new-session -A -s <name>` so existing sessions are reattached when present
- `-A` flag creates or reattaches depending on whether the session exists
- Server options applied on each launch: `mouse on`, `history-limit 50000`, `status off`, `escape-time 0`
- Session names persisted in `TerminalSessionEntry.tmuxSessionName` for cross-restart reattach
- Graceful fallback to direct shell launch when tmux is unavailable
- Behavior settings: "On quit" (detach/terminate) and "On tab close" (detach/terminate)
- Settings session manager remains available for admin cleanup
- VibeSpace `Sessions` sidebar provides the day-to-day browser for local and remote tmux sessions
