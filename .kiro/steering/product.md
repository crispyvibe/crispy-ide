# Product Overview

Crispy is a native macOS terminal-first workspace IDE.

## Purpose

A workspace-oriented IDE that treats the terminal as a first-class citizen. Users organize work into workspaces (collections of projects), with integrated terminal sessions, file editing, git operations, and AI-assisted tooling.

## Target Users

- Professional developers who work across multiple projects simultaneously
- Terminal-heavy workflows (DevOps, backend, full-stack)
- Users who want IDE features without leaving the terminal

## Key Capabilities

- Multi-project workspaces with persistence and session restore
- Terminal sessions with tabs, presets, board layout, spotlight focus mode, and rail previews
- File explorer with git-aware status
- Editor with markdown, code, and preview support
- Source control (git) integration
- AI agent integration (ACP protocol, VibeCast, text services)
- SSH remote development
- macOS-only native experience

## Business Objective

Provide a native macOS IDE that treats the terminal as a first-class citizen, delivering a fast, integrated development environment for developers who live in the terminal.

## Terminology

- **Workspace** — a collection of projects opened together
- **Project** — a single directory within a workspace
- **Spotlight** — modal overlay that expands a terminal to focused view
- **Rail** — compact terminal preview strip alongside the editor
- **Terminal Board** — grid-only canvas mode showing terminal tiles
- **Shelf** — persistent file collection across sessions
- **VibeCast** — AI compose and broadcast feature
- **ACP** — Agent Conversation Protocol for AI agent sessions

## Reference

The Rust rearchitecture at `../crispyvibes-rust/` is extracting requirements from this codebase. This Swift IDE is the reference implementation and source of truth for product behavior.
