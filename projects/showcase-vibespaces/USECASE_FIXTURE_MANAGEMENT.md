# Use-Case and Fixture Management

`projects/showcase-vibespaces` contains deterministic vibespace fixtures used for demos and UI scenario validation.

## Purpose

- Represent realistic multi-project use cases for product demos.
- Support stable UI showcase runs and manual walkthrough verification.
- Keep fixture structure predictable so screenshots and test flows remain reproducible.

## Use-Case Buckets

- `engineer-workbench-*`: software engineering workflow scenarios.
- `multi-repo`: platform/operations workflow scenarios.
- `parent-child`: monorepo and nested project workflows.
- `writing-studio`: authoring and publishing workflows.

## Change Workflow

1. Identify scenario goal (which user journey is being represented).
2. Update only the minimum fixture files/folders needed.
3. Keep filenames and directory names human-readable and stable.
4. If a fixture change affects screenshots or showcase flows, rerun showcase capture:
   - `xcodebuild test -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes -destination 'platform=macOS' -only-testing:CrispyVibesUITests`
5. Refresh demo assets if output changed.

## Guardrails

- Do not add sensitive/real credentials or production data.
- Prefer small representative files over large binary payloads.
- Keep cross-fixture naming consistent to reduce maintenance cost.
