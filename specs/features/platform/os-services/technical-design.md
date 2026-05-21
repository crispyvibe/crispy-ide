# OS Services — Technical Design

## Overview

Crispy registers three system-wide macOS Services: `Crispy: rephrase`, `Crispy: research`, and `Crispy: open in terminal`. These appear in any application's Services menu (or right-click → Services) when Crispy is running. Text services invoke the configured CLI tool; the terminal service routes file URLs into Crispy vibespaces.

## Architecture

### Registration

- Services are declared in Info.plist under the `NSServices` key.
- `TextProcessorService` is set as `NSApp.servicesProvider` during `applicationWillFinishLaunching` and `applicationDidFinishLaunching`.
- `NSUpdateDynamicServices()` is called to refresh the system services cache.

### Registered Services

| Service | Input Types | Behavior |
|---|---|---|
| Crispy: rephrase | `NSStringPboardType`, `public.utf8-plain-text`, `public.text` | Rewrites selected text via CLI tool with rephrase prompt |
| Crispy: research | Same as rephrase | Enriches selected text via CLI tool with research prompt |
| Crispy: open in terminal | `public.folder`, `public.shell-script`, `public.unix-executable` | Opens file/folder URLs in Crispy vibespace |

## Data Flow

### Rephrase / Research Flow

1. Read selected text from the services pasteboard.
2. Chunk input if > 4,000 characters (up to 6 chunks; truncated after 24,000 characters with truncation notice).
3. Render prompt using the configured template. If template contains `{{text}}`, input replaces the placeholder; otherwise input is appended after the template.
4. Resolve CLI command and arguments from the configured text service profile.
5. Resolve agent name (rephrase: `CRISPYVIBES_KIRO_REPHRASE_AGENT`; research: `CRISPYVIBES_KIRO_RESEARCH_AGENT` → `CRISPYVIBES_KIRO_AGENT` → UserDefaults → compiled default). If agent flag is enabled and first attempt fails, retry without it.
6. Launch CLI via `/usr/bin/env` with PATH resolution.
7. Wait up to 20 seconds (configurable via `CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS`). Terminate process on timeout.
8. Strip terminal escape sequences (ANSI CSI, OSC, DCS/PM/APC/SOS, single-char escapes).
9. Extract response: find last line starting with `>`, take everything after it, stop at any line starting with `▸ Time:`.
10. Write result back to services pasteboard, replacing original selection.

Errors are reported via the NSServices error mechanism.

### Open in Terminal Flow

1. Read file URLs from services pasteboard (`public.folder`, `public.shell-script`, `public.unix-executable`).
2. Filter to URLs that exist on disk.
3. Submit to `ExternalOpenRelay` with `preferTerminal: true`.
4. CrispyVibes creates a new vibespace with the folders in terminal-only mode, or adds them to the active vibespace.

## API / Command Contracts

### Info.plist NSServices Entry

Each service declares:
- `NSMenuItem` — the service menu item title
- `NSMessage` — the selector invoked on the services provider
- `NSSendTypes` / `NSReturnTypes` — pasteboard types accepted and returned
- `NSPortName` — the app's registered port name

### CLI Invocation

```
/usr/bin/env <command> <arguments> <prompt>
```

Configuration shared with VibeCast text services (CLI profile, trust mode, prompt templates, agent settings).

### Timeout

- Default: 20 seconds.
- Override: `CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS` environment variable.

## State Management

- No persistent state owned by OS Services directly.
- CLI profile, prompt templates, and agent settings are read from UserDefaults (managed by App Settings → Text Services).
- Services are stateless per invocation; each request reads current configuration.

## Dependencies (frameworks, libraries)

- `AppKit` — `NSApplication.servicesProvider`, `NSPasteboard`, `NSUpdateDynamicServices()`
- `Foundation` — `Process` for CLI subprocess launch, `FileManager` for URL existence checks

## Platform Considerations

- Services are available system-wide only while Crispy is running.
- `NSUpdateDynamicServices()` must be called to make newly registered services visible in other apps.
- Services provider is set twice (willFinishLaunching + didFinishLaunching) to ensure registration across launch timing variations.
- CLI is launched via `/usr/bin/env` to resolve the executable from the user's PATH.

## Performance Constraints

- 20-second timeout prevents hung CLI processes from blocking the calling application.
- Large text chunking caps at 24,000 characters (6 × 4,000) to bound CLI invocation time.
- ANSI stripping and response extraction are string operations with negligible overhead.

## Migration / Rollout Notes

_None._
