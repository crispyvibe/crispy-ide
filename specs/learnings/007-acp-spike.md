# ACP Research Refresh: Reference Implementation Findings for CrispyVibes

**Date**: 2026-04-09
**Status**: Refreshed from implementation review
**Source of truth for this refresh**: legacy Phase 11 reference implementation in the sibling `crispyvibes-ide-2` codebase
**Reference repo on this machine**: `../crispyvibes-ide-2`

---

## 1. Summary

The original ACP spike was written as a forward-looking proposal. That proposal is now stale.

A later Phase 11 implementation exists in the legacy codebase and changes the picture materially:

- CrispyVibes did not end up with a pure ACP-only agent layer.
- The implemented design was a **unified agent session layer**:
  - native ACP sessions for ACP-compatible agents
  - direct integrations for tools that needed their own transport/runtime (`CodexSession`, `ClaudeCodeSession`)
- The UI and settings work were broader than the original spike:
  - app-wide background agent
  - per-project agent sessions
  - standalone agent sessions for content tabs/tiles
- Several planned ACP features remained incomplete even in the reference branch.

The current repository still does not contain ACP code, but future work should port the reference implementation concepts into the newer protocol-first architecture instead of following the old proposal literally.

The local reference path above is machine-specific. It should be treated as an implementation source for this workstation, not as a portable repository reference.

## 2. What Was Actually Built

### 2.1 Unified Session Abstraction

The reference implementation introduced a common session interface:

- `AgentSessionProtocol`
- `ACPSession`
- `CodexSession`
- `ClaudeCodeSession`

This is the most important architectural finding from the implementation review. The chat UI consumed one session protocol and did not care whether the backing transport was:

- ACP / JSON-RPC over stdio
- Codex app-server JSON-RPC
- Claude Code NDJSON stream

That abstraction is a better fit for CrispyVibes than a hard ACP-only assumption.

### 2.2 Session Manager Tiers

`ACPSessionManager` in the reference branch managed three distinct session tiers:

- `backgroundSession`
  - app-wide background agent for rephrase/research flows
- `projectSessions`
  - one structured agent session per project path
- `standaloneSessions`
  - independent agent sessions used by standalone agent content items

The original spike only emphasized per-project ACP sessions. The reference implementation proved that CrispyVibes also needed background and standalone session lifecycles.

### 2.3 ACP Transport and Session Lifecycle

For native ACP agents, the reference branch implemented:

- `ACPTransportProtocol`
  - testability seam used by `ACPSession`
  - allows mock transport injection in unit tests
- `JSONRPCMessage.swift`
  - JSON-RPC 2.0 request / response / notification types
  - flexible ID handling for both string and integer IDs
- `ACPTransport.swift`
  - subprocess management via `Process`
  - newline-delimited JSON-RPC over stdio
  - async request/response correlation
  - notification stream
  - server-initiated request handling
  - crash detection and stderr capture
- `ACPSession.swift`
  - `initialize`
  - `session/new`
  - `session/prompt`
  - `session/cancel`
  - `session/update` routing
  - capability parsing for available modes and models
  - `setMode(_:)` for agent mode switching

Important implementation detail: the transport preserves actor isolation for request/response state, but bridges blocking stdout reads through an internal dispatch queue inside `readLoop` to avoid actor deadlock around `availableData`.

### 2.4 Direct Integrations That Bypassed ACP

The reference branch also added:

- `CodexSession.swift`
  - `codex app-server`
  - JSON-RPC over stdio
  - mandatory `initialized` notification after `initialize` response; missing it causes `codex app-server` to hang
  - explicit `thread/start` then `turn/start` lifecycle
  - auth error detection from stderr
  - trust mode mapped into `approvalPolicy` and `sandbox`
  - server-initiated approval requests such as `item/commandExecution/requestApproval`, `item/fileRead/requestApproval`, and `item/fileChange/requestApproval`
  - token usage reporting via `thread/tokenUsage/updated`
- `ClaudeCodeSession.swift`
  - `claude --output-format stream-json --input-format stream-json --verbose`
  - `--permission-prompt-tool stdio` in non-full-trust mode
  - `--dangerously-skip-permissions` in full-trust mode
  - optional `--model` support
  - cumulative partial NDJSON messages converted into incremental deltas via `blockTextLengths: [Int: Int]`
  - NDJSON event stream mapped into `ACPUpdate`

This means the real architecture was not "ACP everywhere". It was "one structured agent UX with multiple transport adapters".

Direct-integration-specific configuration also existed in the shared session layer:

- `AgentReasoningLevel`
  - `low`, `medium`, `high`, `max`
- `AgentModelCatalog`
  - hardcoded model lists for direct integrations
  - 5 Codex model options in the reference branch
  - 4 Claude model options in the reference branch

### 2.5 Chat View Model and Timeline UX

The structured chat surface centered on `ACPChatViewModel` and a timeline model with:

- user messages
- streaming assistant messages
- thought/reasoning messages
- grouped tool calls
- plan updates

The view model accumulated streamed chunks and updated tool calls/plan entries in place.

The reference UI also included:

- inline permission cards
- inline diff rendering
- slash command autocomplete
- mode switching when the agent exposed modes
- model display when the session exposed models

The update model itself was richer than the original spike implied. The reference branch also used:

- `sessionInfoUpdate`
  - session metadata / usage reporting
- typed tool-call content and location parsing
  - `ACPDiff`
  - `ACPToolCallLocation`
  - `ACPToolCallContentParser`

### 2.6 Client Capability Handlers

The reference branch implemented three client-side handler types:

- `ACPFileSystemHandler`
  - `fs/read_text_file`
  - `fs/write_text_file`
  - project-boundary enforcement
  - optional `line` / `limit` support
- `ACPTerminalHandler`
  - `terminal/create`
  - `terminal/output`
  - `terminal/wait_for_exit`
  - `terminal/kill`
  - `terminal/release`
  - ACP terminal ID to CrispyVibes terminal tab ID mapping
  - `exitContinuations: [String: [CheckedContinuation<Int32?, Never>]]` for multi-waiter `wait_for_exit`
  - pending waiters resumed with `nil` on release to avoid continuation leaks
- `ACPPermissionHandler`
  - `session/request_permission`
  - allow / deny / allow-always options
  - diff extraction from tool-call payloads
  - per-session allow-all toggle
  - `onDiffsReceived` callback used to push parsed diffs into the existing timeline tool-call entry before approval

### 2.7 Discovery, Settings, and VibeSpace Wiring

The reference implementation added:

- `ACPAgentRegistry`
  - PATH scanning
  - built-in catalog definitions
  - custom agent definitions from preferences via `CustomACPAgent`
  - `CustomACPAgent` persisted `id`, `title`, `executable`, and `arguments` for user-defined agents
- app settings for default agent selection
  - default agent picker
  - trust mode picker
  - model picker for direct integrations
  - reasoning level picker
  - custom agent CRUD
- vibespace settings for per-project agent override
- `ACPVibeSpaceConnector`
  - auto-connect on vibespace open
  - disconnect on close
  - switch chat context when focused project changes
  - standalone store teardown on vibespace close before global session disconnect

Standalone session glue was also non-trivial and is in scope for migration analysis even if standalone surfaces are later deferred:

- `StandaloneACPSessionStore`
  - owns an independent `ACPChatViewModel`
  - creates the correct session type based on tool definition
  - installs handlers
  - manages connect / disconnect / teardown
  - `applySettingsDefaults()` support for standalone agent tabs
  - exposes `isDirectIntegration`, `availableModels`, and `tabTitle`
- `ACPAgentSetupView`
  - standalone agent/project/trust/model/reasoning configuration UI
- `ACPStandaloneContentView`
  - setup + chat wrapper for standalone agent content items

### 2.8 Test Coverage in the Reference Branch

The legacy Phase 11 branch included unit tests for:

- JSON-RPC wire types
- ACP update decoding
- ACP session connect / prompt / cancel / disconnect
- ACP session manager behavior
- file system, terminal, and permission handlers
- discovery and settings behavior
- chat view model timeline behavior

Concretely, the reference branch had 6 focused ACP test files covering those concerns. The existence of those tests makes the reference branch suitable as a migration source, not just a design inspiration.

## 3. Where The Original Spike Was Wrong or Incomplete

### 3.1 It Assumed ACP Would Replace the Agent Layer

The reference implementation showed that CrispyVibes still benefited from a transport-agnostic session abstraction. ACP was important, but not sufficient to describe the full shipped design.

### 3.2 It Assumed One Session Tier

The spike focused on per-project sessions. The implementation added:

- background structured agent session
- standalone structured sessions

Those tiers changed both settings and lifecycle requirements.

### 3.3 It Assumed Legacy Text Flows Would Disappear

The reference branch kept legacy behavior in some places and added structured routing selectively. Rephrase and research were moved toward the background structured agent flow with fallback, not deleted outright.

### 3.4 It Overstated Discovery and Ecosystem Reach

The spike implied near-automatic onboarding of any ACP-compatible agent. The implementation stayed more conservative:

- discovery started from known catalog definitions
- PATH scan confirmed availability
- custom agents could be added explicitly

That is a much more realistic product posture.

## 4. Gaps That Still Existed In The Reference Implementation

The reference branch marked several items as still incomplete or partial:

- ACP terminals were not auto-minimized in the terminal board
- ACP terminals were not excluded from terminal-only detailed view
- `terminal/output` did not read the Ghostty buffer; it mostly returned exit status metadata
- no session persistence / reload support
- no ACP authentication flow
- no MCP server passthrough
- no explorer highlighting or file-opening behavior from tool-call locations

So the correct conclusion is not "Phase 11 is fully done". It is "a substantial implementation exists, and it narrows the remaining porting/rewrite problem considerably".

## 5. Porting Implications For The Current Repository

The current repository has newer Phase 12 protocol seams that did not exist in the reference branch:

- `ProjectProviding`
- `FolderExploring`
- `TerminalProviding`
- `FileContentProviding`

That changes how ACP/agent integration should be ported.

### 5.1 Avoid Concrete ViewModel Coupling

The reference branch wired handlers directly to:

- `ProjectSession`
- `FolderExplorerViewModel`
- `TerminalViewModel`

In the current repository, the port should prefer protocol-backed adapters:

- file handlers should operate through `FileContentProviding` or a dedicated project file adapter
- terminal handlers should depend on `TerminalProviding`
- project lifecycle wiring should depend on `ProjectProviding` / `AnyProjectSession`

### 5.2 Keep The Unified Agent Session Layer

The `AgentSessionProtocol` result from the reference implementation should be preserved.

Recommendation:

- keep one structured session interface
- allow multiple transport adapters behind it
- treat ACP as one adapter, not the entire architecture
- preserve explicit testability seams such as `ACPTransportProtocol`

### 5.3 Move Ownership Out Of `ContentView`

The reference implementation owned session manager and chat state high in the app shell. The current repository should instead prefer:

- explicit dependency registration in `AppContainer`
- vibespace-scoped coordination through services/coordinators
- minimal `ContentView` state

### 5.4 Rework VibeSpace Lifecycle Integration

The old `ACPVibeSpaceConnector` assumed the legacy vibespace model. In the current repository, ACP/agent coordination should bind to:

- vibespace open / close events
- focused `AnyProjectSession`
- protocol-backed explorer and terminal providers

### 5.5 Make A Deliberate Product Decision On Direct Integrations

The current repo should explicitly decide whether to keep:

- ACP only
- ACP plus direct Codex / Claude integrations

The reference implementation strongly suggests the second option is the more practical one if structured UX parity matters across tools.

That decision also includes whether to preserve:

- `AgentReasoningLevel`
- `AgentModelCatalog`
- standalone agent content surfaces and their setup UI

## 6. Recommended Port Order

1. Port shared models and tests first.
2. Port `AgentSessionProtocol`, `ACPTransport`, `ACPSession`, and `ACPUpdate` decoding.
3. Rebuild client handlers against `ProjectProviding` / `TerminalProviding` / file-provider abstractions.
4. Reintroduce the chat timeline UI and settings wiring.
5. Only then decide whether to bring over `CodexSession` and `ClaudeCodeSession`.

## 7. Updated Recommendation

**GO, but not by following the old spike literally.**

The correct next-step design for this repository is:

- use the legacy Phase 11 implementation as migration reference
- preserve the unified structured agent session abstraction
- port native ACP support
- adapt all host integration points to the current protocol-first architecture
- treat unfinished reference features as an explicit backlog, not as hidden assumptions
