# Browser — Technical Design

## Overview

The in-app browser embeds WebKit to provide vibespace-integrated web browsing. It is not a standalone feature module — it lives within the VibeSpace feature and surfaces through three vibespace contexts: board tiles, spotlight previews, and detailed content viewer tabs. The browser supports full navigation, an address bar with frecency-ranked suggestions, find-in-page, downloads, console capture, element picking, crash recovery, and a Playwright-style agent automation API. Several subsystems (profiles, data import, remote proxy, WebAuthn) are implemented but not yet wired to UI.

## Architecture

### Component Model

The browser follows the standard app layering: SwiftUI views → view model → delegates and services, all wired through AppContainer with no singletons.

The central view model is an `@MainActor ObservableObject` that owns the WKWebView instance and all published state. It coordinates navigation, URL resolution, security policy, focus management, element picking, favicon fetching, zoom, and crash recovery. KVO observers on the WebView drive reactive state updates for URL, title, loading progress, navigation capability, and security status.

A coordinator manages view model lifecycles across the three surface types (board tiles, detailed view tabs, floating preview). It handles session snapshot capture, persist scheduling, and promotion flows between surfaces.

Two delegate objects — navigation and UI — are plain callback-based classes (not protocol-injected). The view model wires closures into them at init time. This keeps delegate logic stateless while allowing the view model to react to navigation decisions, downloads, errors, and crash events.

### Surface Hosting and Ownership Arbitration

A single WKWebView instance can only be attached to one NSView at a time, but the same browser session may appear on multiple surfaces (e.g., a board tile promoted to spotlight). An ownership coordinator arbitrates which container view holds the physical WebView using priority-based preemption:

- Board tiles have the lowest priority, with active tiles ranked above inactive ones.
- Detailed content viewer tabs rank higher than board tiles.
- Spotlight has the highest priority and always preempts.

When a higher-priority surface requests ownership, the coordinator detaches the WebView from the current owner and reattaches it. The displaced owner is notified to retry acquisition later. Weak references prevent the coordinator from retaining container views.

### Dependency Injection

The history store is created once in AppContainer and injected into the coordinator, which propagates it to each view model. The agent API is created via a factory closure on the coordinator. No browser component discovers its dependencies through globals.

## Navigation & Address Bar

### Smart URL Resolution

Address bar input is classified through a priority chain:

1. If it parses as a URL with an explicit scheme (http, https, file) — use as-is.
2. If it looks like a localhost address — prepend http.
3. If it contains a dot without spaces — prepend https (likely a domain).
4. If it contains a colon or slash without spaces — prepend https (likely a URL with port or path).
5. Otherwise — treat as a search query and route to the configured search engine.

The search engine is configurable (Google, DuckDuckGo, Bing). When input resolves to a URL rather than a search, the navigation is recorded as a "typed" visit, which boosts its frecency score for future suggestions.

### Why NSViewRepresentable for the Address Field

SwiftUI's TextField cannot intercept arrow keys or Escape reliably — these are consumed by the framework before reaching the field. The address bar wraps an NSTextField via NSViewRepresentable and uses a field editor delegate to intercept arrow keys (for suggestion navigation), Enter (for submission), and Escape (for dismissal). This is the only reliable way to get full keyboard control in a text field embedded in a SwiftUI view hierarchy.

### Suggestion System

Suggestions combine two sources: local history entries ranked by frecency, and remote search suggestions from a search provider API. History suggestions appear first (with a clock icon), followed by remote suggestions (with a search icon).

Remote suggestions are debounced at 250ms with a 1-second timeout to avoid blocking the UI on slow networks. Suggestions are suppressed when the address bar text matches the current URL (to avoid suggesting the page you're already on) and after navigation commits.

Frecency scoring weights several factors: exact URL match, host prefix match, substring match in URL or title, recency (decaying over hours), visit frequency (logarithmic), and typed navigation count (logarithmic, weighted higher than visits). This means URLs you type directly rank higher than URLs you arrived at through links.

## Session Management

### Dual-Stack History Model

WKWebView maintains its own back/forward list internally, but this list is not serializable and cannot be restored across app launches. To support session persistence, the browser maintains parallel back and forward stacks alongside WebKit's native history.

During normal browsing, the native WebKit history is authoritative. On session restore, the parallel stacks are populated from the persisted snapshot and a flag switches navigation methods to use them instead. Back and forward operations pop from one stack and push to the other, then load the target URL.

The parallel stacks are abandoned on any new user-initiated navigation — at that point, WebKit's native history takes over again. This avoids the complexity of keeping two history models in sync during active browsing.

### Session Snapshot

A session snapshot captures the current URL, back/forward URL stacks, zoom level, and theme mode. Snapshots are taken on a debounced schedule and before coordinator teardown. On restore, zoom is clamped to safe bounds and the URL is loaded if it's not blank.

### Crash Recovery

When the WebView's content process terminates (detected via the navigation delegate), the browser:

1. Captures a session snapshot from the dying WebView.
2. Tears down the old WebView (removes observers, nils delegates).
3. Creates a fresh WebView with the same data store configuration.
4. Rewires delegates and observers.
5. Restores the session from the snapshot.

This is transparent to the user — the page reloads at the same URL with history intact.

## Security

### Insecure HTTP Blocking

HTTP URLs are blocked by default. A built-in allowlist permits localhost variants, and a configurable allowlist supports wildcard patterns (e.g., `*.local` matches any subdomain). When a blocked URL is encountered, the user is presented with three options: open in the system browser, proceed anyway (one-time bypass), or cancel.

This is a deliberate tradeoff: developers frequently need localhost HTTP for local servers, but arbitrary HTTP should require conscious opt-in.

### External URL Handling

Non-web URL schemes (anything outside http, https, about, blob, data, file) are handed off to the system's default handler and the navigation is cancelled. This prevents the embedded browser from attempting to handle schemes like mailto, slack, or custom app protocols.

A separate host allowlist (regex-based) can route specific URLs to the system browser entirely, useful for OAuth flows or sites that don't work well in an embedded WebView.

### User-Agent

The browser sends a Safari user-agent string to avoid bot detection and ensure sites render their standard desktop experience. Many sites serve degraded content or CAPTCHAs to unrecognized user agents.

### TLS Policy

Deprecated TLS versions are rejected outright. All other authentication challenges use default system handling. There is no option to override certificate errors — this is intentional to prevent accidental exposure to MITM attacks.

## Focus & Keyboard

### The Focus Guard Problem

Background WebViews can steal focus from the active editor or terminal when JavaScript on the page calls `focus()` or uses autofocus attributes. This is a fundamental problem with embedding multiple WebViews in a vibespace.

The solution is a two-part focus gate on the WebView subclass:

1. A primary flag that prevents all focus acquisition when the browser is not the active surface.
2. A click-through counter that temporarily permits focus during mouse-down events, so clicking a browser pane both activates it and delivers the click to web content.

This means background pages cannot steal focus, but clicking into a browser works naturally.

### Key Routing Priority

The WebView subclass overrides key equivalent handling with a specific priority chain:

1. Active IME composition takes precedence (for CJK input methods).
2. Return/Enter without modifiers goes to WebKit for form submission.
3. Non-Cmd keystrokes go to WebKit for typing in web forms.
4. Cmd+Shift+V is intercepted for paste-as-plain-text (strips formatting).
5. Other Cmd shortcuts are offered to the app's main menu first (so vibespace shortcuts like Cmd+T work).
6. Unhandled Cmd shortcuts fall through to WebKit.

This ordering ensures that vibespace-level shortcuts aren't swallowed by web content, while typing and form interaction work normally.

## Element Picker

The element picker is a self-contained JavaScript overlay injected into the page — no third-party dependencies. On hover, it draws a highlight overlay and a label showing the element's tag, ID, and classes. On click, it copies rich context to the clipboard: CSS selector path, tag info, visible text, outer HTML, and (if available) React component name and source file.

React detection works by walking the fiber tree through internal instance keys on DOM elements. This provides useful component-level context on React apps and degrades gracefully to just DOM info on non-React pages.

The picker auto-deactivates after a selection or Escape. The view model polls a JS flag to detect deactivation and update its state. The picker is designed for agent workflows where an AI needs to understand page structure.

## Agent Automation API

### Design

The agent API provides Playwright-style browser control through 84+ commands organized into categories: navigation, DOM interaction (click, fill, type, press, check), DOM queries, state checks, semantic element finding, accessibility snapshot, wait conditions, cookies, and storage.

### Element Reference System

Commands that find or query elements return opaque reference tokens (like `@e1`, `@e2`). These tokens map to CSS selectors internally. Subsequent commands can use either a reference token or a raw CSS selector. This allows agents to work with stable references across multiple commands without re-querying.

### React-Compatible Form Filling

Standard value assignment on form elements doesn't trigger React's synthetic event system, causing React state to diverge from DOM state. The fill command works around this by walking the prototype chain to find the native value setter and calling it directly, then dispatching input and change events. This ensures React components detect the value change.

### Accessibility Snapshot

The snapshot command walks the DOM and produces an indented accessibility tree with roles, names, and element references. It maps HTML elements to implicit ARIA roles, respects visibility, and caps traversal depth. This gives agents a semantic view of the page without needing to parse raw HTML.

### Wait Conditions

The wait command supports four condition types: selector presence, text content, URL content, and page load completion. It uses a MutationObserver for efficient DOM watching with a timeout fallback. The Swift-side timeout adds a buffer beyond the JS timeout to account for message passing overhead.

### Current Limitations

The agent API is fully implemented but not yet callable from the terminal. It needs a Unix socket server and CLI binary to bridge terminal-based agents to the browser API. Currently it can only be invoked programmatically from within the app.

## Downloads

Downloads use a two-phase flow: WebKit writes to a temporary file first, then an NSSavePanel lets the user choose the final destination. This design is forced by WKDownload's API, which requires a destination path before the download begins — but we want the user to choose where to save.

Download progress is boolean only (downloading vs. not downloading). WebKit doesn't expose granular progress for downloads initiated through the navigation delegate, so percentage-based progress would require a separate URLSession download, adding complexity for marginal benefit.

## Find in Page

Find-in-page is implemented in JavaScript using a TreeWalker rather than WKWebView's native find. The reason: WebKit's native find API provides no hooks for custom UI — you get the system find bar or nothing. Since the browser needs find integrated into its own chrome, a JS implementation was the only option.

The JS walks all text nodes, wraps matches in highlight elements, and tracks the current match for navigation. Highlights are cleaned up by replacing mark elements with their text content and normalizing the DOM.

## Console Capture

JavaScript injection overrides console methods at document start, buffering messages with level, text, and timestamp. The buffer is capped at 512 entries per page load and can be flushed to the view model on demand. This is designed for agent workflows where an AI needs to inspect console output. There is no viewer UI yet.

## Subsystems (Implemented, Not Yet UI-Wired)

### Browser Profiles

Profiles provide isolated data stores so different browsing contexts don't share cookies or storage. The default profile uses WebKit's persistent data store; all other profiles use non-persistent (ephemeral) stores, meaning their data is lost on quit. This is a known limitation — persistent isolated stores require more complex lifecycle management that hasn't been built yet.

### Data Import

History can be imported from Chrome and Safari by reading their SQLite databases directly. The databases are copied to temp files before reading to avoid locking the live browser's database. Imported entries are deduplicated against existing history by URL.

### Remote Proxy

For remote vibespace browsing, an SSH SOCKS5 tunnel can be established to route WebView traffic through the remote host. This uses the proxy configuration API on `WKWebsiteDataStore`. Tunnel processes are tracked and terminated on coordinator teardown.

### WebAuthn

A JavaScript bridge intercepts WebAuthn credential creation and assertion requests, routing them to the native passkey system via AuthenticationServices. A leak-avoider pattern prevents the retain cycle that would otherwise occur between WKWebView and its script message handler.

## Design Decisions Summary

| Decision | Rationale |
|---|---|
| NSViewRepresentable for address bar | SwiftUI TextField can't intercept arrow keys reliably |
| JS-based find-in-page | WKWebView's native find has no API for custom UI |
| Dual-stack session history | WKWebView doesn't expose a session restore API |
| Custom JS element picker | No dependency on third-party tools; works offline |
| Callback-based delegates | Keeps delegate objects stateless; view model controls all behavior |
| Priority-based WebView ownership | Single WKWebView can only attach to one NSView; arbitration avoids cloning |
| Safari user-agent | Prevents bot detection and degraded site rendering |
| Non-persistent stores for non-default profiles | Persistent isolated stores need lifecycle management not yet built |

## Platform Requirements

The browser feature inherits the app's deployment target (macOS 26+ Tahoe). All AppKit/WebKit APIs used here — proxy configuration, WebAuthn passkeys via AuthenticationServices, and `WKWebView.isInspectable` — are unconditionally available at this target.

## Known Limitations

- Agent API needs a socket server to be callable from terminal-based agents.
- Non-default browser profiles lose data on quit (ephemeral stores).
- Download progress is boolean only — no percentage indication.
- Console capture has no viewer UI — flush-only for agent consumption.
- History import requires file system access permissions for Chrome/Safari databases.
