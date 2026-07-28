# Stop Managing Agents. Start Designing Expectations.

AI agents are becoming capable enough to write code, investigate incidents,  
prepare releases, and carry work across a project. But capability is not the  
same as reliability.

Most agent workflows still begin with a large prompt and end when the agent  
says it is done. The difficult questions are left implicit:

-   What outcome should actually exist?
-   How will we verify it?
-   How long should the agent keep trying?
-   What should happen when it gets stuck?
-   What context must move to the next stage?
-   Can the same definition be reused without copying it everywhere?

We have been exploring a model in Crispy that makes those questions first-class  
objects. We call the model **Vibes, Vibe Lanes, and Schedules**.

```text
Vibe (Loop) -> Vibe Lane (Spiral) -> Schedule

bounded feedback -> accumulating progress -> recurring application
```

The central idea is simple:

> Do not manage the agent's conversation. Define the outcome, the proof, and  
> the boundaries of the work.

## The Atomic Unit: An Expectation Construct

The smallest unit in this model is an **Expectation Construct**. In the product,  
we call it a **Vibe**.

A Vibe contains three essential parts:

1.  **Work** - what the agent must produce.
2.  **Verification** - what must be true before the work is accepted.
3.  **Bounds** - how much time and how many attempts are allowed.

That Work -> Verification -> Feedback cycle is why the explanatory model calls
a Vibe a **Loop**. It retries one expectation until it passes or reaches its
authored bounds.

For example, "Implement the feature" is not a strong expectation. It describes  
an activity, but not a trustworthy stopping point.

A better Vibe might say:

```text
Work
Implement the requested behavior with focused tests.

Verification
The new tests pass, the relevant regression suite passes, and the implementation
matches the accepted behavior without unrelated changes.

Bounds
Up to 5 attempts or 30 minutes. Ask for steering if exhausted.
```

Skills can support both sides without turning verification into a hardcoded type.
A Vibe may give the worker **Work skills** for producing the outcome and give the
independent reviewer **Review skills** for checking it. A reusable code-review or
security-review skill is a procedure the reviewer can follow; the pass criteria
still define the bar.

This changes the unit of progress. Progress is no longer "the agent responded."  
Progress is "the authored expectation passed its verification."

## Why Vibes Are Independent Entities

An expectation becomes more valuable when it can be reused.

"Reproduce the bug," "Review the public API," and "Verify the release" should  
not need to be rewritten inside every workflow. They should live in a central  
library, carry a category, and evolve as versioned entities.

That also solves a common naming problem. Two Vibes may both be called  
"Verify," but one may belong to Incident Response while another belongs to  
Release. The name is familiar; the category and definition provide the  
necessary context.

When a Vibe changes, existing workflows do not silently change with it. They  
continue using the version they selected until an author explicitly adopts the  
new one. Reuse should reduce duplication without introducing invisible  
behavior changes.

## A Vibe Lane Is a Progressive Spiral

A single expectation is useful, but meaningful work usually requires a  
sequence.

A **Vibe Lane** is an ordered, repeatable recipe made from Vibe loops. It forms
a **Spiral** because each verified handoff carries richer evidence, decisions,
and context into the next stage.

The spiral moves forward; it does not imply that execution jumps backward
between stages. Each Vibe owns its own bounded retry loop, while the Vibe Lane
owns the accumulating progression across those loops.

Think about a restaurant kiosk. The restaurant defines reusable items and  
options centrally. A customer assembles a meal by choosing and ordering those  
items. The kiosk does not create a new copy of "grilled vegetables" every time  
someone adds it to a meal. It references the known item and records the  
selection.

The Vibe Lane designer follows the same idea:

-   browse a categorized library of reusable Vibes;
-   add Vibes to a recipe;
-   arrange them in the required order;
-   define what each step receives and passes forward;
-   explicitly adopt newer Vibe versions when appropriate.

A bug-fix Vibe Lane might look like this:

```text
Reproduce -> Patch -> Verify -> Summarize
```

Each step is independently bounded and verified. Passing one step produces a  
handoff for the next. A failed verification sends concrete feedback back to  
the worker instead of advancing on confidence alone.

The Vibe owns the reusable expectation. The Vibe Lane owns ordering and  
handoffs.

That distinction matters. "Verify" should mean the same thing wherever it is  
used, while the input it receives may differ between a bug fix, a release, and  
an incident response process.

## Verification Is Separate From Work

Agent systems become fragile when the same process both performs the work and  
decides that the work is correct.

In a Vibe Lane, a worker performs the Work and a reviewer evaluates the actual  
outcome against the authored Verification.

```text
            feedback
               |
               v
Work attempt -> Verify -> PASS -> Handoff
                  |
                  +---- FAIL -> next bounded attempt
```

The reviewer can inspect files, run checks, and evaluate evidence. It does not  
invent the completion criteria after seeing the result. The criteria were part  
of the Vibe before execution began. Review skills can tell it how to perform a
specialized review, but those skills are not sent to the worker and cannot change
what passing means.

This creates a useful separation:

-   the worker optimizes for producing the outcome;
-   the reviewer optimizes for testing the outcome;
-   the author controls what "done" means.

## Handoffs Make Multi-Stage Work Durable

Long agent conversations are a weak place to store workflow state. Sessions  
end, context windows change, applications restart, and later stages should not  
need to replay every earlier message.

Vibe Lanes use explicit handoffs and named inputs and outputs.

After a step passes, its result can be written to a durable handoff file and its  
declared outputs carried forward. The next step receives references to that  
evidence and reads it when needed.

This keeps context where it belongs:

-   project state lives in project files;
-   decisions and evidence live in handoffs;
-   small structured values live in named outputs;
-   the engine coordinates progress instead of pretending to be memory.

## Humans Enter at Defined Moments

Autonomy should not mean that a system keeps improvising forever.

A Vibe can stop when its bounds are exhausted or escalate to a person for  
steering. A Vibe Lane can also pause when it needs a missing user-supplied input  
or a human review.

The product presents these moments as **Needs you**:

-   **Supply** - provide a required input.
-   **Steer** - give guidance after bounded attempts are exhausted.
-   **Review** - approve the outcome or request changes with feedback.

Human involvement becomes an authored part of the process, not an emergency  
hidden in a chat transcript.

## A Schedule Applies the Recipe

A Vibe is an expectation. A Vibe Lane is a recipe. A **Schedule** applies that  
recipe to a real project and cadence.

Conceptually:

```text
Schedule = Vibe Lane + project + task instruction + schedule
```

For example:

```text
Vibe Lane: Dependency maintenance
Project:    payments-service
Task:       Review and update outdated dependencies
Schedule:   Every Monday at 9:00 AM
```

A Schedule does not create a second execution engine. When it is due, it starts a  
normal Vibe Lane task using the version approved when the Schedule was saved.

That frozen snapshot is important. If someone edits the source Vibe Lane on  
Tuesday, Friday's scheduled work should not change silently. The Schedule can show  
that an update exists, but adopting it remains an explicit decision.

The same principle applies throughout the chain:

```text
Vibe update
    -> explicitly adopted by a Vibe Lane
        -> explicitly adopted by a Schedule
```

This gives reusable automation a comprehensible change model.

## What This Model Changes

Prompts are still part of agent execution, but they are no longer the primary  
architecture.

The architecture becomes:

-   reusable expectations instead of copied prompt fragments;
-   independently verified stages instead of one large self-reported task;
-   explicit bounds instead of unbounded retries;
-   durable handoffs instead of chat-history dependence;
-   versioned recipes instead of silently changing workflows;
-   scheduled applications instead of duplicated automation logic.

The user experience changes too. Authors work with a library and a recipe  
designer, much like configuring a kiosk or assembling a pipeline. Operators see  
where work is, what passed, what failed, and when a person is needed.

## The Bigger Idea

The future of agentic software will not be defined only by better models. It  
will also be defined by better structures around those models.

Agents need clear expectations, independent checks, bounded retries, durable  
state, and explicit change control. Those are not restrictions on autonomy.  
They are what make autonomy understandable and reusable.

That is the purpose of this model:

> A Vibe defines what good looks like.  
> A Vibe (Loop) retries against that expectation within bounds.  
> A Vibe Lane (Spiral) carries verified progress forward.  
> A Schedule applies that recipe to real work over time.

We are still refining the language and experience, but the direction feels  
clear: stop treating every agent task as a new conversation, and start treating  
reliable work as something we can design.
