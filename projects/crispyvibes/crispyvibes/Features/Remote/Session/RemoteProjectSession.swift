// RemoteProjectSession.swift — SSH Remote Development
//
// Wires all remote components together into a ProjectProviding conformance.
// Terminal is configured with SSH processLaunchOverride (optionally using tmux).

import AppKit
import Combine
import Foundation

@MainActor
final class RemoteProjectSession: ProjectProviding {
    let id = UUID()
    let metadata: any ProjectMetadata
    let folderExplorer: any FolderExploring
    let gitExplorer: any GitExploring
    let terminal: any TerminalProviding
    let fileContent: any FileContentProviding
    @Published var paneLayout: ProjectPaneLayoutState = .default

    var onFileOpenRequested: ((ExplorerOpenRequest) -> Void)?
    var onFileRenamed: ((ExplorerRenameEvent) -> Void)?

    private let connection: SSHConnection
    private let remotePath: String
    private let terminalViewModel: TerminalViewModel
    private let vibespaceManagement: VibeSpaceManagementService?
    private let vibespaceID: UUID?
    private var cancellables = Set<AnyCancellable>()
    private var lastKnownConnectionState: ConnectionState = .disconnected
    private var shouldReviveTerminalTabsOnNextConnect = false

    init(
        connection: SSHConnection,
        remotePath: String,
        terminalViewModelFactory: @MainActor () -> TerminalViewModel,
        vibespaceManagement: VibeSpaceManagementService? = nil,
        vibespaceID: UUID? = nil,
        enhancedExplorerEnabled: Bool = false
    ) {
        self.connection = connection
        self.remotePath = remotePath
        self.vibespaceManagement = vibespaceManagement
        self.vibespaceID = vibespaceID
        self.metadata = RemoteProjectMetadata(connection: connection, remotePath: remotePath)

        let executor = RemoteCommandExecutor(connection: connection)
        let fileSystem = SFTPFileSystemProvider(connection: connection)
        let watcher = PollingDirectoryWatcher(
            fileSystem: fileSystem,
            interval: enhancedExplorerEnabled ? 2.0 : 5.0,
            snapshotMode: enhancedExplorerEnabled ? .metadata : .namesOnly
        )

        self.fileContent = SFTPFileContentProvider(connection: connection)
        let explorer = RemoteFolderExplorer(
            remotePath: remotePath,
            fileSystem: fileSystem,
            watcher: watcher,
            enhancedMode: enhancedExplorerEnabled
        )
        self.folderExplorer = explorer
        self.gitExplorer = LocalGitExplorer(explorer: explorer, commandExecutor: executor)

        let terminalVM = terminalViewModelFactory()
        self.terminalViewModel = terminalVM
        terminalVM.defaultHostLabel = connection.profile.displayName
        let profile = connection.profile
        let conn = connection
        let rPath = remotePath
        let stableRemoteTmuxSessionName = "crispyvibes-\(Self.stableHash("\(profile.sshURI)\(rPath)"))"
        terminalVM.sessionConfigurator = { [weak terminalVM] session in
            let existingSessionNames = Set(terminalVM?.sessions.values.compactMap(\.tmuxSessionName) ?? [])
            session.tmuxSessionName = Self.resolveRemoteTmuxSessionName(
                persistedSessionName: session.tmuxSessionName,
                existingSessionNames: existingSessionNames,
                stableSessionName: stableRemoteTmuxSessionName
            )
            session.processLaunchOverride = { session in
                Self.makeSSHLaunchInvocation(
                    profile: profile,
                    workingDirectory: rPath,
                    hasTmux: conn.hasTmux,
                    tmuxSessionName: session.tmuxSessionName,
                    relaySocketPath: profile.isAgentCLIEnabled ? CLIExecRelayPathResolver.defaultPath().path : nil
                )
            }
        }
        self.terminal = terminalVM

        restoreRemoteSessionState()
        wireRemotePersistence()

        // Wire file open/rename events
        explorer.$openRequest
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                guard let self, let request else { return }
                explorer.openRequest = nil
                self.onFileOpenRequested?(request)
            }
            .store(in: &cancellables)

        explorer.renameEvents
            .receive(on: RunLoop.main)
            .sink { [weak self] event in self?.onFileRenamed?(event) }
            .store(in: &cancellables)

        connection.statePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, self.hasActivated else { return }
                let previousState = self.lastKnownConnectionState
                self.lastKnownConnectionState = state
                self.handleConnectionStateChange(from: previousState, to: state)
            }
            .store(in: &cancellables)
    }

    var sshConnection: SSHConnection { connection }

    func activate() {
        guard !hasActivated else { return }
        hasActivated = true
        lastKnownConnectionState = connection.state

        if connection.state == .connected {
            presentConnectedSession(afterReconnect: false)
        } else if connection.state != .connecting {
            connectTask = Task {
                do {
                    try await connection.connect()
                } catch {
                    AppDiagnostics.record(category: .terminalLifecycle, level: .error, event: "remote_connect_failed", metadata: ["host": connection.profile.host, "error": error.localizedDescription])
                }
            }
        }
    }

    func ensureExplorerLoaded() { activate() }

    private var hasActivated = false
    private var connectTask: Task<Void, Never>?

    func shutdown() {
        connectTask?.cancel()
        connectTask = nil
        cancellables.removeAll()
        persistRemoteSessionState()
        terminalViewModel.sessionConfigurator = nil
        terminal.shutdown()
        (folderExplorer as? RemoteFolderExplorer)?.stopWatching()
        let connection = connection
        Task { await connection.disconnect() }
    }

    static func shellEscape(_ arg: String) -> String {
        if arg.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "/" || $0 == "." }) { return arg }
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func stableHash(_ input: String) -> String {
        var hash: UInt64 = 5381
        for byte in input.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return String(hash, radix: 16).prefix(8).lowercased()
    }

    static func resolveRemoteTmuxSessionName(
        persistedSessionName: String?,
        existingSessionNames: Set<String>,
        stableSessionName: String
    ) -> String {
        if let persistedSessionName, !persistedSessionName.isEmpty {
            return persistedSessionName
        }
        if existingSessionNames.isEmpty {
            return stableSessionName
        }
        return TmuxService.generateSessionName()
    }

    static func remoteTmuxLaunchCommand(
        workingDirectory: String,
        sessionName: String
    ) -> String {
        let escapedDirectory = shellEscape(workingDirectory)
        let escapedSessionName = shellEscape(sessionName)
        // If the session already exists (e.g. on reconnect, with an agent still
        // running in it), attach cleanly and DON'T re-run the priming setup —
        // re-applying it perturbs the live session. Setup runs only when
        // creating a new session.
        return """
        cd \(escapedDirectory) || exit 1
        export TERM=xterm-256color
        export COLORTERM=truecolor
        if tmux has-session -t \(escapedSessionName) 2>/dev/null; then exec tmux attach-session -t \(escapedSessionName); fi
        \(TmuxService.remotePrimingCommand)
        exec tmux new-session -s \(escapedSessionName) || exec $SHELL -l
        """
    }

    static func makeSSHLaunchInvocation(
        profile: SSHConnectionProfile,
        workingDirectory: String,
        hasTmux: Bool,
        tmuxSessionName: String?,
        relaySocketPath: String? = nil
    ) -> (String, [String]) {
        // Forward COLORTERM so remote programs running outside tmux can detect
        // truecolor support. The remote sshd silently drops env vars it does not
        // accept (`AcceptEnv`), so this is a safe no-op when not whitelisted.
        var args = ["-t", "-o", "SendEnv=COLORTERM", "-p", String(profile.port)]
        if case .keyFile(let path) = profile.authMethod {
            args += ["-i", NSString(string: path).expandingTildeInPath]
        }
        // F051: reverse-forward the local exec-relay socket so a remote `crispy`
        // shim can drive the local app. Forwarding failure is non-fatal — we do
        // NOT set ExitOnForwardFailure — so hosts that forbid forwarding degrade
        // gracefully (the shim then prints a clear error when invoked).
        var relaySetup = ""
        if let relaySocketPath {
            let remoteSock = remoteRelaySocketPath(profile: profile, workingDirectory: workingDirectory)
            args += ["-o", "StreamLocalBindUnlink=yes", "-R", "\(remoteSock):\(relaySocketPath)"]
            relaySetup = remoteRelaySetup(remoteSocketPath: remoteSock, projectPath: workingDirectory)
        }
        args += ["\(profile.user)@\(profile.host)"]
        let launch: String
        if let tmuxSessionName {
            launch = remoteTmuxLaunchCommand(
                workingDirectory: workingDirectory,
                sessionName: tmuxSessionName
            )
        } else {
            launch = "cd \(shellEscape(workingDirectory)) && exec $SHELL -l"
        }
        // Relay setup is best-effort and isolated so it can never abort the shell.
        let remoteCommand = relaySetup.isEmpty ? launch : "{\n\(relaySetup)\n} 2>/dev/null\n\(launch)"
        args += [remoteCommand]
        return ("/usr/bin/ssh", args)
    }

    /// Deterministic per-profile/project remote socket path for the F051 relay
    /// reverse forward. Lives in `/tmp` (transient across reboots);
    /// `StreamLocalBindUnlink=yes` removes it when the forward closes.
    static func remoteRelaySocketPath(profile: SSHConnectionProfile, workingDirectory: String) -> String {
        "/tmp/.crispy-relay-\(stableHash("\(profile.sshURI)\(workingDirectory)")).sock"
    }

    /// Best-effort POSIX-sh that installs a session `crispy` shim on `PATH`. The
    /// shim relays its argv (NUL-separated, prefixed by cwd + project path) to the
    /// local app over the reverse-forwarded socket and reproduces stdout/exit. It
    /// never aborts the launching shell; if `nc`/`socat` are absent it prints a
    /// clear error only when `crispy` is actually invoked.
    static func remoteRelaySetup(remoteSocketPath: String, projectPath: String) -> String {
        let escSock = shellEscape(remoteSocketPath)
        let escProject = shellEscape(projectPath)
        // The wrapper is written to ~/.local/bin so it's on the login PATH that
        // fresh agent shells (`bash -lc "crispy …"`) rebuild — a temp dir on the
        // launch shell's PATH isn't inherited by those. The relay socket and
        // project path are baked in as fallbacks so the wrapper still works when
        // the launch env isn't inherited; the launching shell also exports the
        // live values, which take precedence.
        return """
        mkdir -p "$HOME/.local/bin" 2>/dev/null
        cat > "$HOME/.local/bin/crispy" <<'CRISPY_EOF'
        #!/bin/sh
        : "${CRISPY_RELAY_SOCK:=\(remoteSocketPath)}"
        : "${CRISPY_PROJECT_PATH:=\(projectPath)}"
        if command -v nc >/dev/null 2>&1; then __c() { nc -U "$CRISPY_RELAY_SOCK"; }
        elif command -v socat >/dev/null 2>&1; then __c() { socat - "UNIX-CONNECT:$CRISPY_RELAY_SOCK"; }
        else echo "crispy: IDE relay needs nc or socat on the remote host" >&2; exit 127; fi
        __r=$({ printf '%s\\0' "$PWD" "$CRISPY_PROJECT_PATH"; for a in "$@"; do printf '%s\\0' "$a"; done; printf '\\n'; } | __c 2>/dev/null)
        [ -z "$__r" ] && { echo "crispy: IDE relay unavailable" >&2; exit 127; }
        __code=$(printf '%s\\n' "$__r" | head -n1)
        printf '%s' "$__r" | tail -n +2
        case "$__code" in ""|*[!0-9]*) exit 1 ;; esac
        exit "$__code"
        CRISPY_EOF
        chmod +x "$HOME/.local/bin/crispy" 2>/dev/null
        PATH="$HOME/.local/bin:$PATH"; export PATH
        CRISPY_RELAY_SOCK=\(escSock); export CRISPY_RELAY_SOCK
        CRISPY_PROJECT_PATH=\(escProject); export CRISPY_PROJECT_PATH
        """
    }

    private func handleConnectionStateChange(from previousState: ConnectionState, to state: ConnectionState) {
        let decision = Self.connectionTransitionDecision(
            for: state,
            shouldReviveOnNextConnect: shouldReviveTerminalTabsOnNextConnect
        )
        shouldReviveTerminalTabsOnNextConnect = decision.shouldReviveOnNextConnect

        if decision.shouldStopWatching {
            (folderExplorer as? RemoteFolderExplorer)?.stopWatching()
        }
        if decision.shouldPresentConnectedSession {
            presentConnectedSession(afterReconnect: decision.afterReconnect)
        }
    }

    private func presentConnectedSession(afterReconnect: Bool) {
        (folderExplorer as? RemoteFolderExplorer)?.setRootFolder(URL(fileURLWithPath: remotePath))
        if afterReconnect {
            reviveTerminalTabsAfterReconnect()
        }
        terminal.ensureActiveTerminal(defaultDirectory: URL(fileURLWithPath: remotePath), transitionID: nil, startIfCreated: true)
    }

    private func reviveTerminalTabsAfterReconnect() {
        for restart in Self.reconnectRestartPlan(
            tabs: terminal.tabs,
            activeTabID: terminal.activeTabID
        ) {
            terminal.restartTab(restart.tabID, activateTab: restart.activate)
        }
    }

    private func restoreRemoteSessionState() {
        ProjectTerminalSessionPersistence.restore(
            into: terminalViewModel,
            vibespaceManagement: vibespaceManagement,
            vibespaceID: vibespaceID,
            projectIdentifier: metadata.identifier,
            defaultDirectory: URL(fileURLWithPath: remotePath)
        )
    }

    private func wireRemotePersistence() {
        guard vibespaceManagement != nil, vibespaceID != nil else { return }

        terminalViewModel.tabsPublisher
            .combineLatest(terminalViewModel.activeTabIDPublisher)
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.persistRemoteSessionState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.persistRemoteSessionState()
                self?.terminalViewModel.shutdown()
            }
            .store(in: &cancellables)

        persistRemoteSessionState()
    }

    private func persistRemoteSessionState() {
        ProjectTerminalSessionPersistence.persist(
            from: terminalViewModel,
            vibespaceManagement: vibespaceManagement,
            vibespaceID: vibespaceID,
            projectIdentifier: metadata.identifier
        )
    }

    struct ReconnectRestart: Equatable {
        let tabID: UUID
        let activate: Bool
    }

    struct ConnectionTransitionDecision: Equatable {
        let shouldReviveOnNextConnect: Bool
        let shouldPresentConnectedSession: Bool
        let afterReconnect: Bool
        let shouldStopWatching: Bool
    }

    static func connectionTransitionDecision(
        for state: ConnectionState,
        shouldReviveOnNextConnect: Bool
    ) -> ConnectionTransitionDecision {
        switch state {
        case .connected:
            return ConnectionTransitionDecision(
                shouldReviveOnNextConnect: false,
                shouldPresentConnectedSession: true,
                afterReconnect: shouldReviveOnNextConnect,
                shouldStopWatching: false
            )
        case .connecting:
            return ConnectionTransitionDecision(
                shouldReviveOnNextConnect: shouldReviveOnNextConnect,
                shouldPresentConnectedSession: false,
                afterReconnect: false,
                shouldStopWatching: false
            )
        case .disconnected, .failed:
            return ConnectionTransitionDecision(
                shouldReviveOnNextConnect: true,
                shouldPresentConnectedSession: false,
                afterReconnect: false,
                shouldStopWatching: true
            )
        }
    }

    static func reconnectRestartPlan(
        tabs: [TerminalTab],
        activeTabID: UUID?
    ) -> [ReconnectRestart] {
        tabs.map { tab in
            return ReconnectRestart(
                tabID: tab.id,
                activate: tab.id == activeTabID
            )
        }
    }

    deinit {
        connectTask?.cancel()
        cancellables.removeAll()
    }
}
