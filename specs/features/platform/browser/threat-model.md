# Browser — Threat Model

## Overview

The in-app browser embeds WKWebView to render arbitrary web content within the vibespace. It performs network I/O (page loads, downloads, search suggestions, SSH proxy), executes JavaScript (find-in-page, console capture, element picker, agent API), handles file uploads/downloads, imports browser history from external SQLite databases, and supports WebAuthn passkey flows. The threat surface is significantly broader than most features due to exposure to untrusted remote content.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Crispy app process ↔ WKWebView content process | WebKit runs web content in a separate process. JavaScript bridge messages cross this boundary. |
| Browser ↔ Remote web servers | Arbitrary HTTPS/HTTP connections to user-navigated URLs. |
| Browser ↔ Local filesystem | File uploads via NSOpenPanel, downloads via NSSavePanel, local file URL loading. |
| Browser ↔ External SQLite databases | Chrome/Safari history import reads SQLite files from `~/Library/`. |
| Agent API ↔ Web content | Agent commands execute arbitrary JavaScript in the page context. |
| Browser ↔ SSH SOCKS5 proxy | Traffic routed through SSH tunnel for remote browsing. |
| JavaScript bridge ↔ ASAuthorizationController | WebAuthn passkey operations bridge between web content and system auth. |
| Browser ↔ BrowserHistoryStore | Frecency-ranked history persisted as JSON; contains visited URLs. |

## Attack Surfaces

1. **Injected JavaScript** — find-in-page, console capture, element picker, theme injection, and agent API all inject JS into page context.
2. **Agent API command dispatch** — 84+ commands that can navigate, click, fill forms, execute JS, and take screenshots programmatically.
3. **Address bar URL resolution** — user input is classified as URL vs. search query; incorrect classification could navigate to unintended destinations.
4. **Insecure HTTP allowlist** — wildcard patterns in `customInsecureHTTPAllowlist` could be overly broad.
5. **Browser history JSON persistence** — contains all visited URLs in plaintext on disk.
6. **SQLite history import** — reads Chrome/Safari databases; SQL injection if query construction is flawed.
7. **Download handling** — files downloaded to user-chosen locations; MIME type determines download trigger.
8. **Search suggestions fetch** — sends user keystrokes to Google Suggest API with 250ms debounce.
9. **Named profile data stores** — isolated WKWebsiteDataStore per profile; profile metadata in JSON.
10. **WebAuthn bridge** — intercepts `navigator.credentials` calls and delegates to system APIs.

## Threats

### F012-T01: Cross-site scripting via injected JavaScript

- **Vector:** Crispy injects JavaScript for find-in-page, console capture, and element picker. If page content can influence the injected script (e.g., via DOM manipulation that alters expected element structure), it could hijack the injection context.
- **Impact:** Page-level XSS within the WKWebView sandbox; potential data exfiltration from the page.
- **Likelihood:** Low — injected scripts use `WKUserScript` or `evaluateJavaScript` with static templates; page content cannot modify the injection source.
- **Mitigation:** All injected JavaScript MUST be static templates that do not interpolate page-derived values into executable code. `TreeWalker`-based find uses text node comparison, not innerHTML parsing. Console capture overrides are set at document-start. Linked NFR: SEC-Input-Sanitization.

### F012-T02: Agent API enables arbitrary JavaScript execution

- **Vector:** The `browser.eval` command executes arbitrary JavaScript provided by the agent. A compromised or malicious agent could exfiltrate page data, modify DOM, or interact with authenticated sessions.
- **Impact:** Full page-context control — cookie theft, form manipulation, data exfiltration.
- **Likelihood:** Medium — by design, the agent API has full page control. Risk depends on agent trust model.
- **Mitigation:** Agent API access MUST be gated by the ACP permission system. The `browser.eval` command SHOULD be logged in ACP observability. Agent sessions require explicit user initiation. The browser runs in WKWebView's process sandbox, limiting system-level impact. Linked NFR: SEC-Input-Sanitization.

### F012-T03: URL spoofing via address bar resolution logic

- **Vector:** Crafted input that looks like a search query but resolves as a URL (or vice versa) could navigate the user to a phishing site. For example, input like `evil.com login.bank.com` might be treated as a URL.
- **Impact:** User navigates to attacker-controlled site believing it's a search result.
- **Likelihood:** Low — resolution logic checks for dots/colons (URL) vs. spaces (search).
- **Mitigation:** Address bar resolution follows explicit rules: contains "localhost" → http://, contains dot or colon → https://, contains spaces or no pattern match → search query. The address bar MUST always display the actual loaded URL after navigation completes. Linked NFR: SEC-Input-Sanitization.

### F012-T04: Browsing history leakage from JSON persistence

- **Vector:** The `BrowserHistoryStore` persists up to 5000 URL entries as JSON in the app's data directory. Any same-user process can read this file.
- **Impact:** Disclosure of user's browsing history within Crispy.
- **Likelihood:** Medium — file is plaintext, accessible to same-user processes.
- **Mitigation:** History is stored in the app's sandboxed data directory. `clearBrowsingData()` removes both history JSON and WKWebsiteDataStore data. Users can clear history on demand. No history is transmitted externally. Linked NFR: SEC-Data-Protection.

### F012-T05: SQL injection in browser history import

- **Vector:** `BrowserDataImporter` reads Chrome/Safari SQLite databases using hardcoded SQL queries. If the query construction were dynamic, malicious database content could inject SQL.
- **Impact:** Arbitrary SQLite operations on the imported database (read-only risk since import only reads).
- **Likelihood:** Very low — queries are static string literals with no interpolation of external values.
- **Mitigation:** Import queries are compile-time constants (confirmed in `BrowserDataImporter`). No user input is interpolated into SQL. The databases are opened read-only. Safari import uses a temp file copy to avoid locking the live database. Linked NFR: SEC-Input-Sanitization.

### F012-T06: Insecure HTTP allowlist bypass

- **Vector:** Overly broad wildcard patterns in `customInsecureHTTPAllowlist` (e.g., `*`) could disable HTTP blocking entirely, exposing the user to network sniffing on all HTTP connections.
- **Impact:** Credentials and data transmitted in cleartext.
- **Likelihood:** Low — requires user to explicitly configure broad patterns.
- **Mitigation:** Default allowlist is limited to localhost variants (127.0.0.1, ::1, 0.0.0.0, localhost). Custom patterns require explicit user action. The insecure HTTP alert provides three options (Open in Default Browser, Proceed, Cancel) for non-allowlisted hosts. Linked NFR: SEC-Data-Protection.

### F012-T07: Download path traversal or overwrite

- **Vector:** A malicious server sends a `Content-Disposition` header with a filename containing path traversal characters (e.g., `../../.ssh/authorized_keys`).
- **Impact:** File written to unexpected location.
- **Likelihood:** Very low — downloads use NSSavePanel which shows the user the exact save location; WebKit sanitizes suggested filenames.
- **Mitigation:** Downloads use a two-phase flow: temporary file then NSSavePanel for final location. The user explicitly confirms the save path. WebKit's download delegate sanitizes the suggested filename. Linked NFR: SEC-Input-Sanitization.

### F012-T08: Search suggestion privacy leakage

- **Vector:** Address bar keystrokes are sent to Google Suggest API after 250ms debounce when `searchSuggestionsEnabled` is true. This leaks partial queries to Google.
- **Impact:** Privacy — partial URLs, search terms, and potentially sensitive text sent to third party.
- **Likelihood:** Medium — enabled by default (per spec).
- **Mitigation:** Search suggestions are configurable (`searchSuggestionsEnabled`). Requests time out after 1 second. Users can disable remote suggestions. Only the query text is sent, not browsing context. Linked NFR: SEC-Data-Protection.

### F012-T09: WebAuthn relay attack via JavaScript bridge

- **Vector:** A malicious page crafts a `navigator.credentials.create/get` call with attacker-controlled parameters, attempting to register a passkey for an attacker's relying party or authenticate to an unintended service.
- **Impact:** Credential confusion — user creates passkey for wrong relying party.
- **Likelihood:** Low — ASAuthorizationController shows the relying party domain to the user for confirmation.
- **Mitigation:** WebAuthn operations are delegated to `ASAuthorizationController` which displays the relying party to the user. The system enforces origin validation. The `LeakAvoider` pattern prevents retain cycles but does not affect security. Linked NFR: SEC-Data-Protection.

### F012-T10: Resource exhaustion via console message flooding

- **Vector:** A malicious page floods `console.log()` to fill the 512-entry capture buffer rapidly, consuming memory and potentially causing UI lag in the developer tools view.
- **Impact:** Minor memory pressure; developer tools UI slowdown.
- **Likelihood:** Low.
- **Mitigation:** Console capture is capped at 512 entries with `flushConsoleMessages()`. The buffer is fixed-size. Developer tools auto-refresh is on a 2-second timer, not per-message. Linked NFR: PERF-Responsiveness.

## Residual Risks

- WKWebView runs web content in a sandboxed process, but the app has full access to the JavaScript bridge. A WebKit zero-day could potentially escape the content process sandbox — this is mitigated by macOS system updates.
- The agent API intentionally provides full page control. Trust in the agent is the security boundary, not the browser feature itself.
- Named browser profiles share the same app process. Profile isolation is at the WKWebsiteDataStore level (cookies, storage) but not at the process level.
- Local file URL loading grants read access to the parent directory — this is by WebKit design and limited to explicitly loaded local files.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Static JS templates; no SQL interpolation; URL resolution rules enforced. |
| SEC-Data-Protection | Compliant | History clearable; downloads user-confirmed; suggestions configurable. |
| PERF-Responsiveness | Compliant | Console capped; suggestions debounced; crash recovery transparent. |
| A11Y | Partial | VoiceOver keyboard navigation planned (F012-S79). |
| OBS | Compliant | Agent API actions logged via ACP observability when enabled. |
