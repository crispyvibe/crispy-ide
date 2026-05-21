# ADR-001: Four-Document Feature Convention

Status: accepted
Date: 2026-04-15
Deciders: Crispy Team

## Context

Feature documentation was scattered across single `feature.md` files under `docs/features/` with no consistent structure. There was no separation between specs, technical design, threat models, and user-facing guides. The crispyvibes-rust repo established a structured convention that we needed to align with.

## Decision

Adopt the four-document convention from crispyvibes-rust:

- `spec.md` — requirements and BDD scenarios
- `technical-design.md` — architecture, data flow, API contracts
- `threat-model.md` — attack surfaces, trust boundaries, mitigations
- `usage-guide.md` — end-user workflows with Astro-compatible frontmatter

Features are organized under domain folders (D1–D9) with globally unique F{NNN} prefixes. See `specs/features/CONVENTION.md` for full details.

## Consequences

- Every feature ships with 4 reviewed documents.
- Per-feature threat models replace the single global threat model.
- Usage guides serve triple duty: in-app help, website, and repo.
- Higher upfront cost per feature, but better traceability and review coverage.
- Both crispyvibes-ide and crispyvibes-rust repos share the same convention.
