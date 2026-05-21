---
title: "Onboarding"
feature: F017
domain: app-shell
audience: "user"
version: "1.0"
sidebar:
  label: Onboarding
  order: 4
---

# Onboarding

## Overview

The first time you launch CrispyVibes, a disclaimer screen and an optional walkthrough guide you through the app. The disclaimer is a one-time gate — once accepted, you won't see it again. The walkthrough highlights key features and can be revisited any time.

> **Terminology:** A *VibeSpace* is Crispy's name for a vibespace — a collection of projects, terminals, and settings. *VibeCast* is a tool for sending commands to one or all of your terminals. *ACP* (Agent Conversation Protocol) lets you chat with AI coding assistants like Claude Code or Kiro directly inside Crispy.

## Getting Started

### First launch: the disclaimer

On your very first launch, Crispy shows a disclaimer screen before anything else. No vibespace, toolbar, or interactive UI appears behind it — the disclaimer is the only thing on screen.

If you launch CrispyVibes directly from the downloaded disk image, your Downloads folder, or a temporary system location, CrispyVibes first asks whether it should move itself into `/Applications`. This prevents duplicate **Open With** entries in Finder. Choosing **Move to Applications** relaunches CrispyVibes from the installed copy. Choosing **Not Now** continues from the current location.

The disclaimer tells you:

- CrispyVibes does not collect telemetry.
- CrispyVibes does not send crash reports.
- The software is provided as-is with no liability.
- "It is just you and your vibe."

It also notes that CrispyVibes may ask once for macOS Keychain access to store a small security key used to make sure your vibespace settings haven't been changed by another app.

You have two choices:

- **Accept and Continue** — dismisses the disclaimer and lets you into the app. Your acceptance is saved permanently.
- **Quit** — closes the app immediately.

There is no way to dismiss the disclaimer by pressing Escape, clicking outside, or navigating elsewhere. You must explicitly accept or quit.

### Keychain permission

Shortly after accepting the disclaimer, macOS may show a system prompt asking you to allow Keychain access. This is expected — Crispy stores a small security key in your Mac's Keychain to make sure your vibespace settings haven't been changed by another app. If you deny the prompt, Crispy shows a simple retry message so you can grant access when ready.

### The walkthrough

After the disclaimer, CrispyVibes presents a 6-step guided walkthrough the first time you open a vibespace. Each step shows an annotated screenshot highlighting a key area of the app, along with a keyboard shortcut hint.

The walkthrough steps:

| Step | Topic | Shortcut hint |
|------|-------|---------------|
| 1 | Welcome to Crispy | ⌘⇧N to create a VibeSpace |
| 2 | VibeSpace Dashboard | Toolbar: VibeSpace Dashboard |
| 3 | Views and Layout | ⌘D (Detailed), ⌘T (Terminal Board) |
| 4 | Project Navigation | ⌘1–⌘9 to focus mapped projects |
| 5 | Terminal View Enhancements | Use New Terminal in Terminal Board view |
| 6 | You Are Ready | Toolbar: Walkthrough |

Use **Next** and **Back** to move between steps. The progress indicator shows "Step N of 6." On the last step, the button reads **Done**.

You can tap **Skip** at any point to close the walkthrough immediately. Both Skip and Done mark the walkthrough as completed.

## Workflows

### Revisiting the walkthrough

Already completed or skipped the walkthrough? You can reopen it at any time:

- Click the **Walkthrough** button in the toolbar.
- Open it from **App Settings**.
- Select it from the **Help** menu.

The walkthrough always restarts from Step 1 when reopened.

### Typical first-launch flow

1. Launch CrispyVibes → disclaimer appears.
2. Read the disclaimer → click **Accept and Continue**.
3. macOS Keychain prompt appears → click **Allow**.
4. Create or open a vibespace → walkthrough appears automatically.
5. Step through the walkthrough or click **Skip**.
6. You're in — start adding projects and working.

## Keyboard Shortcuts

There are no dedicated keyboard shortcuts for onboarding. The disclaimer buttons and walkthrough navigation are mouse/trackpad driven.

## Settings / Configuration

- **Disclaimer acceptance** is stored permanently. It survives app updates. You can reset it from App Settings if needed (this will show the disclaimer again on next launch).
- **Walkthrough completion** is stored in your preferences. Reopening the walkthrough from the toolbar ignores the completion flag and shows it fresh.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Disclaimer keeps appearing | Your preferences may have been reset. Accept the disclaimer again — it will be saved. |
| Walkthrough didn't appear after disclaimer | The walkthrough only auto-presents when you open a vibespace. Create or open one first. |
| Walkthrough button in toolbar does nothing | The walkthrough feature may be disabled in your build. This is a known limitation in some versions. |
| Keychain prompt was denied | Crispy shows a retry message. Click retry and allow Keychain access when the system prompt reappears. |

## Known Limitations

- The walkthrough feature may be disabled in some versions. When disabled, the walkthrough will not auto-present and the toolbar button has no effect.
- The walkthrough auto-presents only once per session, even if you close it without completing it. Reopen it manually from the toolbar if needed.
- The disclaimer cannot be dismissed with Escape or by clicking outside — this is intentional.

## Related Guides

- [Navigation](../navigation/usage-guide.md)
- [VibeSpace Lifecycle](../../vibespace/lifecycle/usage-guide.md)
