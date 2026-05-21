# Agent Board — Spec

Status: vision

## Overview

The Agent Board is a project-scoped coordination surface for multi-phase agent work. It coordinates development workflows (plan → build → verify → review) across agent conversations, terminal runs, and source-control state without replacing those underlying systems.

Full spec to be written in Phase D of the [Agent Platform Implementation Plan](../../../planning/agent-platform-implementation-plan.md).

## Vision Document

See [Agent Board Vision](../../../planning/agent-board-vision.md) for the complete product vision, domain model, UX model, and first-slice recommendation.

## Dependencies

- F040 (Agent Conversation Persistence) — provides the thread model, persistence infrastructure, and session resume that the board builds on
- F011 (ACP) — provides the agent session lifecycle and transport
- F001 (Terminal Sessions & Tabs) — verification phases use terminal infrastructure
- F026 (Git Operations) — review phases read source-control state

## Requirements

Requirements will be defined in Phase D of the implementation plan. The vision document identifies these key areas:

- Board per project with entry point in project surfaces
- Workflow templates (built-in catalog, project default, card-level override)
- Work card lifecycle (create, advance, retry, pause, archive)
- Phase automation policies
- Card detail inspector
- Needs-input flow with direct navigation to blockers
- Artifact links to conversations, terminal runs, source control
- Board and window naming conventions
