---
title: "Vibe Lanes"
feature: "F059"
domain: "ai-agents"
audience: "user"
version: "5.2"
sidebar:
  label: "Vibe Lanes"
  order: 5
---

# Vibe Lanes

## Overview

Vibe Lanes runs work through reusable processes:

- A **Vibe (Loop)** retries one expectation within its Work, Verification, and
  Bounds.
- A **Vibe Lane (Spiral)** moves through ordered Vibes and accumulates verified
  context at every handoff.
- A **Schedule** starts a new task on a recurring cadence using an approved,
  frozen Vibe Lane revision.

You give a **task** to a Vibe Lane; the lane moves the task through ordered
**checkpoints** until the work is done, stopped, or waiting for you. A Vibe can
retry its current checkpoint, but the Vibe Lane does not jump backward to an
earlier checkpoint.

Each checkpoint has:

- **Work** — what the worker should produce.
- **Verification** — how an independent reviewer decides whether the outcome is
  done, optionally using reusable Review skills.
- **Bounds** — how many attempts and how much time the checkpoint gets before it
  stops or asks you to steer.

Checkpoints pass context forward as named values, so later checkpoints can depend
on earlier results.

## Getting Started

1. Open **Automation**, then choose **Skills**, **Vibes**, or **Vibe Lanes** to
   author reusable definitions. Use the Vibe Lanes task surface with a project
   open to run work manually.
2. Press **New task**, describe the work, and choose a Vibe Lane.
3. Optionally change the **project directory** (defaults to the focused project).
4. Review the Vibe Lane route and its read-only per-step engine summaries.
5. Watch the task move through its checkpoint path.
6. Open the task when it is **Needs you**, Stopped, or Done.

## Opening Vibe Lanes

Use **Automation** in the application side menu to manage Schedules, compose
Vibe Lanes, and maintain the central Vibe library. Automation is
available without an open VibeSpace.

Use the **flowchart** button in the title bar. Its behavior follows the active
view:

- **Board view** — opens Vibe Lanes as a spotlight. Use the pin button in the
  spotlight header to keep it as a persistent board tile.
- **Detailed view** — activates the existing Vibe Lanes tab or opens one.
- **Detached board window** — adds a Vibe Lanes tile directly to that window.

Each board surface can contain one Vibe Lanes tile. A detached window's button is
disabled when its board is full or already has the tile.

## Task States

- **Running** — the engine is running or waiting for capacity to run the task.
- **Needs you** — the task is paused for a Supply, Steer, or Review answer.
- **Stopped** — the task cannot continue without starting different work or
  changing the Vibe Lane/task setup.
- **Done** — the final checkpoint passed and the outcome is recorded.

Needs you tasks appear first on the dashboard, and a notification fires the
moment a task pauses for you.

## How a Task Moves

At each checkpoint, the worker performs the Work. The verification checks the
actual outcome against the definition and returns PASS or FAIL — by default an
independent reviewer agent judges; checkpoints authored as **Verified by: You**
pause for your verdict instead.

Work skills and Review skills have different jobs. Work skills guide the worker
that produces the outcome. Review skills guide only the independent reviewer
that tests the outcome against the pass criteria. A Review skill can encode a
reusable procedure such as code review, security review, or semantic-version
validation without introducing a hardcoded verifier type.

- PASS records a handoff, stores declared outputs, and advances.
- FAIL sends reviewer feedback back to the worker for another attempt.
- Exhausted bounds either stop the task or ask you to steer, depending on the
  Vibe.

The worker can change files and explain what it did, but it cannot decide that a
checkpoint is complete. Completion comes from the reviewer.

## Managing Skills

Open **Skills** from Automation to manage the procedures available to Vibes.
Each skill is a folder with a `SKILL.md` entrypoint and optional references,
scripts, assets, templates, or agent metadata.

- **Bundled** skills ship with Crispy and are read-only.
- **Personal** skills are created and edited in Crispy.
- **Linked** skills stay in an external folder and are read-only in Crispy.

Use **Import Skills** to select one `SKILL.md`, one package folder, or a
repository containing many nested packages. Crispy discovers the packages
recursively and does not copy linked sources. Duplicate a bundled or linked
skill to create an editable personal package, including all supporting files.

The Skills library shows category, Work/Review roles, unattended or interactive
execution, resources, required commands, and readiness. A missing referenced
file or required command makes a skill unavailable for new Vibe assignments.
Interactive skills can guide Work but cannot be used by an unattended reviewer.
Before a Run starts its first attempt, Crispy also checks that every assigned
package still has a `SKILL.md`.

## Supply

Supply happens when a checkpoint requires an input marked ask-user and the value
is not already in carry-forward.

Example: a Deploy checkpoint requires `api_base`. The task pauses as **Needs
you**, asks for `api_base`, stores your answer, and continues.

## Steer

Steer happens when a checkpoint exhausts its bounds and the Vibe Lane author
chose to escalate. The task shows the last reviewer feedback and asks for
guidance.

Your guidance is fed to the worker as feedback. The checkpoint gets a fresh
bounded attempt window and resumes. Steers are limited by the Vibe Lane's steer
limit; once reached, the next exhausted bound stops the task.

## Review (human verification)

Review happens when a checkpoint is authored with **Verified by: You**. After
the worker finishes, the task pauses as **Needs you** with the checkpoint's
done-when checklist. Inspect the outcome yourself — project files, the diff, or
the worker thread — then:

- **Approve** — records a PASS and the Vibe Lane advances.
- **Request changes** — requires feedback; records a FAIL and your feedback goes
  to the worker for another attempt, then the step pauses for your review again.

Waiting on your verdict never consumes attempts or time; rejections count like
any failed attempt.

## Creating and Editing Vibes

Open **Vibes** from Automation. A Vibe centrally defines:

- Category: where the Vibe appears in the library and Vibe Lane designer;
- Outcome: the goal, working instructions, and Work skills;
- Done when: pass criteria, Review skills, and who verifies them;
- Limits: max attempts, time limit, stop or ask to steer;
- Execution: optional agent, model, mode, and reasoning.

Vibes marked **Needs setup** remain available in the library but cannot be added
to a Vibe Lane. Choose an existing category or use the adjacent add control to
create one with a custom name and icon. Category and status filters can be
combined, and category labels distinguish Vibes that intentionally share a
short name such as **Implement** or **Verify**. Editing a Vibe creates a new
version; Vibe Lanes using an older version do not change automatically.

## Creating and Editing Vibe Lanes

Open **Vibe Lanes** from the dashboard. The designer shows the Vibe library
beside the Vibe Lane recipe. Add and reorder Vibes, then configure:

- name and description;
- steer limit;
- stable step IDs;
- handoffs: required inputs, ask-user behavior, and produced outputs.

Each step is a pinned reference to one central Vibe and shows a compact Outcome
-> Done when -> Limits summary. When a newer Vibe version exists, choose
**Use latest** to adopt it for that Vibe Lane.

Edits apply to new tasks. Existing tasks keep the Vibe Lane version they started
on. Use **Restore starters** to re-add deleted starter Vibe Lanes and refresh
unedited ones to the latest shipped versions — Vibe Lanes you edited are never
changed.

## Choosing a Step Engine

Engine settings belong to each checkpoint, not to the task creation screen.
Leave a setting at its default to inherit ACP behavior:

- **Agent** inherits the app-wide ACP agent.
- **Model** inherits the app-wide model when the agent is inherited. If you pick
  a different agent and leave Model at **Agent default**, that agent chooses its
  own model.
- **Mode** uses the selected agent's default.
- **Reasoning** inherits the app-wide ACP default.

Every Vibe Lane worker, reviewer, handoff, outcome, and rerun session uses
**Full Trust**. There is currently no Standard trust option for Vibe Lane steps.

Model and mode choices are scoped to the selected agent. Protocol agents such as
Kiro load their options from a temporary ACP session when selected; direct
integrations use their known model catalog. Starter lanes inherit the installed
agent and model but choose a reasoning level suited to each step.

## Following Work

Open a task to see:

- checkpoint path and status;
- current activity;
- last verification result and feedback;
- carry-forward inputs/outputs;
- any open Supply, Steer, or Review request;
- worker and reviewer chats.

The current checkpoint shows the engine reported by its live session. Completed
attempts keep their own engine history, so later app-default changes do not
rewrite what ran.

## Rerunning One Step

A Done or Stopped task can rerun any checkpoint that has attempt history:

1. Open the task and select the checkpoint.
2. Press the rerun button.
3. Choose the engine for this attempt and press **Rerun**.

The rerun starts fresh worker and reviewer sessions and a fresh bounded attempt
window. It does not edit the lane or remove earlier attempts. After the step
passes, the task returns to its previous Done or Stopped state. Downstream steps
are not automatically replayed.

## Running Many Tasks

Tasks are independent in state. One task needing input or stopping does not affect
another. Until per-task workspace isolation exists, code-editing tasks should be
serialized per project so two workers do not edit the same files at once.

## Restart Behavior

Running tasks resume from the last persisted checkpoint after restart. Needs you
tasks remain paused with the same request. Done and Stopped tasks remain terminal.
Invalid saved state is refused instead of replayed.

## Troubleshooting

- **A task says Needs you.** Open it and answer the Supply, Steer, or Review
  request, or stop it.
- **A skill is unavailable.** Open its Requirements tab and install the missing
  command or restore the referenced package file.
- **A linked skill changed unexpectedly.** Linked packages are read from their
  external location. Duplicate the package when a stable local copy is needed.
- **A task stopped after missing input.** The lane likely required a key that no
  earlier checkpoint produced and did not mark it ask-user.
- **A task stopped after repeated Steer.** The lane reached its steer limit.
- **A checkpoint keeps failing.** Tighten its Work or Verification, or add an
  earlier checkpoint that produces the context it needs.
- **An agent's Model list is empty.** Wait for its engine options to load. A
  warning icon means the temporary ACP discovery session failed; verify the
  agent is installed and can connect in regular ACP chat.
- **A chosen model or mode stops the task.** The connected agent did not offer or
  apply that saved choice. Edit the lane and select an available option.
- **The spotlight remains open after Pin.** A Vibe Lanes tile already exists on
  that surface, or the board has reached its tile limit.
- **A task will not resume after restart.** Its persisted state failed validation.

## Known Limitations

- No per-task workspace isolation yet.
- The Vibe Lanes task surface does not author triggers. Recurring time triggers
  are managed through **Schedules** in Automation.
- Human verification is per-checkpoint (authored); there are no blanket
  approve-every-advance gates.
- Reviewer read-only behavior is currently policy/prompt-driven unless ACP adds a
  technical read-only trust mode.
- Reasoning controls are available only for agents that expose them; other
  agents use their own reasoning behavior.
- Step rerun is available only after a task is Done or Stopped and does not
  replay downstream checkpoints.
- Linked skill packages are not versioned or snapshotted by Crispy. Their source
  can change after a Vibe is authored.
- Skill readiness validates package structure and declared commands; it is not a
  sandbox or a guarantee that scripts and instructions are safe.
