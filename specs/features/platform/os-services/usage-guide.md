---
title: "macOS Services"
feature: "F033"
domain: "platform"
audience: "user"
version: "1.0"
sidebar:
  label: "OS Services"
  order: 5
---

# macOS Services

## Overview

Crispy registers three macOS Services menu items that allow you to process selected text or open files/folders from any application on your Mac. The services use a configurable CLI tool (such as an AI assistant) to rephrase or research text, and can open folders directly in Crispy's terminal.

## Getting Started

1. Select text in any macOS application.
2. Right-click and navigate to **Services** in the context menu (or use the app's Services menu).
3. Choose one of the Crispy services: **rephrase**, **research**, or **open in terminal**.
4. The first time you use a service, you may need to enable it in System Settings → Keyboard → Keyboard Shortcuts → Services.

## Workflows

### Rephrasing Selected Text

1. Select text in any application (TextEdit, Notes, Safari, etc.).
2. Right-click → Services → **Crispy: rephrase** (or use the application's Services menu).
3. Crispy sends the selected text to the configured CLI tool with the rephrase prompt template.
4. The CLI processes the text and returns a rephrased version.
5. The selected text is replaced with the CLI's response.

### Researching Selected Text

1. Select text in any application.
2. Right-click → Services → **Crispy: research**.
3. Crispy sends the selected text to the configured CLI tool with the research prompt template.
4. The CLI processes the text and returns research results.
5. The selected text is replaced with the CLI's response.

### Opening a Folder in Crispy Terminal

1. In Finder or any app that provides file/folder references, select a folder (or shell script, or Unix executable).
2. Right-click → Services → **Crispy: open in terminal**.
3. Crispy opens the selected path in a new terminal session within the active vibespace.

## Keyboard Shortcuts

macOS allows you to assign keyboard shortcuts to Services:

1. Open **System Settings → Keyboard → Keyboard Shortcuts → Services**.
2. Find the Crispy services under "Text" (rephrase, research) or "Files and Folders" (open in terminal).
3. Assign your preferred shortcut.

## Settings

| Setting | Location | Description |
|---------|----------|-------------|
| CLI profile | Settings → Services | Selects a preset CLI configuration (e.g., for different AI tools) |
| Trust mode | Settings → Services | Controls preset defaults for the selected profile |
| CLI command | Settings → Services | The executable to run (e.g., `kiro`, `claude`) |
| CLI arguments | Settings → Services | Arguments passed before the prompt text |
| Default agent | Settings → Services | Agent name passed with `--agent` flag |
| Pass `--agent` argument | Settings → Services | Toggle whether to include the agent flag |
| Rephrase prompt | Settings → Services | Template for rephrase operations (supports `{{text}}` placeholder) |
| Research prompt | Settings → Services | Template for research operations (supports `{{text}}` placeholder) |
| Reset Defaults | Settings → Services | Restores all service settings to factory defaults |

## Tips

- Prompt templates support a `{{text}}` placeholder. If present, the selected text replaces it. If absent, the text is appended after the template.
- Large text selections are automatically chunked (4,000 characters per chunk, up to 6 chunks max = 24,000 characters). Excess text is truncated with a notice.
- The CLI command timeout defaults to 20 seconds. Override with the `CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS` environment variable.
- Terminal formatting (ANSI escape sequences) is automatically stripped from CLI output.
- The service extracts the assistant's response by finding the last line starting with `>` in the output, then collecting text until a timing line (`▸ Time:`) is encountered.
- If `--agent` is enabled and the preferred agent fails, the service retries without the agent flag as a fallback.
- The "open in terminal" service accepts `public.folder`, `public.shell-script`, and `public.unix-executable` file types.
- Services are registered at app launch via `NSApp.servicesProvider` and `NSRegisterServicesProvider`. The dynamic services list is updated with `NSUpdateDynamicServices()`.
- You can configure different agent names per service type via environment variables: `CRISPYVIBES_KIRO_REPHRASE_AGENT` and `CRISPYVIBES_KIRO_RESEARCH_AGENT`.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Services don't appear in the menu | Enable them in System Settings → Keyboard → Keyboard Shortcuts → Services. You may need to log out and back in after first install. |
| "No selected text was provided" | Ensure text is actually selected before invoking the service. |
| "The configured CLI returned an empty response" | The CLI command ran but produced no usable output. Check your CLI command and arguments in Settings → Services. |
| "The configured CLI failed with exit code N" | The CLI command returned an error. Check that the command is installed and accessible. The error details show stderr output. |
| "Unable to launch the configured CLI" | The CLI command path is invalid or the executable is not found. Verify the command in Settings → Services. |
| "The configured CLI timed out after N seconds" | The CLI took too long. Increase the timeout via `CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS` or check if the CLI is hanging. |
| "No CLI command is configured" | Set a CLI command in Settings → Services (e.g., `kiro` or `claude`). |
| "open in terminal" does nothing | Ensure the selected item is a valid folder, shell script, or Unix executable that exists on disk. |
