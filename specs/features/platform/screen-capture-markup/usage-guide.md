---
title: "Screen Capture & Screenshot Studio"
feature: "F062"
domain: "platform"
audience: "user"
version: "2.4"
sidebar:
  label: "Screen Capture"
  order: 9
---

# Screen Capture & Screenshot Studio

## Overview
Crispy provides one fast screenshot workflow. Select a Region, Window, or Display; Screenshot Studio opens with the result already copied and saved in local history. Studio starts in **Markup** with **Pen** selected and remains open while you annotate, copy, and browse recent screenshots. Crispy never presses ⌘V for you.

## Getting Started
Start the same capture from any of these app-wide entry points:
- press **⌃⇧4** while Crispy is running (you can change or disable it);
- choose **File > Capture Screenshot…**; or
- click the camera toolbar button, even with no VibeSpace open.

The first capture uses Region mode. Later captures remember your most recent mode, delay, and pointer setting. The ⌃⇧4 default avoids a shortcut previously used by Grammarly. It uses Control rather than Command, so it does not replace macOS ⇧⌘4. Apple’s ⇧⌘3, ⇧⌘4, and ⇧⌘5 shortcuts remain unchanged. Standard ⇧⌘S also remains available for Save As.

Crispy asks for screen-recording permission only after you start a capture. If prompted, allow Crispy under **System Settings > Privacy & Security > Screen & System Audio Recording**. Local and production builds may need permission separately.

## Workflows
### Capture a Region
1. Choose Region or press **R**.
2. Drag around the content. The Region stays on its starting display and visibly stops at that display edge.
3. Release to finish. A pointer magnifier helps with precision.

For keyboard or VoiceOver selection, Tab to an edge, use the arrow keys to adjust it, and press Return. Escape cancels and returns focus to where the capture began.

### Capture a Window or Display
Choose Window (**W**) or Display (**D**), focus or click the highlighted target, then press Return or click. Crispy is designed to capture a window that spans displays and to preserve the display’s full image detail. Results can depend on display hardware, scaling, arrangement, and macOS behavior. Protected content may be unavailable; Crispy does not bypass that protection.

### Use a delay or include the pointer
The selection screen offers **None, 3, 5, or 10 seconds** and **Include pointer**. These settings are remembered. Escape cancels during the countdown.

### Work in Screenshot Studio
After a successful capture:
1. Current appears in Studio, designed to open on the captured display in the current Space. macOS may adjust placement when displays or Spaces change.
2. Crispy copies complete PNG and TIFF data to the clipboard.
3. Crispy saves one PNG in local screenshot history.
4. Studio stays open in **Markup** with **Pen** selected.

Add Pen, Line, Arrow, Rectangle, Ellipse, Highlight, Text, Blur, Pixelate, or Redact annotations; use Select, Crop, Undo, Redo, Revert, and zoom as needed. **Use Redact for sensitive information**—Blur and Pixelate are visual obscuration, not secure removal.

When your latest edits settle, a short background task refreshes the clipboard, saved image, and thumbnail.

- **Copy** refreshes the latest edits immediately and keeps Studio open. Use it to retry or refresh while continuing to edit.
- **Copy & Dismiss** is the primary action. It copies and saves the latest edits, then closes Studio. Press Return to use it.
- **Close** is separate and is available with Escape. It closes Studio without promising that the latest edits were copied and saved.

If drawing, image creation, clipboard, or history saving fails, Studio stays open with your current edits and offers a retry. Place the destination cursor yourself and press ⌘V.

### Browse recent screenshots
The bottom rail shows **Current** and recent saved screenshots, newest first. Select an item to start a fresh annotation session. If a selection cannot open or a newer selection wins, the current editor remains unchanged. Thumbnails are previews only.

### Delete or clear history
Use the trash control beside a recent item to delete it. Use **Clear History** in Studio, or **Settings > Screen Capture > Clear Screenshot History**, to remove all saved screenshot history. Settings shows the item count, progress, and any failure.

History stays on this Mac, is excluded from backup, and is limited to **50 screenshots** and **30 days**. Crispy cleans it automatically. The local history file stores the saved image plus minimal dimensions and times—not app names, window titles, the app where capture started, targets, editable annotation details, or recognized text.

## Keyboard Shortcuts
| Action | Shortcut |
|---|---|
| Capture Screenshot | **⌃⇧4** by default; configurable or disableable |
| Region / Window / Display | **R / W / D** during selection |
| Move through targets and controls | Tab / Shift-Tab |
| Choose the keyboard target | Return |
| Cancel selection or countdown | Escape |
| Undo / Redo | ⌘Z / ⇧⌘Z |
| Temporarily pan | Hold unmodified Space and drag |
| Copy the current image and stay open | ⇧⌘C or Studio **Copy** |
| Copy and save the latest edits, then close | Return or Studio **Copy & Dismiss** |
| Close Studio without waiting for copy/save | Escape or Studio **Close** |

There are no Repeat Last Area, Reopen Last Capture, Capture to Clipboard, or Capture & Markup commands. All capture entry points use the same workflow.

## Settings / Configuration
Screen Capture settings include:
- one system-wide Screenshot Shortcut and its conflict status;
- remembered Region, Window, or Display mode;
- delay;
- Include pointer;
- permission status and recovery actions; and
- Clear Screenshot History count, status, and control.

Crispy remembers only the mode, delay, and pointer choice. There is no setting for a different action after capture.

## Privacy
- Capture requires your command and a visible target choice.
- The selection screen and Studio are kept out of the screenshot.
- Screenshots and history are not uploaded, indexed, scanned for text, or shared through a Crispy service.
- Clipboard managers and Universal Clipboard can retain or sync clipboard images under their own settings.
- The initial image reaches the clipboard and history before later annotations. When redacting secrets, allow the edit refresh to finish, then clear older clipboard-manager records if needed. Clear Screenshot History removes Crispy’s saved copy.
- Crispy does not store or show the app where capture started, paste automatically, or return focus there after a successful capture.

## Troubleshooting
### The shortcut does not work
Try **File > Capture Screenshot…**. If the menu works, open Settings and resolve the shortcut conflict, enable the shortcut, or choose another key combination. macOS allows only one running app to use a particular global shortcut at a time. The normal and local Crispy builds can request the same default; one may work while the other reports a conflict. After the other app or build releases the shortcut, activate Crispy to try again. Crispy must be running.

### Permission is denied, revoked, or needs a relaunch
Use the offered Open System Settings, Recheck, Relaunch Crispy, or Cancel action. Start capture again after relaunch. A failed or cancelled attempt does not change the clipboard or history.

### Studio did not appear or the capture is blank
Protected content may be unavailable. If no active display can show the selection screen, Crispy stops cleanly and enables Capture Screenshot again instead of waiting invisibly. For ordinary content, recheck permission and try again after the display arrangement settles. If an existing Studio was temporarily hidden and capture then fails or is cancelled, Crispy shows it again. Recovery brings forward only the recovery panel, not the main IDE window.

### Copy or history update failed
The current image remains open. Copy & Dismiss stays open whenever drawing, image creation, clipboard, or history saving fails. Use **Retry Copy** for an output or history failure, **Copy** to refresh and stay open, **Copy & Dismiss** to try copying, saving, and closing again, or **Refresh** if history cannot load. Newer edits and selected images are protected from older background tasks. If Crispy closes while saving, it suppresses later clipboard, thumbnail, history-status, and Studio updates. A save that finished first may appear normally after the next launch and remains subject to the 50-item and 30-day cleanup limits.

### A recent item is unavailable
Studio sets aside damaged or incomplete history during startup and continues loading valid items. Refresh; if failures persist, clear screenshot history.

### History is missing an older screenshot
Items expire after 30 days, and only the newest 50 are retained. Delete and clear also remove items from the rail.

## Known Limitations
- macOS 26+ only; permission, display, and Space behavior can vary by macOS release and hardware.
- Region capture is limited to one display.
- Mixed-scale displays, windows spanning displays, full-detail output, and current-Space placement are designed behaviors but may be affected by display drivers, scaling, arrangement, protected content, and macOS window management. They require manual validation on the target hardware.
- No video/GIF, scrolling capture, layered screenshot document, cloud sync, text recognition, file drag promise, or separate Save As route.
- History stores one finished image; annotations are not separately editable after another item is selected.
- Pasting requires a destination that accepts PNG or TIFF.

## Change History
| Date | Change | Author |
|---|---|---|
| 2026-10-04 | Version 2.4: replaced implementation terms with user-facing copy, clarified friendly shortcut-conflict recovery for normal/local builds, and qualified display, full-detail, spanning-window, and Space behavior for manual hardware checks. | — |
| 2026-10-04 | Version 2.3: documented shortcut conflict status, clean no-display recovery, recovery-panel focus, and restoration of a temporarily hidden Studio. | — |
| 2026-10-04 | Version 2.2: changed the default from ⌃⇧S to ⌃⇧4 while preserving customized or disabled choices and leaving macOS shortcuts unchanged. | — |
| 2026-10-04 | Version 2.1: restored Copy & Dismiss so the latest edits must reach the clipboard and local history before Studio closes; failures remain open and retryable. | — |
| 2026-10-04 | Version 2.0: introduced one capture workflow, automatic clipboard refresh, bounded local history, Screenshot Studio, and delete/clear controls. | — |
