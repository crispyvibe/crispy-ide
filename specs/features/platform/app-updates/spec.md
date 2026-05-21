# App Updates — Spec

Status: draft

## Overview

App Updates provides automatic and manual update checking through Sparkle against a configurable appcast feed URL, plus update controls in app settings. Update ordering is driven by the monotonically increasing build number, while the display version may remain stable or change independently.

## Dependencies

_None._

## Requirements

### F030-R01: Automatic Update Checks

App MUST use Sparkle automatic update checks when enabled.

### F030-R02: Manual Update Checks

Manual check MUST delegate to Sparkle and show Sparkle result feedback.

### F030-R03: Update Prompt

Available updates MUST be ordered by build number and presented through Sparkle's update UI.

### F030-R04: Update Settings

App settings MUST provide toggle for automatic checks, feed URL editing, and manual check trigger.

## Scenarios

### Scenario F030-S01: Automatic update check runs on launch when enabled and interval elapsed

**Given** app settings have automatic update checks enabled
**When** the app finishes launching
**Then** Sparkle schedules update checking against the configured appcast feed
**And** startup UI remains usable while the check runs in background

### Scenario F030-S02: Manual check for updates always performs a fresh check

**Given** the app menu is available
**When** the user selects `Check for Updates…`
**Then** the app asks Sparkle to perform a manual update check
**And** Sparkle result feedback is shown to the user

### Scenario F030-S03: Manual check reports up-to-date status clearly

**Given** a manual update check succeeds
**And** the feed build is not newer than the current app build
**When** the check completes
**Then** Sparkle reports that the app is up to date

### Scenario F030-S04: Available update offers direct download path

**Given** the appcast contains a newer build than the current app build
**When** the update check completes
**Then** Sparkle offers the newer update
**And** the user can install it through Sparkle's normal update flow

### Scenario F030-S05: App settings provide update controls

**Given** `App Settings` view is open
**When** the user selects the `Updates` category
**Then** the user can toggle automatic update checks
**And** the user can edit the configured appcast feed URL
**And** the user can trigger `Check for Updates Now` from settings

### Scenario F030-S06: Manual check surfaces invalid feed or network failures

**Given** the configured appcast feed URL is invalid or unreachable
**When** the user runs a manual `Check for Updates…`
**Then** Sparkle reports the failure
**And** no install flow is started

## Acceptance Criteria

- Automatic check runs in background without blocking startup.
- Manual check uses Sparkle.
- Build number is the canonical update-order value.
- Appcast feed remains user-configurable.

## Open Questions

_None._

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Extracted from docs/features/app-shell/feature.md (APP-064–069) | — |
| 2026-04-20 | Simplified app updates to Sparkle-only runtime flow and build-driven ordering | Codex |
