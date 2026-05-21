# AGENTS.md - projects/showcase-vibespaces

Scope: applies to everything under `projects/showcase-vibespaces/`.

## 1) Fixture Use-Case Management

- This project stores deterministic fixture vibespaces for demos and UI flows.
- Keep scenario intent explicit in directory names and file naming.
- Prefer minimal fixture deltas for scenario updates.

Detailed guidance: `./USECASE_FIXTURE_MANAGEMENT.md`

## 2) Organization and Validation

- Keep fixture paths stable to avoid breaking automated showcase flows.
- Do not commit sensitive data or machine-specific secrets.
- After fixture changes, rerun showcase capture and verify outputs.

Detailed guidance: `./ORGANIZATION_AND_GUIDELINES.md`

## 3) Validation Command

From repo root:

```bash
xcodebuild test \
  -project projects/crispyvibes/crispyvibes.xcodeproj \
  -scheme crispyvibes \
  -destination 'platform=macOS' \
  -only-testing:CrispyVibesUITests
```
