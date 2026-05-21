# NFR: Accessibility

## Scope

Requirements for making the application usable by people with disabilities, following WCAG 2.1 AA and platform accessibility guidelines.

## Requirements

### A11Y-1: Screen Reader Support

- All interactive elements MUST have appropriate semantic roles, labels, and states.
- Dynamic content updates MUST use live regions where appropriate (configurable to avoid noise).
- Navigation landmarks MUST be defined for all major UI regions.
- Focus order MUST follow logical reading order.

### A11Y-2: Keyboard Navigation

- Every feature MUST be operable via keyboard alone.
- Focus MUST be visually indicated with a high-contrast ring (minimum 3:1 contrast ratio).
- Tab order within panels MUST be logical and predictable.
- Modal overlays MUST trap focus and return it to the trigger element on dismiss.
- Keyboard shortcuts MUST be documented and discoverable within the application.

### A11Y-3: Color and Contrast

- All text MUST meet WCAG AA contrast ratios: 4.5:1 for normal text, 3:1 for large text.
- Information MUST NOT be conveyed by color alone — always provide a secondary differentiator (shape, label, animation, pattern).
- At least one high-contrast theme MUST be available.

### A11Y-4: Text and Zoom

- The UI MUST remain functional at 200% zoom.
- Font sizes MUST be user-configurable or use relative units.
- Text MUST NOT be clipped or overlapped at any supported zoom level.

### A11Y-5: Motion

- Users MUST be able to disable animations via a setting or by respecting `prefers-reduced-motion`.
- All transitions and animated indicators MUST be suppressed when reduced motion is preferred.
- No content may flash at rates exceeding 3 per second.

### A11Y-6: Test Identifiers

- All interactive elements MUST have stable identifiers for automated accessibility testing.
- Naming convention: `{feature}.{component}.{action}`.
- Identifiers MUST be stable across releases.

### A11Y-7: Platform Integration

- macOS: Respect system accessibility settings (increased contrast, reduce transparency, reduce motion).
- Windows: Support High Contrast mode — UI MUST remain usable with system-forced colors.
- Respect system font size preferences where applicable.

## Verification

- Automated accessibility audit (Lighthouse or axe-core) on every PR.
- Manual screen reader testing (VoiceOver, Narrator) before each release.
- Keyboard-only navigation smoke test in CI.
