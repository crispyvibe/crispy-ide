---
title: "App Settings"
feature: "F036"
domain: "platform"
audience: "user"
version: "1.0"
sidebar:
  label: "App Settings"
  order: 8
---

# App Settings

## Overview

App Settings contains preferences that apply to Crispy as an app: account state, appearance, keyboard shortcuts, terminal defaults, AI service defaults, agent defaults, update delivery, experimental feature gates, connection profiles, and reset controls.

VibeSpace and project settings are managed separately in VibeSpace Settings.

## Getting Started

Open **App Settings** with **Cmd+,** or from the app side menu. The settings view uses a sidebar on the left and the selected category on the right.

## Workflows

### Appearance

Use **Appearance** for visual and chrome settings:

- window appearance mode
- theme preset and custom theme tokens
- font family, font size, rail terminal font scale, and text color
- border shape and border visibility
- default rail position and app side menu dock

### Keyboard Shortcuts

Use **Keyboard Shortcuts** to customize app-wide shortcuts and the terminal inline trigger. VibeSpace command shortcuts and project shortcut slots are managed in VibeSpace Settings.

### Terminal

Use **Terminal** for shell defaults, terminal engine selection, and tmux integration behavior.

### AI Services And Agents

Use **AI Services** for text action CLI defaults and prompt templates. Use **Agents** for ACP/default agent settings, model/reasoning defaults, and custom agents.

### Connections

Use **Connections** for SSH profile management.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+, | Open App Settings |

## Settings / Configuration

| Category | What It Contains |
|----------|------------------|
| Account | Sign in/out |
| Appearance | Theme, typography, borders, and app chrome defaults |
| Keyboard Shortcuts | App-wide shortcut bindings and terminal inline trigger |
| Terminal | Shell, engine, and tmux controls |
| AI Services | Text action CLI defaults and prompt templates |
| Agents | ACP/default agent settings and custom agents |
| Updates | Auto-check and appcast feed |
| Experimental | Feature gates |
| Connections | Remote SSH profiles |
| Reset | Local reset action |

## Troubleshooting

If a setting seems missing, check whether it is vibespace-scoped. Project shortcuts, project colors, startup overrides, and project shell overrides live in VibeSpace Settings.

## Known Limitations

None.
