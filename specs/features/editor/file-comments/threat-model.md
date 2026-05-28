# File Comments — Threat Model

## Overview

F049 stores user/agent-authored prose anchored to file ranges in the existing encrypted libSQL database, surfaced through the persistence helper subprocess (already trusted), the local CLI Unix socket (already gated by macOS file permissions and process ancestry checks per F044-T03), and rendered in SwiftUI views. The trust model is single-user, single-machine, with agents running as the user's own subprocesses.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| User/agent ↔ comment composer | Comment body submitted to the store; rendered later in the panel |
| CLI ↔ comment store | `comments.*` JSON-RPC methods accept file paths and bodies from agent processes |
| Persistence helper ↔ libSQL | Comment rows stored encrypted at rest |
| Editor ↔ comment renderer | Markdown subset rendered in SwiftUI; no WKWebView for comment content |

## Attack Surfaces

1. Comment body content (markdown rendering)
2. CLI file path inputs
3. Comment bodies presented to other parts of the app (e.g., observability logs, exports)

## Threats

### F049-T01: Markdown rendering hygiene

- **Vector:** A comment body containing raw HTML, `<script>` tags, or `javascript:` URIs is rendered in the SwiftUI panel.
- **Impact:** None in SwiftUI's native markdown renderer (it does not execute scripts), but residual concern if a future renderer change introduces a WKWebView path or if comments are exported to HTML for sharing.
- **Likelihood:** Low.
- **Mitigation:** Render via `AttributedString(markdown:)` (SwiftUI native), which only honors a safe subset. A whitelist filter strips `<script>`, `<iframe>`, `<object>`, `<embed>`, event handler attributes, and `javascript:` URIs at write time as defense-in-depth. Linked NFR: SEC-Input-Sanitization.

### F049-T02: Path traversal via CLI

- **Vector:** Agent calls `crispy comments add --file ../../etc/passwd ...` to attach a comment to a file outside the vibespace.
- **Impact:** Comment metadata (file path, body) recorded against an arbitrary host file. No file content is read or written, but stored paths could leak in cross-file views or exports.
- **Likelihood:** Low (the CLI Unix socket is gated by `F044-T03` ancestry checks; the calling agent is already trusted as the user). Defense-in-depth still warranted.
- **Mitigation:** `CLICommandRouterCommentsHandlers.handleCommentsAdd` resolves the file path to its canonical form and rejects paths that do not lie within any project root of the active vibespace. Linked NFR: SEC-Input-Sanitization.

### F049-T03: Practical limits / runaway writes

- **Vector:** A misbehaving agent loop posts unbounded comments, growing the database and degrading UI responsiveness.
- **Impact:** Database growth, panel render slowdowns. Not a security threat — robustness only.
- **Likelihood:** Low.
- **Mitigation:** F049-R17 limits enforced in the Rust handler (1,000 active comments per file, 10,000 chars per body, depth 50). Limit violations return `limit_exceeded` and are surfaced as a non-blocking notification. Linked NFR: REL.

### F049-T04: CSS selector storage and replay (HTML / browser surfaces)

- **Vector:** Comments anchored to HTML preview iframes and browser windows store a CSS selector path (e.g., `"#hero > article > h2:nth-of-type(3)"`) in the persistence helper. A malicious or misbehaving agent could persist arbitrary selector strings.
- **Impact:** Selectors are passed only to `document.querySelector(...)` — which performs CSS matching, not script execution. There is no DOM-based code execution risk. The selector string is bounded to 1 KB at write time, so storage cannot be weaponized for resource exhaustion.
- **Likelihood:** Low.
- **Mitigation:** Selectors are treated as opaque strings throughout — never interpolated into script code, only passed verbatim to `querySelector`. Bounded to 1 KB. The Rust handler's `MAX_ACTIVE_PER_FILE` and `MAX_BODY_CHARS` limits apply equally to file and browser surfaces.

### F049-T05: PII / secrets in browser comment URLs

- **Vector:** Browser comment surfaces use the canonical URL as the anchor key. Real-world URLs sometimes carry sensitive data in the query string: auth tokens, session IDs, API keys, OAuth state. Persisting these in the comments DB exposes secrets to anyone with access to the vibespace database file.
- **Impact:** Tokens and session identifiers persisted in the encrypted libSQL DB. Encryption-at-rest mitigates exposure to filesystem snooping; the threat is realized if the DB key is recovered or if a backup is exported.
- **Likelihood:** Medium without mitigation.
- **Mitigation:** `BrowserCommentURLNormalizer.canonicalize` strips a curated allowlist of sensitive query parameters before storage (see `strippedQueryParams`): `token`, `access_token`, `id_token`, `refresh_token`, `session`, `session_id`, `sid`, `key`, `api_key`, `apikey`, `auth`, `authorization`, plus all common analytics tracking params (`utm_*`, `fbclid`, `gclid`, etc.). Fragment identifiers are also dropped. The normalizer runs at all storage entry points (Swift `BrowserSurfaceBridge` writes, agent-CLI `comment.add` for browser surfaces, and cross-file navigation). Future work: per-origin disable list in vibespace settings.

### F049-T06: Cross-frame access limitation

- **Vector:** A page loaded in a browser surface may embed cross-origin iframes (e.g., authentication widgets, third-party embeds). The injected comments JS bundle runs in the page's main frame and cannot reach into cross-origin children due to the same-origin policy.
- **Impact:** Comments cannot be created or rendered against content inside cross-origin embedded iframes. This is a feature limitation, not a security exposure — same-origin policy itself is the security boundary.
- **Likelihood:** N/A (limitation, not threat).
- **Mitigation:** Documented as an explicit limitation in the usage guide. Selecting text inside a cross-origin iframe will not produce an "Add Comment" button; users selecting in the page's main frame work normally.

## Residual Risks

- A trusted agent can intentionally write garbage comments. This is not a security issue under the single-user trust model — agents have full user-level access already.
- Markdown rendering edge cases in future iOS/macOS releases could introduce new HTML interpretation. Mitigated by the write-time whitelist filter.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Markdown subset whitelist; CLI path canonicalization. |
| REL | Compliant | Hard limits enforced in Rust; transactional writes; encrypted at rest. |
| OBS | Compliant | Lifecycle and limit-violation events emitted (R18). |
| A11Y | Compliant | Per UI requirements (R06); accessibility identifiers on every interactive element. |
