# Diagnostics — Technical Design

## Overview

Crispy uses Apple Unified Logging (`OSLog`/`Logger`) and signposts for runtime diagnostics. It also keeps a bounded in-memory diagnostics event buffer used for user-triggered diagnostics export.

Diagnostics are designed to be:

- Bounded (no unbounded local file logging)
- Privacy-aware (sensitive values are hashed/sanitized)
- Field-debuggable (exportable bundle from app UI)

ACP-specific in-app observability is designed separately in `docs/technical/acp-observability.md` and follows the same bounded and privacy-aware rules, but uses structured ACP-specific stores rather than generic event logs.

## Architecture

### Log Categories

App diagnostics use the app bundle identifier as subsystem and these OSLog instances as categories:

- `vibespace.lifecycle`
- `vibespace.signpost`
- `terminal.lifecycle`
- `terminal.signpost`
- `terminal.host`
- `terminal.host.signpost`

### Signposted Flows

The app emits signposts using the above OSLog instances for key transitions, including:

- Project focus switch (`ProjectFocusSwitch`)
- Terminal activation flow (`EnsureActiveTerminal`)
- Terminal session lifecycle (`TerminalSessionStart`, termination/exit events)
- Terminal host attach lifecycle (`TerminalAttachRequested`, attached)

### Deep Diagnostics Mode

Deep terminal host debug logs are gated by environment variable `CRISPYVIBES_TERMINAL_DIAGNOSTICS=1`.

When disabled (default):

- Deep host debug logs are suppressed.
- High-frequency `debug` diagnostics events are not emitted into unified logs or in-memory export buffer.

## Data Flow

### Terminal Host Ownership Behavior

`TerminalContainerView` hosts a `GhosttyTerminalView` (`NSView`) that can only be attached to one container at a time. During Project focus switches, the terminal host may move between:

- Focused Project terminal pane (regular density)
- Stacked Project rail card (compact density)

Attach flow behavior:

- If another live container still owns the terminal view, attach is deferred.
- The host retries attach on the main queue while the window is active (bounded retries).
- On successful attach, the owning host reapplies target display density.
- Non-owning hosts do not force density changes.

Structured events for this flow:

- `terminal_attach_requested`
- `terminal_attached`

### Diagnostics Export Bundle

`Export Diagnostics…` creates a JSON payload that includes:

- Export timestamp and app/build/OS metadata
- Selected app defaults snapshot
- VibeSpace summary counts
- Sanitized vibespace catalog snapshot
- Sanitized app layout state snapshot
- Recent structured diagnostics events (in-memory ring buffer)

### Field Debugging Workflow

1. Reproduce issue.
2. Run `Export Diagnostics…` from app menu.
3. Attach exported JSON to issue report.
4. If needed, enable `CRISPYVIBES_TERMINAL_DIAGNOSTICS=1`, reproduce again, and export a second bundle.

## API / Command Contracts

### Sanitization Rules

- Path-like strings are replaced with hashed tokens (for example `path#...`).
- Command strings are not exported in plain form where hashes are sufficient.
- Export includes hashes for selected large state blobs for correlation.

## State Management

- CrispyVibes keeps a ring buffer of recent structured diagnostic events in memory, capped at 1500 events.
- Diagnostics JSON is written only when the user explicitly chooses `Export Diagnostics…`.

## Dependencies

- Apple Unified Logging (`OSLog` / `Logger`)
- macOS signpost infrastructure

## Platform Considerations

- Unified logs are managed by macOS logging infrastructure and rotated by system policy.
- CrispyVibes does not continuously write its own plain-text log files.
- Diagnostics should not be treated as an audit log.
- Event schema may evolve; consumers should tolerate additional keys.
- Keep deep diagnostics disabled unless active troubleshooting requires it.

## Performance Constraints

- In-memory ring buffer is capped at 1500 events to bound memory usage.
- Deep diagnostics mode is off by default to avoid high-frequency event overhead.
- Terminal host attach retries are bounded to prevent runaway retry loops.
