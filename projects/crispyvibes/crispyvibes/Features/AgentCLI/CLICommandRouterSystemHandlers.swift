import Foundation

// MARK: - System handlers

extension CLICommandRouter {

    func handlePing(_ request: CLIRequest) -> CLIResponse {
        return .ok(id: request.id, result: [
            "version": .string(appVersion),
            "build": .string(appBuild),
            "app": .string(appBundleName),
            "protocol_version": .int(1),
        ])
    }

    func handleIdentify(_ request: CLIRequest) -> CLIResponse {
        let env = request._env ?? .empty
        agentCLILogger.notice("identify: store_attached=\(self.vibespaceCatalogStore != nil, privacy: .public) count=\(self.vibespaceCatalogStore?.vibespaces.count ?? -1, privacy: .public)")

        let parsedContext = env.context.flatMap { CLITaggedID(rawValue: $0) }

        let envVibespaceUUID = env.vibespace.flatMap { CLITaggedID(rawValue: $0)?.id }
        let focusedVibespace = vibespaceCatalogStore?.vibespaces.first { $0.id.uuidString == envVibespaceUUID }
            ?? vibespaceCatalogStore?.vibespaces.first
        let staleEnv = (envVibespaceUUID != nil && focusedVibespace?.id.uuidString != envVibespaceUUID)

        var result: [String: CLIJSONValue] = [
            "context": parsedContext.map { .string($0.stringValue) } ?? .null,
            "context_kind": parsedContext.map { .string($0.kind) } ?? .null,
            "vibespace": focusedVibespace.map { .string("vibespace.\($0.id.uuidString)") } ?? .null,
            "vibespace_name": .string(focusedVibespace?.name ?? ""),
            "project_path": .string(env.project_path ?? ""),
            "project_name": .string(URL(fileURLWithPath: env.project_path ?? "").lastPathComponent),
        ]
        if staleEnv {
            result["stale_env"] = .array([.string("vibespace")])
        }
        return .ok(id: request.id, result: result)
    }

    func handleHelp(_ request: CLIRequest) -> CLIResponse {
        if let method = request.params?["method"]?.stringValue, !method.isEmpty {
            guard let registration = commandRegistry.first(where: { $0.method == method }) else {
                return .error(
                    id: request.id,
                    code: CLIErrorCode.unknownMethod,
                    message: "Unknown method: \(method)"
                )
            }
            return .ok(id: request.id, result: [
                "protocol_version": .int(1),
                "commands": .array([registration.descriptor.toJSON(method: registration.method)]),
            ])
        }

        var byDomain: [String: [CommandRegistration]] = [:]
        for reg in commandRegistry {
            let domain = Self.domain(of: reg.method)
            byDomain[domain, default: []].append(reg)
        }
        let domainsArray: [CLIJSONValue] = Self.domains.compactMap { info in
            guard let regs = byDomain[info.name], !regs.isEmpty else { return nil }
            let commands: [CLIJSONValue] = regs.map { reg in
                .object([
                    "method": .string(reg.method),
                    "summary": .string(reg.descriptor.summary),
                ])
            }
            return .object([
                "name": .string(info.name),
                "description": .string(info.description),
                "commands": .array(commands),
            ])
        }
        let conceptsArray: [CLIJSONValue] = Self.concepts.map { c in
            .object([
                "term": .string(c.term),
                "definition": .string(c.definition),
            ])
        }
        return .ok(id: request.id, result: [
            "protocol_version": .int(1),
            "app": .string(appBundleName),
            "summary": .string(Self.appSummary),
            "concepts": .array(conceptsArray),
            "domains": .array(domainsArray),
        ])
    }

    /// Top-level description of what the channel client is connected to.
    static let appSummary = """
    Crispy is a native macOS terminal-first workspace IDE. Developers organize \
    their work into vibespaces (saved collections of projects), each containing \
    one or more projects (root folders). Each vibespace has its own panes \
    holding terminal and browser surfaces, an editor, a pinned shelf of files \
    and folders, and integrated source control. Agents inside a Crispy terminal \
    can read terminal output, drive panes and surfaces, manage the shelf, and \
    operate browser panels — all through this CLI.
    """

    struct ConceptDefinition {
        let term: String
        let definition: String
    }

    /// Glossary of the top concepts an agent will encounter.
    static let concepts: [ConceptDefinition] = [
        ConceptDefinition(
            term: "vibespace",
            definition: "A saved, persistent collection of one or more projects with its own panes, terminals, browser panels, shelf, and settings. The dashboard lists vibespaces; opening one is the user's primary entry point."
        ),
        ConceptDefinition(
            term: "project",
            definition: "One opened root folder inside a vibespace. A vibespace can hold multiple projects; one is focused at a time."
        ),
        ConceptDefinition(
            term: "pane",
            definition: "A split container inside a vibespace that holds terminals, browser panels, or editor tabs. Panes can be split horizontally or vertically."
        ),
        ConceptDefinition(
            term: "shelf",
            definition: "A persistent collection of pinned files and folders shown in the vibespace sidebar. Entries survive app restart; removing an entry never deletes the file on disk."
        ),
        ConceptDefinition(
            term: "channel client",
            definition: "Any process — typically an agent — invoking the `crispy` CLI. Each invocation inherits a tagged context ID (e.g. `terminal.<uuid>` or `acpchat.<uuid>`) and the focused vibespace and project from CRISPY_* environment variables Crispy injects when spawning the process."
        ),
    ]

    /// Returns the domain (namespace prefix) of a method name, or `"core"` for bare names.
    static func domain(of method: String) -> String {
        if let dotIndex = method.firstIndex(of: ".") {
            return String(method[..<dotIndex])
        }
        return "core"
    }

    struct DomainInfo {
        let name: String
        let description: String
    }

    /// Domain catalog. Order here controls the order they appear in `help` output.
    static let domains: [DomainInfo] = [
        DomainInfo(name: "core", description: "Universal meta commands: connectivity, identity, introspection."),
        DomainInfo(name: "todo", description: "Quick todos / sticky notes scoped to a vibespace or project. Agents can add, list, complete, reopen, update, and remove todos; data persists in the encrypted store and surfaces in the Todos panel."),
        DomainInfo(name: "shelf", description: "The shelf is a persistent collection of files and folders pinned by the user, surviving app restarts and visible in the vibespace sidebar. Agents can add or remove entries; Crispy never deletes the underlying files when an entry is removed."),
        DomainInfo(name: "terminal", description: "Terminal sessions inside vibespaces. Each terminal has a UUID and runs a shell process; agents can read screen contents, send text, send key sequences, spawn new terminals, and wait for completion."),
        DomainInfo(name: "browser", description: "Embedded WebKit browser panels scoped to a vibespace. Agents drive navigation, capture DOM snapshots, click and type into elements, evaluate JavaScript, and handle page dialogs."),
        DomainInfo(name: "shortcut", description: "User-defined terminal shortcut catalog (saved command snippets). Agents can list existing shortcuts to discover the project's standard build/test commands, and add new shortcuts that appear alongside user-created ones."),
        DomainInfo(name: "vibespace", description: "A vibespace is Crispy's name for a workspace — a collection of projects with their own settings, terminals, panes, and shelf. Each vibespace can have multiple projects."),
        DomainInfo(name: "pane", description: "Panes are split containers inside a vibespace, holding terminal and browser tabs. Agents inspect the pane tree to discover terminals and browser panels beyond their own."),
        DomainInfo(name: "file", description: "Editor integration. The CLI exposes only what is unique to Crispy (opening a file in the editor with optional cursor position); ordinary file I/O should go through the agent's own filesystem tools or shell."),
    ]
}
