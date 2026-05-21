# Organization, Validation, and Coding Guidelines

This file defines how fixture content should be organized and maintained.

## File Organization

- Group by top-level scenario family first, then by vibespace/project.
- Keep directory depth intentional; avoid unnecessary nesting.
- Use descriptive names that match user-visible context in demos.
- Preserve stable file paths to avoid breaking scripted captures.

## Validation Expectations

There is no dedicated Xcode test target in this folder, but fixture changes still require validation:

1. Run the showcase UI capture flow:
   - `xcodebuild test -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes -destination 'platform=macOS' -only-testing:CrispyVibesUITests`
2. Confirm the run completes without missing-file errors.
3. Verify generated screenshots/manifest reflect the intended scenario changes.

## Coding Guidelines For Fixture Code

Some fixture projects include source files for realism. Keep those files:

- Simple and readable (illustrative, not production-grade complexity).
- Free from external dependency assumptions that break portability.
- Deterministic (avoid requiring network calls or machine-local secrets).
- Consistent with language defaults used by each fixture project.

## Maintenance Checklist

- Scenario intent is still clear from folder and file names.
- Fixture remains compatible with current showcase scripts.
- No stale temporary artifacts are committed.
