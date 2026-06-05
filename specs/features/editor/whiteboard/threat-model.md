# Whiteboarding — Threat Model

## Overview

F052 embeds a third-party web app (Excalidraw) in a `WKWebView` and reads/writes `.excalidraw` files. The security goals are: (1) the embedded canvas is **provably offline** — it cannot reach the network; (2) the local resource server cannot be tricked into serving files outside the runtime bundle; (3) untrusted `.excalidraw` file contents cannot escalate into code execution or unwanted file writes.

## Trust Boundaries

- **App ↔ embedded web content:** the Excalidraw UMD bundle is third-party code running in a `WKWebView`. It is treated as untrusted and confined by CSP, a custom resource scheme, and a navigation policy.
- **App ↔ file contents:** a `.excalidraw` file may come from anywhere (shared, agent-authored, downloaded). Its JSON is parsed in the web layer and rendered by Excalidraw.
- **Shelf ↔ project file tree:** an in-app drag carries a file path that becomes a filesystem `moveItem`.

## Attack Surfaces

- The `app-excalidraw://local/*` scheme handler (path → bundle file).
- The page CSP and navigation policy.
- The JS ↔ Swift bridge messages (`whiteboardReady/Changed/Log`, `crispyvibesSetScene/SetTheme`).
- The shelf-drag → move file operation.
- The vendored runtime supply chain.

## Threats

### F052-T01: Network exfiltration / phone-home by embedded content
- Vector: Excalidraw (or a crafted scene) attempts to fetch a remote URL (fonts, telemetry, library browser, share/collab endpoints).
- Impact: data egress; breaks the offline guarantee.
- Likelihood: Medium (the upstream app has remote features).
- Mitigation: page CSP permits only the local scheme — `default-src 'none'`, `connect-src 'self' app-excalidraw:`, `font-src 'self' app-excalidraw:`, no remote origins. `EXCALIDRAW_ASSET_PATH` points at the local scheme. The scheme handler only reads from the bundle. Net: no remote origin is reachable.

### F052-T02: Path traversal / symlink escape in the scheme handler
- Vector: a request path like `../../../../etc/passwd`, or a symlink inside the runtime folder, attempts to read outside the bundle.
- Impact: arbitrary local file disclosure into the web context.
- Likelihood: Low.
- Mitigation: requested paths are resolved with `resolvingSymlinksInPath()` and must equal or be prefixed by the symlink-resolved runtime root, else the request is rejected. Responses set `X-Content-Type-Options: nosniff`.

### F052-T03: CSP bypass via `data:`/inline script
- Vector: a crafted scene or injected DOM triggers a `data:text/html` navigation (null origin, no inherited CSP) or relies on inline script.
- Impact: script execution outside CSP.
- Likelihood: Low.
- Mitigation: the navigation policy allows only the local scheme plus `about:`/`blob:`; `data:` navigation is denied. The page ships **no inline scripts** (all externalized to `config.js`/`bridge.js`), so `script-src` does not grant `'unsafe-inline'`.
- Residual: `script-src 'unsafe-eval'` and `style-src 'unsafe-inline'` are retained because the Excalidraw runtime requires them. Risk is contained by the offline, bundle-only origin (no attacker-controlled code can be loaded).

### F052-T04: Malicious `.excalidraw` content
- Vector: hostile JSON (huge element counts, malformed fields, embedded data URIs).
- Impact: at worst a render error or slowdown in the sandboxed web view; no host code execution.
- Likelihood: Low.
- Mitigation: content is parsed/normalized by Excalidraw inside the web sandbox; the Swift side treats the scene as an opaque JSON string. Bridge messages are validated by name and type before use.

### F052-T05: Unintended file move / overwrite
- Vector: a shelf drop targets a directory outside any project, or collides with an existing file.
- Impact: file written to an unexpected location, or data overwrite.
- Likelihood: Low.
- Mitigation: `moveShelfItemToProject` rejects targets not inside an open project root, never overwrites (uniquifies the destination name on collision), and flushes unsaved edits before moving so content isn't lost.

### F052-T06: Drag-payload information leak
- Vector: the shelf drag pasteboard exposes the local file path to other applications.
- Impact: minor path disclosure.
- Likelihood: Low.
- Mitigation: the drag item uses `visibility: .ownProcess`.

### F052-T07: Supply-chain tampering of the vendored runtime
- Vector: a compromised or drifting Excalidraw/React version is vendored.
- Impact: malicious code shipped in the bundle.
- Likelihood: Low.
- Mitigation: versions are pinned in `package.json` + `package-lock.json`; `build.sh` uses `npm ci` (lockfile-exact, reproducible). The runtime is offline-confined regardless.

## Residual Risks

- `unsafe-eval` / inline styles required by Excalidraw (T03) — accepted, contained by the offline bundle-only origin; revisit on Excalidraw upgrades.
- Sub-second autosave-debounce window before a move (see technical-design Known Gaps) — content, not security.
- Web inspector is enabled in DEBUG builds only.

## NFR Compliance

- **SEC** — offline-only (CSP + local scheme + nav policy), symlink-safe path containment, `nosniff`, pinned/lockfile-reproducible runtime, own-process drag payload, no host code paths from file content.
- **REL** — autosave through `DocumentBuffer`; pre-move flush; collision-safe, project-scoped moves.
- **A11Y** — canvas exposes an accessibility label; follows app light/dark appearance.
- **PERF** — runtime loaded lazily; autosave debounced; bundle size comparable to existing web runtimes.
- **DEP** — no new Swift package dependencies; web deps pinned and vendored.
