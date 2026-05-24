# Feature Index

## Domains

| ID | Domain | Scope |
|----|--------|-------|
| D1 | App Shell | Window management, navigation, theming, keyboard shortcuts, onboarding |
| D2 | VibeSpace | Lifecycle, persistence, projects, settings, color coding |
| D3 | Terminal | Sessions, tabs, engines, board, spotlight, rail, presets, focus |
| D4 | Editor | Content viewer, file editing, markdown, code, previews, split panes |
| D5 | Explorer | File tree, sidebar, file operations, watching, drag & drop |
| D6 | Source Control | Git status, diff, branch, commit, clone |
| D7 | AI & Agents | VibeCast, text services, ACP protocol |
| D8 | Remote | SSH connections, SFTP, remote projects |
| D9 | Platform | App updates, OS services, diagnostics, shelf |

## Features

Next available prefix: F049. Numbers are never reused.

| Prefix | Feature | Domain | Folder | Status |
|--------|---------|--------|--------|--------|
| F001 | Terminal Sessions & Tabs | D3 | `terminal/sessions-and-tabs` | draft |
| F002 | Terminal Board | D3 | `terminal/board` | implemented |
| F003 | Terminal Spotlight | D3 | `terminal/spotlight` | draft |
| F004 | Terminal Rail | D3 | `terminal/rail` | draft |
| F005 | Terminal Presets | D3 | `terminal/presets` | draft |
| F006 | Content Viewer | D4 | `editor/content-viewer` | draft |
| F007 | Editing | D4 | `editor/editing` | draft |
| F008 | Markdown | D4 | `editor/markdown` | draft |
| F009 | Previews | D4 | `editor/previews` | draft |
| F010 | tmux Integration | D3 | `terminal/tmux` | draft |
| F011 | ACP | D7 | `ai-agents/acp` | draft |
| F012 | Browser | D9 | `platform/browser` | implemented |
| F013 | Worker | D9 | `platform/worker` | draft |
| F014 | Navigation | D1 | `app-shell/navigation` | draft |
| F015 | Theming | D1 | `app-shell/theming` | draft |
| F016 | Keyboard Shortcuts | D1 | `app-shell/shortcuts` | draft |
| F017 | Onboarding | D1 | `app-shell/onboarding` | draft |
| F020 | VibeSpace Lifecycle | D2 | `vibespace/lifecycle` | draft |
| F021 | VibeSpace Projects | D2 | `vibespace/projects` | implemented |
| F022 | VibeSpace Settings | D2 | `vibespace/settings` | draft |
| F023 | Project Color Coding | D2 | `vibespace/color-coding` | draft |
| F024 | File Explorer | D5 | `explorer/file-explorer` | draft |
| F025 | Drag & Drop | D5 | `explorer/drag-and-drop` | draft |
| F026 | Git Operations | D6 | `source-control/git-operations` | draft |
| F027 | Clone Repository | D6 | `source-control/clone` | draft |
| F028 | VibeCast | D7 | `ai-agents/vibecast` | draft |
| F029 | Text Services | D7 | `ai-agents/text-services` | draft |
| F030 | App Updates | D9 | `platform/app-updates` | draft |
| F031 | OS Services | D9 | `platform/os-services` | draft |
| F032 | Diagnostics | D9 | `platform/diagnostics` | draft |
| F033 | Shelf | D9 | `platform/shelf` | draft |
| F034 | SSH Remote Development | D8 | `remote/ssh-remote` | draft |
| F035 | Authentication | D9 | `platform/authentication` | draft |
| F036 | App Settings | D9 | `platform/app-settings` | draft |
| F037 | Terminal Board Dock | D3 | `terminal/dock` | draft |
| F038 | Terminal Inline Triggers | D3 | `terminal/inline-triggers` | draft |
| F039 | Document Buffer | D4 | `editor/document-buffer` | draft |
| F040 | Agent Conversation Persistence | D7 | `ai-agents/agent-conversation-persistence` | draft |
| F041 | Terminal Context Summary | D3 | `terminal/context-summary` | draft |
| F042 | Agent Board | D7 | `ai-agents/agent-board` | vision |
| F043 | Compose History | D1 | `app-shell/compose-history` | draft (single-file layout — see folder note) |
| F044 | Agent CLI | D9 | `platform/agent-cli` | implemented |
| F045 | Office Document Preview | D4 | `editor/office-document-preview` | draft |
| F046 | Terminal Scroll Assist | D3 | `terminal/scroll-assist` | draft |
| F047 | External Agent Sessions | D7 | `ai-agents/external-agent-sessions` | implemented |
| F048 | Terminal Board Multi-Monitor | D3 | `terminal/board-multi-monitor` | implemented |

## NFR Index

| Prefix | NFR | File |
|--------|-----|------|
| SEC | Security | `specs/nfr/security.md` |
| DEP | Dependency Management | `specs/nfr/dependency-management.md` |
| OS | Cross-Platform Support | `specs/nfr/cross-platform.md` |
| OBS | Observability | `specs/nfr/observability.md` |
| A11Y | Accessibility | `specs/nfr/accessibility.md` |
| PERF | Performance | `specs/nfr/performance.md` |
| REL | Reliability | `specs/nfr/reliability.md` |
| TEST | Testability | `specs/nfr/testability.md` |

## ID Formats

| Document | Format | Example |
|----------|--------|---------|
| spec.md | `F{NNN}-R{NN}` (requirement) | `F001-R01` |
| spec.md | `F{NNN}-S{NN}` (scenario) | `F001-S01` |
| threat-model.md | `F{NNN}-T{NN}` (threat) | `F001-T01` |

## Glossary

| Term | Definition |
|------|-----------|
| VibeSpace | Crispy's name for a vibespace — a collection of projects, terminals, and settings |
| VibeCast | Tool for sending commands to one or all terminals |
| ACP | Agent Conversation Protocol — hosts AI coding assistant sessions |
| Project Rail | The stacked project cards shown on the side in Detailed view |
| Canvas | The main content area (editor pane or terminal board) |
