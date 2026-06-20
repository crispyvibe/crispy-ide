# ADR-003: Centralized Content Surface Presentation

Status: accepted
Date: 2026-06-19
Deciders: Crispy Team

## Context

When the user opens something in a vibespace — a new agent chat, an existing
conversation thread, todos, VibeCast, a file, a terminal — the app must decide
*where* it appears. The vibespace has two layout modes (`VibeSpaceCanvasMode`:
`.detailed`, `.terminalOnly`) but content can land on four surfaces: a detail
**tab**, a board **tile**, a floating **docked preview**, or a **spotlight**
overlay.

That decision was re-derived independently at every "open X" entry point
(toolbar actions, the unified sidebar actions, the file-open use case), each
with its own copy of `if selectedCanvasMode == .terminalOnly { … } else { … }`
plus direct `layoutPersistence.setCanvasMode(.detailed, …)` / `.addACPTileToBoard`
calls. The copies drifted:

- New Agent Chat from the sidebar always forced `.detailed`, ignoring board mode.
- Todos/VibeCast opened a tab without switching modes, so in board mode the tab
  landed on a surface the board view doesn't show (silently lost).
- "Open Agent Conversation" forced `.detailed` instead of adding a board tile.

These were not separate bugs; they were one missing abstraction surfacing
repeatedly. Patching individual call sites kept regressing.

## Decision

Introduce a single decision authority and a single dispatch entry point.

- **`ContentKind`** — payload-free decision vocabulary (`agentChat`,
  `conversationThread`, `todos`, `vibeCast`, `terminal(preferTemporary:)`,
  `file`).
- **`ContentSurface`** — the four real surfaces (`detailTab`, `boardTile`,
  `dockedPreview`, `spotlight`), decoupled from the two-case layout mode.
- **`ContentSurfacePolicy.surface(for:mode:)`** — the single, pure, unit-tested
  function mapping `ContentKind × VibeSpaceCanvasMode → ContentSurface`.
- **`VibeSpaceCanvasActionsCoordinator.present(_:)`** — the single dispatch for
  the tab/tile/preview cases (`PresentableContent`). It consults the policy,
  switches/keeps the layout, and routes.

(All in `Features/VibeSpace/Canvas/Support/ContentPresentation.swift` +
`VibeSpaceCanvasActionsCoordinator`.)

Rules:

- Entry points say *what* to surface (`present(.agentChat(...))`), never *where*.
- Flows with bespoke creation (terminal, file open) keep their own dispatch but
  derive the decision from `ContentSurfacePolicy.surface(for:mode:)` — they do
  not branch on canvas mode themselves.
- `layoutPersistence.setCanvasMode` is called directly only for an explicit user
  view-mode switch (the Detailed/Board toggle), never as a side effect of
  surfacing content. Its doc comment states this.
- `.addACPTileToBoard` is posted only from `present(_:)`.

## Consequences

- The canvas-mode → surface decision lives in exactly one place; adding a
  content type is a `ContentKind` case + a policy row + a test, not a codebase
  sweep.
- The policy is synchronously unit-tested (`ContentSurfacePolicyTests`) with no
  view or payload setup, covering every kind × mode.
- Three latent bugs are fixed by construction (todos/VibeCast no longer lost in
  board mode; agent flows are view-aware everywhere).
- Enforcement is by convention + the policy + the `setCanvasMode` doc guardrail,
  not by access control: `setCanvasMode` has a legitimate non-surfacing caller
  (the explicit view-mode toggle), so it cannot be made private.
- Web-page opening is intentionally out of scope: it does not branch on canvas
  mode (always a detail tab; the board browser preview is a separate mechanism).
