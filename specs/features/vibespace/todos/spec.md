# Quick Todos & Sticky Notes — Spec

Status: implemented

## Overview

Quick, vibespace/project-scoped todos with per-todo rich-text (markdown) notes and a flat activity thread. Todos are managed from a **dockable surface** (opened like VibeCast as a content-viewer tab) and from an **instant-capture HUD** (a hotkey-invoked floating field), and are fully scriptable from the agent CLI. State persists in the encrypted libSQL store shared with File Comments (F049). Reminders are deferred to a later phase (schema columns reserved).

## Dependencies

- F044 (Agent CLI) — `todo.*` command surface
- F049 (File Comments) — shared `crispyvibes-persistence` helper + `AgentConversationStore`; the established scoped-store pattern
- F021 (VibeSpace Projects) — focused-project resolution and the project list for scoping
- F015 (Theming) / App Settings — palette tokens and `crispyvibesUIScale` font scaling
- F016 (Keyboard Shortcuts) — editable binding for the capture hotkey

## Requirements

### F053-R01: Instant capture
A todo MUST be creatable from anywhere in the app via a hotkey-invoked floating HUD: type a title and press Return to save and dismiss; Esc or click-outside cancels. The hotkey MUST be reconfigurable in Settings → Keyboard Shortcuts.

### F053-R02: Capture target
The capture HUD MUST default to the currently-focused project (snapshotted when it opens) and MUST show that target and allow retargeting to any project in the vibespace or to the vibespace-level (no-project) inbox.

### F053-R03: Capture confirmation
On save, the HUD MUST show a brief (~1s) success confirmation with animation before dismissing — only after the write actually persists. If the write fails, the HUD MUST show the error and keep the typed text so the capture is not lost.

### F053-R04: Dockable surface
Todos MUST be presentable as a dockable content-viewer surface (master list + detail), opened/toggled from the toolbar — the same docking model as VibeCast. The surface MUST adapt to its container: wide hosts show list and detail side by side; narrow panes collapse to a single column where selecting a card pushes the detail with a Back control.

### F053-R05: List & scoping
The list MUST show sticky-note cards scoped to the focused project with an "All in VibeSpace" toggle, support a quick-add field, completion toggle, and delete, with active items in a stable creation-order section above a collapsible "Completed (n)" section. Sort keys MUST NOT change on edit (no reorder-under-the-cursor). The header MUST show active/completed counts; a search field (shown once the list grows) filters by title and body. Each card MUST render its sticky color as a leading edge and offer complete/color/delete from a context menu. Deletion MUST be confirmed (it cascades to the thread). Completion and deletion MUST update optimistically and reconcile with the store, and store errors MUST surface in a dismissible banner. ↑/↓ move selection, ⌦ prompts delete, and ⎋ clears selection when the list has focus.

### F053-R06: Detail, rich text & threads
The detail pane MUST support an inline-editable title (committing on Return and on focus loss), a sticky-color picker, created/completed metadata with project and attached-file chips, a markdown notes body (edit/preview with a visible hover affordance and ⎋ cancel), and a flat thread of markdown messages with a composer. Consecutive same-author messages MUST group under a single header with a relative timestamp; user and agent authorship MUST be visually distinguished.

### F053-R07: CLI access
The CLI MUST expose `todo.add|list|complete|reopen|update|remove|show` and `todo.message.add`, with project context resolved from `_env.project_path`. CLI mutations MUST be indistinguishable from UI ones and update the UI live.

### F053-R08: Persistence
Todos and thread messages MUST persist per vibespace (and project) across launches in the encrypted helper store. Deleting a todo MUST cascade-delete its messages.

### F053-R09: Theming & scaling
All Todos UI MUST draw colors from the active theme palette (no hardcoded colors) and MUST scale fonts, spacing, icons, and frames via `crispyvibesUIScale` so it responds to cmd+/cmd-/cmd-0 like other surfaces.

### F053-R10: Reminders (deferred)
Reminders are out of scope for v1. The schema reserves `due_at`/`reminder_at` so a later phase can add scheduling without migration.

## Scenarios

### Scenario F053-S01: Instant capture
**Given** any surface is focused **When** the user presses the capture hotkey, types a title, and presses Return **Then** a todo is created in the focused project, a ~1s "Todo added" confirmation animates, and the HUD dismisses.

### Scenario F053-S02: Retarget capture
**Given** the capture HUD is open showing the focused project **When** the user opens the "Lands in" menu and picks another project (or VibeSpace) **Then** focus returns to the field and the todo saves to the chosen target.

### Scenario F053-S03: Capture cancel
**When** the user presses Esc or clicks outside the HUD **Then** it dismisses with no todo created.

### Scenario F053-S04: Open the dockable surface
**Given** an active vibespace **When** the user clicks the Todos toolbar button (or triggers the toggle) **Then** the Todos surface opens (or re-activates): in **Detailed** view as a content-viewer tab, and in **Terminal Board** view as a floating **spotlight** over the board. The surface decision comes from `ContentSurfacePolicy` (see ADR-003), so the toolbar never forces a layout switch.

### Scenario F053-S05: Quick-add in the list
**When** the user types in the list's quick-add field and presses Return **Then** a card is created in the current scope and auto-selected.

### Scenario F053-S06: Select → detail
**When** the user selects a card **Then** the detail pane shows its title, notes, and thread; the selected card shows an accent-tinted fill and leading bar.

### Scenario F053-S07: Edit rich-text body
**When** the user edits the notes body and saves (⌘Return) **Then** the markdown body persists and renders formatted in preview.

### Scenario F053-S08: Thread message
**When** the user types in the composer and presses Return **Then** a "You" message appears in the thread, grouped under the author header with a relative timestamp.

### Scenario F053-S09: Agent thread message via CLI
**When** an agent runs `crispy todo message add <id> --text "…"` **Then** an agent-authored (distinctly styled) message appears live in the thread.

### Scenario F053-S10: Complete / delete
**When** the user toggles completion **Then** the card updates instantly (optimistically) and moves into the collapsible Completed section; deleting asks for confirmation, then removes the todo and clears selection if it was selected.

### Scenario F053-S14: Narrow-pane adaptation
**Given** the Todos surface is hosted in a pane narrower than the two-column breakpoint **When** the user selects a card **Then** the detail replaces the list with a Back control, and widening the pane restores the side-by-side layout.

### Scenario F053-S15: Sticky color
**When** the user assigns a color from a card's context menu or the detail color picker **Then** the card renders that color as its leading edge, and `crispy todo add --color <tag>` produces the same result.

### Scenario F053-S11: CLI add / list / show
**When** an agent runs `crispy todo add --text "X"`, `crispy todo list`, and `crispy todo show <id>` **Then** the todo is created in the resolved project, listed, and shown with its full thread; the open surface updates live.

### Scenario F053-S12: Font scaling
**Given** the Todos surface is open **When** the user presses cmd+ / cmd- / cmd-0 **Then** the list, cards, detail, thread, composer, and capture HUD scale fonts/spacing/icons accordingly.

### Scenario F053-S13: Persistence across relaunch
**Given** todos and messages exist **When** the app relaunches **Then** they are restored for the vibespace; deleting a todo also removes its messages.

## Acceptance Criteria

- Capture is sub-2s, zero-decision, with a visible target and confirmation.
- Dockable surface matches the VibeCast open/toggle model.
- Bodies and thread messages are markdown; threads group by author with relative timestamps.
- CLI mutations are indistinguishable from UI ones and live-update the surface.
- All colors come from the palette; all sizes scale with `crispyvibesUIScale`.
- Todos/messages persist; message delete cascades.

## Open Questions

1. **Vibespace-switch refresh:** the open surface does not yet auto-refresh when the active vibespace changes (parity hook with comments pending).
2. **Board tile parity:** Todos now floats as a **spotlight** over the board (a full `TerminalSpotlightState.Source.todos` citizen; surface chosen by `ContentSurfacePolicy`, ADR-003). A dedicated board *tile* (alongside ACP/Browser tiles) is still deferred.
3. **Session restore:** a `.todos` tab is not persisted across relaunch (parity with VibeCast, which also isn't).
4. **Reminders staging:** when added, separate "due date" from "reminder time" or a single field?
5. **Markdown link hardening:** thread/body markdown is rendered inline-only (no HTML/JS execution), but unlike comments the body is not server-sanitized — see threat-model F053-T01.

## Change History

| Date | Change |
|------|--------|
| 2026-06-03 | Initial spec (sidebar panel; SQLite; reminders deferred). |
| 2026-06-04 | Reworked to the shipped feature: dockable surface (VibeCast model), per-todo rich-text notes + flat threads, instant-capture HUD with project picker + success feedback, palette theming + `crispyvibesUIScale`. Status → implemented. |
| 2026-06-19 | Surfacing now goes through the centralized `ContentSurfacePolicy` (ADR-003): in Terminal Board view Todos floats as a spotlight instead of being a detail-tab-only surface that the board hid. |
| 2026-07-11 | Management-surface overhaul: adaptive one/two-column layout (R04), stable sections with counts + search + sticky-color rendering + optimistic updates + confirmed deletes + error banner + keyboard navigation (R05), honest capture confirmation (R03), detail metadata/color picker/focus-loss title commit (R06). Added S14/S15; model logic covered by `TodoModelTests`. |
