# Text Services — Spec

Status: draft

## Overview

Text Services provides macOS system services for AI-powered text rephrase and research, plus an Open in Terminal service. It covers service registration, input validation, prompt construction, multi-CLI profile invocation with trust mode, output parsing, pasteboard update, configurable timeouts, large text chunking, and CLI tool catalog integration.

## Dependencies

- F011 (ACP) — shares CLI tool catalog and agent configuration
- F028 (VibeCast) — VibeCast rephrase delegates to text services CLI

## Requirements

### F029-R01: macOS Services Registration

Rephrase, research, and openInTerminal services MUST be registered at app launch and discoverable from the macOS text service menu with port name `com.crispyvibe.app`.

### F029-R02: Input Validation

Services MUST reject invocations with no selected text, returning a localized error.

### F029-R03: Rephrase Behavior

Rephrase MUST send a clarity-preserving prompt to the configured CLI, using app settings prompt override when configured.

### F029-R04: Research Behavior

Research MUST augment text with concise practical context via the configured CLI, using app settings prompt override when configured.

### F029-R05: CLI Invocation

Services MUST resolve the active TextServiceCLIProfile, pass trust-mode-aware arguments, resolve agent from environment with fallback chain, retry without agent on failure, and expand PATH for common install locations.

### F029-R06: Output Parsing

CLI output MUST have ANSI sequences stripped, assistant output region extracted, and pasteboard replaced on success. Empty or failing responses MUST return a user-visible error.

### F029-R07: Prompt Templates

Templates containing `{{text}}` MUST insert selected text at the placeholder without appending a trailing `Text:` block.

### F029-R08: Open in Terminal

openInTerminal MUST accept file and folder URLs and open a terminal session at the selected path.

### F029-R09: Multi-CLI Profile

TextServiceCLIProfile MUST define per-profile executable and base arguments for kiro, claudeCode, codex, gemini, opencode, and custom profiles.

### F029-R10: Trust Mode

Standard trust MUST NOT pass `--trust-all-tools`. Full trust MUST include `--trust-all-tools`.

### F029-R11: Configurable Timeout

CLI process MUST respect `CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS` with a 20-second default.

### F029-R12: Large Text Chunking

Text exceeding 4000 characters MUST be split into up to 6 sequential chunks processed independently.

### F029-R13: CLI Tool Catalog

Catalog MUST offer terminal presets for supported CLI tools.

## Scenarios

### Scenario F029-S01: Services are registered at app launch

**Given** application startup lifecycle runs
**When** will-finish and did-finish launch hooks execute
**Then** `rephrase` and `research` services are registered as app services provider
**And** dynamic services are refreshed

### Scenario F029-S02: Services are discoverable from macOS text service menu

**Given** `Info.plist` includes NSServices entries
**When** user selects text or file/folder in compatible context
**Then** service menu exposes `Crispy: rephrase`, `Crispy: research`, and `Crispy: open in terminal`

### Scenario F029-S03: Services use Crispy service port name

**Given** `Info.plist` includes NSServices entries
**When** service metadata is resolved
**Then** each service `NSPortName` is `com.crispyvibe.app`

### Scenario F029-S04: Service fails when no selected text is available

**Given** service is invoked without non-empty string data on pasteboard
**When** processing begins
**Then** request is rejected with `No selected text was provided.`

### Scenario F029-S05: Rephrase sends clarity-preserving prompt to Kiro CLI

**Given** selected text is available
**When** `rephrase` service is invoked
**Then** prompt instructs rewriting for clarity/smoothness
**And** meaning preservation is requested
**And** app settings prompt override is used when configured
**And** response should contain rewritten text only

### Scenario F029-S06: Research augments text with concise context

**Given** selected text is available
**When** `research` service is invoked
**Then** prompt requests concise practical research context
**And** app settings prompt override is used when configured
**And** response should contain improved text only

### Scenario F029-S07: Service runs configured CLI profile with trust-mode-aware arguments

**Given** service prompt is prepared
**When** CLI process is launched
**Then** command is resolved from active `TextServiceCLIProfile` (kiro, claudeCode, codex, gemini, opencode, custom)
**And** each profile defines its own executable and base arguments
**And** standard trust mode passes `--no-interactive` and `--wrap never`
**And** fullTrust mode additionally passes `--trust-all-tools`
**And** CLI arguments are loaded from app settings when overridden

### Scenario F029-S08: Agent name is resolved from environment with fallback

**Given** service needs an agent value
**When** environment variables are evaluated
**Then** service checks kind-specific key (`CRISPYVIBES_KIRO_REPHRASE_AGENT` or `CRISPYVIBES_KIRO_RESEARCH_AGENT`)
**And** falls back to `CRISPYVIBES_KIRO_AGENT`
**And** then falls back to app setting `textServiceDefaultAgent`
**And** no `--agent` argument is passed when nothing is configured
**And** `--agent` is included only when app setting `textServicePassAgentFlag` is enabled

### Scenario F029-S09: Agent fallback retry occurs on failure

**Given** an initial CLI attempt fails
**When** a preferred agent was used first
**Then** service retries once without explicit agent argument

### Scenario F029-S10: PATH is expanded for common CLI install locations

**Given** service process environment is built
**When** command launches
**Then** PATH is extended with Homebrew, local bin, and user bin locations

### Scenario F029-S11: ANSI and terminal control sequences are stripped

**Given** CLI output includes terminal formatting codes
**When** response parsing runs
**Then** escape sequences are removed before content extraction

### Scenario F029-S12: Response extraction trims assistant output region

**Given** cleaned CLI output is available
**When** parser identifies assistant marker lines
**Then** response text is extracted from last prompt marker section
**And** stops before trailing timing metadata lines when present

### Scenario F029-S13: Successful service replaces pasteboard text

**Given** service returns non-empty processed text
**When** operation succeeds
**Then** pasteboard is cleared and replaced with processed output

### Scenario F029-S14: Empty or failing response returns user-visible error

**Given** CLI response is empty or process exits non-zero
**When** service handling completes
**Then** service reports localized failure message back to macOS service caller

### Scenario F029-S15: Prompt templates support explicit text placeholder

**Given** a prompt template contains `{{text}}`
**When** service renders request prompt
**Then** selected text is inserted at placeholder position
**And** selected text is not appended again as a trailing `Text:` block

### Scenario F029-S16: openInTerminal accepts file and folder URLs

**Given** user selects a file or folder in Finder or compatible context
**When** `openInTerminal` service is invoked
**Then** Crispy opens a terminal session at the selected path

### Scenario F029-S17: TextServiceCLIProfile enum defines per-profile invocation

**Given** `TextServiceCLIProfile` includes kiro, claudeCode, codex, gemini, opencode, and custom
**When** a text service is invoked
**Then** the active profile determines the CLI executable and base invocation arguments

### Scenario F029-S18: Trust mode controls CLI argument set

**Given** a CLI profile is active
**When** trust mode is `standard`
**Then** `--trust-all-tools` is not passed
**When** trust mode is `fullTrust`
**Then** `--trust-all-tools` is included in CLI arguments

### Scenario F029-S19: CLI process respects configurable timeout

**Given** `CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS` environment variable may be set
**When** CLI process is launched
**Then** timeout defaults to 20 seconds when env var is absent
**And** timeout uses the env var value when present

### Scenario F029-S20: Text exceeding 4000 characters is split into chunks

**Given** selected text length exceeds 4000 characters
**When** service prepares CLI invocations
**Then** text is split into up to 6 sequential chunks
**And** each chunk is processed independently

### Scenario F029-S21: CLI tool catalog provides terminal presets

**Given** the CLI tool catalog is available
**When** user configures a custom CLI profile
**Then** catalog offers terminal presets for supported CLI tools

## Acceptance Criteria

- Service registration completes before app becomes active (PERF-3).
- CLI invocation respects configured timeout (REL-1).
- ANSI stripping handles all common escape sequences (REL-1).
- Pasteboard operations are atomic (SEC-1).
- Services are accessible from macOS accessibility APIs (A11Y-2).
- Service invocations are logged (OBS-1).

## Open Questions

- Should text services support additional AI operations beyond rephrase and research?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/text-services/feature.md (TXT-001 through TXT-021) | — |
