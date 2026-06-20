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
  `file`, `spotlightPin`).
- **`ContentSurface`** — the four real surfaces (`detailTab`, `boardTile`,
  `dockedPreview`, `spotlight`), decoupled from the two-case layout mode.
- **`ContentSurfacePolicy.surface(for:mode:)`** — the single, pure, unit-tested
  function mapping `ContentKind × VibeSpaceCanvasMode → ContentSurface`.
- **`VibeSpaceCanvasActionsCoordinator.present(_:)`** — the single dispatch for
  the `detailTab` / `boardTile` / `dockedPreview` cases (`PresentableContent`:
  agent chat, conversation thread, todos, VibeCast). It consults the policy,
  switches to / keeps the layout, and routes. A surface the policy never
  produces for a given payload hits an `assertionFailure` fallback that still
  lands a detail tab in production — so a future policy change that breaks the
  invariant is caught loudly without dropping the action.

(All in `Features/VibeSpace/Canvas/Support/ContentPresentation.swift` +
`VibeSpaceCanvasActionsCoordinator`.)

The policy table (board mode = `.terminalOnly`):

| Kind | `.detailed` | `.terminalOnly` (board) |
|------|-------------|-------------------------|
| `agentChat` | detail tab | board tile |
| `conversationThread`, `file` | detail tab | docked preview |
| `todos`, `vibeCast` | detail tab | spotlight |
| `terminal(preferTemporary: true)` | spotlight | spotlight |
| `terminal(preferTemporary: false)` | spotlight | board tile |
| `spotlightPin` | detail tab | board tile |

Rules:

- Entry points say *what* to surface (`present(.agentChat(...))`), never *where*.
- Flows with bespoke creation (terminal, file open) keep their own dispatch but
  derive the decision from `ContentSurfacePolicy.surface(for:mode:)` — they do
  not branch on canvas mode themselves.
- The **`spotlight`** surface is dispatched outside `present(_:)`: `present(_:)`
  owns the tab/tile/preview surfaces, while the `.toggleTodos` / `.toggleVibeCast`
  handlers in `ContentView` consult the policy and, in board mode, call
  `presentTodosSpotlight()` / `presentVibeCastSpotlight()` (the terminal spotlight
  overlay), falling through to `present(_:)` for the detail tab in detailed mode.
  Todos is now a full spotlight citizen (`TerminalSpotlightState.Source.todos`).
  Terminal owns its own spotlight dispatch.
- A git diff has no board surface: `openSourceControlDiff` asks the policy for
  `.file` and, when that yields `.dockedPreview` (board mode), shows the changed
  file in the docked preview instead of yanking the layout to `.detailed`;
  otherwise it opens the diff in a detail tab. File-open (`VibeSpaceCanvasFileOpenUseCase`)
  routes the same way through the policy.
- Pinning a spotlight preview (`spotlightPin`) resolves to a `boardTile` in board
  mode ("Pin to Dock") or a `detailTab` in detailed mode ("Open in Viewer"); the
  pin UI derives that from the policy rather than branching on mode.
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
- Three latent bugs are fixed by construction (todos/VibeCast float as a
  spotlight over the board instead of being silently lost; git diff shows a
  docked preview rather than forcing detailed; agent flows are view-aware
  everywhere).
- Enforcement is by convention + the policy + the `setCanvasMode` doc guardrail,
  not by access control: `setCanvasMode` has a legitimate non-surfacing caller
  (the explicit view-mode toggle), so it cannot be made private.
- Web-page opening is intentionally out of scope: it does not branch on canvas
  mode (always a detail tab; the board browser preview is a separate mechanism).
