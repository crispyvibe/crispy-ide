---
title: "Screen Capture & Screenshot Studio"
feature: "F062"
domain: "platform"
audience: "user"
version: "2.1"
sidebar:
  label: "Screen Capture"
  order: 9
---

# Screen Capture & Screenshot Studio

## Overview
Crispy provides one fast screenshot workflow. Select a Region, Window, or Display; Screenshot Studio opens with the result already copied and saved to bounded local history. Studio starts in **Markup** with **Pen** selected and remains open while you annotate, copy, and browse recent screenshots. Crispy never presses ⌘V for you.

## Getting Started
Start the same capture from any of these app-wide entry points:
- press **⇧⌘2** while Crispy is running (configurable or disableable);
- choose **File > Capture Screenshot…**; or
- click the camera toolbar button, even with no VibeSpace open.

The first capture uses Region mode. Later captures remember your most recent mode, delay, and pointer setting. Apple’s ⇧⌘3, ⇧⌘4, and ⇧⌘5 shortcuts remain unchanged.

Crispy requests macOS Screen Recording permission only after you start capture. If prompted, allow Crispy under **System Settings > Privacy & Security > Screen & System Audio Recording**. Local and production builds can require separate authorization.

## Workflows
### Capture a Region
1. Choose Region or press **R**.
2. Drag around the content. The Region stays on its starting display and visibly stops at that display edge.
3. Release to commit. Native-pixel dimensions and a pointer magnifier help with precision.

For keyboard or VoiceOver selection, Tab to an edge, use arrow keys to adjust, and press Return. Escape cancels and returns focus to where capture began.

### Capture a Window or Display
Choose Window (**W**) or Display (**D**), focus/click the highlighted target, and press Return or click. A spanning Window is captured whole. Display output uses native backing resolution. macOS-protected content may be unavailable; Crispy does not bypass protection.

### Use a delay or include the pointer
The overlay offers **None, 3, 5, or 10 seconds** and **Include pointer**. These settings are remembered. Escape cancels during countdown.

### Work in Screenshot Studio
After successful acquisition:
1. Current appears in Studio on the captured display/current Space.
2. Crispy eagerly copies complete PNG/TIFF data to the clipboard.
3. Crispy saves one flattened PNG to local screenshot history.
4. Studio stays open in **Markup** with **Pen** selected.

Add Pen, Line, Arrow, Rectangle, Ellipse, Highlight, Text, Blur, Pixelate, or Redact annotations; use Select, Crop, Undo, Redo, Revert, and zoom as needed. **Use Redact for sensitive information**—Blur and Pixelate are visual obscuration, not secure removal.

When an edit settles, Crispy automatically refreshes the clipboard and replaces that history item’s flattened image and thumbnail.

- **Copy** manually runs the same full-resolution refresh immediately and keeps Studio open. Use it to retry or refresh while continuing to edit.
- **Copy & Dismiss** is the primary action. It immediately flushes the latest selected revision, waits until complete PNG/TIFF clipboard data and flattened local history are both committed and published, then closes Studio. Press Return to invoke it.
- **Close** remains separate and is available with Escape; it does not claim delivery completed.

If render, encoding, clipboard, or history delivery fails, Studio stays open with the current edits and a retryable failure. Place the destination cursor yourself and press ⌘V.

### Browse recent screenshots
The bottom rail shows **Current** and recent flattened screenshots, newest first. Select an item to open a fresh annotation session. A failed or superseded selection leaves the current editor unchanged. Thumbnails are previews only and never replace the editor by themselves.

### Delete or clear history
Use the trash control beside a recent item to delete it. Use **Clear History** in Studio, or **Settings > Screen Capture > Clear Screenshot History**, to remove all saved screenshot history. Settings shows item count, progress, and failure status.

History is local to this Mac, excluded from backup, limited to **50 screenshots** and **30 days**, and cleaned automatically. It stores flattened images and minimal dimensions/timestamps—not app names, window titles, origin apps, targets, annotation layers/text, or OCR data.

## Keyboard Shortcuts
| Action | Shortcut |
|---|---|
| Capture Screenshot | **⇧⌘2** by default; configurable/disableable |
| Region / Window / Display | **R / W / D** in selection |
| Traverse targets/controls | Tab / Shift-Tab |
| Commit keyboard target | Return |
| Cancel selection/countdown | Escape |
| Undo / Redo | ⌘Z / ⇧⌘Z |
| Temporarily pan | Hold unmodified Space and drag |
| Copy current flattened image and stay open | ⇧⌘C or Studio **Copy** |
| Copy latest selected revision, commit history, then close | Return or Studio **Copy & Dismiss** |
| Close Studio without a delivery guarantee | Escape or Studio **Close** |

There are no Repeat Last Area, Reopen Last Capture, Capture to Clipboard, or Capture & Markup commands. All capture entry points use the same route.

## Settings / Configuration
Screen Capture settings include:
- one system-wide Screenshot Shortcut and its registration/conflict status;
- remembered Region/Window/Display mode;
- delay;
- Include pointer;
- Screen Recording permission status/recovery; and
- Clear Screenshot History count/status/control.

Preference schema stores only mode, delay, and pointer state. There is no post-capture behavior picker.

## Privacy
- Capture requires explicit command and visible target commitment.
- Capture UI and Studio are excluded from acquired pixels.
- Pixels and history are not uploaded, indexed, OCR-processed, or shared over a Crispy service.
- Clipboard managers and Universal Clipboard can retain/sync clipboard images under their own settings.
- Initial raw output reaches clipboard/history before later annotations. When redacting secrets, allow the edit refresh to finish, then clear older clipboard-manager records if applicable. Clear Screenshot History removes Crispy’s retained copy.
- Crispy does not store or show the origin app name and does not synthesize paste or return focus after successful capture.

## Troubleshooting
### The shortcut does not work
Try **File > Capture Screenshot…**. If the menu works, open Settings and resolve the shortcut conflict, enable it, or record another chord. Crispy must be running.

### Permission is denied, revoked, or needs relaunch
Use the offered Open System Settings, Recheck, Relaunch Crispy, or Cancel action. Invoke capture again after relaunch. A failed/cancelled attempt does not modify clipboard or history.

### Studio did not appear or capture is blank
Protected/DRM content may be unavailable. For ordinary content, recheck permission and capture again after display topology settles.

### Copy or history update failed
The current image remains open. Copy & Dismiss never closes on render, encoding, clipboard, history, or publication failure. Use **Retry Copy** for output/history delivery failure, **Copy** for a stay-open manual refresh, **Copy & Dismiss** to retry the close guarantee, or **Refresh** for history loading failure. A newer item/revision is protected from older late completions. If Crispy closes while saving, no late clipboard, thumbnail, history status, or other Studio update appears. Closing prevents unfinished disk work but does not undo a history version that finished saving first; that version may appear normally after the next launch and remains subject to the 50-item/30-day cleanup rules.

### A recent item is unavailable
Studio isolates corrupt/incomplete history during startup and continues loading valid items. Refresh; if failures persist, clear screenshot history.

### History is missing an older screenshot
Items expire after 30 days and the newest 50 are retained. Delete/clear operations also permanently remove them from the rail.

## Known Limitations
- macOS 26+ only; hardware/TCC behavior depends on ScreenCaptureKit.
- Region capture is single-display.
- No video/GIF, scrolling capture, layered screenshot document, cloud sync, OCR, file-promise drag, or explicit Save As route.
- History is flattened and bounded; annotations are not separately editable after another item is selected.
- Clipboard paste requires a destination that accepts PNG or TIFF.

## Change History
| Date | Change | Author |
|---|---|---|
| 2026-10-04 | Version 2.1: restored Copy & Dismiss; latest selected output must reach clipboard and flattened history before close, while failures remain open and retryable. | — |
| 2026-10-04 | Clarified close/shutdown behavior for unfinished work versus a history version already saved atomically. | — |
| 2026-10-04 | Version 2.0: one capture route, eager clipboard, persistent bounded local history, Screenshot Studio current/recent rail, automatic edited-output refresh, delete/clear, and updated privacy guidance. | — |
