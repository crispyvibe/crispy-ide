---
title: "Schedules"
feature: "F061"
domain: "ai-agents"
audience: "user"
version: "1.3"
sidebar:
  label: "Schedules"
  order: 9
---

# Schedules

## Overview

A Schedule runs a Vibe Lane on a recurring cadence. Each Schedule targets one
local project folder and keeps the exact Vibe Lane version you approved when
you saved it.

Schedules is the default tab in **Automation**, which is available from the
application side menu even when no VibeSpace is open. The other tabs manage
reusable **Vibe Lanes** and **Vibes**. A **Vibe (Loop)** retries one
expectation within bounds; a **Vibe Lane (Spiral)** carries verified progress
forward across those Vibes. A Schedule owns recurrence only. Scheduled work
runs while Crispy is open.
If Crispy is asleep or quit, your missed-run setting decides what happens when
it returns.

## Getting Started

1. Select **Automation** in the application side menu.
2. Select **New Schedule**.
3. Enter a name and task instruction.
4. Choose a known project or select any local folder.
5. Pick a Vibe Lane.
6. Choose Interval, Daily, or Weekly.
7. Open **Advanced** if you need a different time zone or missed-run behavior.
8. Select **Save Paused** to finish without scheduling work, or **Review &
   Enable** to review Full Trust and start the schedule.

Crispy asks you to confirm that Vibe Lanes use Full Trust and scheduled work may
edit files and run commands without asking first.

If the right Vibe Lane does not exist, use **Manage Vibe Lanes** from
the Schedule editor. Use **Manage Vibes** to create or update the reusable
expectations used by Vibe Lane steps. Returning to the Schedules tab preserves
the Schedule draft. A Vibe Lane edit does not silently change that draft;
choose the updated Vibe Lane version explicitly.

## Workflows

### Monitor scheduled work

The dashboard shows each Schedule's project, Vibe Lane, schedule, next run, and
status:

- **Scheduled** — enabled and waiting.
- **Queued** — its task is waiting for Vibe Lane capacity.
- **Running** — its Vibe Lane task is active.
- **Needs you** — the task is waiting for supply, steer, or review input.
- **Paused** — disabled until you enable it.
- **Blocked** — the project, Vibe Lane snapshot, or schedule cannot be used.

Use the filter control to focus on active, paused, or attention-needed Schedules.
Schedule and execution are tracked independently, so a paused Schedule with a task
still running appears under both Active and Paused. Select a row to inspect its
configuration and run history.

### Run outside the schedule

Select **Run Now** from a row or Schedule detail. This starts an extra occurrence
without changing the next scheduled time. Run Now still refuses to overlap an
existing Queued, Running, or Needs-you task for the same Schedule. Crispy opens the
Schedule or created task so the outcome is visible.

### Pause or resume

Use the pause control to stop future occurrences. Pausing does not stop a task
that already started; open the linked task to stop it. Enabling any Schedule requires
Full Trust confirmation again.

When stopping from a Schedule's linked task, choose **Stop current run** to keep the
schedule enabled, or **Stop and pause** to stop the task and prevent the next
occurrence. Stopping the same task from the Vibe Lanes surface stops only that
run; it does not silently change the Schedule definition.

### Open a run

Open a Schedule and select **Open task** beside a started run. The normal Vibe Lane
task detail shows checkpoint progress, activity, verification, and any input
the task needs. Run history follows the linked task through Running, Needs you,
Completed, or Stopped; stopped entries also show the lane stop reason.

### Update a saved Vibe Lane

A Schedule freezes its Vibe Lane definition when saved. If the source Vibe Lane
changes, the Schedule detail shows that an update is available. Select **Update Vibe
Lane** to use the new revision for future runs. Before saving, Crispy shows the
old and new versions and the new stage route for confirmation. Existing tasks
keep their original revision.

### Handle missed runs

- **Run once when Crispy returns** starts only the latest missed occurrence.
- **Skip missed runs** records the latest missed occurrence without starting a
  task.

Crispy never replays every missed interval. Skip missed runs applies when
Crispy returns late; it does not skip normal scheduled wakes while the app is
running.

### Delete a Schedule

Delete removes the Schedule and its schedule history. If a full-trust run is active,
choose **Stop Run and Delete** or **Keep Run and Delete Schedule**. Keeping it
removes future scheduling while the current task continues in Vibe Lanes.
Completed tasks remain available in Vibe Lanes.

## Keyboard Shortcuts

The Schedules surface has no dedicated global keyboard shortcut in version 1.
Standard macOS keyboard navigation works for the side menu, form controls,
buttons, and pickers. In the editor, Return activates **Save** when focus
allows.

## Settings / Configuration

Time zone and missed-run behavior are in the editor's **Advanced** section.

### Interval

Choose a number of minutes, hours, or days. The minimum is 15 minutes.
Intervals remain anchored to their original cadence; sleep does not shift every
future run.

### Daily and weekly

Choose a local time, time zone, and for Weekly one or more weekdays. On daylight
saving changes, a missing local time advances to the next valid time and a
repeated local time runs once.

## Troubleshooting

### A Schedule is Blocked

Open the Schedule and verify that its project folder still exists. Edit and save the
Schedule to select a replacement folder or valid Vibe Lane.

### Schedule changes could not be saved

Crispy leaves the last durable Schedule state unchanged and shows a persistence
error. Check available disk space and access to Crispy's application-support
folder, then retry the action. A failed scheduled claim does not start a task.

### A scheduled run did not start

Check whether:

- Crispy was quit and the Schedule is set to skip missed runs;
- the previous task is still Running or Needs you;
- the Schedule is paused;
- the selected project folder is unavailable.

Run history records skipped and blocked occurrences.

If the previous task needs input, the Schedule itself appears as **Needs you** and
the linked history entry carries the same state. Open that task to supply input,
steer, approve, or stop it. The Schedule returns to Running or Scheduled as the task
continues or finishes.

If you stop only the task, an enabled Schedule returns to **Scheduled** and can run
again at its next occurrence. Use **Stop and pause** when both the current work
and future schedule should stop.

### A Vibe Lane edit is not used

This is intentional. Open the Schedule and select **Update Vibe Lane**. Schedules do not
silently adopt later Vibe Lane edits.

## Known Limitations

- Crispy must be running for exact-time execution. Quit-time occurrences are
  handled when the app next launches.
- Version 1 supports local folders only, not SSH or remote projects.
- Cron expressions, webhooks, file-change triggers, and calendar integration
  are not supported.
- A Schedule always skips overlap rather than queueing another task.
