# F017 — Onboarding

Status: draft

Sub-feature of **App Shell**.
Covers the walkthrough, disclaimer gate, first-run experience, and re-access from settings.

---

## Scenarios

### F017-S01 · First launch — disclaimer blocks the app (WLK-001)

```gherkin
Feature: Disclaimer gate

  Scenario: First launch — disclaimer blocks the app
    Given the user has never accepted the disclaimer
    And AppPreferences.onboardingDisclaimerAcceptedKey is not set in UserDefaults
    When the app launches and resolves disclaimer state
    Then shouldPresentDisclaimer is true
    And the vibespace content is hidden (allowsHitTesting false, accessibilityHidden true)
    And HomeWelcomeSurfaceView renders the disclaimerGate view

  Scenario: Disclaimer content
    Given the disclaimer gate is displayed
    Then it shows the CrispyVibes brand lockup (logo, title, tagline)
    And lists the following disclaimer points:
      | Telemetry notice          |
      | Crash reporting notice    |
      | As-is disclaimer          |
      | Liability disclaimer      |
      | "Just you and your vibe"  |
    And a keychain storage note is displayed
    And two action buttons are available: "Quit" and "Accept and Continue"

  Scenario: Accept the disclaimer
    Given the disclaimer gate is displayed
    When the user taps "Accept and Continue"
    Then vibespaceManagement.setAcceptedDisclaimer(true) persists acceptance
    And hasAcceptedDisclaimer becomes true
    And the disclaimer gate is dismissed, revealing the home surface

  Scenario: Quit from disclaimer
    Given the disclaimer gate is displayed
    When the user taps "Quit"
    Then NSApplication.shared.terminate is called and the app exits

  Scenario: Subsequent launches skip the disclaimer
    Given the disclaimer was previously accepted
    When the app launches
    Then hasAcceptedDisclaimer resolves to true
    And the disclaimer gate is not shown
```

### F017-S02 · Walkthrough auto-presentation (WLK-002)

```gherkin
Feature: Walkthrough auto-presentation

  Scenario: Auto-present walkthrough on first vibespace open
    Given the disclaimer has been accepted
    And featureWalkthroughCompletedKey is not set in UserDefaults
    And the walkthrough feature flag (isWalkthroughEnabled) is true
    When evaluateAutoPresentation(hasVibeSpace: true) is called
    Then the controller sets isPresented = true and resets to step 0

  Scenario: Do not auto-present if no vibespace is open
    Given hasVibeSpace is false
    When evaluateAutoPresentation is called
    Then isPresented remains false

  Scenario: Do not auto-present if already completed
    Given featureWalkthroughCompletedKey is true in UserDefaults
    When evaluateAutoPresentation is called
    Then isPresented remains false

  Scenario: Auto-presentation evaluates only once per session
    Given evaluateAutoPresentation has already been called
    When it is called again
    Then the second call is a no-op (didEvaluateAutoPresentation guard)
```

### F017-S03 · Walkthrough steps (WLK-003)

```gherkin
Feature: Walkthrough steps

  DefaultFeatureWalkthroughStepProvider defines 6 steps:

  Scenario Outline: Display walkthrough step
    Given the walkthrough is presented at step <index>
    Then the overlay shows title "<title>" and message "<message>"
    And a hero image named "<heroImage>" is displayed
    And <annotationCount> annotations are positioned on the hero image at normalized coordinates
    And a keyboard shortcut hint "<shortcutHint>" is shown

    Examples:
      | index | id                   | title                        | heroImage                      | annotationCount | shortcutHint                              |
      | 0     | welcome              | Welcome to Crispy             | WalkthroughWelcome             | 2               | Cmd+Shift+N to create a vibespace         |
      | 1     | vibespace-dashboard  | VibeSpace Dashboard          | WalkthroughDashboard           | 2               | Toolbar: VibeSpace Dashboard              |
      | 2     | views-and-layout     | Views and Layout             | WalkthroughViewsLayout         | 2               | Cmd+D (Detailed), Cmd+T (Terminal Board)  |
      | 3     | project-shortcuts    | Project Navigation           | WalkthroughProjectNavigation   | 2               | Cmd+1 ... Cmd+9 to focus mapped projects  |
      | 4     | terminal-workflow    | Terminal View Enhancements   | WalkthroughTerminalWorkflow    | 2               | Use New Terminal in Terminal Board view    |
      | 5     | complete             | You Are Ready                | WalkthroughReady               | 2               | Toolbar: Walkthrough                      |

  Scenario: Annotations render with callout cards
    Given a step has annotations
    Then each annotation renders a dot (accent-colored circle) at its normalized position
    And a callout card with title and detail text is offset based on placement (topLeading/topTrailing/bottomLeading/bottomTrailing)
```

### F017-S04 · Walkthrough navigation (WLK-004)

```gherkin
Feature: Walkthrough navigation

  Scenario: Advance to next step
    Given the walkthrough is on step 2 of 6
    When the user taps "Next"
    Then currentStepIndex increments to 3
    And progressText updates to "Step 4 of 6"

  Scenario: Go back to previous step
    Given the walkthrough is on step 3
    When the user taps "Back"
    Then currentStepIndex decrements to 2

  Scenario: Back is disabled on first step
    Given the walkthrough is on step 0
    Then the "Back" button is disabled

  Scenario: Complete walkthrough on last step
    Given the walkthrough is on the last step (index 5)
    And the button label reads "Done"
    When the user taps "Done"
    Then featureWalkthroughCompletedKey is set to true in UserDefaults
    And isPresented becomes false and the overlay is dismissed

  Scenario: Skip the walkthrough
    Given the walkthrough is presented at any step
    When the user taps "Skip"
    Then completeWalkthrough is called
    And the completion key is persisted and the overlay is dismissed
```

### F017-S05 · Re-access walkthrough from toolbar (WLK-005)

```gherkin
Feature: Re-access walkthrough

  Scenario: Reopen walkthrough from the toolbar
    Given the walkthrough was previously completed
    And the walkthrough feature flag is enabled
    When the user triggers the walkthrough action from the toolbar
    Then FeatureWalkthroughController.presentFromToolbar() is called
    And the walkthrough resets to step 0 and isPresented becomes true
    And the full overlay is shown again regardless of completion state
```

### F017-S06 · Walkthrough overlay rendering (WLK-006)

```gherkin
Feature: Walkthrough overlay rendering

  Scenario: Overlay blocks interaction with the app
    Given the walkthrough is presented
    Then a full-screen semi-transparent backdrop (black at 45% opacity) covers the window
    And the walkthrough card is centered with max width 980px
    And the card contains: progress text, skip button, title, message, hero slide, shortcut hint, back/next buttons

  Scenario: Accessibility identifiers
    Then the following identifiers are set:
      | walkthrough.container  |
      | walkthrough.progress   |
      | walkthrough.skip       |
      | walkthrough.title      |
      | walkthrough.message    |
      | walkthrough.slide      |
      | walkthrough.shortcut   |
      | walkthrough.previous   |
      | walkthrough.next       |
      | walkthrough.finish     |
```

### F017-S07 · UI test support (WLK-007)

```gherkin
Feature: UI test support

  Scenario: Force walkthrough in UI tests
    Given CRISPYVIBES_UI_TEST_FORCE_WALKTHROUGH=1 is set in the launch environment
    When evaluateAutoPresentation is called
    Then the walkthrough is presented regardless of completion state

  Scenario: Disable auto-presentation in UI tests
    Given CRISPYVIBES_UI_TEST_DISABLE_AUTO_WALKTHROUGH=1 is set
    When evaluateAutoPresentation is called
    Then auto-presentation is suppressed

  Scenario: Reset walkthrough state in UI tests
    Given CRISPYVIBES_UI_TEST_RESET_WALKTHROUGH=1 is set
    Then the completion key is removed from UserDefaults on init

  Scenario: Isolated completion key in UI test mode
    Given CRISPYVIBES_UI_TEST_MODE=1 is set
    Then the completion key is suffixed with ".ui-test" to avoid polluting production state
```

### F017-S08 · First-launch disclaimer blocks app entry (WLK-008)

```gherkin
Feature: First-launch disclaimer gate

  Scenario: Disclaimer is a hard gate on first launch
    Given the user has never accepted the disclaimer
    When the app launches
    Then the disclaimer screen is the first visible experience
    And no home screen, vibespace restoration, or interactive UI is shown behind it
    And the disclaimer cannot be dismissed by Escape, clicking outside, or opening another surface

  Scenario: Disclaimer communicates product terms
    Given the disclaimer screen is displayed
    Then it states: no telemetry, no crash reporting, as-is software, no liability
    And closes with "It is just you and your vibe"
    And exactly two actions are available: "Accept and Continue" and "Quit"
```

### F017-S09 · Guided walkthrough after disclaimer acceptance (WLK-009)

```gherkin
Feature: Post-disclaimer walkthrough

  Scenario: Walkthrough presents after disclaimer acceptance
    Given the user has accepted the disclaimer
    And the walkthrough has not been completed
    When the app proceeds past the disclaimer
    Then a guided walkthrough highlighting key features is presented
    And walkthrough content uses annotated screenshots
```

### F017-S10 · Launching from transient install locations prompts move to Applications

```gherkin
Feature: Install location guard

  Scenario: Launch from DMG, Downloads, or temporary folders
    Given Crispy is launched from a mounted read-only disk image, the Downloads folder, or a temporary system folder
    When application startup begins
    Then the user is prompted to move Crispy to /Applications before normal service registration continues
    And the prompt explains that moving prevents duplicate Open With entries

  Scenario: Accept move to Applications
    Given the move prompt is displayed
    When the user chooses "Move to Applications"
    Then the app is copied or replaced at /Applications/Crispy.app
    And the installed copy is relaunched
    And the transient instance terminates

  Scenario: Decline move to Applications
    Given the move prompt is displayed
    When the user chooses "Not Now"
    Then the current instance continues launching from its existing location

  Scenario: Launch from Applications or developer checkout
    Given Crispy is launched from /Applications, ~/Applications, or another non-transient location
    When application startup begins
    Then no move prompt is shown
```

### F017-S11 · Walkthrough re-access and skip (WLK-010)

```gherkin
Feature: Walkthrough re-access

  Scenario: Walkthrough is skippable after disclaimer
    Given the walkthrough is presented
    When the user chooses to skip
    Then the walkthrough is dismissed and the app proceeds normally

  Scenario: Re-access walkthrough from App Settings
    Given the walkthrough was previously completed or skipped
    When the user opens the walkthrough from App Settings or Help menu
    Then the full walkthrough is presented again from the first step

  Scenario: Re-access walkthrough from Help menu
    Given the walkthrough was previously completed or skipped
    When the user selects the walkthrough option from the Help menu
    Then the walkthrough is presented again
```

### F017-S12 · Keychain permission explanation during onboarding (WLK-011)

```gherkin
Feature: Keychain permission inline explanation

  Scenario: Keychain access is explained before first permission-bound operation
    Given the user has accepted the disclaimer
    When onboarding reaches the point before the first Keychain-bound operation
    Then a brief inline explanation states Crispy stores a local signing key in the macOS Keychain
    And the explanation appears within the onboarding surface (no separate multi-step wizard)

  Scenario: System Keychain prompt appears in context
    Given the user continues past the Keychain explanation
    When the app performs the first Keychain-bound operation
    Then the macOS system Keychain permission prompt appears immediately in context

  Scenario: Denied Keychain permission shows simple retry
    Given the system Keychain prompt was denied
    When the app detects the denial
    Then a simple retry message is shown
    And onboarding does not escalate into a complex recovery wizard
```

---

## Requirements

| ID | Requirement |
|----|-------------|
| F017-R01 | Disclaimer gate blocks all app interaction until accepted; only Quit and Accept actions available |
| F017-R02 | Disclaimer acceptance persists via UserDefaults; subsequent launches skip the gate |
| F017-R03 | Walkthrough auto-presents on first vibespace open after disclaimer acceptance |
| F017-R04 | Walkthrough does not auto-present if no vibespace is open or if already completed |
| F017-R05 | Auto-presentation evaluates only once per session |
| F017-R06 | Walkthrough provides 6 steps with hero images, annotations, and shortcut hints |
| F017-R07 | Walkthrough supports forward/back navigation, skip, and done actions |
| F017-R08 | Completion persists in UserDefaults; done/skip both set the completion key |
| F017-R09 | Walkthrough is re-accessible from toolbar, App Settings, and Help menu |
| F017-R10 | Overlay blocks app interaction with semi-transparent backdrop and centered card |
| F017-R11 | Accessibility identifiers are set on all walkthrough UI elements |
| F017-R12 | UI test environment variables control force-present, disable, reset, and key isolation |
| F017-R13 | Keychain permission is explained inline during onboarding; denied permission shows simple retry |
| F017-R14 | Launches from DMG, Downloads, and temporary folders prompt moving Crispy to /Applications before normal startup continues |
