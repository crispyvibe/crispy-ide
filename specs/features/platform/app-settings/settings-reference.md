# App Settings — Reference

Complete inventory of every setting in the App Settings sheet, organized by section.

## Navigation

Settings open as a split view: category sidebar on the left, detail panel on the right. The sidebar contains app-level categories only. `Connections` is always visible and owns SSH profile management.

---

## 1. Account

Icon: `person.crop.circle`

| Setting | Control | Description |
|---------|---------|-------------|
| Sign in with Apple | Button | Authenticates via Cognito-backed Sign in with Apple flow. Requires hosting NSWindow as presentation anchor. |
| Sign out | Button | Clears authentication state. Shown only when signed in. |

Internal settings (not user-visible in this section):
- `authCognitoDomain` — Cognito domain override
- `authCognitoMacClientId` — Cognito client ID override

---

## 2. Appearance

Icon: `paintbrush`
Subtitle: Visual style, typography, and app chrome defaults

### Display Mode card

| Setting | Control | Storage Key | Default | Description |
|---------|---------|-------------|---------|-------------|
| Appearance | Picker (Auto / Light / Dark) | `appearancePreference` binding | Auto | System appearance override. Shows warning when theme preset overrides this. |

### Theme Presets card

| Setting | Control | Storage Key | Default | Description |
|---------|---------|-------------|---------|-------------|
| Theme preset | Picker | `themePreset` binding | System | Selects from built-in presets or Custom. |
| Quick preset buttons | LazyVGrid of ThemePresetQuickButton | — | — | Visual grid of all non-custom presets with palette preview swatches. |

### Typography card

| Setting | Control | Storage Key | Default | Description |
|---------|---------|-------------|---------|-------------|
| Font family | Picker | `codeFontFamilyKey` | System default | Monospace font used in editors and terminals. |
| Font size | Slider (8–32) | `codeFontSizeKey` | System default | Base font size. Clamped to valid range. |
| Rail terminal font scale | Segmented picker | `railTerminalFontScaleKey` | Default | Scale factor for terminal text in rail tiles. |
| Text color | ColorPicker + hex TextField | Custom theme draft | — | Terminal foreground color. Edits switch to Custom preset. |

### Container Style card

| Setting | Control | Storage Key | Default | Description |
|---------|---------|-------------|---------|-------------|
| Border shape | Segmented picker | `borderShape` (theme) | — | Container corner radius style. |
| Show borders | Toggle | `borderVisible` (theme) | — | Toggle border strokes on all panes. |

### App Chrome card

| Setting | Control | Storage Key | Default | Description |
|---------|---------|-------------|---------|-------------|
| Rail position | Picker | `defaultRailPosition` binding | First-run default | Default position of the project rail for new VibeSpaces. |
| App side menu dock | Picker | `sideMenuDockPositionRaw` binding | First-run default | Dock position of the app-level side menu. |

### Advanced Theme Tokens card

Visible only when Custom theme preset is selected.

| Setting | Control | Description |
|---------|---------|-------------|
| Per-role color tokens | ColorPicker + hex TextField per role | Edit individual theme palette colors (accent, background, text, selection, etc.). |
| Reset to base | Button | Resets custom palette to the base preset. |

---

## 3. Keyboard Shortcuts

Icon: `keyboard`
Subtitle: Customize app-wide keyboard shortcuts and navigation keys

### App Shortcuts card

| Setting | Control | Description |
|---------|---------|-------------|
| Per-shortcut row | Record button / Disable / Reset | Each app shortcut shows current binding, status (active/disabled/custom), and actions to record new key, disable, or reset to default. |
| Terminal inline trigger | TextField | Character sequence that activates the inline compose bar in terminal and agent inputs. |

Recording uses `NSEvent.addLocalMonitorForEvents` to capture key combinations. Escape cancels, Delete disables.

VibeSpace and project command shortcuts are managed in VibeSpace Settings, not App Settings.

---

## 4. Terminal

Icon: `terminal`
Subtitle: Shell defaults, input behavior, and rendering

| Setting | Control | Storage Key | Default | Description |
|---------|---------|-------------|---------|-------------|
| Default terminal shell | Picker | `defaultTerminalShellRaw` binding | System default | Shell used for new terminal sessions (zsh, bash, fish, etc.). |
| Terminal engine | Segmented picker (Ghostty / SwiftTerm) | `nerdTerminalEngineKey` | Ghostty | Selects the terminal rendering backend. Falls back to SwiftTerm if Ghostty runtime is unavailable. |
| Enable tmux integration | Toggle | `experimentalTmuxIntegrationKey` | Off | Enables tmux-backed terminal sessions. This setting is managed in Terminal, not Experimental. |

### Tmux Integration card

Conditionally visible when tmux integration is enabled.

| Setting | Control | Storage Key | Default | Description |
|---------|---------|-------------|---------|-------------|
| Session behavior | Picker (Detach / Terminate) | `experimentalTmuxSessionBehaviorKey` | Detach | What happens to tmux session when disconnecting. |
| Tab close behavior | Picker (Detach / Terminate) | `experimentalTmuxTabCloseBehaviorKey` | Terminate | What happens to tmux session when closing a tab. |

---

## 5. AI Services

Icon: `text.bubble`
Subtitle: CLI command defaults and reusable prompt templates

### CLI Defaults card

| Setting | Control | Storage Key | Default | Description |
|---------|---------|-------------|---------|-------------|
| CLI profile | Picker | `textServiceCLIProfileKey` | Default profile | Selects a preset CLI tool profile. Changing profile auto-fills command, arguments, and agent flag. |
| Trust mode | Picker | `textServiceCLITrustModeKey` | Standard | Trust level for CLI invocations. Conditionally visible based on profile. |
| CLI command | TextField | `textServiceCLICommandKey` | Profile default | Executable path or command name. |
| CLI arguments | TextField | `textServiceCLIArgumentsKey` | Profile default | Arguments inserted before the prompt. |
| Default agent | TextField | `textServiceDefaultAgentKey` | Empty | Agent identifier passed to CLI. |
| Pass `--agent` argument | Toggle | `textServicePassAgentFlagKey` | Profile default | Whether to append `--agent <id>` when invoking the CLI. |

### Prompt Templates card

| Setting | Control | Storage Key | Default | Description |
|---------|---------|-------------|---------|-------------|
| Rephrase prompt | TextEditor | `textServiceRephrasePromptKey` | Default template | System prompt used for text rephrase operations. |
| Research prompt | TextEditor | `textServiceResearchPromptKey` | Default template | System prompt used for research operations. |
| Reset defaults | Button | — | — | Restores both prompts to their default templates. |

---

## 6. Agents

Icon: `sparkles`
Subtitle: Default agent selection and custom agent commands

### Agent Defaults card

| Setting | Control | Storage Key | Default | Description |
|---------|---------|-------------|---------|-------------|
| Default agent | Picker | `acpDefaultAgentIDKey` | Empty | Selects from discovered available agents. Auto-clears if selected agent becomes unavailable. |
| Trust mode | Segmented picker | `acpDefaultTrustModeKey` | Standard | Default trust level for ACP sessions. Shown only for agents with direct integration. |
| Model | Picker | `acpDefaultModelKey` | Agent default | Default model for the selected agent. Auto-set when agent changes. Shown only for direct integration agents. |
| Reasoning level | Segmented picker | `acpDefaultReasoningLevelKey` | Medium | Reasoning depth for agent responses. Shown only for direct integration agents. |

### Custom Agents list

| Setting | Control | Description |
|---------|---------|-------------|
| Custom agent list | List with delete | Shows user-defined custom ACP agents. Each row shows title and executable. |
| Add custom agent: Title | TextField | Display name for the custom agent. |
| Add custom agent: Executable | TextField | Path to the agent executable. |
| Add custom agent: Arguments | TextField | Command-line arguments for the agent. |
| Add | Button | Saves the custom agent and refreshes discovery. |

Agent discovery runs on appear and after adding/removing custom agents.

---

## 7. Updates

Icon: `arrow.trianglehead.2.clockwise.rotate.90`
Subtitle: Automatic checks and update feed configuration

| Setting | Control | Storage Key | Default | Description |
|---------|---------|-------------|---------|-------------|
| Auto-check for updates | Toggle | `autoUpdateChecksEnabledKey` | true | Periodically check for new versions. |
| Appcast feed URL | TextField | `appUpdateFeedURLKey` | Default feed | Custom Sparkle appcast URL for update checks. |
| Check now | Button | — | — | Triggers an immediate update check. |
| Reset feed URL | Button | — | — | Restores the default appcast URL. |

---

## 8. Experimental

Icon: `flask`
Subtitle: Opt-in features that may change or be removed

| Setting | Control | Storage Key | Default | Description |
|---------|---------|-------------|---------|-------------|
| ACP Observability | Toggle | `experimentalACPObservabilityKey` | Off | Enables ACP diagnostics in Developer Tools. Disabling also disables verbose mode. |
| Terminal Insight | Toggle | `experimentalTerminalInsightKey` | Off | Shows last command summary at the top of each terminal. |

---

## 9. Connections

Icon: `network`
Subtitle: SSH connection profiles and key management

Always visible.

| Setting | Control | Description |
|---------|---------|-------------|
| SSH profiles list | List with add/edit/delete | Manage SSH connection profiles (host, port, user, key, etc.). |
| Import from SSH config | Button | Parses `~/.ssh/config` and imports discovered hosts. |
| Host key prompt | Sheet | Shown when connecting to an unknown host — accept/reject host key. |
| Generated SSH key | Sheet | Displays a newly generated SSH key pair for copying. |

---

## 10. Reset

Icon: `arrow.counterclockwise`
Subtitle: Clear local overrides and start from a fresh machine state

| Setting | Control | Description |
|---------|---------|-------------|
| Reset local state | Destructive button | Clears app storage, layout persistence, shelf store, walkthrough controller. Shows confirmation alert before executing. |

---

## Developer Tools (separate view)

Not part of the settings sheet. Accessed separately. Contains 5 diagnostic tabs:

| Tab | Description |
|-----|-------------|
| Operations | Live feed of parent/child operation records with timing. |
| Summary | Aggregated operation counts by type and project. |
| Terminal | Session details, latencies, diagnostic snapshots. |
| ACP | Probe controls (connect/disconnect/send prompt), session list, turn history, event log, aggregates. |
| Remote | Remote connection event records. |

Refreshes on a 2-second timer. Dependencies: `OperationMetricsStore`, `TerminalDiagnosticsSnapshot`, `ACPObservabilityStore`, `ACPDeveloperToolsService`.

---

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-20 | Initial comprehensive settings inventory — all 12 sections documented | — |
| 2026-04-27 | Consolidated visual/chrome controls under Appearance and moved terminal engine into Terminal | — |
