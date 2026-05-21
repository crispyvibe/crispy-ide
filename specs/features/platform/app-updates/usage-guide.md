---
title: "App Updates"
feature: "F030"
domain: "platform"
audience: "user"
version: "1.0"
sidebar:
  label: "App Updates"
  order: 1
---

# App Updates

## Overview

Crispy uses the Sparkle framework to deliver automatic and manual update checks against a configurable appcast feed. Updates are ordered by build number, ensuring you always receive the correct newer version regardless of display version changes.

## Getting Started

1. Open Crispy — automatic update checks run in the background on launch when enabled.
2. To manually check, open the **Crispy** menu and select **Check for Updates…**.
3. If an update is available, Sparkle presents a native update dialog with release notes and an install button.

## Workflows

### Checking for Updates Manually

1. Click the **Crispy** menu in the menu bar.
2. Select **Check for Updates…**.
3. Sparkle performs a fresh check against the configured appcast feed.
4. If up to date, a confirmation dialog appears. If an update is available, Sparkle shows the update UI with download and install options.

### Configuring Update Settings

1. Open **Settings** (Crispy menu → Settings…, or Cmd+,).
2. Navigate to the **Updates** category.
3. Toggle **Automatically check for updates** on or off.
4. Select an **Update channel**:
   - **Stable** — Only promoted releases. Recommended for most users.
   - **Dev** — Every build. May be unstable; for insiders/preview.
   - **Custom** — Manually specify a feed URL.
5. If Custom is selected, enter the appcast feed URL in the text field.
6. Click **Check for Updates Now** to trigger an immediate check from settings.

### Installing an Update

1. When Sparkle detects a newer build, it presents an update dialog.
2. Review the release notes.
3. Click **Install Update** to download and install.
4. Crispy restarts with the new version.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open Settings | Cmd+, |

No dedicated keyboard shortcut exists for Check for Updates — use the Crispy menu.

## Settings

| Setting | Location | Description |
|---------|----------|-------------|
| Automatically check for updates | Settings → Updates | Enables/disables background checks on launch |
| Update channel | Settings → Updates | Stable, Dev, or Custom feed selection |
| Custom feed URL | Settings → Updates | Appcast endpoint (visible only when channel is Custom) |

## Tips

- The **build number** determines update ordering, not the display version. A higher build number always means a newer release.
- The Stable channel feed URL is `https://crispyvibe.com/updates/macos/stable/appcast.xml`.
- The Dev channel feed URL is `https://crispyvibe.com/updates/macos/dev/appcast.xml`.
- Automatic checks run at a configured interval after launch — they do not block the startup UI.
- If you previously used a custom feed URL, Crispy automatically infers your channel (Stable or Dev) if the URL matches a known feed.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Check for Updates" shows no result | Verify network connectivity and that the feed URL is reachable. |
| Update check reports failure | The configured appcast feed URL may be invalid or the server unreachable. Check Settings → Updates for the URL. |
| Automatic checks not running | Ensure the toggle is enabled in Settings → Updates. Checks only run after the configured interval has elapsed since the last successful check. |
| Sparkle updater disabled | The `CrispyVibesEnableSparkleUpdater` Info.plist key may be set to false in your build configuration. This is normal for local development builds. |
