# App Updates — Threat Model

## Overview

App Updates uses the Sparkle framework to check for and install updates from a configurable appcast feed URL. This is one of the few features that performs network I/O — fetching the appcast XML and downloading update packages. The threat surface includes feed URL manipulation, man-in-the-middle attacks on the update channel, and local privilege escalation during installation.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Crispy app ↔ Sparkle framework | Sparkle is a linked framework that manages the full update lifecycle. Crispy delegates feed URL resolution and update UI to Sparkle. |
| Sparkle ↔ Remote appcast server | HTTPS connection to `crispyvibe.com/updates/macos/` (stable or dev channel) or a user-configured custom URL. |
| Sparkle ↔ Downloaded update package | The `.dmg` or `.zip` is downloaded to a temp location, signature-verified, then installed. |
| UserDefaults ↔ Feed URL config | `appUpdateFeedURL` and `appUpdateChannelRaw` are stored in UserDefaults and read by `feedURLString(for:)`. |

## Attack Surfaces

1. **Appcast feed URL** — user-configurable via App Settings; stored in UserDefaults. Determines where Sparkle fetches update metadata.
2. **Network transport** — HTTPS connection to the appcast server. Subject to TLS interception if system trust store is compromised.
3. **Update package signature** — Sparkle verifies Ed25519 signatures embedded in the appcast against the app's public key.
4. **Automatic check interval** — controlled by `AppPreferences.appUpdateAutoCheckInterval`. A manipulated interval could suppress or flood checks.
5. **Feed URL normalization** — `normalizedAppUpdateFeedURL` processes the stored string before passing to Sparkle.

## Threats

### F030-T01: Malicious appcast via custom feed URL

- **Vector:** An attacker with local UserDefaults access (same-user process) changes `appUpdateFeedURL` to a server they control, serving a crafted appcast pointing to a malicious binary.
- **Impact:** If signature verification is bypassed, arbitrary code execution with user privileges.
- **Likelihood:** Very low — Sparkle's Ed25519 signature verification prevents installation of unsigned/mis-signed packages.
- **Mitigation:** Sparkle MUST have Ed25519 public key embedded in the app bundle (`SUPublicEDKey`). Sparkle MUST reject packages whose signature does not match. The app MUST NOT disable Sparkle's signature verification. Linked NFR: SEC-Data-Protection.

### F030-T02: Man-in-the-middle on appcast fetch

- **Vector:** An attacker on the network intercepts the HTTPS connection to the appcast server (e.g., via compromised CA or corporate proxy) and serves a modified appcast.
- **Impact:** Could direct Sparkle to download a malicious package (blocked by signature verification) or suppress updates by serving an empty/old appcast.
- **Likelihood:** Low — requires TLS interception capability.
- **Mitigation:** Sparkle uses HTTPS with standard system TLS validation. Ed25519 signature verification provides defense-in-depth even if TLS is compromised. Certificate pinning is not implemented (acceptable given signature verification). Linked NFR: SEC-Data-Protection.

### F030-T03: Update suppression via interval manipulation

- **Vector:** A local attacker sets `autoUpdateChecksEnabled` to false or sets the check interval to an extremely large value in UserDefaults, preventing the user from receiving security updates.
- **Impact:** User remains on a vulnerable version indefinitely.
- **Likelihood:** Low — requires same-user local access.
- **Mitigation:** Manual "Check for Updates" remains always available via the app menu regardless of automatic check settings. The update channel UI clearly shows the current state. Linked NFR: SEC-Data-Protection.

### F030-T04: Denial of service via invalid feed URL

- **Vector:** Feed URL is set to an invalid or extremely slow endpoint, causing Sparkle to hang or consume resources during update checks.
- **Impact:** Background resource consumption; potential UI stall if manual check blocks.
- **Likelihood:** Low.
- **Mitigation:** Sparkle handles network timeouts internally. Manual checks delegate to Sparkle which shows its own progress/failure UI. The app startup UI remains usable while background checks run (confirmed in `configureSparkleUpdater`). Linked NFR: PERF-Responsiveness.

### F030-T05: Downgrade attack via build number manipulation

- **Vector:** A crafted appcast advertises a package with a lower build number but higher display version, tricking the user into installing an older (vulnerable) build.
- **Impact:** Installation of a known-vulnerable version.
- **Likelihood:** Very low — Sparkle compares build numbers (monotonically increasing) for update ordering.
- **Mitigation:** Update ordering is driven by build number, not display version. Sparkle's `SUFeedItem` comparison uses `sparkle:version` (build number) as the canonical ordering value. Linked NFR: SEC-Data-Protection.

## Residual Risks

- A user who intentionally configures a custom feed URL accepts the risk of that feed's trustworthiness. Signature verification remains the final gate.
- If the Ed25519 private key used to sign updates is compromised at the build server, all update channels are affected. This is an operational security concern outside the app's control.
- Sparkle's installer runs with user privileges and may require admin authentication for `/Applications` installs — this is standard macOS behavior.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Data-Protection | Compliant | Ed25519 signature verification; HTTPS transport; no secrets in defaults. |
| PERF-Responsiveness | Compliant | Background checks don't block startup UI. |
| SEC-Input-Sanitization | Compliant | Feed URL normalized before use; Sparkle handles URL validation. |
