---
title: "Text Services"
feature: "F029"
domain: "ai-agents"
audience: "user"
version: "1.0"
sidebar:
  label: "Text Services"
  order: 2
---

# Text Services

## Overview

Text Services provides macOS system-level AI-powered text operations — Rephrase and Research — accessible from any app's Services menu. It also includes an Open in Terminal service. These services invoke a configured CLI agent to process selected text and replace it with the result via the system pasteboard.

## Getting Started

1. Ensure at least one supported CLI agent is installed (Kiro, Claude Code, Codex, Gemini, or OpenCode).
2. Open **App Settings → AI → Text Services** and select your preferred CLI profile.
3. Select text in any macOS application.
4. Access **Services → Crispy: rephrase** or **Crispy: research** from the application menu or right-click context menu.

## Workflows

### Rephrasing Text

1. Select text in any application (editor, browser, notes, etc.).
2. Open the app menu → Services → **Crispy: rephrase**.
3. The selected text is sent to the configured CLI agent with a clarity-preserving prompt.
4. On success, the pasteboard is replaced with the rewritten text.
5. Paste (⌘V) to insert the rephrased version.

### Researching Text

1. Select text you want to augment with context.
2. Open the app menu → Services → **Crispy: research**.
3. The CLI agent receives a prompt requesting concise practical research context.
4. On success, the pasteboard is replaced with the enriched text.
5. Paste to insert the researched version.

### Opening a Path in Terminal

1. Select a file or folder in Finder or any compatible context.
2. Open the app menu → Services → **Crispy: open in terminal**.
3. Crispy opens a terminal session at the selected path.

### Configuring CLI Profiles

1. Open **App Settings → AI → Text Services**.
2. Choose a CLI profile: Kiro, Claude Code, Codex, Gemini, OpenCode, or Custom.
3. For Custom profiles, specify the executable path and base arguments.
4. Set trust mode: Standard (no `--trust-all-tools`) or Full Trust (includes `--trust-all-tools`).
5. Optionally override the default rephrase and research prompts.

## Keyboard Shortcuts

Text Services are invoked through the macOS Services menu. No dedicated keyboard shortcuts are assigned by default, but you can assign them in **System Settings → Keyboard → Keyboard Shortcuts → Services**.

## Settings

- **CLI Profile** (App Settings → AI): Select which CLI tool handles text service requests (kiro, claudeCode, codex, gemini, opencode, custom).
- **Trust Mode**: Standard or Full Trust — controls whether `--trust-all-tools` is passed.
- **Rephrase Prompt Override**: Custom prompt template for rephrase operations. Use `{{text}}` as placeholder.
- **Research Prompt Override**: Custom prompt template for research operations. Use `{{text}}` as placeholder.
- **Default Agent**: Agent name passed via `--agent` flag (configurable per service kind via environment variables).
- **Pass Agent Flag**: Toggle whether `--agent` is included in CLI invocations.
- **Timeout**: Controlled via `CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS` environment variable (default: 20 seconds).

## Tips

- Text exceeding 4,000 characters is automatically split into up to 6 chunks processed independently.
- Agent resolution follows a fallback chain: kind-specific env var → generic env var → app setting → no agent flag.
- If the initial CLI attempt fails with a configured agent, the service retries once without the agent argument.
- PATH is automatically expanded to include Homebrew, `/usr/local/bin`, and `~/.local/bin` for CLI discovery.
- Prompt templates with `{{text}}` insert selected text at the placeholder position without appending it again.
- Services are registered at app launch and appear in the macOS Services menu as "Crispy: rephrase", "Crispy: research", and "Crispy: open in terminal".

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Services don't appear in menu | Restart Crispy to re-register services. Check System Settings → Keyboard → Shortcuts → Services to ensure they're enabled. |
| "No selected text was provided" | Ensure text is actually selected before invoking the service. |
| Empty response from CLI | The agent may have timed out or returned no content. Check that the CLI tool is working independently. Increase timeout via `CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS`. |
| CLI command not found | Verify the CLI executable is installed and accessible. Text Services expands PATH but the tool must exist in a standard location. |
| Service times out | Default timeout is 20 seconds. Set `CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS` to a higher value for complex operations. |
| ANSI artifacts in output | This should not occur — ANSI stripping is automatic. If seen, report as a bug. |
