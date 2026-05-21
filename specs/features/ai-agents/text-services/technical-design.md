# Text Services — Technical Design

## Overview

Technical design pending. This document will cover the architecture of macOS service registration, TextServiceCLIProfile resolution, trust-mode argument construction, agent fallback chain, ANSI stripping, response extraction, pasteboard update, timeout handling, large text chunking, and CLI tool catalog integration.

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

### Text Service CLI

Purpose:

- Power `crispyvibes:rephrase` and `crispyvibes:research` macOS Services

Invocation pattern:

- `/usr/bin/env <configured-cli> <configured-args> <prompt>`
- Default profile is Kiro (`kiro-cli chat --no-interactive --trust-all-tools --wrap never`)
- Settings can switch command/args profile (for example Claude Code, Codex, Gemini, or Custom)

Agent resolution order:

1. `CRISPYVIBES_KIRO_REPHRASE_AGENT` or `CRISPYVIBES_KIRO_RESEARCH_AGENT`
2. `CRISPYVIBES_KIRO_AGENT`
3. App setting `Default agent`
4. no `--agent` argument (default)
