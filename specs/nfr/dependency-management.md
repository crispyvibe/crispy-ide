# NFR: Dependency Management

## Scope

Requirements for managing all application dependencies — backend and frontend.

## Requirements

### DEP-1: VibeSpace Structure

- The project MUST use a monorepo vibespace with domain-separated modules.
- Shared dependencies MUST be declared centrally to enforce version consistency.
- No module may introduce a dependency that duplicates functionality already provided by an existing dependency.

### DEP-2: Selection Criteria

- Prefer actively maintained libraries with broad adoption and no unnecessary `unsafe` usage.
- Platform-specific dependencies MUST be conditionally compiled — not included on unsupported targets.
- Vendored or forked dependencies MUST be documented with version, source, license, and rationale.

### DEP-3: Version Pinning

- Lock files MUST be committed for all package managers.
- Dependency updates MUST go through dedicated PRs with diff review.
- Major version bumps require changelog review and migration notes.

### DEP-4: Frontend Minimalism

- Frontend dependencies MUST be kept minimal — only what is required for core UI functionality.
- No large framework unless justified by complexity. Prefer lightweight, purpose-specific libraries.

### DEP-5: License Compliance

- All dependencies MUST use licenses compatible with the project license.
- An allowlist of approved licenses MUST be enforced in CI.
- Any copyleft dependency requires explicit approval and an isolation plan.

### DEP-6: Build Reproducibility

- Builds MUST be reproducible given the same commit, toolchain version, and OS.
- Toolchain versions MUST be pinned via configuration files committed to the repository.

### DEP-7: Hygiene

- Duplicate transitive dependencies MUST be minimized — zero duplicates for security-critical categories (crypto, serialization).
- Unused dependencies MUST be detected and removed in CI.
- Feature flags on dependencies MUST be explicitly listed — no blanket "all features" usage.

## Verification

- CI runs dependency audit, license check, and unused dependency detection.
- PR template includes a dependency change checklist.
- Quarterly review for staleness and vulnerability backlog.
