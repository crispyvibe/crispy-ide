---
title: "Terminal Inline Triggers"
feature: "F038"
domain: "terminal"
audience: "user"
version: "1.0"
sidebar:
  label: "Inline Triggers"
  order: 8
---

# Terminal Inline Triggers

## Overview

Terminal Inline Triggers let you type a configured trigger inside terminal-adjacent inputs to insert a file path, insert a saved shortcut, or generate a command without leaving the current input.

## Getting Started

Type the configured trigger inside:

- a terminal input
- terminal spotlight compose
- ACP compose
- VibeCast compose

The inline picker opens for the current context and keeps the result in the input for review.

## Workflows

### Insert a file or directory

1. Type the trigger and part of a path query.
2. Choose a file or directory from the picker.
3. Confirm to insert the path into the current draft.

### Insert a saved shortcut

1. Type the trigger and part of the shortcut name.
2. Choose the shortcut from the picker.
3. Confirm to insert the shortcut text into the current draft.

### Generate a command

1. Type the trigger and a short request.
2. Move to `Generate Command`.
3. Confirm to insert the generated result for review.

## Keyboard Shortcuts

- `Up` / `Down`: move selection
- `Right Arrow`: move into the action pane when present
- `Tab` / `Enter`: confirm selection
- `Escape`: dismiss the picker

## Settings / Configuration

- The trigger token is configurable in settings.
- Shortcut management is available from the picker when supported by the current surface.

## Troubleshooting

- If the picker closes, continue editing normally or start a new trigger token to reopen it.
- If the current surface does not expose shortcut management, the `Manage Shortcuts…` action is hidden.

## Known Limitations

- Remote SSH path-result parity is planned separately and may differ from local path search until that backend ships.
