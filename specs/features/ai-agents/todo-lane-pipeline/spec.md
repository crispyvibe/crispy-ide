# Todo Lane Pipeline — Spec

Status: implemented

Feature: F060 · Canonical source of truth

## Overview

The Todo Lane Pipeline turns todos (F053) from passive notes into the intake
funnel for autonomous work (F059 Vibe Lanes). A todo moves through four stages,
each optional except capture:

> **Capture** — zero-friction, unchanged from F053.
> **Triage** — a short-lived background agent enriches the todo: relevant
> files, clarifying questions, and a ranked lane suggestion.
> **Refine** — an interactive ACP chat session attached to the todo turns it
> into a dispatchable task; the agent writes agreed changes back into the todo.
> **Dispatch** — the todo becomes a Vibe Lane task with seeded carry-forward;
> lane lifecycle events flow back into the todo's thread.

Supporting both agents and the human are **file links**: a todo carries live
references (path + optional line) to files, added via drag-and-drop or the
inline file search (F038 trigger). Links open in the content viewer like any
file and travel to agents as path lists — never copies.

Design tenets:

- **Additive, never blocking.** Every pipeline stage is optional. A todo with
  triage off, no links, and no refinement is exactly an F053 todo. Pipeline
  failures degrade to "nothing happened," never to data loss or blocked capture.
- **The todo is the artifact.** Refinement sessions and triage runs are
  disposable; their durable output lives on the todo (fields, thread messages,
  links). Losing a session loses nothing.
- **Agents never rewrite the user silently.** Triage writes only to its own
  structured field and the thread. Only the interactive refine session — acting
  on the user's explicit conversational agreement — updates title/body, via the
  same audited CLI surface agents already use.
- **Features stay decoupled.** Todos and Vibe Lanes do not import each other.
  A bridge service above both (wired in AppContainer) owns dispatch, lifecycle
  fan-in, and triage orchestration.
- **Surface parity.** A todo behaves identically regardless of where it was
  created or edited — app UI, quick capture, or agent CLI. Triage, chips,
  refine, and dispatch key off the store, never off the originating surface,
  and every pipeline action available in the UI has a CLI equivalent.

Core terms:

- **File link** — a live `{path, line?}` reference on a todo. Not a copy; the
  target may change or vanish independently.
- **Triage** — one bounded, headless agent run over a settled todo producing a
  structured result: context files, questions, lane suggestion.
- **Refine session** — an interactive ACP session attached to a todo by ID,
  reattachable across opens.
- **Dispatch** — creating a Vibe Lane task from a todo, including seeding the
  lane's first-checkpoint required inputs (carry-forward).
- **Dispatch block** — structured markdown sections in the todo body
  (Goal / Done when / Context files / Constraints) that refinement produces and
  dispatch parses.

## Dependencies

- F053 (Quick Todos & Sticky Notes) — the todo model, store, surfaces, thread.
- F059 (Vibe Lanes) — task creation, carry-forward, task states.
- F011 (ACP) — refine chat sessions.
- F047 (External Agent Sessions) — headless triage sessions.
- F044 (Agent CLI) — agent write-back path (`crispy todo …`).
- F038 (Terminal Inline Triggers) — inline file search in todo composers.
- F006 (Content Viewer) — opening linked files and the refine chat pane.

## Requirements

### F060-R01: File links on todos

A todo MUST support an ordered list of file links, each `{path, line?}`. Links
are references, not copies: no file content is duplicated or managed by the
app. Links MUST be addable via drag-and-drop onto the todo detail pane and via
the inline file-search trigger (F038) in the todo body editor and thread
composer. Deleting a todo drops its links and MUST NOT touch linked files.

The existing single `filePath` on a todo MUST migrate to (or coexist as) the
first file link; no data loss on upgrade.

### F060-R02: File links open like files

Activating a file link MUST open the file in the content viewer
(`openFileInTab`), honoring the line anchor when present. Links to paths
outside any project root MUST still open (standalone file tabs).

A link whose path does not currently resolve MUST render in a distinct
"missing" state and MUST still be removable or re-pickable. Missing links MUST
NOT be silently dropped, and prompts sent to agents MUST mark unresolvable
paths as missing rather than omit them.

### F060-R03: Dispatch a todo to a lane

The user MUST be able to dispatch a todo to a chosen lane, from the todo UI
and from the CLI (F060-R09) with identical semantics. Dispatch creates a
Vibe Lane task via the lane manager with the todo's title as task input, the
todo's project path (or an explicitly chosen one when the todo is
vibespace-level), and seeded carry-forward per F060-R04. The todo MUST record
the created task's ID (`laneTaskID`).

A todo MUST have at most one linked non-terminal lane task. Re-dispatch MUST be
possible once the linked task is terminal (done/stopped) or deleted; the link
then points at the newest task. Deleting a dispatched todo MUST NOT stop or
delete the lane task — the link is dropped, the task runs on.

### F060-R04: Seeded carry-forward

Task creation MUST accept initial carry-forward values so a dispatched todo can
satisfy the lane's first-checkpoint `requires` contract without an immediate
Supply pause. Dispatch MUST map, in priority order: parsed dispatch-block
sections, triage-prefilled keys, and file links (as a path list) onto the
lane's required input keys. Keys that remain unresolved MUST be surfaced
before creation — in the dispatch UI, or in the CLI response — so the caller
can fill them or proceed knowingly (falling back to the normal F059 Supply
flow). The CLI MUST require an explicit flag to proceed with unresolved keys.

### F060-R05: Lane lifecycle feedback into the thread

The bridge MUST observe linked task state transitions and post agent-authored
messages into the todo's thread for at least: dispatched (with lane name),
needs input (with request kind), stopped (with reason), and done. Each
transition MUST produce at most one message. When the linked task reaches
`done`, the todo MUST surface a completion affordance (one-tap complete or
auto-complete per setting); it MUST NOT auto-complete on `stopped`.

### F060-R06: Auto-triage on settled todos

When enabled, a todo MUST be triaged by a short-lived headless agent run after
its content settles (debounce ≥ 10 s after the last edit; never mid-typing).
Triage MUST apply identically to todos created or edited from any surface —
the trigger is the store change, not the UI.
Triage receives the todo (title, body, project, links) and the lane catalog
summary (names, descriptions, first-checkpoint `requires` keys) and produces a
structured result:

- context: project files/symbols the todo appears to reference;
- questions: 2–4 clarifying questions, mapped to missing lane input keys where
  possible;
- lane suggestion: ranked lane candidates with a one-line reason, or an
  explicit "not lane-shaped" verdict;
- prefill: carry-forward key/values it could already determine.

The result MUST be stored in a structured `triage` field on the todo (status:
pending | done | skipped | failed) and summarized as one agent message in the
thread. Triage MUST NOT modify the todo's title, body, color, links, or status.

### F060-R07: Triage guardrails

Triage MUST be governed by:

- a per-vibespace setting: off | project-scoped todos only | all todos
  (default: project-scoped only);
- skip heuristics: todos under a minimum length and vibespace-level errand-like
  todos are skipped (status `skipped`), not queued;
- a generation guard: triage snapshots `updatedAt` at start; if the todo was
  edited or deleted before the result lands, the result MUST be discarded (and
  triage re-queued on edit);
- a concurrency cap (≤ 2 concurrent triage runs) with a bounded queue; triage
  MUST NOT consume Vibe Lane task capacity;
- a time box in the triage prompt and a hard session timeout; on timeout or
  error the todo records `failed` silently — no user-facing error, no retry
  storm (one automatic retry max);
- material edits to a triaged todo re-queue triage, replacing the prior result.

### F060-R08: Interactive refine session

The user MUST be able to open a refine session on a todo: an ACP chat pane
whose session is created programmatically, seeded with the todo's content,
links, triage result (when present), and instructions to interview the user
toward a dispatch block. The todo MUST store the session ID
(`refinementSessionID`); reopening refine on the same todo MUST reattach to the
existing session when it is still available, else start fresh.

The refine agent updates the todo only through the existing agent CLI
(`crispy todo update`, `todo message add`, and the new link commands), so all
write-back is audited, live in the UI, and subject to F053 validation. With
the user's explicit conversational agreement, the refine agent MAY complete
the pipeline itself via `todo dispatch` (F060-R09) — dispatch semantics are
identical to the UI path. The session itself is disposable; closing or losing
it MUST NOT lose refined content.

### F060-R09: CLI parity

The agent CLI MUST grow: `todo file add <id> --path <path[:line]>`,
`todo file remove <id> --path <path>`, `todo file list <id>`,
`todo triage show <id>` (structured triage result), and
`todo dispatch <id> --lane <name-or-id> [--input key=value …]
[--allow-unresolved]`.

CLI dispatch MUST route through the same bridge path as UI dispatch: same
one-active-task rule (dispatching a todo with a non-terminal linked task MUST
fail with a clear error), same carry-forward mapping with `--input` values
taking highest priority, and same thread fan-in. Without `--allow-unresolved`,
unresolved required keys MUST fail the command and be listed in the output so
the caller (typically a refine agent) can supply them and retry.

### F060-R10: Decoupled bridge

Todos and Vibe Lanes MUST NOT import each other's types. A bridge service
owned by AppContainer MUST mediate dispatch, task-state observation, and triage
orchestration. The lane manager MUST expose task creation with initial
carry-forward and a task-state-change callback; the todo store MUST expose the
fields above (`laneTaskID`, `refinementSessionID`, `triage`, file links). Either
feature MUST function fully with the bridge absent.

## Scenarios

### F060-S01: Link, open, and pass along a file

- **Given** a todo about a parser bug
- **When** the user drags `Parser.swift` onto the detail pane and adds
  `Tokenizer.swift:88` via the inline trigger in the body editor
- **Then** both render as chips, clicking opens them in the content viewer (the
  second at line 88), and both paths appear in any triage/refine/dispatch
  prompt for this todo.

### F060-S02: Missing link degrades gracefully

- **Given** a todo linking `Scratch.md`, which the user later deletes from disk
- **When** the todo is opened and later dispatched
- **Then** the chip shows a missing state with remove/re-pick actions, and the
  dispatch prompt marks the path as missing instead of omitting it.

### F060-S03: Capture triggers triage

- **Given** auto-triage is enabled for project-scoped todos
- **When** the user captures "login form drops trailing spaces in email" scoped
  to a project and stops editing for the debounce window
- **Then** one headless triage run executes, and the todo gains a lane
  suggestion chip, question count chip, and one thread summary message —
  title/body untouched.

### F060-S13: CLI-created todo behaves identically

- **Given** the same triage settings
- **When** an agent creates an equivalent todo via `crispy todo add --project …`
- **Then** the same debounce, skip heuristics, and triage run apply, and the
  resulting chips and thread summary are indistinguishable from the
  UI-captured case.

### F060-S04: Triage result outdated by an edit

- **Given** a triage run in flight for a todo
- **When** the user edits the todo body before the run completes
- **Then** the in-flight result is discarded and triage re-queues against the
  edited content; no stale result is ever stored.

### F060-S05: Trivial todo is skipped

- **Given** auto-triage enabled for all todos
- **When** the user captures "buy milk" at vibespace level
- **Then** triage records `skipped` without spawning a session and no chips or
  thread messages appear.

### F060-S06: Refine picks up where triage left off

- **Given** a triaged todo with three open questions
- **When** the user opens Refine
- **Then** the chat pane opens seeded with the triage findings and questions
  (not a cold "what do you want?"), the conversation produces a dispatch
  block, and the agent writes it to the todo body via `crispy todo update` —
  visible live in the detail pane.

### F060-S07: Refine session reattaches

- **Given** a todo with an existing refine session
- **When** the user closes the pane and reopens Refine later
- **Then** the same session resumes with its history; if the session is gone, a
  fresh one starts seeded from the todo's current state.

### F060-S08: Dispatch with full seed

- **Given** a refined todo whose dispatch block covers the lane's
  first-checkpoint `requires` keys
- **When** the user dispatches to the suggested lane
- **Then** a task is created with seeded carry-forward, runs without an
  immediate Supply pause, `laneTaskID` links the two, and a "dispatched"
  message lands in the thread.

### F060-S09: Dispatch with gaps falls back to Supply

- **Given** an unrefined todo dispatched to a lane requiring `repro`
- **When** the dispatch UI shows `repro` unresolved and the user proceeds anyway
- **Then** the task is created and pauses per F059-R05 with a Supply request,
  and the todo thread receives the "needs input" message.

### F060-S10: Lifecycle fans into the thread, done completes the todo

- **Given** a dispatched todo with auto-complete enabled
- **When** the task hits `needsInput`, then later `done`
- **Then** the thread receives exactly one message per transition and the todo
  is completed on `done`; on `stopped` it would instead stay active with a
  stopped-reason message.

### F060-S11: Todo deleted, task unaffected

- **Given** a dispatched todo whose lane task is running
- **When** the user deletes the todo
- **Then** the task continues under Vibe Lanes' own lifecycle; only the link
  and pending thread fan-in are dropped.

### F060-S12: Re-dispatch after terminal task

- **Given** a todo whose linked task stopped
- **When** the user refines further and dispatches again
- **Then** a new task is created and `laneTaskID` now points at it; the old
  task's record remains in Vibe Lanes untouched.

### F060-S14: Refine agent dispatches on agreement

- **Given** a refine conversation that has produced a complete dispatch block
- **When** the user says to go ahead and the agent runs
  `crispy todo dispatch <id> --lane "Fix a bug"`
- **Then** the task is created through the same bridge path as UI dispatch,
  `laneTaskID` links the todo, and the "dispatched" message appears in the
  thread.

### F060-S15: CLI dispatch blocks on unresolved keys

- **Given** an unrefined todo missing the lane's required `repro` key
- **When** an agent runs `todo dispatch` without `--allow-unresolved`
- **Then** the command fails listing `repro` as unresolved and no task is
  created; with `--input repro="…"` or `--allow-unresolved` it proceeds.

### F060-S16: CLI dispatch respects the one-active-task rule

- **Given** a todo whose linked task is running
- **When** any caller (UI or CLI) attempts to dispatch it again
- **Then** the attempt fails with a clear error naming the active task; no
  second task is created.

## Acceptance Criteria

- File links are references only: no copy, no managed storage, no deletion of
  linked files, missing state rendered and communicated to agents.
- The inline file-search trigger works in the todo body editor and thread
  composer, configured with the todo's project (or vibespace projects) as
  search roots.
- Dispatch seeds carry-forward; a fully refined todo runs its first checkpoint
  with zero Supply pauses; unresolved keys are visible pre-dispatch.
- One linked non-terminal task per todo, re-dispatch after terminal, todo
  deletion never touches the task.
- Lifecycle transitions produce exactly one thread message each; `done`
  honors the completion setting; `stopped` never auto-completes.
- Triage never mutates user-authored fields; debounce, generation guard,
  concurrency cap, skip heuristics, and silent failure are unit-tested with
  deterministic fakes.
- Refine write-back flows exclusively through the agent CLI; refined content
  survives session loss.
- Neither Features/Todos nor Features/VibeLanes imports the other; removing
  the bridge leaves both features fully functional.
- CLI: `todo file add/remove/list` and `todo triage show` round-trip.
- Surface parity: UI and CLI dispatch share one bridge code path (verified by
  a shared unit-test suite run against both entry points); triage behavior is
  identical for UI- and CLI-created todos; `todo dispatch` fails without
  `--allow-unresolved` when required keys are unresolved and enforces the
  one-active-task rule.

## Out of Scope

- Voice input or any command surface beyond the existing UI/CLI.
- Copying/snapshotting linked files, file watching, or rename tracking for
  links; a stale chip with a missing state is the accepted behavior.
- Bulk triage of pre-existing todos on upgrade; triage applies to new/edited
  todos.
- Multiple simultaneous lane tasks per todo.
- Lane suggestions learning from dispatch history.
- VibeCast (F028) integration; the pipeline has no VibeCast dependency.

## Open Questions

- Should the dispatch block's section names be user-visible convention only, or
  validated structure with authoring help in the detail pane?
- Default for the done-completion behavior: one-tap affordance vs.
  auto-complete (leaning one-tap for v1).
- Whether triage should be allowed to add file links it discovers (currently
  write-back of links is refine-only; triage stores candidates in its own
  field).
- Whether `todo triage show` should include the raw agent transcript reference
  for debugging.

## Change History

- 2026-07-12 — Implemented across all four stages: schema v5 + todo_files,
  bridge with dispatch (UI sheet + `todo dispatch` CLI, one code path),
  lifecycle fan-in with dedupe, triage coordinator with guardrails + chips +
  settings, reattachable refine sessions with seeded prompts, file links
  (chips, drag-drop, F038 inline trigger, CLI). Agent CLI env
  (`CRISPY_SOCKET`) now injected into all ACP sessions. Unit tests: bridge,
  triage, models; Rust: persistence v5 + CLI parsing.
- 2026-07-11 — Surface parity made a design tenet and requirement: triage and
  dispatch behave identically for UI- and CLI-originated todos; `todo
  dispatch` added to R09 (same bridge path, `--input`/`--allow-unresolved`,
  one-active-task enforcement); refine agents may dispatch on the user's
  conversational agreement. Scenarios S13–S16 added.
- 2026-07-11 — Initial draft: file links (references, not copies; F038 trigger
  reuse), bounded auto-triage with guardrails, reattachable refine sessions
  with CLI write-back, dispatch with seeded carry-forward and lifecycle
  fan-in, decoupled bridge.
