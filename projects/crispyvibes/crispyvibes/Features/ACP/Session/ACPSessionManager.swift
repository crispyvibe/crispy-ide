import Combine
import Foundation

@MainActor
class ACPSessionManager: ObservableObject {
    @Published private(set) var backgroundSession: ACPSession?
    @Published private(set) var projectSessionsByIdentifier: [String: ACPSession] = [:]
    @Published private(set) var standaloneSessions: [UUID: any AgentSessionProtocol] = [:]

    private let observabilityStore: ACPObservabilityStore?

    init(observabilityStore: ACPObservabilityStore? = nil) {
        self.observabilityStore = observabilityStore
    }

    func connectBackground(
        agent: ACPAgentDefinition,
        workingDirectory: URL,
        autoAllowPermissions: Bool = false
    ) async throws -> ACPSession {
        backgroundSession?.disconnect()
        let session = makeSession(
            hostContext: .background(workingDirectory: workingDirectory),
            agent: agent,
            origin: "background",
            autoAllowPermissions: autoAllowPermissions
        )
        try await session.connect()
        backgroundSession = session
        return session
    }

    func connect(
        project: AnyProjectSession,
        agent: ACPAgentDefinition,
        autoAllowPermissions: Bool = false
    ) async throws -> ACPSession {
        let key = project.projectIdentifier
        projectSessionsByIdentifier[key]?.disconnect()

        let session = makeSession(
            hostContext: ACPHostContext(project: project),
            agent: agent,
            origin: "project",
            autoAllowPermissions: autoAllowPermissions
        )
        try await session.connect()
        projectSessionsByIdentifier[key] = session
        return session
    }

    func registerStandalone(id: UUID, session: ACPSession) {
        standaloneSessions[id] = session
    }

    func registerStandalone(id: UUID, session: any AgentSessionProtocol) {
        standaloneSessions[id] = session
    }

    func unregisterStandalone(id: UUID) {
        standaloneSessions.removeValue(forKey: id)?.disconnect()
    }

    func connectStandalone(
        id: UUID,
        project: AnyProjectSession,
        agent: ACPAgentDefinition,
        autoAllowPermissions: Bool = false
    ) async throws -> ACPSession {
        standaloneSessions[id]?.disconnect()

        let session = makeSession(
            hostContext: ACPHostContext(project: project),
            agent: agent,
            origin: "standalone",
            autoAllowPermissions: autoAllowPermissions
        )
        try await session.connect()
        standaloneSessions[id] = session
        return session
    }

    func session(for projectIdentifier: String) -> ACPSession? {
        projectSessionsByIdentifier[projectIdentifier]
    }

    func disconnect(projectIdentifier: String) {
        projectSessionsByIdentifier.removeValue(forKey: projectIdentifier)?.disconnect()
    }

    func release(_ session: ACPSession) {
        if backgroundSession?.id == session.id {
            backgroundSession?.disconnect()
            backgroundSession = nil
            return
        }
        if let key = projectSessionsByIdentifier.first(where: { $0.value.id == session.id })?.key {
            projectSessionsByIdentifier.removeValue(forKey: key)?.disconnect()
            return
        }
        if let key = standaloneSessions.first(where: { $0.value.id == session.id })?.key {
            standaloneSessions.removeValue(forKey: key)?.disconnect()
        }
    }

    func disconnectAll() {
        backgroundSession?.disconnect()
        backgroundSession = nil
        for session in projectSessionsByIdentifier.values {
            session.disconnect()
        }
        projectSessionsByIdentifier.removeAll()
        for session in standaloneSessions.values {
            session.disconnect()
        }
        standaloneSessions.removeAll()
    }

    private func makeSession(
        hostContext: ACPHostContext,
        agent: ACPAgentDefinition,
        origin: String,
        autoAllowPermissions: Bool
    ) -> ACPSession {
        let session = ACPSession(
            projectPath: hostContext.projectRootURL,
            agent: agent,
            origin: origin,
            observabilityStore: observabilityStore
        )

        let permissionHandler = ACPPermissionHandler(observabilityStore: observabilityStore)
        permissionHandler.allowAll = autoAllowPermissions

        session.installHandlers(
            fileSystem: ACPFileSystemHandler(
                hostContext: hostContext,
                observabilityStore: observabilityStore,
                onDiffGenerated: { [weak session] toolCallId, diff in
                    Task { @MainActor in
                        session?.permissionHandler?.onDiffsReceived?(toolCallId, [.diff(diff)])
                    }
                }
            ),
            terminal: ACPTerminalHandler(
                sessionIdentifier: session.id.uuidString,
                terminalProvider: hostContext.terminalProvider,
                observabilityStore: observabilityStore
            ),
            permission: permissionHandler
        )
        return session
    }
}
