# Clone Repository — Technical Design

## Overview

The clone sheet provides three source modes for cloning a Git repository: GitHub CLI-backed picker, manual URL entry, and an initial provider-checking state. After cloning, the directory is added as a vibespace project with terminal hydration and source control updates.

## Architecture

### Source Modes

| Mode | Trigger | Behavior |
|------|---------|----------|
| `checkingProviders` | Sheet presented | Calls `gitHubCloneOptions` to detect GitHub CLI + auth status |
| `githubPicker` | GitHub CLI authenticated | Populates list of user's GitHub repositories; filterable by `nameWithOwner` or description |
| `manualURL` | GitHub CLI not available or auth failed | User pastes repository URL directly |

### Destination Resolution

Default destination parent path resolved in priority order:

1. Parent directory of the focused project.
2. Parent directory of the first project.
3. User's home directory.

User can override via directory picker panel. Optional explicit directory name.

## Data Flow

### Clone Flow

1. Sheet enters `checkingProviders` on presentation.
2. `gitHubCloneOptions` called to detect GitHub CLI availability and authentication.
3. If authenticated → `githubPicker` mode with repository list. If not → `manualURL` mode.
4. In GitHub picker: repositories filterable by search query matching `nameWithOwner` or description. Effective clone URL from selected repository's `cloneURL`.
5. Submission validates: repository URL and destination path must be present.
6. `gitCloneRepository` called with **120-second timeout**.
7. On success:
   - Cloned directory added as new project in active vibespace.
   - Project focused.
   - VibeSpace catalog persisted.
   - Terminal hydration scheduled.
   - Source control view model updated.
   - Sheet dismissed.
8. On failure: error message displayed on sheet.

## State Management

- Clone sheet state: current source mode, selected GitHub repository (if picker), manual URL text, destination path, optional directory name.
- GitHub repository list cached for the duration of the sheet presentation.

## API / Command Contracts

| Command | Timeout | Purpose |
|---------|---------|---------|
| `gitHubCloneOptions` | — | Detect GitHub CLI + auth status |
| `gitCloneRepository` | 120 s | Clone repository to destination |

## Dependencies (frameworks, libraries)

- `PaneWorkerClient` (sourceControl kind) — clone execution
- GitHub CLI (`gh`) — repository browsing and authentication detection
- `NSOpenPanel` — directory picker for destination

## Platform Considerations

- GitHub CLI detection is best-effort; fallback to manual URL is seamless.
- Clone timeout (120 s) accommodates large repositories over slow connections.

## Performance Constraints

- Clone timeout: 120 seconds.
- GitHub repository list loaded once per sheet presentation.
