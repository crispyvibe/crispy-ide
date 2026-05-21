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
        vibespaceID: UUID? = nil
    ) {
        self.connection = connection
        self.remotePath = remotePath
        self.vibespaceManagement = vibespaceManagement
        self.vibespaceID = vibespaceID
        self.metadata = RemoteProjectMetadata(connection: connection, remotePath: remotePath)

        let executor = RemoteCommandExecutor(connection: connection)
        let fileSystem = SFTPFileSystemProvider(connection: connection)
        let watcher = PollingDirectoryWatcher(connection: connection)

        self.fileContent = SFTPFileContentProvider(connection: connection)
        let explorer = RemoteFolderExplorer(remotePath: remotePath, fileSystem: fileSystem, watcher: watcher)
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
                    tmuxSessionName: session.tmuxSessionName
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
        let tmuxSetupCommands = [
            // tmux 2.1+ uses 'mouse on'; older versions use mode-mouse/mouse-select-*
            "tmux set-option -g mouse on 2>/dev/null || { tmux set-option -g mode-mouse on 2>/dev/null; tmux set-option -g mouse-select-pane on 2>/dev/null; tmux set-option -g mouse-resize-pane on 2>/dev/null; tmux set-option -g mouse-select-window on 2>/dev/null; }",
            "tmux set-option -g history-limit 50000 2>/dev/null",
            "tmux set-option -g status off 2>/dev/null",
            "tmux set-option -g escape-time 0 2>/dev/null",
            // Enable truecolor (24-bit RGB) passthrough so modern TUIs (vim, nvim,
            // lazygit, btop, etc.) render with full color fidelity. Append rather
            // than replace so any user-provided overrides are preserved.
            "tmux set-option -ga terminal-overrides \",*:RGB\" 2>/dev/null",
            // Promote default-terminal away from tmux's bare 'screen' default so
            // inner programs see a 256-color capable terminfo. Only override when
            // the user has not configured something themselves (still at default).
            "__crispy_default_term=$(tmux show-option -gqv default-terminal 2>/dev/null); if [ -z \"$__crispy_default_term\" ] || [ \"$__crispy_default_term\" = \"screen\" ]; then tmux set-option -g default-terminal \"$__crispy_term\" 2>/dev/null; fi"
        ]
        // Pick the best terminfo entry actually installed on the remote so we
        // never advertise a terminfo the system can't resolve. Falls back to
        // tmux's own default ('screen') if neither modern entry is available.
        let pickTermFunction = """
        __crispy_pick_term() {
            if command -v infocmp >/dev/null 2>&1; then
                if infocmp tmux-256color >/dev/null 2>&1; then echo tmux-256color; return; fi
                if infocmp screen-256color >/dev/null 2>&1; then echo screen-256color; return; fi
            fi
            echo screen
        }
        __crispy_term=$(__crispy_pick_term)
        """
        // Start server first to ensure set-option works, then create/attach.
        return """
        cd \(escapedDirectory) || exit 1
        export TERM=xterm-256color
        export COLORTERM=truecolor
        \(pickTermFunction)
        tmux start-server 2>/dev/null; \(tmuxSetupCommands.joined(separator: "; "))
        exec tmux new-session -A -s \(escapedSessionName) || exec $SHELL -l
        """
    }

    static func makeSSHLaunchInvocation(
        profile: SSHConnectionProfile,
        workingDirectory: String,
        hasTmux: Bool,
        tmuxSessionName: String?
    ) -> (String, [String]) {
        // Forward COLORTERM so remote programs running outside tmux can detect
        // truecolor support. The remote sshd silently drops env vars it does not
        // accept (`AcceptEnv`), so this is a safe no-op when not whitelisted.
        var args = ["-t", "-o", "SendEnv=COLORTERM", "-p", String(profile.port)]
        if case .keyFile(let path) = profile.authMethod {
            args += ["-i", NSString(string: path).expandingTildeInPath]
        }
        args += ["\(profile.user)@\(profile.host)"]
        let remoteCommand: String
        if let tmuxSessionName {
            remoteCommand = remoteTmuxLaunchCommand(
                workingDirectory: workingDirectory,
                sessionName: tmuxSessionName
            )
        } else {
            remoteCommand = "cd \(shellEscape(workingDirectory)) && exec $SHELL -l"
        }
        args += [remoteCommand]
        return ("/usr/bin/ssh", args)
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
