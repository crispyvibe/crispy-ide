---
title: "VibeSpace Projects"
feature: "F021"
domain: "vibespace"
audience: "user"
version: "1.8"
sidebar:
  label: "Projects"
  order: 2
---

# VibeSpace Projects

## Overview

VibeSpace Projects covers project creation, focus management, add/remove operations, terminal hydration, stacked card previews, and layout persistence within a vibespace. Projects are the fundamental unit of work — each represents a directory with its own terminal sessions, file explorer state, and editor context.

## Getting Started

1. Open or create a vibespace in Crispy.
2. Click **Add Project** in the toolbar or Dashboard to add project folders.
3. Select one or more directories in the folder picker.
4. Projects appear in the project rail; the last added project becomes focused.
5. Each project gets its own terminal session, file tree, and editor state.

## Workflows

### Adding Projects

1. Click **Add Project** from the toolbar, Dashboard, or project rail CTA.
2. The folder picker supports multi-select — choose one or more existing directories, or use **New Folder** to create a directory and select it immediately.
3. One project is created per selected folder.
4. Duplicates are ignored (matched by normalized path).
5. If a selected folder is already open, it becomes focused instead of duplicated.
6. The last processed project becomes the focused project with an active terminal ensured.

### Focusing Projects

1. Click a stacked project card in the rail to focus that project.
2. Terminal availability is ensured for the newly focused project.
3. Keyboard focus moves to the focused project's active terminal.
4. Use **⌘⌥]** / **⌘⌥[** to cycle focus between projects.
5. Use **⌘1–⌘9** to focus projects by their assigned shortcut slot.

### Understanding Hydration Order

1. When a vibespace opens, the focused project's terminal hydrates first.
2. Non-focused project terminals hydrate progressively in background order.
3. This ensures the focused project is immediately interactive.
4. Rail previews become live as background hydration completes.
5. Startup defaults are applied once per project per session.

### Viewing Stacked Project Cards

1. Non-focused projects appear as stacked cards in the project rail.
2. Each card shows one representative terminal (chosen by activity, then recency).
3. Additional terminals are grouped behind the representative as a collapsed stack.
4. Cards with terminal activity show an inline activity indicator.
5. Cards without a terminal session show "Loading Terminal" until hydration completes.
6. Double-click a card to open a Terminal Spotlight overlay without changing focus.

### Closing Projects

1. Click the close icon in the focused project's header to remove it.
2. Focus falls back to the last remaining project.
3. Closing the last project returns to the empty state UI.
4. The empty state shows an "Add Project(s)" call to action.

### Restarting a Project

1. With a project focused, trigger **Restart Project** from the project header.
2. This restarts all pane workers:
   - Explorer worker restarts (file tree reloads).
   - Editor worker restarts and reloads the current file if one is open.
   - Terminal pane restarts and recreates an active tab.

### Adjusting Layout

1. In Detailed mode, drag the splitter between editor and terminal to adjust proportions.
2. Layout fractions are stored per project (keyed by normalized path).
3. Fractions persist across app restarts.
4. When a project is reopened, its saved layout is restored.

### Single-Project Rail Behavior

1. When exactly one project is open, the rail shows an "Add Project(s)" call to action.
2. No passive "No Stacked Projects" placeholder is shown.
3. This encourages building multi-project workspaces.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Focus Next Project | ⌘⌥] |
| Focus Previous Project | ⌘⌥[ |
| Focus Project 1–9 | ⌘1–⌘9 |

## Settings

- **Startup Defaults** (VibeSpace Settings): Terminal count and per-terminal startup profiles applied when a project first receives focus.
- **Per-Folder Overrides** (VibeSpace Settings → Projects): Custom startup commands/presets for specific project folders that supersede vibespace defaults.
- **Shortcut Assignments** (VibeSpace Settings → Shortcuts): Map ⌘1–⌘9 to exact projects for deterministic focus switching. Remote project keys include the SSH host, and each numeric slot belongs to only one project.
- **Project Color Tags** (VibeSpace Settings → Projects): Assign colors to project roots for visual identification.

## Tips

- Startup defaults are applied once per project per session — switching focus back to a project doesn't re-run startup.
- Non-focused projects still hydrate terminal sessions in background order for live rail previews, even though startup profiles defer until first focus.
- Each startup profile can launch either a preset or a custom command for its terminal slot.
- Shortcut slots are unique across folders — assigning the same slot to a different folder reassigns ownership.
- The representative terminal on stacked cards uses activity-first ordering: if a terminal has recent output, it's shown first.
- Terminal Spotlight from a stacked card doesn't change the focused project, file preview, or main terminal selection.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Project not appearing after add | Check that the folder exists and isn't already open (duplicates are silently ignored). |
| Terminal not starting for new project | Hydration runs asynchronously. Wait a moment — the "Loading Terminal" placeholder should resolve. |
| Layout not restoring | Layout is keyed by normalized path. If you moved the project folder, the layout association is lost. |
| Startup command not running | Check VibeSpace Settings for the startup configuration. Ensure the vibespace config is trusted (not tampered). |
| Focus shortcut not working | Verify the shortcut assignment in VibeSpace Settings → Shortcuts. Ensure no conflict with other shortcuts. |
| Stacked card shows no terminal | The project's terminal hasn't hydrated yet. It will show "Loading Terminal" until ready. |
| Close button missing | The close icon is in the focused project's header. Stacked cards don't have a direct close — focus the project first. |

## Project Context Menu

Right-clicking an active project row exposes a shared menu, and the menu is the same whether you're in the classic **Files** pane or the **Workspace** (unified) side panel:

- **Make Current Project** — focuses the project and makes it current (same as clicking its stacked card).
- **Open in Terminal** — always opens a *new* terminal tab at the project root (it never just re-selects an existing terminal).
- **Open in System** — opens a local project directory in its default macOS application. For a remote project, Crispy first makes a protected temporary local copy through the remote transfer workflow.
- **Reveal in Finder** — reveals a local project folder in Finder. It is not shown for remote/SSH projects.
- **Download…** — available only for an active remote/SSH project; choose a local destination for a downloaded copy.
- **New File** / **New Folder** — creates an item at the project root.
- **Copy Path** — copies the project's path to the clipboard.
- **Park Project** — see *Parking Projects* below.
- **Remove Project** — see *Removing Projects* below.

Remote project-root Open in System and Download… share the app-wide transfer overlay with remote explorer file/folder actions. Only one coordinator-backed explorer/root transfer runs at a time. The overlay shows preparation/transfer progress, cancelling, publication, completion, or a failure that stays visible until dismissed. Cancel is unavailable once cancellation or publication begins, and a cancelling operation keeps the slot until network and partial-file cleanup finish. Before publishing, Crispy acknowledges the publication state and checks cancellation once more immediately before the atomic replace/move; a cancellation after that final check may not stop publication, so no Cancel control appears while publishing. Remote HTML opened from its editor is independent and uses the editor busy indicator and normal alert instead of this overlay. Other applicable actions behave exactly like their file or folder row counterparts, so wording and results are consistent everywhere.

## Parking Projects

Parking puts a project into a dormant state without removing it from the vibespace. Crispy gathers browser state by the qualified identity plus only an unambiguous legacy root, deduplicates it, and persists exactly once under the qualified identity. It then marks the project parked, closes owned board/file panes, removes the live project, closes browsers, collects both newly returned and previously displaced/outstanding file flushes for that exact project, and races the complete flush set against a real 30-second timeout. Whichever finishes first cancels the other monitor; the retained session shuts down exactly once. Removing live state before browser close prevents fallback behavior from refocusing the project, while delayed shutdown keeps remote file access available until close-time saves finish. Terminal working directories, browser URLs and history, open-file state, and related project configuration remain available for activation later.

### Park a project

1. Open the **Files** tab in the sidebar.
2. Right-click the project header.
3. Choose **Park Project**.

The project disappears from the project rail and from terminal hydration. Its entry moves to a "Parked Projects" section at the bottom of the Files tab. A parked SSH project is recognized with the same parser used for active project restoration, including percent-encoded and legacy paths. Its row shows a server icon, an **SSH** badge, the literal host (plus a non-default port), and only `…/basename`; it omits the username and ancestor paths, and its accessibility identifier hashes the saved address. Because it has no active session, its menu contains only **Activate Project** and **Remove Project**.

### Activate a parked project

1. Open the **Files** tab.
2. Scroll to the **Parked Projects** section.
3. Right-click the parked project entry.
4. Choose **Activate Project**.

The project becomes the focused project. Terminals are recreated from their saved working directories. Browser tabs are restored to their last-known URLs.

### What is preserved across park/unpark

| State | Preserved |
|-------|-----------|
| Terminal tabs (working directory, custom name, origin) | Yes |
| Browser tabs (URL, back/forward history, zoom, theme) | Yes |
| Color tag, shortcut, startup overrides | Yes |
| Layout splitter positions | Yes (per-path) |

## Removing Projects

Removing a project takes it out of the vibespace entirely. Unlike parking, no state is preserved — to bring it back you add the folder again with **Add Project**. Removal happens immediately with no confirmation prompt.

### Remove an active project

1. Open the **Files** tab in the sidebar.
2. Right-click the project header.
3. Choose **Remove Project**.

The project's terminals and browsers are closed and it leaves the project rail. Focus falls back to the last remaining project.

### Remove a parked project

1. Open the **Files** tab and scroll to the **Parked Projects** section.
2. Right-click the parked project entry.
3. Choose **Remove Project**.

The parked entry is dropped from the vibespace without being activated. Its saved snapshot is discarded.

> Removing is also available from the agent CLI — see the Agent CLI guide (`crispy vibespace remove-project <path>`).

## Click-to-Select Project

When you click a tab in the content viewer, the project that owns that tab automatically becomes the focused project. No double-click required. This applies to:

- **File tabs** — focus follows the file's owning project (longest path-prefix match).
- **Browser tabs** — focus follows the browser's owning project (set when the browser was created).
- **Terminal tabs** — focus follows the terminal's owning project.

VibeCast and ACP-pane tabs do not have a project owner, so clicking them does not change project focus.

## Project Identity in Source Control and Spotlight

Remote project identity includes its SSH host, not just the folder path. A repository remains attached to that exact project when another server exposes the same raw path. Selecting a tracked change opens a preloaded diff containing staged changes followed by working-tree changes; selecting an untracked/new file reads through that project's own remote provider.

The same identity follows main and detached Spotlight through direct opens, temporary terminals, shortcuts, splits/permanent terminals, ACP, links, files, browsers, editor panes, restore, and detached attachment. Nested actions stay on the originating host. Project-scoped terminal shortcuts and ⌘1–⌘9 focus assignments use that exact project identity, and each numeric focus slot is unique.

### Upgrading saved SSH project identities

Crispy automatically converts older SSH project addresses—including the earlier unescaped full address—to the current percent-encoded identity. The migration carries terminal and browser state, colors, startup/agent/shell overrides, and both project shortcut definitions and numeric focus slots. It also covers inactive parked and unavailable projects, removes duplicate parked entries, and keeps their settings while no project session is running. A verified parent VibeSpace configuration is saved immediately after canonicalization; an integrity-failed configuration is not silently re-signed.

## Automatic Board Cleanup

Parking or removing an active project also clears every board pane that Crispy can prove belongs to that project, whether the pane is visible, minimized, in Spotlight, on the main board, or in a detached board window. If cleanup empties a detached board window, that window closes automatically. Unrelated panes remain where they are.

Crispy queries browser state through the current project identity and, when safe, its legacy lookup identity, removes duplicates, and saves the result once under the current identity. The saved browser list is refreshed even when no browsers are open, preventing an older snapshot from returning later. It does not persist duplicate snapshots under both identities. Activating the project restores pinned browsers on the main board with their prior tile identity and browsing snapshot, and restored project terminals are recreated during terminal reconciliation.

Remote ownership includes the SSH host. Projects using the same remote path on different servers remain separate. Older remote panes whose owner cannot be determined safely are kept rather than deleted; you can close such a retained legacy pane manually. Moving remote tiles between board windows is unchanged.

Owned pinned file panes and an owned unpinned preview close through their own file providers before project shutdown. If a close-time write fails, the dirty buffer is retained rather than silently discarded. Switching VibeSpaces eagerly closes and prunes outgoing docked file groups so they cannot appear in the incoming VibeSpace.

## Known Limitations

- A parked remote project cannot browse, open, download, mutate files, or launch a terminal until it is activated.
- Remote project-root and explorer external actions inherit the SSH transfer limitations described in F034: one coordinator-backed explorer/root transfer at a time, cancellation retained through cleanup, and no resumability. Editor-triggered remote HTML open is independent.
- Remote drag and drop remains unsupported.

## Documentation Verification

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. Static regression source directly covers prior raw full SSH config migration, browser and shortcut state, canonical loading, parked deduplication, and immediate verified-parent rewrite. Runtime preservation of every parked/unresolved settings dictionary, exact same-root repository attachment, staged-then-working preloaded diffs, exact untracked providers, the complete Spotlight matrix, qualified browser lifecycle migration, project-keyed outstanding flushes, the true 30-second race, and exactly-once shutdown were verified from production source only.

## Change History

- 2026-10-23: Version 1.8 documents automatic canonical SSH migration for active, unavailable, and parked projects, dormant settings/shortcut preservation, trust-safe parent rewrite, and corrected static/build evidence.
- 2026-10-23: Version 1.7 documents exact source-control/Spotlight/shortcut identity, qualified-only browser persistence after safe legacy lookup, project-keyed displaced/outstanding flushes, and a true flush-vs-timeout exactly-once shutdown race; narrows verification to static/build-only evidence.
- 2026-10-23: Version 1.6 documents file-flush-aware deferred shutdown, the 30-second watchdog, owned unpinned previews, eager VibeSpace group pruning, and qualified-only browser snapshot persistence after legacy-compatible lookup.
- 2026-10-20: Added automatic board cleanup guidance for park/remove, empty detached-window closure, safe same-root SSH isolation, fail-closed legacy panes, and ownership-preserving unpark restoration.

- 2026-10-20: Corrected fallback-refocus and publication-boundary guidance; the 2026-10-23 entry supersedes the earlier immediate-shutdown wording with file-flush-aware deferred shutdown.
