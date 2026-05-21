# Crispy Threat Model

Last updated: 2026-04-16

## 1. System Overview

Crispy is a native macOS IDE (Swift/SwiftUI, macOS 26+) with integrated terminal, SSH remote development, file editing, and vibespace management. Bundle ID: `com.crispyvibe.app`.

### Trust Boundaries

```
┌─────────────────────────────────────────────────────────┐
│  User's macOS Machine                                   │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Crispy.app (sandboxed/signed)                     │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │  │
│  │  │ Terminal  │ │ Editor   │ │ VibeSpace Mgmt   │  │  │
│  │  │ (Ghostty/ │ │ (WKWeb-  │ │ (HMAC-signed     │  │  │
│  │  │ SwiftTerm)│ │  View)   │ │  JSON configs)   │  │  │
│  │  └────┬─────┘ └────┬─────┘ └────────┬─────────┘  │  │
│  │       │             │                │            │  │
│  │  ┌────┴─────────────┴────────────────┴─────────┐  │  │
│  │  │  macOS Keychain (HMAC keys, auth tokens)    │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  └───────────────┬───────────────┬───────────────────┘  │
│                  │               │                       │
└──────────────────┼───────────────┼───────────────────────┘
                   │               │
        ┌──────────┴──┐    ┌──────┴──────────┐
        │ Remote SSH  │    │ External Services│
        │ Hosts       │    │ - Cognito Auth   │
        │ (system ssh │    │ - Sparkle Update │
        │  Control-   │    │ - crispyvibe.com   │
        │  Master)    │    │                  │
        └─────────────┘    └──────────────────┘
```

### Key Assets

| Asset | Storage | Sensitivity |
|-------|---------|-------------|
| HMAC signing key | macOS Keychain | High — guards vibespace config integrity |
| Cognito auth tokens | macOS Keychain | High — user identity |
| SSH private keys | User's `~/.ssh` / SSH agent | Critical — remote host access |
| VibeSpace configs | `~/Library/Application Support/CrispyVibes/` | Medium — contain project paths, startup commands |
| Sparkle EdDSA public key | Info.plist (`SUPublicEDKey`) | Medium — update verification anchor |
| User source code | Local filesystem / SFTP | High — intellectual property |

## 2. Threat Categories (STRIDE)

### T1 — Spoofing

| ID | Threat | Component | Mitigation | Status |
|----|--------|-----------|------------|--------|
| T1.1 | Forged vibespace config triggers malicious startup commands | VibeSpacePersistenceStore | HMAC-SHA256 signature verification; untrusted configs block command execution | ✅ Mitigated |
| T1.2 | Rogue Sparkle update feed serves malicious binary | AppDelegateUpdates | EdDSA signature verification via `SUPublicEDKey`; code signing + notarization | ✅ Mitigated |
| T1.3 | Spoofed SSH host key during remote connection | SSHConnection (system ssh) | Preflight check via ssh-keygen against known_hosts; BatchMode=yes prevents interactive prompts. `.acceptAnything()` fallback replaced with `KnownHostsValidator` + `HostKeyUnknownError` (scan H3 — fixed 2026-04) | ✅ Mitigated |
| T1.4 | Browser panel spoofs Safari user agent | BrowserPanelViewModel | Common practice for embedded WebKit browsers; no direct vulnerability (scan M9) | ✅ Accepted risk |
| T1.5 | PKCE code verifier falls back to UUID if SecRandomCopyBytes fails | CognitoAuthSecurity | Near-zero probability of CSPRNG failure on macOS; UUID still provides 122 bits of entropy (scan L5) | ✅ Accepted risk |

### T2 — Tampering

| ID | Threat | Component | Mitigation | Status |
|----|--------|-----------|------------|--------|
| T2.1 | Tampered `vibespace.json` or `projects/<hash>.json` on disk | VibeSpacePersistenceStore | HMAC signature check on load; tampered files treated as untrusted | ✅ Mitigated |
| T2.2 | Tampered `layout.json` | LayoutPersistenceService | Unsigned — contains no executable content (UI layout only) | ✅ Acceptable risk |
| T2.3 | Modified app bundle post-install | macOS Gatekeeper | Code signing + notarization; Gatekeeper blocks tampered bundles | ✅ Mitigated |
| T2.4 | Man-in-the-middle on update feed | Sparkle | HTTPS transport + EdDSA signature on update payloads | ✅ Mitigated |
| T2.5 | HMAC verification uses non-constant-time string comparison | AppPersistenceDataStore | Local file I/O only (not network-exposed); practical timing attack infeasible. Consider using `HMAC.isValidAuthenticationCode` for best practice (scan M1) | ⚠️ Low risk — accepted |

### T3 — Repudiation

| ID | Threat | Component | Mitigation | Status |
|----|--------|-----------|------------|--------|
| T3.1 | User denies executing a terminal command | Terminal sessions | No audit logging of terminal commands | ⚠️ Accepted — IDE is single-user |

### T4 — Information Disclosure

| ID | Threat | Component | Mitigation | Status |
|----|--------|-----------|------------|--------|
| T4.1 | Keychain items accessible by other apps | macOS Keychain | Keychain items scoped to app bundle ID; code signing enforces access | ✅ Mitigated |
| T4.2 | VibeSpace configs expose project paths on disk | VibeSpacePersistenceStore | Files stored in user-owned `~/Library/Application Support/`; standard macOS file permissions | ✅ Acceptable risk |
| T4.3 | SSH credentials leaked through logs or crash reports | SSHConnection | Verify no credential logging in debug/release builds | ⚠️ Review needed |
| T4.4 | Cognito tokens persisted insecurely | CognitoAuthSecurity | Tokens stored in Keychain | ✅ Mitigated |
| T4.5 | Remote file content cached in temp staging files | SFTPFileContentProvider | Staged preview files in temp directory; cleanup on document change | ⚠️ Verify cleanup completeness |
| T4.6 | Diagnostics export includes CLI command configuration | AppDiagnostics | User-initiated export only; data is operational, not credential-level. Consider redacting CLI args (scan M8) | ⚠️ Low risk — accepted |
| T4.7 | WKWebView granted root filesystem read access | MarkupRenderedEditor | Required for editor to resolve relative image/asset paths across user projects; same model as mainstream IDE webviews. Security boundary is same-origin policy + app-controlled top-level page (scan L3) | ✅ Accepted risk |
| T4.8 | Browser WKWebView inspectable in all builds | BrowserPanelViewModel | Web Inspector is an expected developer tool capability; same as Chrome/Safari/Firefox shipping with dev tools (scan L4) | ✅ Accepted risk |

### T5 — Denial of Service

| ID | Threat | Component | Mitigation | Status |
|----|--------|-----------|------------|--------|
| T5.1 | Malicious vibespace with excessive terminal startup count | VibeSpaceManagementService | `startupTerminalCount` clamped to 1–8 (INV-001) | ✅ Mitigated |
| T5.2 | Extremely large remote directory listing exhausts memory | RemoteFolderExplorer | Lazy-load only expanded directories | ✅ Mitigated |
| T5.3 | Corrupted vibespace directory blocks app launch | VibeSpaceManagementService | Incomplete vibespace directories pruned on launch | ✅ Mitigated |

### T6 — Elevation of Privilege

| ID | Threat | Component | Mitigation | Status |
|----|--------|-----------|------------|--------|
| T6.1 | Crafted vibespace config executes arbitrary commands on open | VibeSpacePersistenceStore + TextProcessorService | HMAC verification blocks startup commands from untrusted configs | ✅ Mitigated |
| T6.2 | macOS Service input triggers unintended shell execution | TextProcessorService (rephrase/research) | Service input is text-only; commands are preset-defined, not user-injected. Arguments passed as array (no shell). Consider prepending `--` before user text to prevent flag injection (scan M3) | ⚠️ Verify input sanitization |
| T6.3 | URL scheme handler processes malicious deep links | Info.plist (`CFBundleURLSchemes`) | Verify URL scheme input validation | ⚠️ Review needed |
| T6.4 | WKWebView JavaScript bridge escalation | MarkdownRuntime | CSP meta tag added to editor.html restricting script/resource origins (scan H4 — fixed 2026-04) | ✅ Mitigated |
| T6.5 | DistributedNotificationCenter spoofing triggers file opens | AppDelegate IPC | senderPID check prevents self-delivery only | ⚠️ Any process can spoof — see scan M5 |
| T6.6 | Git clone hook execution from malicious repository | PaneWorkerExecutorGitCloneSupport | `--` separator prevents flag injection | ⚠️ Inherent to git — accepted risk |
| T6.7 | Sparkle feed URL override via UserDefaults | AppPreferences + Sparkle | EdDSA signature verification on update payloads | ✅ Mitigated by EdDSA |
| T6.8 | File drop onto terminal injects shell commands via unescaped metacharacters | TerminalSessionHostView | Now uses `ShellEscaping.singleQuote` for full metacharacter escaping (scan H5 — fixed 2026-04) | ✅ Mitigated |
| T6.9 | Directory watcher follows symlinks outside project scope | DirectoryWatcher | `open(path, O_EVTONLY)` follows symlinks | ⚠️ Low impact — see scan M12 |
| T6.10 | No App Sandbox entitlements — app runs with full user-level access | crispyvibes entitlements | Standard for IDEs; any code execution vulnerability has full user-level access. Consider adding specific entitlements to signal intent (scan M2) | ⚠️ Accepted risk |
| T6.11 | Ghostty loads user config files with no validation | GhosttyTerminalEngineSurfaceConfig | Expected behavior for terminal emulators; user controls their own config. Malicious config requires prior compromise of user account (scan M10) | ✅ Accepted risk |
| T6.12 | Terminal URL handler opens arbitrary URLs via NSVibeSpace | GhosttyTerminalEngine | User-initiated (clicking link in terminal output); same behavior as mainstream terminal emulators. Consider filtering dangerous URL schemes like `applescript://` (scan M11) | ⚠️ Low risk — review URL scheme filtering |

## 3. Attack Surface Summary

### External Inputs

| Input | Entry Point | Trust Level |
|-------|-------------|-------------|
| VibeSpace JSON files | VibeSpacePersistenceStore | Untrusted until HMAC verified |
| SSH host responses | SSHConnection (system ssh) | Untrusted network |
| Sparkle update feed | AppDelegateUpdates | Untrusted until EdDSA verified |
| Cognito auth responses | CognitoAuthService | Untrusted network (HTTPS) |
| macOS Service text input | AppDelegate service handlers | Untrusted (any app can invoke) |
| URL scheme invocations | App URL handler | Untrusted (any app can invoke) |
| Files opened via Finder / drag-and-drop | Document type handlers | Untrusted user content |
| Remote SFTP file content | SFTPFileContentProvider | Untrusted network |
| Markdown/HTML content rendered in WKWebView | Editor feature | Untrusted user content |

### Shell Execution Points

| Component | Execution Method | Input Source |
|-----------|-----------------|--------------|
| Terminal sessions | GhosttyKit / SwiftTerm PTY | User interactive |
| TextProcessorService | Shell command execution | Preset catalog commands + selected text |
| Terminal presets | Preset-defined CLI commands | TextServiceCLIPresetCatalog |
| Remote terminal | `/usr/bin/ssh -t` spawn | SSH connection profile |
| macOS "open in terminal" service | Terminal session with path | Finder-provided file path |

## 4. Existing Security Controls

| Control | Implementation |
|---------|---------------|
| Config integrity | HMAC-SHA256 signing of vibespace and project configs |
| Keychain storage | HMAC keys and auth tokens stored in macOS Keychain |
| Code signing | Developer ID Application signing (team `45G2XY67YF`) |
| Notarization | Apple notarization for Gatekeeper approval |
| Update verification | Sparkle EdDSA signature verification |
| SSH auth model | Key-based only; password auth intentionally unsupported |
| Atomic writes | `Data.write(to:options:.atomic)` for crash-safe persistence |
| Input clamping | Startup terminal count clamped 1–8; shortcut indices 1–9 |
| Untrusted config handling | Tampered configs load for display but block command execution |

## 5. Recommended Actions

| Priority | Action | Threat |
|----------|--------|--------|
| ~~High~~ | ~~Fix SSH `.acceptAnything()` fallback~~ | T1.3 / H3 ✅ Fixed 2026-04 |
| ~~High~~ | ~~Add CSP to editor.html or sanitize marked.js HTML output~~ | T6.4 / H4 ✅ Fixed 2026-04 |
| ~~High~~ | ~~Fix terminal drop handler shell escaping~~ | T6.8 / H5 ✅ Fixed 2026-04 |
| Medium | Audit `TextProcessorService` for shell injection via service input text | T6.2 |
| Medium | Audit URL scheme handler for input validation | T6.3 |
| Medium | Replace DistributedNotificationCenter IPC with XPC or add sender validation | T6.5 / M5 |
| Medium | Audit SSH/SFTP code paths for credential logging | T4.3 |
| Medium | Verify temp file cleanup for remote binary previews | T4.5 |
| Low | Consider redacting CLI config from diagnostics export | T4.2 / M8 |
| Low | Consider adding entitlements to restrict app capabilities | General hardening |
| Low | Document accepted risks for single-user threat model | T3.1 |
