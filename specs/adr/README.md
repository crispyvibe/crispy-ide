# Architecture Decision Records

Status: active

## Convention

Each ADR is a numbered markdown file: `{NNN}-{title}.md`

```
specs/adr/
  README.md
  001-four-doc-feature-convention.md
  002-domain-based-organization.md
  ...
```

### Template

```markdown
# ADR-{NNN}: {Title}

Status: proposed | accepted | deprecated | superseded by ADR-{NNN}
Date: YYYY-MM-DD
Deciders: {names}

## Context

What is the issue that we're seeing that is motivating this decision?

## Decision

What is the change that we're proposing and/or doing?

## Consequences

What becomes easier or more difficult to do because of this change?
```

### Rules

- Numbers are sequential and never reused.
- Status changes are recorded inline (not new files).
- Superseded ADRs link to their replacement.
