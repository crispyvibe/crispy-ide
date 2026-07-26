# Archived Vision Draft: Loops Are One Dimension Short

> This is historical background, not current product terminology. The current
> model is **Vibe (Loop) -> Vibe Lane (Spiral) -> Schedule**: a Vibe retries one
> expectation, a Vibe Lane carries verified progress forward, and a Schedule
> repeats the lane over time. See the repository-root `blog.md` and the
> canonical F059/F061 specs for current language.

You already know what prompts and retry loops are. This piece is about giving
those loops a bar, a direction, and a reusable place in a larger process.

Remember only this:

-   Prompts express intent.
-   Vibes create bounded feedback loops.
-   Vibe Lanes create forward progression.
-   Schedules create recurrence.

Direction comes first. As leaders, builders, and operators, we usually begin directionally correct. We know the outcome we want. We know the kind of progress that should count. Then we create processes around that direction. Over time, those processes become flywheels.

> A Vibe loops. A Vibe Lane spirals. A Schedule repeats.

Systems thinking starts with the structure that produces behavior. Vibe Lanes
apply that idea to agent work: define the expectations, connect the Vibe loops,
and let verified work compound through the Spiral.

Vibe loops are powerful because they let one expectation retry until its
verification passes or its bounds are exhausted. A coding Vibe can patch a
file, run a test, read the failure, and patch again. A writing Vibe can draft,
critique, and revise. Schedules handle a different concern: starting a new Vibe
Lane task every day, every hour, or whenever its supported recurrence is due.

Recurrence creates motion; process turns direction into compounding progress.

Before asking an agent to run, define the process around the direction. Define what should exist, how it will be judged, where it goes after it passes, and when the attempt should stop. That is the role of an Expectation Construct.

> A prompt says, “do this.” A Vibe says, “produce this and prove it.” A Vibe
> Lane carries the proof forward. A Schedule starts the recipe again over time.

## Real Work Moves Through Expectations

A healthcare workflow makes this obvious. Imagine a patient-facing discharge instruction update for a hospital system. The work is more than “write the instructions.” It sits inside a regulated operating model: clinical ownership, HIPAA minimum-necessary handling, PHI boundaries, health-literacy requirements, accessibility obligations, change control, audit trail, and publication governance.

```text
Clinical Intent
  Work: define clinical owner, patient population, care setting, and intended outcome
  Proof: contraindications, escalation guidance, and out-of-scope cases are named
  Carry-forward: clinical safety boundary

        ↓

PHI Boundary
  Work: classify data needs under HIPAA minimum-necessary principles
  Proof: PHI usage, logging, retention, and model/tool exposure are explicitly bounded
  Carry-forward: approved privacy and data-handling constraints

        ↓

Patient Content
  Work: draft instructions for the patient or caregiver
  Proof: content matches clinical guidance, avoids diagnosis drift, and uses plain language
  Carry-forward: clinically reviewed patient-facing artifact

        ↓

Accessibility & Language
  Work: adapt for WCAG/Section 508-style access and language needs
  Proof: reading level, screen-reader flow, contrast, translations, and interpreter notes pass
  Carry-forward: content the intended patient population can understand and use

        ↓

Governance
  Work: prepare approval packet and change-control record
  Proof: clinical sign-off, privacy review, accessibility review, owner, rationale, and effective date are recorded
  Carry-forward: approval for governed release

        ↓

Publish
  Work: release the approved artifact
  Proof: version, owner, effective date, distribution surface, rollback path, and monitoring plan are documented
  Carry-forward: live, traceable artifact ready for monitoring
```

Each point carries its own expectation, and the carry-forward from one becomes
the ground the next stands on. Each Vibe loops until its expectation clears the
bar or reaches its bounds. The Vibe Lane supplies the next place to go and
accumulates what was learned.

## Start With Expectation Constructs

An Expectation Construct is the smallest useful unit of agent process design. It has three parts: work, verification, and bounds.

Work defines what should exist after the attempt. Verification defines how the result will be judged. Bounds define how long, or how many times, the agent should try before the process stops and asks for a different kind of intervention.

Notice what a construct does *not* hold: the task itself. It carries the reusable expectation — the work, its bar, its limits — not the specific instruction. The instruction ("fix this flaky test," "draft that launch post") is what you run *through* the construct. That separation is why one construct, and one lane, serves every task.

```text
Expectation Construct

Work ──▶ Verify ── pass ──▶ Carry-forward
  ▲        │
  │        fail
  └──── feedback
```

This keeps freedom and discipline in separate places. The worker gets freedom inside the attempt. The reviewer holds the expectation. The bounds keep the loop honest.

## Then Form a Vibe Lane

A Vibe Lane is what you get when you put Expectation Constructs in order.

```text
Expectation Construct → Expectation Construct → Expectation Construct → Outcome
          ↺                         ↺                         ↺
```

The lane forms a Spiral across Vibes. It says where the work starts, what it
must satisfy along the way, what context moves forward, and what complete looks
like. The task can be new every time; the lane stays reusable. The healthcare
discharge-content lane above is one shape of this, and the form generalizes. A
bug-fix lane might move from reproduce to patch, then verify and summarize.

```text
Reproduce → Patch → Verify → Summarize
```

A writing lane might move from research to draft, then claims check, edit, and publish.

```text
Research → Draft → Check Claims → Edit → Publish
```

> Design the expectations first. Then compose the lane from them.

## Discovery Belongs Inside the Lane

Everything useful will rarely be known at the beginning. That is fine. A lane starts with the expectations you can name. The journey discovers the rest.

The first checkpoint may reveal a constraint. Verification may expose a better test. A handoff may carry context nobody knew to ask for in the original prompt. The next checkpoint starts with that discovery and turns it into better work.

This is why a lane should guide the path rather than freeze the answer. Starting on the right path and following the process are what let the discoveries along the lane make the final outcome specific, grounded, and unique.

## Verification Deserves Its Own Seat

Agents are good at sounding done. Real completion needs evidence.

In a Vibe Lane, the worker and reviewer are separate roles. The worker creates the artifact. The reviewer checks the artifact against the expectation.

For code, the reviewer can inspect the diff, run tests, and return concrete feedback. For writing, the reviewer can check claims, audience fit, structure, and clarity. For research, the reviewer can challenge sources and gaps. For healthcare content, the reviewer can check clinical safety, privacy boundaries, accessibility evidence, and governance documentation.

Passing means the expectation has been met. Failing means the next attempt gets sharper feedback.

> Freedom inside the attempt. Discipline at the expectation. Direction across the lane.

## Handoffs Make Progress Durable

When a checkpoint passes, the worker writes a handoff summary. In a regulated workflow, that handoff may be better understood as carry-forward context: the approved constraints, evidence, decisions, and boundaries that the next checkpoint must inherit.

The handoff says what changed, what matters, and what the next checkpoint
should carry forward. It gives the next Vibe context without letting the
previous Vibe rewrite the next expectation.

That keeps the lane stable while the task learns. The process remembers the journey. The next checkpoint starts smarter than the first one did.

## The Work Should Be Visible

Once agent work becomes a lane, the interface can change too. The primary object becomes the task, with a visible path through expectations.

```text
Running
• Draft launch post        Check Claims
• Fix sidebar flicker      Verify Patch
• Add export flow          Polish Summary

Done
• Update sample docs       Published

Stopped
• Refactor loader          Attempts exhausted
```

You can still open the worker and reviewer chats. The difference is that the chats sit under the task. The task shows where the work is, what it passed, what it is trying now, and why it stopped.

> Manage the flow, not the conversation.

## Reference Implementation

The first reference implementation is in Crispy, my native macOS terminal-first workspace IDE. This branch adds Vibe Lanes as a native surface.

It includes a lane catalog and editor for authoring reusable checkpoint pipelines, a task dashboard for launching and watching work move through lanes, a task detail view with checkpoint history and verification output, and a headless engine that drives worker and reviewer ACP sessions. It also persists lane definitions, task state, checkpoint runs, handoffs, and logs, with bounds so tasks can stop cleanly when they run out of attempts or time.

The implementation stays intentionally small: Work, Verification, Bounds. Expectation Constructs first, Vibe Lanes second.

## The Bigger Idea

The future of agentic work looks like visible tasks moving through reusable
expectations. Prompts express intent. Vibes define the outcome and proof, then
loop within bounds. Vibe Lanes turn those Vibes into a forward-moving Spiral.
Schedules repeat the approved lane over time.

Give the work a path, give each point a bar, and let discovery make the outcome better than the starting prompt.
