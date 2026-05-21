# Agent Conversation Protocol (ACP) — Spec

Status: draft

## Overview

ACP provides the protocol and UI layer for discovering, connecting to, and conversing with AI agents inside Crispy. It supports three agent session types: ACPSession (generic ACP JSON-RPC over stdio), ClaudeCodeSession (direct stream-json), and CodexSession (direct app-server JSON-RPC). The feature covers agent discovery, session lifecycle, transport, chat UI with streaming, message rendering, tool call visualization, permission handling, compose bar, conversation management, standalone panes, board tiles, settings, and observability.

## Dependencies

- F001 (Terminal Sessions & Tabs) — ACP terminal handlers create and manage terminal tabs
- F002 (Terminal Board) — ACP tiles live on the terminal board
- F003 (Terminal Spotlight) — ACP tiles participate in spotlight carousel
- F006 (Content Viewer) — standalone ACP pane hosted in detailed content viewer
- F028 (VibeCast) — shares vibespace context and terminal provider

## Requirements

### F011-R01: Agent Discovery

The agent registry MUST discover agents from CLIToolCatalog (supportsACP) and user-defined custom entries. Agents whose executable cannot be resolved MUST be marked unavailable.

### F011-R02: Session Lifecycle

Session manager MUST support project, background, and standalone session types. Connecting a new session for the same key MUST disconnect the previous one. Disconnect MUST clean up all pending continuations and terminate the transport process.

### F011-R03: ACP Transport Protocol

ACP transport MUST use JSON-RPC 2.0 over stdio. Requests MUST time out. Incoming agent requests MUST be routed to registered handlers; unrecognized methods MUST return method-not-found.

### F011-R04: Direct Integration Transport

Claude Code sessions MUST communicate via stream-json transport. Codex sessions MUST communicate via app-server JSON-RPC transport. Both MUST support the same session lifecycle semantics as ACP sessions.

### F011-R05: Initialize Handshake

ACP sessions MUST perform an initialize handshake exchanging protocol version and client capabilities before any session operations.

### F011-R06: Authentication

ACP sessions MUST support agent-initiated authentication challenges during the initialize handshake. `[planned]`

### F011-R07: Session Operations

ACP sessions MUST support session/new, session/load, and session/resume for creating and restoring conversations. session/list, session/delete, and session/fork MUST be supported for conversation management. `[planned: list, delete, fork]`

### F011-R08: Prompt Operations

All session types MUST support sending prompts, cancelling in-progress prompts, and receiving streamed updates. ACP sessions MUST additionally support session/set_mode and session/set_model.

### F011-R09: Message Rendering

The chat timeline MUST render user messages, assistant messages, thought blocks, tool calls, plans, and diffs in distinct visual styles. Code blocks MUST be syntax-highlighted. All messages MUST support copy actions.

### F011-R09a: Turn-Based Timeline Grouping

Within a single prompt turn, the timeline MUST group related entries: thinking (collapsed by default), tool call work log (collapsed by default with count badge), assistant response text, and a changed files summary. Entries within a turn MUST NOT be interleaved with entries from other turns.

### F011-R09b: Changed Files Summary

File changes produced during a turn MUST be summarized after the assistant response as a collapsible changed files tree with per-file addition/deletion counts. Users MUST be able to expand individual files to view inline diffs.

### F011-R09c: Git-Based Turn Checkpointing

Before each agent turn begins, the system MUST capture a git checkpoint of the project working tree. After the turn completes, the system MUST compute a diff between the pre-turn and post-turn checkpoints. This ensures all file changes are captured regardless of how the agent made them (file writes, terminal commands, or external tools).

### F011-R10: Streaming UI

The UI MUST show streaming state with a cancel affordance during prompt execution. Tool operations MUST show progress indication. All streaming entries MUST be marked complete with a timestamp on finish.

### F011-R11: Tool Call Visualization

Tool calls MUST render as cards with title, kind, and content. File changes MUST render as diffs with a changed-files summary. Terminal tool calls MUST show embedded output.

### F011-R12: Permission Handling

Standard trust MUST require per-action user approval via permission cards. Full trust MUST auto-approve all requests. Allow-always MUST escalate to auto-approve for the session. Permission cards MUST show inline diff previews for file changes.

### F011-R13: Compose Bar

The compose bar MUST support text input with send action, slash command suggestions, and model/mode selection. File attachment and @mention MUST be supported.

### F011-R13a: Compose Bar Inline Insert Trigger

ACP compose inputs MUST support the inline insert trigger behavior defined in F038 (Terminal Inline Triggers). The ACP project context MUST be used as the originating context. When ACP is hosted in a board tile, the picker MUST use the board-scoped popup presentation per F038-R07.

### F011-R14: Conversation Management

Conversations MUST persist to local store. Users MUST be able to list, search, create, and resume conversations. Context window usage MUST be visible.

### F011-R15: Setup Experience

The setup strip MUST provide agent picker, connection status with structured errors, and onboarding for first-time users.

### F011-R16: Standalone Pane

Standalone pane MUST provide agent, project, and model pickers. Trust mode and reasoning level pickers MUST appear for direct-integration agents. Pane state MUST persist and restore across sessions.

### F011-R17: Board Tile

ACP tiles MUST be addable to the terminal board, render chat and session controls, and participate in spotlight carousel navigation.

### F011-R18: Settings

ACP settings MUST allow configuring default agent, trust mode, model, and reasoning level. Custom agent registration and per-project agent overrides MUST be supported.

### F011-R19: File System Sandboxing

File system handlers MUST resolve paths relative to the project root. Paths outside the project boundary MUST be rejected.

### F011-R20: Terminal Handlers

Agent terminal requests MUST create tabs, read output, wait for exit, kill, and release terminal mappings.

### F011-R21: Observability

ACP sessions MUST emit structured observability events with category, duration, and metadata for lifecycle and turn events.

### F011-R22: Model Selection

Sessions MUST negotiate available models from the agent. Users MUST be able to switch models mid-session. Direct-integration agents MUST use a static model catalog.

### F011-R23: Reasoning Level

Reasoning level MUST be configurable for direct-integration agents and persist across pane restores.

## Scenarios

### Protocol Layer

#### Scenario F011-S01: Installed ACP agents are discovered from catalog and custom entries `[all]`

**Given** the ACP agent registry is queried
**When** discovery runs
**Then** agents from CLIToolCatalog with supportsACP are included alongside custom agents defined in user preferences
**And** each agent resolves its executable path via PATH or absolute path lookup
**And** agents whose executable cannot be resolved are marked unavailable

#### Scenario F011-S02: Custom ACP agents can be registered in settings `[all]`

**Given** the user opens Settings > ACP
**When** the user adds a custom agent with title, executable, and arguments
**Then** the agent appears in the discovered agents list and is available for selection in standalone panes and board tiles

#### Scenario F011-S03: ACP session connects to an agent for a project `[acp]`

**Given** a project is focused and an ACP agent is selected
**When** the session manager creates and connects a session
**Then** the transport spawns the agent executable via stdio
**And** an initialize handshake exchanges protocol version and client capabilities
**And** a session/new request establishes a session scoped to the project working directory
**And** the session transitions to connected state

#### Scenario F011-S04: Direct integration session connects via native transport `[direct]`

**Given** a project is focused and a direct-integration agent (Claude Code or Codex) is selected
**When** the session manager creates and connects a session
**Then** the transport uses stream-json (Claude Code) or app-server JSON-RPC (Codex)
**And** the session transitions to connected state with the agent's native handshake

#### Scenario F011-S05: Session manager supports project, background, and standalone sessions `[all]`

**Given** the session manager is active
**When** sessions are requested for different contexts
**Then** project sessions are keyed by project identifier, background sessions operate on an arbitrary working directory, and standalone sessions are keyed by UUID
**And** connecting a new session for the same key disconnects the previous one

#### Scenario F011-S06: Session disconnects and cleans up on teardown `[all]`

**Given** a session is connected
**When** disconnect is called or the agent process terminates
**Then** pending prompt continuations are finished
**And** pending terminal exit waits are released
**And** the transport process is terminated
**And** the session transitions to disconnected state

#### Scenario F011-S07: Session manager disconnects all sessions on vibespace close `[all]`

**Given** multiple sessions are active
**When** disconnectAll is called
**Then** all project, background, and standalone sessions are disconnected and cleaned up

#### Scenario F011-S08: ACP transport communicates via JSON-RPC over stdio `[acp]`

**Given** an ACP transport is started with an executable and arguments
**When** messages are exchanged
**Then** outbound requests and notifications are JSON-RPC 2.0 encoded to stdin
**And** inbound responses, notifications, and requests are read line-by-line from stdout
**And** stderr output is captured for diagnostics

#### Scenario F011-S09: Transport handles request timeouts `[acp]`

**Given** a JSON-RPC request is sent to the agent
**When** no response arrives within the configured timeout
**Then** the pending request fails with a requestTimedOut error and the timeout task is cleaned up

#### Scenario F011-S10: Transport routes incoming agent requests to registered handlers `[acp]`

**Given** the transport receives a JSON-RPC request from the agent
**When** the request method matches a registered handler
**Then** the handler is invoked and the result is sent back as a JSON-RPC response
**And** unrecognized methods return a method-not-found error

#### Scenario F011-S11: Initialize handshake exchanges capabilities `[acp]`

**Given** an ACP transport connection is established
**When** the client sends the initialize request
**Then** the agent responds with its protocol version, supported methods, and capabilities
**And** the client validates compatibility before proceeding to session operations

#### Scenario F011-S12: Agent-initiated authentication during handshake `[acp]`

**Given** an ACP agent requires authentication
**When** the agent sends an authentication challenge during initialize
**Then** the client presents credentials or prompts the user
**And** the handshake completes only after successful authentication

#### Scenario F011-S13: Session is created with session/new `[acp]`

**Given** an ACP session has completed the initialize handshake
**When** a session/new request is sent with the project working directory
**Then** the agent creates a new conversation context
**And** the response includes session ID, available models, and current model

#### Scenario F011-S14: Session is loaded from agent history with session/load `[acp]`

**Given** an ACP session is connected and a previous session ID is known
**When** a session/load request is sent with the session ID
**Then** the agent restores the conversation context and returns the session state

#### Scenario F011-S15: Session is resumed with session/resume `[acp]`

**Given** an ACP session was previously disconnected
**When** a session/resume request is sent
**Then** the agent resumes the most recent session for the working directory

#### Scenario F011-S16: Session list returns available sessions `[acp]` `[planned]`

**Given** an ACP session is connected
**When** a session/list request is sent
**Then** the agent returns a list of available sessions with IDs, titles, and timestamps

#### Scenario F011-S17: Session is deleted `[acp]` `[planned]`

**Given** an ACP session is connected and a session ID is specified
**When** a session/delete request is sent
**Then** the agent removes the session from its history

#### Scenario F011-S18: Session is forked from an existing conversation `[acp]` `[planned]`

**Given** an ACP session is connected with an active conversation
**When** a session/fork request is sent
**Then** the agent creates a new session branching from the current conversation state
**And** the new session ID is returned

#### Scenario F011-S19: User sends a prompt and receives streamed responses `[all]`

**Given** a session is connected and the compose bar is visible
**When** the user types a message and sends it
**Then** the message appears as a user entry in the timeline
**And** the session sends a prompt request and assistant message chunks are streamed into the timeline in real time

#### Scenario F011-S20: User cancels an in-progress prompt `[all]`

**Given** a prompt is streaming
**When** the user clicks Cancel
**Then** a cancel request is sent to the agent, the prompt task is cancelled, and isStreaming transitions to false

#### Scenario F011-S21: Session mode is changed mid-conversation `[acp]`

**Given** an ACP session is connected
**When** a session/set_mode request is sent with a new mode
**Then** the agent acknowledges the mode change and subsequent interactions use the new mode

#### Scenario F011-S22: Session model is changed mid-conversation `[acp]`

**Given** an ACP session is connected with multiple available models
**When** a session/set_model request is sent with a new model ID
**Then** the agent switches to the specified model and the session updates its currentModelId

#### Scenario F011-S23: File system read requests are sandboxed to project root `[all]`

**Given** a session is connected for a project
**When** the agent sends a file read request
**Then** the handler resolves the path relative to the project root
**And** paths outside the project boundary are rejected with an outsideProjectBoundary error

#### Scenario F011-S24: File system write requests are sandboxed to project root `[all]`

**Given** a session is connected for a project
**When** the agent sends a file write request
**Then** the handler resolves the path relative to the project root and writes the content
**And** paths outside the project boundary are rejected with an outsideProjectBoundary error

#### Scenario F011-S25: Agent terminal create request opens a terminal tab `[all]`

**Given** a session is connected with a terminal provider
**When** the agent sends a terminal/create request with a command
**Then** a new terminal tab is created with the specified command and working directory
**And** a terminal mapping is stored for subsequent operations

#### Scenario F011-S26: Agent terminal wait_for_exit blocks until process exits `[all]`

**Given** a terminal tab was created by an agent request
**When** the agent sends terminal/wait_for_exit
**Then** the handler blocks until the terminal process exits and returns the exit code and output

#### Scenario F011-S27: Agent terminal kill sends interrupt signal `[all]`

**Given** a terminal tab was created by an agent request
**When** the agent sends terminal/kill
**Then** an interrupt signal is sent to the terminal process

#### Scenario F011-S28: Agent terminal release cleans up mapping `[all]`

**Given** a terminal tab was created by an agent request
**When** the agent sends terminal/release
**Then** the terminal mapping is removed and resources are freed

#### Scenario F011-S29: Standard trust mode requires per-action permission approval `[all]`

**Given** a session is connected with standard trust mode
**When** the agent requests permission for a tool call
**Then** a permission card is shown with the tool call title and available options
**And** the user must explicitly allow or deny the action before the agent proceeds

#### Scenario F011-S30: Full trust mode auto-approves agent permission requests `[all]`

**Given** a session is connected with full trust mode
**When** the agent requests permission
**Then** the request is automatically resolved with the first allow option and no permission card is shown

#### Scenario F011-S31: Allow-always escalates to auto-approve for the session `[all]`

**Given** a permission request offers an allow_always option
**When** the user selects that option
**Then** allowAll is set to true on the permission handler and subsequent requests are auto-approved for the session

#### Scenario F011-S32: Session negotiates available models from the agent `[acp]`

**Given** an ACP session completes the session/new handshake
**When** the response includes a models payload
**Then** availableModels and currentModelId are parsed and published to the model picker

#### Scenario F011-S33: Direct integration agents use a static model catalog `[direct]`

**Given** the selected agent has a direct integration type
**When** the standalone pane resolves available models
**Then** models are sourced from the static catalog for that integration type with the default pre-selected

#### Scenario F011-S34: Reasoning level is configurable for direct integration agents `[direct]`

**Given** the selected agent supports direct integration
**When** the user selects a reasoning level
**Then** the level is passed to the session on connect and persists across pane restores

#### Scenario F011-S35: Sessions emit structured observability events `[all]`

**Given** observability is enabled
**When** session lifecycle events occur (connect, disconnect, prompt, turn completion)
**Then** structured event records are emitted with category, duration, and metadata
**And** turn summaries include counts for assistant chunks, thought chunks, tool calls, plan updates, permission requests, terminal requests, and file operations

#### Scenario F011-S36: VibeSpace context store tracks the focused project `[all]`

**Given** a vibespace is active with multiple projects
**When** the focused project changes
**Then** the context store updates the focused project identifier, display name, and root path
**And** active sessions sync the new focused project

### UI Layer — Message Rendering

#### Scenario F011-S37: Code blocks render with syntax highlighting and language label `[all]` `[planned]`

**Given** the assistant response contains a fenced code block with a language identifier
**When** the message renders in the timeline
**Then** the code block is syntax-highlighted for the specified language
**And** a language label and copy button are displayed on the block header

#### Scenario F011-S38: Markdown content renders with rich formatting `[all]`

**Given** the assistant response contains markdown (headings, lists, links, bold, italic)
**When** the message renders in the timeline
**Then** the markdown is rendered with appropriate rich formatting styles

#### Scenario F011-S39: User messages render as bubbles with accent background `[all]`

**Given** the user sends a message
**When** the message appears in the timeline
**Then** it renders as a bubble with the app accent background color, visually distinct from assistant messages

#### Scenario F011-S40: Assistant messages render with agent avatar `[all]` `[planned]`

**Given** the assistant sends a response
**When** the message renders in the timeline
**Then** the message is prefixed with the agent's avatar icon

#### Scenario F011-S41: Thought blocks render collapsed by default `[all]` `[planned]`

**Given** the agent streams thought/reasoning chunks during a turn
**When** the thought block renders in the timeline
**Then** it uses a secondary visual style distinct from regular assistant text
**And** it is collapsed by default with a "Thinking" label and expand toggle

#### Scenario F011-S42: Messages display timestamps `[all]` `[planned]`

**Given** a message is added to the timeline
**When** the message renders
**Then** a timestamp is displayed showing when the message was sent or completed

#### Scenario F011-S43: Individual messages support copy action `[all]` `[planned]`

**Given** a message is displayed in the timeline
**When** the user triggers the copy action on that message
**Then** the message content is copied to the system clipboard as plain text

#### Scenario F011-S44: Messages have a context menu with actions `[all]` `[planned]`

**Given** a message is displayed in the timeline
**When** the user right-clicks or long-presses the message
**Then** a context menu appears with Copy and Regenerate options

### UI Layer — Streaming

#### Scenario F011-S45: Typing indicator shows while waiting for first token `[all]` `[planned]`

**Given** a prompt has been sent to the agent
**When** no assistant tokens have arrived yet
**Then** a typing indicator animation is displayed in the timeline

#### Scenario F011-S46: Streaming cursor appears at end of text during response `[all]` `[planned]`

**Given** assistant tokens are streaming into the timeline
**When** the response is in progress
**Then** a blinking cursor is displayed at the end of the streamed text

#### Scenario F011-S47: Cancel button is visible during streaming `[all]`

**Given** a prompt is streaming
**When** the compose bar renders
**Then** a Cancel button replaces the Send button and clicking it cancels the in-progress prompt

#### Scenario F011-S48: Tool operations show progress indication `[all]` `[planned]`

**Given** the agent is executing a tool call
**When** the tool call card renders in the timeline
**Then** a progress indicator (spinner or progress bar) is displayed until the tool call completes

### UI Layer — Tool Call Visualization

#### Scenario F011-S49: Tool calls render as cards with title and kind `[all]`

**Given** the agent invokes a tool call
**When** the tool call renders in the timeline
**Then** it appears as a card showing the tool title, kind, and content

#### Scenario F011-S50: Tool call cards show status icon `[all]` `[planned]`

**Given** a tool call card is displayed
**When** the tool call transitions through pending, running, and completed states
**Then** the card displays a status icon reflecting the current state

#### Scenario F011-S51: File change diffs render with changed files summary `[all]`

**Given** the agent produces file changes via a tool call
**When** the diff renders in the timeline
**Then** a changed-files summary shows file names with addition and deletion counts
**And** inline diff content is displayed for each file

#### Scenario F011-S52: Multi-file changes show a file tree `[all]` `[planned]`

**Given** the agent produces changes spanning multiple files
**When** the diff renders in the timeline
**Then** a collapsible file tree groups the changed files by directory

#### Scenario F011-S53: Side-by-side diff option is available `[all]` `[planned]`

**Given** a file change diff is displayed
**When** the user toggles the diff view mode
**Then** the diff switches between inline and side-by-side layout

#### Scenario F011-S54: Terminal tool calls show embedded preview `[all]` `[planned]`

**Given** the agent executes a terminal tool call
**When** the tool call card renders
**Then** an embedded terminal output preview is displayed within the card

#### Scenario F011-S55: File changes offer apply and reject actions `[all]` `[planned]`

**Given** a file change diff is displayed in the timeline
**When** the user reviews the change
**Then** Apply and Reject buttons are available on the diff card
**And** Apply writes the change to disk and Reject discards it

### UI Layer — Permission Cards

#### Scenario F011-S56: Permission card shows tool title and options `[all]`

**Given** the agent requests permission for a tool call in standard trust mode
**When** the permission card renders
**Then** it displays the tool call title and the available permission options (allow, deny, allow-always)

#### Scenario F011-S57: Permission card shows inline diff preview for file changes `[all]`

**Given** the agent requests permission for a file write operation
**When** the permission card renders
**Then** an inline diff preview of the proposed changes is displayed within the card

#### Scenario F011-S58: Permission cards show risk-level indicators `[all]` `[planned]`

**Given** the agent requests permission for a tool call
**When** the permission card renders
**Then** a risk-level indicator (low, medium, high) is displayed based on the tool call type

#### Scenario F011-S59: Auto-allow toggle enables session-wide auto-approval `[all]`

**Given** a permission card is displayed
**When** the user selects the allow-always option
**Then** all subsequent permission requests for the session are auto-approved

### UI Layer — Compose Bar

#### Scenario F011-S60: Compose bar accepts text input and sends on action `[all]`

**Given** a session is connected
**When** the user types a message and triggers the send action
**Then** the message is sent as a prompt to the agent and the compose bar is cleared

#### Scenario F011-S61: Slash commands are suggested on "/" prefix `[all]`

**Given** the agent has advertised available commands
**When** the user types "/" in the compose bar
**Then** matching slash commands are shown as suggestions
**And** selecting a suggestion fills the compose bar with the command

#### Scenario F011-S62: User resends a previous message `[all]`

**Given** the timeline contains a user message entry
**When** the user triggers resend on that entry
**Then** all entries from that point forward are removed and the message text is placed back into the compose bar

#### Scenario F011-S63: Files and images can be attached to a prompt `[all]` `[planned]`

**Given** the compose bar is focused
**When** the user attaches a file or image
**Then** the attachment appears as a preview chip in the compose bar and is included with the prompt

#### Scenario F011-S64: @mention suggests files and symbols `[all]` `[planned]`

**Given** the compose bar is focused
**When** the user types "@"
**Then** a suggestion list of project files and symbols appears
**And** selecting a suggestion inserts a reference into the compose bar

#### Scenario F011-S65: Cmd+Enter sends the message `[all]` `[planned]`

**Given** the compose bar has text content
**When** the user presses Cmd+Enter
**Then** the message is sent as a prompt to the agent

#### Scenario F011-S66: Model picker is available in the compose bar `[all]` `[planned]`

**Given** a session is connected with multiple available models
**When** the compose bar renders
**Then** a model picker is displayed allowing the user to switch models before sending

#### Scenario F011-S67: Runtime mode selector is available in the compose bar `[all]` `[planned]`

**Given** a session is connected
**When** the compose bar renders
**Then** a runtime mode selector (supervised, auto-accept, full-access) is available

#### Scenario F011-S68: Draft messages persist per thread `[all]` `[planned]`

**Given** the user has typed a partial message in the compose bar
**When** the user switches to a different conversation and returns
**Then** the draft text is restored for the original conversation

### UI Layer — Conversation Management

#### Scenario F011-S69: Conversations persist to local store `[all]` `[planned]`

**Given** a conversation has messages in the timeline
**When** the session ends or the vibespace is saved
**Then** the conversation is persisted to the local store for later retrieval

#### Scenario F011-S70: Session history list with search `[all]` `[planned]`

**Given** the user opens the conversation history panel
**When** the panel renders
**Then** a list of past conversations is displayed with titles and timestamps
**And** a search field filters conversations by content

#### Scenario F011-S71: New conversation action creates a fresh session `[all]` `[planned]`

**Given** the user is in an active conversation
**When** the user triggers the new conversation action
**Then** the current conversation is preserved and a new empty conversation begins

#### Scenario F011-S72: Conversation resumes via session/load or local fallback `[all]` `[planned]`

**Given** the user selects a past conversation from history
**When** the conversation is loaded
**Then** the system attempts session/load with the agent first
**And** falls back to restoring from local store if the agent does not support it

#### Scenario F011-S73: Context window meter shows token usage `[all]` `[planned]`

**Given** a session is connected
**When** the chat header renders
**Then** a context window meter displays current token usage relative to the model's context limit

### UI Layer — Setup Experience

#### Scenario F011-S74: Agent picker shows icons and descriptions `[all]` `[planned]`

**Given** the user opens the agent picker
**When** the picker renders
**Then** each agent is displayed with its icon, name, and description

#### Scenario F011-S75: Connection status shows structured errors `[all]`

**Given** a session connection attempt fails
**When** the setup strip renders
**Then** a structured error message is displayed with the failure reason and suggested remediation

#### Scenario F011-S76: Onboarding empty state for first-time users `[all]` `[planned]`

**Given** no agent sessions have been created in the vibespace
**When** the ACP pane renders
**Then** an onboarding empty state is displayed with instructions for selecting an agent and connecting

### UI Layer — Standalone Pane

#### Scenario F011-S77: Standalone pane provides agent, project, and model pickers `[all]`

**Given** the user opens an ACP pane in the detailed content viewer
**When** the pane renders its setup strip
**Then** pickers are shown for agent, project, and model selection
**And** a Connect button is available when an agent and project are selected

#### Scenario F011-S78: Trust mode picker appears for direct integration agents `[direct]`

**Given** the selected agent supports direct integration
**When** the setup strip renders
**Then** a trust mode picker appears with Standard and Full Trust options

#### Scenario F011-S79: Reasoning level picker appears for direct integration agents `[direct]`

**Given** the selected agent supports direct integration
**When** the setup strip renders
**Then** a reasoning level picker appears with Low, Medium, High, and Max options

#### Scenario F011-S80: Standalone pane auto-connects on restore `[all]`

**Given** a standalone pane was previously connected and the vibespace is reopened
**When** the pane restores its persisted state
**Then** the pane automatically reconnects to the previously selected agent and project

#### Scenario F011-S81: Standalone pane state persists across sessions `[all]`

**Given** an ACP standalone pane has agent, model, project, trust mode, and reasoning level selections
**When** the vibespace is saved and reopened
**Then** all selections are restored from the persisted pane snapshot

### UI Layer — Board Tile

#### Scenario F011-S82: ACP tile can be added to the terminal board `[all]`

**Given** the vibespace is in terminal-only canvas mode
**When** the user triggers the add-ACP-tile action from the toolbar
**Then** a new ACP tile is added to the terminal board layout

#### Scenario F011-S83: ACP board tile renders chat and session controls `[all]`

**Given** an ACP tile exists on the terminal board
**When** the tile card renders
**Then** it displays the agent tab title and hosts the ACP chat view with connection and compose controls

#### Scenario F011-S84: ACP tile participates in spotlight carousel `[all]`

**Given** the terminal board has ACP tiles
**When** spotlight carousel navigation enumerates items
**Then** ACP tiles are included with their store ID and title

### UI Layer — Settings

#### Scenario F011-S85: Default agent is configurable in settings `[all]`

**Given** the user opens Settings > ACP
**When** the user selects a default agent
**Then** new ACP sessions use the selected agent unless overridden per-project

#### Scenario F011-S86: Default trust mode is configurable in settings `[all]`

**Given** the user opens Settings > ACP
**When** the user selects a default trust mode
**Then** new sessions use the selected trust mode

#### Scenario F011-S87: Default model and reasoning level are configurable in settings `[all]`

**Given** the user opens Settings > ACP
**When** the user sets a default model and reasoning level
**Then** new sessions use the selected defaults

#### Scenario F011-S88: Custom agents can be registered in settings `[all]`

**Given** the user opens Settings > ACP
**When** the user adds a custom agent entry with title, executable, and arguments
**Then** the agent is available for selection across all panes and tiles

#### Scenario F011-S89: Per-project agent overrides are configurable `[all]`

**Given** a vibespace contains multiple projects
**When** the user sets an ACP agent override for a specific project in vibespace settings
**Then** that project uses the overridden agent instead of the global default
**And** the override is persisted in the vibespace state keyed by project path

#### Scenario F011-S90: Per-project agent override falls back when cleared `[all]`

**Given** a project has an ACP agent override configured
**When** the user clears the override
**Then** the project falls back to the global default ACP agent

### Turn-Based Timeline Grouping

#### Scenario F011-S91: Timeline groups entries by prompt turn `[all]` `[planned]`

**Given** the agent processes a prompt with thinking, tool calls, and a response
**When** the turn completes and renders in the timeline
**Then** all entries from that turn are grouped together visually
**And** entries from different turns are not interleaved

#### Scenario F011-S92: Tool calls within a turn are grouped into a collapsible work log `[all]` `[planned]`

**Given** the agent invokes multiple tool calls during a single turn
**When** the tool calls render in the timeline
**Then** they are grouped into a single collapsible "Work" section with a count badge
**And** the section is collapsed by default showing only the count

#### Scenario F011-S93: Changed files summary appears after the assistant response `[all]` `[planned]`

**Given** the agent produces file changes during a turn
**When** the turn completes
**Then** a changed files summary appears below the assistant response text
**And** the summary shows file names grouped by directory with per-file addition and deletion counts
**And** clicking a file expands its inline diff

#### Scenario F011-S94: Turn rendering order follows thinking then work then response then changes `[all]` `[planned]`

**Given** a prompt turn produces thinking, tool calls, a response, and file changes
**When** the turn renders in the timeline
**Then** the order is: thinking block (collapsed) → tool call work log (collapsed) → assistant response → changed files summary

#### Scenario F011-S95: Diff panel opens in sidebar for detailed file review `[all]` `[planned]`

**Given** a changed files summary is visible in the timeline
**When** the user clicks a file name in the summary
**Then** a diff panel opens as a sidebar showing the full diff for that file
**And** the panel supports navigation between changed files


### Inline Trigger Panel

#### Scenario F011-S100: ACP compose supports inline insert triggers `[all]`

**Given** the ACP compose bar is focused
**When** the user types the configured inline insert trigger
**Then** the inline insert picker opens per F038 behavior using the ACP session's project context
**And** path insertion, shortcut insertion, command generation, board popup presentation, and dismissal follow F038 scenarios


### Git-Based Turn Checkpointing

#### Scenario F011-S96: Git checkpoint is captured before each agent turn `[all]` `[planned]`

**Given** a project is under git version control and an agent turn is about to begin
**When** the user sends a prompt
**Then** the system creates a hidden git ref capturing the current working tree state before the agent executes

#### Scenario F011-S97: Turn diff is computed from git checkpoints after turn completes `[all]` `[planned]`

**Given** a git checkpoint was captured before the turn and the turn has completed
**When** the changed files summary is rendered
**Then** the diff is computed via git diff between the pre-turn and post-turn checkpoints
**And** all file changes are captured regardless of how the agent made them

#### Scenario F011-S98: Git checkpoint diff captures terminal-initiated file changes `[all]` `[planned]`

**Given** an agent modifies files via terminal commands (not fs/write_text_file)
**When** the turn completes and the diff is computed
**Then** the changed files summary includes those terminal-initiated changes

#### Scenario F011-S99: Git checkpoint supports rollback to pre-turn state `[all]` `[planned]`

**Given** a git checkpoint exists for a completed turn
**When** the user requests a rollback
**Then** the working tree is restored to the pre-turn checkpoint state


## Acceptance Criteria

- Agent discovery completes within 500ms (PERF-3).
- Session connect handshake completes within 2s (PERF-3).
- Streaming chunks render within 50ms of receipt (PERF-3).
- File system sandboxing rejects all path traversal attempts (SEC-1).
- Permission cards are accessible via keyboard (A11Y-2).
- All session lifecycle events are logged (OBS-1).
- Markdown rendering handles all CommonMark elements without layout breakage.
- Compose bar is focusable and operable via keyboard alone (A11Y-2).
- Pane state round-trips through save/restore without data loss.
- Tool call cards display correct status for all terminal states (pending, running, completed, failed).

## Open Questions

- Should ACP support multi-agent sessions (multiple agents in one conversation)?
- Should conversation persistence use a shared store or per-vibespace isolation?
- Should file attachment support drag-and-drop from Finder?
- Should the context window meter warn when approaching the limit?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-20 | Added compose-bar inline trigger requirements for standalone, spotlight, and board ACP surfaces | Codex |
| 2026-04-15 | Migrated from docs/features/acp/feature.md (ACP-001 through ACP-036) | — |
| 2026-04-19 | Full rewrite: added agent type tags, UI layer scenarios (S37–S90), expanded protocol scenarios, updated requirements R01–R23 | — |
