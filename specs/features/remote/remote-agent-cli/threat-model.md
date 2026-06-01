# Remote Agent CLI — Threat Model

## Overview

The remote CLI forwards a control channel from a remote host back to the local Crispy app, where commands run with the local user's authority. This deliberately lets a remote shell (and agents on it) drive the local IDE. This document covers the trust boundaries and the residual exposure that introduces.

## Trust Boundaries

| Boundary | Inside (trusted) | Outside (untrusted) |
|---|---|---|
| **Local app** | `CLICommandRouter`, services, local `crispy.sock` (`0600`) | Anything reaching the relay |
| **SSH channel** | The authenticated connection Crispy opened to the remote | Other hosts/networks |
| **Remote relay socket** | The forwarded Unix socket — `0600`, owner-only | Other users on the remote host |
| **Remote host** | The host the user chose to SSH into | Other users/processes on that host |
| **Remote project root** | Files under the remote `CRISPY_PROJECT_PATH` | Paths escaping it |

## Threats

### F051-T01: Forwarded control plane reachable by other remote users

- **Vector**: On a multi-user remote host, another local user connects to the reverse-forwarded loopback endpoint and drives the local IDE.
- **Impact**: Full local Agent CLI control by a third party on the remote.
- **Likelihood**: Medium on shared hosts.
- **Mitigation**: The forwarded remote socket is **`0600`, owner-only** (verified on a live Ubuntu host) — other users on the remote host cannot connect, so exposure is bounded to *processes running as the remote user*. Per-connection opt-in (F051-T05) lets users disable it for shared/untrusted hosts.

### F051-T02: Untrusted remote host as confused deputy

- **Vector**: A compromised/untrusted remote host issues relay requests to manipulate the local IDE (open local files, drive terminals/browser) using Crispy's local authority and any TCC grants.
- **Impact**: Local-side actions driven by a remote attacker — equivalent to the local Agent CLI surface.
- **Likelihood**: Low–Medium (you generally SSH into hosts you trust).
- **Mitigation**: Remote CLI is an explicit trust decision; only enable for hosts you trust. Project-boundary enforcement on `file.*`. Recommend per-profile opt-in. Documented in usage-guide.

### F051-T03: Remote path boundary escape

- **Vector**: `file.open ../../…` from the remote to surface files outside the remote project.
- **Impact**: Read/write outside the project via the IDE.
- **Likelihood**: High (primary file-op pattern).
- **Mitigation**: Resolve against the **remote** project root via the remote/SFTP provider with symlink resolution (reuses F044-R10 logic); reject escapes with `permission_denied`.

### F051-T04: Stale wrapper / forward after abrupt disconnect

- **Vector**: A crash leaves the `~/.local/bin/crispy` wrapper or a dangling forward on the remote.
- **Impact**: Remote residue; a stale socket with no listener.
- **Likelihood**: Medium (inherent across crashes).
- **Mitigation**: `StreamLocalBindUnlink=yes` removes the forwarded socket on (re)connect/teardown. The `~/.local/bin/crispy` wrapper persists but is **inert without a live forward** and is overwritten on the next connect; it fails closed (F051-R08). Open: it is not actively removed on disconnect.

### F051-T05: Always-on remote control surface

- **Vector**: Remote CLI enabled for every remote session widens the attack surface unconditionally.
- **Impact**: Larger standing surface than users may expect.
- **Likelihood**: N/A (design choice).
- **Mitigation**: **Implemented** — per-connection opt-in via `SSHConnectionProfile.agentCLIEnabled` with a toggle in the connection sheet. Default is on (the `0600` socket limits exposure to the remote user); disable per host as needed.

### F051-T06: Wrapper/PATH tampering on the remote

- **Vector**: A remote process replaces the wrapper or shadows it earlier on `PATH`.
- **Impact**: MITM on remote `crispy` invocations.
- **Likelihood**: Low–Medium (requires same-user write on the remote).
- **Mitigation**: Wrapper lives at `~/.local/bin/crispy`, owned by and writable only by the remote user (`0755`). Inherent to same-user remote trust; not defended beyond it.

## Residual Risks

- **R1 (same remote user):** the `0600` socket excludes *other* remote users, but any process running **as the remote user** (incl. untrusted code it runs) can drive the local IDE (F051-T01/T02). Mitigation: per-connection opt-in + only enabling trusted hosts.
- **R2 (remote trust):** enabling remote CLI trusts the remote host with local IDE control (F051-T02). Mitigation is opt-in + user awareness.
- **R3:** scrollback/browser exposure inherited from F044 applies to remote callers too.

## NFR Compliance

| NFR | Reference | Compliance |
|---|---|---|
| **SEC-1** Authentication | `nfr/security.md` | SSH channel auth + `0600` owner-only forwarded socket + local `0600` socket. |
| **SEC-3** Authorization | `nfr/security.md` | Remote project boundary on `file.open`/pin; per-connection opt-in (`agentCLIEnabled`). |
| **OBS-1** Logging | `nfr/observability.md` | Relay invocations logged locally with source profile via `AppDiagnostics`. |
| **REL-2** Fault tolerance | `nfr/reliability.md` | Fail-closed wrapper; forwarded socket removed on disconnect (`StreamLocalBindUnlink`). |
