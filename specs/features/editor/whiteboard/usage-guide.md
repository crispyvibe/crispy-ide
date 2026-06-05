---
title: "Whiteboarding"
feature: "F052"
domain: "editor"
audience: "user"
version: "1.0"
sidebar:
  label: "Whiteboards"
  order: 9
---

# Whiteboarding

## Overview

Whiteboards give you a freeform canvas for diagrams, sketches, and visual notes — powered by an embedded, fully offline [Excalidraw](https://excalidraw.com). A whiteboard is just a `.excalidraw` file that autosaves as you draw, so you can keep it in a project alongside your code and open it any time. Everything runs locally; no account or internet connection is needed.

## Getting Started

- Click the **pencil-and-scribble** button in the toolbar (next to VibeCast and Todos) to create a **New Whiteboard**.
- It opens immediately on the canvas and is added to your **Shelf** as a draft.
- Draw — your changes save automatically.

## Workflows

### Create a whiteboard
Click **New Whiteboard** in the toolbar. A new `Untitled Whiteboard.excalidraw` is created in the Shelf and opened. (Creating more gives `Untitled Whiteboard 2`, `3`, ….)

### Draw and autosave
Use the Excalidraw tools to add shapes, arrows, text, and freehand drawing. There's no Save button — edits are written to the file automatically a moment after you stop drawing.

### Move a whiteboard into a project
A new whiteboard lives in the Shelf (a staging area) until you give it a home:
1. Open the **Files** sidebar so you can see the Shelf and your project's file tree.
2. **Drag the whiteboard's Shelf row onto a folder** in a project's file tree.
3. The file moves into that folder, the open tab follows it, and it leaves the Shelf.

If a file with the same name already exists in the target folder, your whiteboard is moved in under a numbered name so nothing is overwritten.

### Open an existing whiteboard
Open any `.excalidraw` file from the file explorer (or the Shelf) and it renders on the canvas, ready to edit.

## Keyboard Shortcuts

Drawing shortcuts are Excalidraw's own (e.g. `V` select, `R` rectangle, `O` ellipse, `A` arrow, `T` text, and the usual `⌘Z` / `⇧⌘Z` undo/redo) and are shown in the canvas tools. Crispy adds no extra whiteboard-specific shortcuts in this version.

## Settings / Configuration

- **Appearance:** the canvas follows the app's light/dark theme automatically — there's nothing to configure.

## Troubleshooting

- **Dragging the Shelf row doesn't move it:** drop it onto a folder **inside an open project** (drops outside a project are ignored). Make sure the Files sidebar is showing the project's tree.
- **"The whiteboard runtime is unavailable":** the app build is missing its bundled assets — rebuild/reinstall the app.
- **A brief flicker when moving into a project:** the canvas reloads at its new location; your drawing is preserved.

## Known Limitations

- **No realtime collaboration** — whiteboards are local, single-user, offline files (by design).
- **No command-line interface** for whiteboards yet.
- Opening the same whiteboard in two panes at once reloads each independently rather than sharing one live canvas.
