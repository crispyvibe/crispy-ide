# Worker — Spec

Status: draft

## Overview

Worker provides the out-of-process pane worker execution model for filesystem, git, editor, and terminal operations. Covers worker lifecycle (spawn, timeout, generation guards), status signals, explorer methods (list/create/rename/delete/move/copy), git methods (status, diff, branches, stage, unstage, commit, push, pull, fetch, checkout, clone, discard, discovery, snapshots, file content, history), editor methods (read/write), terminal methods (ping, gitCurrentBranch), response contracts, remote file-service readiness, and worker instrumentation.

## Dependencies

- F024 (File Explorer) — explorer worker methods serve file tree
- F026 (Git Operations) — git worker methods serve source control
- F007 (Editing) — editor worker methods serve file editing
- F001 (Sessions & Tabs) — terminal worker methods serve terminal pane

## Requirements

### F013-R01: Pane Worker Execution Model

Workers MUST run out-of-process via app executable with JSON stdin/stdout, support timeout termination, and generation guards.

### F013-R02: Worker Status Signals

Pane status MUST reflect busy, ready, and unavailable states.

### F013-R03: Explorer Methods

Explorer MUST support listTree, createFile, createFolder, rename, delete, move, and copy with validation.

### F013-R04: Git Methods

Git MUST support status, diff, branches, stage, unstage, stageAll, unstageAll, commit, push, pull, fetch, checkout, clone, discard, discardAll, discovery, snapshots, fileContent, fileHistory, commitHistory, and currentBranch.

### F013-R05: Editor Methods

Editor MUST support readFile (multi-encoding) and writeFile (atomic UTF-8).

### F013-R06: Terminal Methods

Terminal worker MUST support ping and gitCurrentBranch.

### F013-R07: Response Contract

Successful responses MUST include success=true with optional value; failures MUST include success=false with error.

### F013-R08: Remote File-Service Readiness

SSH-backed operations MUST retry readiness asynchronously before failing, and support materialized local preview URLs.

### F013-R09: Worker Instrumentation

MeasuredPaneWorker MUST add os_signpost instrumentation; PaneWorkerPersistentSession MUST maintain long-lived subprocess; git probes MUST cache with TTL.

## Scenarios

### Scenario F013-S01: Pane operations run out-of-process through app executable

**Given** a pane worker client executes an operation
**When** request is submitted
**Then** the same app executable is spawned with `--pane-task <pane-kind>`
**And** request payload is sent via stdin as JSON
**And** a JSON response is read from stdout
**Note:** PaneWorkerExecutionMode.resolve() selects between inProcess and subprocess modes; inProcess runs the task directly in the host process while subprocess launches the external executable

### Scenario F013-S02: Worker request timeout terminates process

**Given** a pane request has a configured timeout
**When** no response completes before timeout
**Then** worker process is terminated
**And** caller receives timeout error

### Scenario F013-S03: Worker generation guards stale processes

**Given** worker client has restarted
**When** an older in-flight process completes
**Then** stale process is ignored or terminated by generation mismatch rules

### Scenario F013-S04: Pane status reflects busy and unavailable states

**Given** pane operations are in progress
**When** requests start and end
**Then** status transitions to `busy` and returns to `ready` on success
**When** failures occur
**Then** status transitions to `unavailable` with a user-facing message

### Scenario F013-S05: List tree returns immediate children only

**Given** `listTree` is requested for a directory
**When** worker enumerates filesystem
**Then** only immediate children are returned
**And** package descendants are skipped
**And** hidden entries are included with hidden metadata flags
**And** git-ignored entries are annotated when repository context is available
**And** entries are sorted with directories first

### Scenario F013-S06: Create file generates unique collision-safe name

**Given** requested file name already exists in target directory
**When** `createFile` is executed
**Then** worker appends numeric suffix (`name 1`, `name 2`, ...)
**And** returns created file path

### Scenario F013-S07: Create folder generates unique collision-safe name

**Given** requested folder name already exists in target directory
**When** `createFolder` is executed
**Then** worker appends numeric suffix (`name 1`, `name 2`, ...)
**And** returns created folder path

### Scenario F013-S08: Rename item validates destination and conflicts

**Given** rename request includes old path and new name
**When** new name is empty
**Then** request fails with validation error
**When** destination already exists
**Then** request fails with conflict error
**When** destination is valid
**Then** filesystem move occurs and new path is returned

### Scenario F013-S09: Delete item removes target path

**Given** delete request contains item path
**When** request executes successfully
**Then** worker removes file or directory at that path

### Scenario F013-S10: Git availability is detected before repository checks

**Given** git status is requested
**When** `git --version` fails
**Then** payload reports `gitAvailable=false`
**And** repository state is reported unavailable

### Scenario F013-S11: Non-repository roots are reported explicitly

**Given** git is available but root is not inside work tree
**When** repository check runs
**Then** payload reports `repository=false`
**And** user-facing message indicates non-repository folder

### Scenario F013-S12: Git status parses porcelain output including renames/copies

**Given** git status command returns porcelain v1 z-format output
**When** parser processes entries
**Then** status code and relative path are extracted per record
**And** index and worktree status components are emitted per entry
**And** rename/copy entries resolve to destination path
**And** absolute paths are built from project root

### Scenario F013-S13: Git status entries are sorted case-insensitively

**Given** parsed git entries exist
**When** payload is returned
**Then** entries are sorted by relative path using case-insensitive compare

### Scenario F013-S14: Read file supports multiple text encodings

**Given** editor requests `readFile`
**When** file content is decodable as UTF-8, UTF-16, or ISO Latin-1
**Then** decoded text is returned
**When** no supported encoding matches
**Then** operation fails with unsupported encoding error

### Scenario F013-S15: Write file persists UTF-8 content atomically

**Given** editor requests `writeFile` with content
**When** content is UTF-8 encodable
**Then** file is written with atomic option
**When** encoding fails
**Then** operation returns file encoding error

### Scenario F013-S16: Terminal worker supports health checks and gitCurrentBranch

**Given** terminal pane sends worker request
**When** method is `ping`
**Then** worker returns timestamp
**When** method is `gitCurrentBranch`
**Then** worker returns current branch name for the given repository root
**When** method is any other value
**Then** worker returns unsupported method error

### Scenario F013-S17: Successful response includes optional value

**Given** worker operation succeeds
**When** response is encoded
**Then** `success=true`
**And** `value` may include path/text/payload depending on method

### Scenario F013-S18: Failed response includes error message

**Given** worker operation fails
**When** response is encoded
**Then** `success=false`
**And** `error` contains localized failure details

### Scenario F013-S19: Move item validates destination and remaps path

**Given** move request includes source path and destination directory path
**When** destination is missing, not a directory, or already contains same item name
**Then** request fails with descriptive validation error
**When** source is moved into itself or descendant path
**Then** request fails with self-move validation error
**When** move is valid
**Then** filesystem move occurs and destination path is returned

### Scenario F013-S20: Git diff returns staged and unstaged sections with status fallback

**Given** editor requests `gitDiff` for repository root and relative path
**When** staged and/or unstaged textual diff exists
**Then** response includes corresponding `Staged Changes` and `Working Tree Changes` sections
**When** textual diff is unavailable for changed path
**Then** response falls back to porcelain status information for that path

### Scenario F013-S21: Git branches returns local and remote refs with current branch marker

**Given** explorer requests `gitBranches` for repository root
**When** branch scan succeeds
**Then** payload includes branch options for local and remote refs
**And** payload includes current branch name when available

### Scenario F013-S22: Git stage stages one path

**Given** explorer requests `gitStage` with root path and relative path
**When** command succeeds
**Then** worker returns success for staged path mutation

### Scenario F013-S23: Git unstage unstages one path

**Given** explorer requests `gitUnstage` with root path and relative path
**When** command succeeds
**Then** worker returns success for index reset of that path

### Scenario F013-S24: Git stage-all stages all pending changes

**Given** explorer requests `gitStageAll` with repository root
**When** command succeeds
**Then** worker stages all pending changes in the repository

### Scenario F013-S25: Git commit creates commit with message validation

**Given** explorer requests `gitCommit` with repository root and message
**When** message is empty
**Then** worker returns validation failure
**When** message is non-empty and commit succeeds
**Then** worker returns success

### Scenario F013-S26: Git push publishes current branch

**Given** explorer requests `gitPush` with repository root
**When** push succeeds
**Then** worker returns success

### Scenario F013-S27: Git checkout supports local and remote branch requests

**Given** explorer requests `gitCheckoutBranch` with branch name and remote flag
**When** request succeeds
**Then** local checkout or remote tracking checkout is executed based on flag

### Scenario F013-S28: Git commit history returns bounded commit entries

**Given** explorer requests `gitCommitHistory` with root path and optional limit
**When** command succeeds
**Then** payload returns commits ordered by newest first up to limit

### Scenario F013-S29: Git file history returns commits scoped to relative path

**Given** explorer requests `gitFileHistory` with root path, relative path, and optional limit
**When** command succeeds
**Then** payload returns commits limited to that file path

### Scenario F013-S30: SSH-backed file operations retry readiness asynchronously before failing

**Given** a remote file-system or file-content operation needs an SSH or SFTP client
**When** the underlying SSH connection is still coming online
**Then** the operation retries readiness using a bounded asynchronous backoff
**And** the retry budget is exhausted without blocking the main thread
**And** a connection-readiness error is returned only after those retries fail

### Scenario F013-S31: SSH-backed previewable binary files can request materialized local preview URLs

**Given** a file-content provider backs a remote SSH Project
**When** the editor needs to render an image or PDF through a native local-file renderer
**Then** the provider can require a materialized local preview file instead of direct source-path rendering
**And** the editor stages a temporary local file from remote bytes before handing the preview to native image or PDF components

### Scenario F013-S32: gitDiscoverRepositories finds git repos under project root

**Given** explorer requests `gitDiscoverRepositories` with a project root
**When** scan completes
**Then** worker returns list of discovered git repository paths under that root

### Scenario F013-S33: gitDiscoverRepositoriesBatch discovers repos for multiple roots

**Given** explorer requests `gitDiscoverRepositoriesBatch` with multiple root paths
**When** scan completes
**Then** worker returns discovered repository paths for each provided root

### Scenario F013-S34: gitRepositorySnapshot returns combined status and branches

**Given** explorer requests `gitRepositorySnapshot` for a repository root
**When** command succeeds
**Then** response includes both git status entries and branch information in a single call

### Scenario F013-S35: gitDiscard reverts unstaged changes for a single file

**Given** explorer requests `gitDiscard` with root path and relative path
**When** command succeeds
**Then** unstaged changes for that file are discarded

### Scenario F013-S36: gitDiscardAll reverts all unstaged changes

**Given** explorer requests `gitDiscardAll` with repository root
**When** command succeeds
**Then** all unstaged changes in the repository are discarded

### Scenario F013-S37: gitUnstageAll unstages all staged changes

**Given** explorer requests `gitUnstageAll` with repository root
**When** command succeeds
**Then** all staged changes are reset back to unstaged state

### Scenario F013-S38: gitPull pulls from remote

**Given** explorer requests `gitPull` with repository root
**When** command succeeds
**Then** worker pulls latest changes from the remote

### Scenario F013-S39: gitFetch fetches from remote

**Given** explorer requests `gitFetch` with repository root
**When** command succeeds
**Then** worker fetches remote refs without merging

### Scenario F013-S40: gitFileContent returns file content at HEAD revision

**Given** explorer requests `gitFileContent` with root path and relative path
**When** command succeeds
**Then** worker returns the file content as it exists at HEAD

### Scenario F013-S41: gitCurrentBranch returns current branch name

**Given** explorer requests `gitCurrentBranch` with repository root
**When** command succeeds
**Then** worker returns the current branch name

### Scenario F013-S42: gitHubCloneOptions checks GitHub CLI and lists repos

**Given** explorer requests `gitHubCloneOptions`
**When** GitHub CLI is available
**Then** worker returns available repositories for cloning
**When** GitHub CLI is unavailable
**Then** worker indicates CLI is not available

### Scenario F013-S43: gitCloneRepository clones repo to destination

**Given** explorer requests `gitCloneRepository` with source URL and destination path
**When** clone succeeds
**Then** repository is cloned to the specified destination

### Scenario F013-S44: copyItem copies file or folder to target

**Given** explorer requests `copyItem` with source path and target path
**When** copy succeeds
**Then** file or folder is copied to the target location

### Scenario F013-S45: MeasuredPaneWorker decorator adds os_signpost instrumentation

**Given** a pane worker is wrapped with MeasuredPaneWorker
**When** any worker method is invoked
**Then** os_signpost intervals are emitted for performance tracing

### Scenario F013-S46: PaneWorkerPersistentSession maintains long-lived subprocess

**Given** a persistent worker session is started
**When** requests are sent
**Then** communication uses newline-delimited JSON over a long-lived subprocess
**And** the subprocess is reused across multiple requests

### Scenario F013-S47: Git probe results are cached with TTL

**Given** worker checks `isGitAvailable` or `isGitRepository`
**When** a cached result exists within TTL
**Then** cached value is returned without re-executing the probe
**When** TTL has expired
**Then** probe is re-executed and cache is refreshed

## Acceptance Criteria

- Worker subprocess spawns within 100ms.
- Timeout terminates stale processes reliably.
- File operations validate paths and handle conflicts.
- Git operations parse porcelain output correctly.
- SSH-backed operations retry without blocking main thread.
- Response contract is consistent across all methods.

## Open Questions

_None._

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/worker/feature.md (WRK-001–047) | — |
