# Office Document Preview — Threat Model

## Overview

This feature renders Office documents using macOS Quick Look (`QLPreviewView`). The attack surface is narrow because rendering is delegated entirely to Apple's system framework, which runs with its own security mitigations. This threat model documents residual risks.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| App → Quick Look | Crispy passes a file URL to `QLPreviewView`; rendering happens inside Apple's framework code |
| File System → App | Documents are read from the local file system (user-opened or workspace files) |

## Attack Surfaces

1. **Document file content** — malformed or crafted Office files passed to Quick Look parsers.
2. **File path handling** — the URL passed to `QLPreviewView` could reference unexpected locations if not validated.
3. **Embedded external references** — documents may contain links, macros, or OLE objects referencing external resources.

## Threats

### F045-T01: Malicious Document Exploiting Quick Look Parser

- **Vector**: A crafted `.docx`/`.pptx` file triggers a vulnerability in Apple's Quick Look document parser (historically CVE-documented).
- **Impact**: Potential code execution within the app process or Quick Look subsystem.
- **Likelihood**: Low — Apple patches QL vulnerabilities via macOS updates; Crispy inherits those fixes.
- **Mitigation**:
  - Rely on Apple's ongoing security patches (no custom parsing).
  - Quick Look runs its parsers with its own internal security mitigations regardless of app sandbox status.
  - Consider rendering in a separate XPC process in future if risk profile changes.

### F045-T02: Path Traversal via Constructed File URL

- **Vector**: A programmatic caller passes a file URL pointing outside the workspace (e.g., `/etc/shadow` or a symlink to sensitive data).
- **Impact**: Information disclosure — Quick Look renders content the user did not intend to preview.
- **Likelihood**: Low — file URLs originate from the file explorer or shelf, both scoped to workspace directories.
- **Mitigation**:
  - Validate that the file URL resolves within a known workspace or project directory before passing to `QLPreviewView`.
  - Resolve symlinks and reject paths outside workspace bounds.

### F045-T03: Resource Exhaustion via Oversized Document

- **Vector**: An extremely large or deeply nested document consumes excessive memory/CPU during rendering.
- **Impact**: App becomes unresponsive; potential denial of service for the user's session.
- **Likelihood**: Medium — users may encounter large spreadsheets or presentations.
- **Mitigation**:
  - Check file size before rendering; warn on files > 50 MB (per F045-R05).
  - Render asynchronously so the main thread remains responsive.
  - Allow the user to cancel loading.

## Residual Risks

- Quick Look parser vulnerabilities are outside Crispy's control; mitigation depends on Apple's patch cadence.
- Embedded OLE objects or macros are not executed by Quick Look, but their presence cannot be surfaced to the user.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-1 (Input validation) | Compliant | File URL validated against workspace bounds |
| SEC-3a (No network calls) | Compliant | Quick Look renders locally; no outbound requests |
| PERF-1 (Responsiveness) | Compliant | Async rendering with loading indicator |
