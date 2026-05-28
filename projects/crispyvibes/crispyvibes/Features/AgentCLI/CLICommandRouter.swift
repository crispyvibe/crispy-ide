import Foundation
import OSLog

let agentCLILogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app",
    category: "agent-cli.router"
)

/// Dispatches `CLIRequest`s to handler functions and produces `CLIResponse`s.
/// Stateless aside from references to existing services injected at init.
@MainActor
final class CLICommandRouter {
    let appBundleName: String
    let appVersion: String
    let appBuild: String

    let shelfStore: ShelfStore
    var vibespaceCatalogStore: VibeSpaceCatalogStore?
    var vibespaceManagement: VibeSpaceManagementService?
    var dockedBrowserCoordinator: DockedBrowserCoordinator?
    /// F044-R80–R82: late-bound canvas actions coordinator used by
    /// `vibespace.addProject` / `removeProject` / `parkProject` so CLI mutations
    /// use the same orchestration path (close pipeline, persistence,
    /// hydration) as user-driven UI actions. Wired by `ContentView` once it
    /// has constructed the coordinator. Weak so the router doesn't pin the
    /// UI-layer coordinator.
    weak var vibespaceActionsCoordinator: VibeSpaceCanvasActionsCoordinator?

    /// F049-R02 / R03: late-bound reference to the central comment store so
    /// CLI handlers can read/write comments via the same Rust-backed store
    /// the UI uses.
    weak var vibespaceCommentStore: VibeSpaceCommentStore?

    init(
        appBundleName: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Crispy",
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
        appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
        shelfStore: ShelfStore,
        vibespaceCatalogStore: VibeSpaceCatalogStore? = nil
    ) {
        self.appBundleName = appBundleName
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.shelfStore = shelfStore
        self.vibespaceCatalogStore = vibespaceCatalogStore
    }

    /// Late-bound injection of the catalog store, since `VibeSpaceCatalogStore`
    /// is created during `ContentView` setup, after `AppContainer.makeDefault()`
    /// has already constructed this router.
    func attachVibeSpaceCatalogStore(_ store: VibeSpaceCatalogStore) {
        if vibespaceCatalogStore != nil {
            agentCLILogger.notice("catalog store attach skipped (already attached)")
            return
        }
        self.vibespaceCatalogStore = store
        agentCLILogger.notice("catalog store attached, vibespaces.count=\(store.vibespaces.count, privacy: .public)")
    }

    func attachVibeSpaceManagement(_ service: VibeSpaceManagementService) {
        self.vibespaceManagement = service
    }

    /// Late-bound idempotent injection of the docked browser coordinator. Critical
    /// that this is idempotent: `AppContainer.makeContentViewDependencies` runs on
    /// every `ContentView.init`, which fires every time `RootView.body` re-evaluates.
    /// A fresh `DockedBrowserCoordinator` is created each time, but SwiftUI keeps
    /// only the first via `@StateObject`. If we reassigned on every call, the CLI
    /// router would point at a discarded coordinator while the views still use the
    /// original — `browser list` would return empty, `agentAPI(for:)` would return
    /// "browser_not_found".
    func attachDockedBrowserCoordinator(_ coordinator: DockedBrowserCoordinator) {
        if dockedBrowserCoordinator != nil {
            agentCLILogger.notice("docked browser coordinator attach skipped (already attached)")
            return
        }
        self.dockedBrowserCoordinator = coordinator
        agentCLILogger.notice("docked browser coordinator attached")
    }

    /// Late-bound idempotent injection of the vibespace canvas actions
    /// coordinator. Same rationale as `attachDockedBrowserCoordinator` —
    /// `ContentView.init` runs on every body re-evaluation, so guarding
    /// against re-attach prevents the router from pointing at a stale
    /// coordinator while views still use the original.
    func attachVibeSpaceActionsCoordinator(_ coordinator: VibeSpaceCanvasActionsCoordinator) {
        if vibespaceActionsCoordinator != nil {
            agentCLILogger.notice("vibespace actions coordinator attach skipped (already attached)")
            return
        }
        self.vibespaceActionsCoordinator = coordinator
        agentCLILogger.notice("vibespace actions coordinator attached")
    }

    /// F049: late-bound idempotent injection of the central comment store.
    func attachVibeSpaceCommentStore(_ store: VibeSpaceCommentStore) {
        if vibespaceCommentStore != nil {
            agentCLILogger.notice("vibespace comment store attach skipped (already attached)")
            return
        }
        self.vibespaceCommentStore = store
        agentCLILogger.notice("vibespace comment store attached")
    }

    func dispatch(_ request: CLIRequest) async -> CLIResponse {
        guard let registration = commandRegistry.first(where: { $0.method == request.method }) else {
            return .error(
                id: request.id,
                code: CLIErrorCode.unknownMethod,
                message: "Unknown method: \(request.method)"
            )
        }
        // Forwarded browser commands use the generic async dispatcher
        if request.method.hasPrefix("browser.") && request.method != "browser.list"
            && request.method != "browser.open" && request.method != "browser.close" {
            return await handleBrowserDispatch(request)
        }
        return await registration.handler(request)
    }

    // MARK: - Registry types

    struct CommandRegistration {
        let method: String
        let descriptor: CommandDescriptor
        let handler: (CLIRequest) async -> CLIResponse
    }

    struct CommandDescriptor {
        let summary: String
        let params: [ParamDescriptor]
        let result: [ResultFieldDescriptor]
        let errors: [String]

        func toJSON(method: String) -> CLIJSONValue {
            .object([
                "method": .string(method),
                "summary": .string(summary),
                "params": .array(params.map { $0.toJSON() }),
                "result_fields": .array(result.map { $0.toJSON() }),
                "errors": .array(errors.map { .string($0) }),
            ])
        }
    }

    struct ParamDescriptor {
        let name: String
        let type: String
        var required: Bool = false
        let description: String
        var defaultValue: CLIJSONValue?

        func toJSON() -> CLIJSONValue {
            var obj: [String: CLIJSONValue] = [
                "name": .string(name),
                "type": .string(type),
                "required": .bool(required),
                "description": .string(description),
            ]
            if let defaultValue { obj["default"] = defaultValue }
            return .object(obj)
        }
    }

    struct ResultFieldDescriptor {
        let name: String
        let type: String
        let description: String
        var nullable: Bool = false

        func toJSON() -> CLIJSONValue {
            .object([
                "name": .string(name),
                "type": .string(type),
                "description": .string(description),
                "nullable": .bool(nullable),
            ])
        }
    }

    // MARK: - Command registry

    lazy var commandRegistry: [CommandRegistration] = [
        CommandRegistration(
            method: "ping",
            descriptor: CommandDescriptor(
                summary: "Health check; returns app metadata.",
                params: [],
                result: [
                    .init(name: "version", type: "string", description: "App display version."),
                    .init(name: "build", type: "string", description: "App build number."),
                    .init(name: "app", type: "string", description: "App display name."),
                    .init(name: "protocol_version", type: "integer", description: "Agent CLI protocol version."),
                ],
                errors: []
            ),
            handler: { [unowned self] req in self.handlePing(req) }
        ),
        CommandRegistration(
            method: "whoami",
            descriptor: CommandDescriptor(
                summary: "Returns the channel client's resolved context.",
                params: [],
                result: [
                    .init(name: "context", type: "string", description: "Tagged ID of the caller's process.", nullable: true),
                    .init(name: "context_kind", type: "string", description: "The prefix portion of `context`.", nullable: true),
                    .init(name: "vibespace", type: "string", description: "Tagged ID of the focused vibespace.", nullable: true),
                    .init(name: "vibespace_name", type: "string", description: "Display name of the focused vibespace."),
                    .init(name: "project_path", type: "string", description: "Absolute path to the focused project."),
                    .init(name: "project_name", type: "string", description: "Display name of the focused project."),
                    .init(name: "stale_env", type: "array", description: "Names of `_env` fields whose values were ignored.", nullable: true),
                ],
                errors: []
            ),
            handler: { [unowned self] req in self.handleIdentify(req) }
        ),
        CommandRegistration(
            method: "help",
            descriptor: CommandDescriptor(
                summary: "List all supported methods, or describe a single method when `method` is provided.",
                params: [
                    .init(name: "method", type: "string", required: false, description: "When provided, returns the full descriptor for just that method."),
                ],
                result: [
                    .init(name: "protocol_version", type: "integer", description: "Agent CLI protocol version."),
                    .init(name: "commands", type: "array", description: "Array of command descriptors."),
                ],
                errors: ["unknown_method"]
            ),
            handler: { [unowned self] req in self.handleHelp(req) }
        ),
        CommandRegistration(
            method: "shelf.add",
            descriptor: CommandDescriptor(
                summary: "Add a file or folder to the shelf.",
                params: [
                    .init(name: "path", type: "string", required: true, description: "Absolute path, or relative to the channel client's CRISPY_PROJECT_PATH."),
                    .init(name: "select", type: "boolean", required: false, description: "If true, make this the selected shelf item.", defaultValue: .bool(false)),
                ],
                result: [
                    .init(name: "path", type: "string", description: "Resolved absolute path."),
                    .init(name: "kind", type: "string", description: "\"file\" or \"folder\"."),
                    .init(name: "added", type: "boolean", description: "True if newly added."),
                    .init(name: "selected", type: "boolean", description: "True if now selected."),
                ],
                errors: ["invalid_params", "file_not_found"]
            ),
            handler: { [unowned self] req in self.handleShelfAdd(req) }
        ),
        CommandRegistration(
            method: "shelf.list",
            descriptor: CommandDescriptor(
                summary: "List all entries in the shelf.",
                params: [],
                result: [
                    .init(name: "items", type: "array", description: "Array of shelf items in display order."),
                    .init(name: "selected_path", type: "string", description: "Path of the currently-selected shelf item, or null.", nullable: true),
                ],
                errors: []
            ),
            handler: { [unowned self] req in self.handleShelfList(req) }
        ),
        CommandRegistration(
            method: "shelf.remove",
            descriptor: CommandDescriptor(
                summary: "Remove a file or folder from the shelf. Does not delete the file from disk.",
                params: [
                    .init(name: "path", type: "string", required: true, description: "Path to remove."),
                ],
                result: [
                    .init(name: "removed", type: "boolean", description: "True if an entry was removed."),
                ],
                errors: ["invalid_params"]
            ),
            handler: { [unowned self] req in self.handleShelfRemove(req) }
        ),
        // MARK: File
        CommandRegistration(
            method: "file.open",
            descriptor: CommandDescriptor(
                summary: "Open a file in the editor at an optional line and column.",
                params: [
                    .init(name: "path", type: "string", required: true, description: "Absolute or project-relative path."),
                    .init(name: "line", type: "integer", required: false, description: "1-based line to scroll to."),
                    .init(name: "column", type: "integer", required: false, description: "1-based column (requires line)."),
                ],
                result: [
                    .init(name: "path", type: "string", description: "Resolved absolute path."),
                    .init(name: "line", type: "integer", description: "Caret line if provided.", nullable: true),
                ],
                errors: ["invalid_params", "file_not_found"]
            ),
            handler: { [unowned self] req in self.handleFileOpen(req) }
        ),
        // MARK: Shortcuts
        CommandRegistration(
            method: "shortcut.list",
            descriptor: CommandDescriptor(
                summary: "List saved terminal shortcuts (vibespace + project scoped).",
                params: [],
                result: [.init(name: "shortcuts", type: "array", description: "Array of shortcut descriptors.")],
                errors: []
            ),
            handler: { [unowned self] req in self.handleShortcutList(req) }
        ),
        CommandRegistration(
            method: "shortcut.add",
            descriptor: CommandDescriptor(
                summary: "Register a new terminal shortcut.",
                params: [
                    .init(name: "name", type: "string", required: true, description: "Display name."),
                    .init(name: "command", type: "string", required: true, description: "Command line to run."),
                    .init(name: "launch_behavior", type: "string", required: true, description: "One of: currentTerminal, newPermanentTerminal, newTemporaryTerminal."),
                    .init(name: "scope", type: "string", required: false, description: "\"vibespace\" (default) or \"project\". Project scope uses the caller's CRISPY_PROJECT_PATH.", defaultValue: .string("vibespace")),
                ],
                result: [
                    .init(name: "id", type: "string", description: "UUID of the new shortcut."),
                    .init(name: "name", type: "string", description: "Resolved name."),
                    .init(name: "command", type: "string", description: "Resolved command."),
                    .init(name: "launch_behavior", type: "string", description: "Resolved launch behavior."),
                    .init(name: "scope", type: "string", description: "Resolved scope."),
                ],
                errors: ["invalid_params", "not_connected"]
            ),
            handler: { [unowned self] req in self.handleShortcutAdd(req) }
        ),
        CommandRegistration(
            method: "shortcut.remove",
            descriptor: CommandDescriptor(
                summary: "Remove a shortcut by ID.",
                params: [
                    .init(name: "id", type: "string", required: true, description: "UUID of the shortcut to remove (from shortcut.list output)."),
                ],
                result: [
                    .init(name: "removed", type: "boolean", description: "True if the shortcut was found and removed."),
                ],
                errors: ["invalid_params", "not_connected"]
            ),
            handler: { [unowned self] req in self.handleShortcutRemove(req) }
        ),
        // MARK: Terminal
        CommandRegistration(
            method: "terminal.list",
            descriptor: CommandDescriptor(
                summary: "List all terminals in the focused vibespace.",
                params: [],
                result: [.init(name: "terminals", type: "array", description: "Array of terminal descriptors.")],
                errors: []
            ),
            handler: { [unowned self] req in self.handleTerminalList(req) }
        ),
        CommandRegistration(
            method: "terminal.create",
            descriptor: CommandDescriptor(
                summary: "Spawn a new terminal.",
                params: [
                    .init(name: "cwd", type: "string", required: false, description: "Absolute path for the working directory."),
                    .init(name: "name", type: "string", required: false, description: "Custom tab title."),
                ],
                result: [.init(name: "terminal_id", type: "string", description: "Tagged ID of the new terminal.")],
                errors: ["invalid_params", "not_connected"]
            ),
            handler: { [unowned self] req in self.handleTerminalCreate(req) }
        ),
        CommandRegistration(
            method: "terminal.send",
            descriptor: CommandDescriptor(
                summary: "Inject text into a terminal.",
                params: [
                    .init(name: "text", type: "string", required: true, description: "UTF-8 text to inject."),
                    .init(name: "terminal_id", type: "string", required: true, description: "Tagged or bare UUID of the target terminal."),
                    .init(name: "submit", type: "boolean", required: false, description: "Append newline after text.", defaultValue: .bool(false)),
                ],
                result: [],
                errors: ["invalid_params", "terminal_not_found"]
            ),
            handler: { [unowned self] req in self.handleTerminalSend(req) }
        ),
        CommandRegistration(
            method: "terminal.send_key",
            descriptor: CommandDescriptor(
                summary: "Send a named key event (Enter, Ctrl+C, arrows, etc.).",
                params: [
                    .init(name: "key", type: "string", required: true, description: "Key name (e.g. Enter, Ctrl+C, Tab, Up)."),
                    .init(name: "terminal_id", type: "string", required: true, description: "Tagged or bare UUID of the target terminal."),
                ],
                result: [],
                errors: ["invalid_params", "terminal_not_found"]
            ),
            handler: { [unowned self] req in self.handleTerminalSendKey(req) }
        ),
        CommandRegistration(
            method: "terminal.close",
            descriptor: CommandDescriptor(
                summary: "Close a terminal.",
                params: [
                    .init(name: "terminal_id", type: "string", required: true, description: "Tagged or bare UUID of the terminal to close."),
                ],
                result: [],
                errors: ["invalid_params", "terminal_not_found"]
            ),
            handler: { [unowned self] req in self.handleTerminalClose(req) }
        ),
        CommandRegistration(
            method: "terminal.wait",
            descriptor: CommandDescriptor(
                summary: "Block until terminal output matches text or the process exits.",
                params: [
                    .init(name: "terminal_id", type: "string", required: false, description: "Tagged or bare UUID. Defaults to caller's context."),
                    .init(name: "text", type: "string", required: false, description: "Wait until this substring appears in output."),
                    .init(name: "exit", type: "boolean", required: false, description: "Wait until the terminal process exits."),
                    .init(name: "timeout", type: "integer", required: false, description: "Seconds to wait (1-600).", defaultValue: .int(30)),
                ],
                result: [
                    .init(name: "matched", type: "boolean", description: "True if condition was met before timeout."),
                    .init(name: "text", type: "string", description: "Matched text (when text condition triggered).", nullable: true),
                    .init(name: "exit_code", type: "integer", description: "Process exit code (when exit condition triggered).", nullable: true),
                ],
                errors: ["invalid_params", "terminal_not_found", "timeout"]
            ),
            handler: { [unowned self] req in await self.handleTerminalWait(req) }
        ),
        // MARK: Browser
        CommandRegistration(
            method: "browser.list",
            descriptor: CommandDescriptor(
                summary: "List open browser tabs owned by the caller's project (default), or across the vibespace.",
                params: [
                    .init(name: "query", type: "string", required: false, description: "Filter by title or URL substring."),
                    .init(name: "scope", type: "string", required: false, description: "\"project\" (default) returns browsers owned by CRISPY_PROJECT_PATH / focused project; \"vibespace\" returns every browser in the vibespace.", defaultValue: .string("project")),
                ],
                result: [.init(name: "tabs", type: "array", description: "Array of {browser_id, title, url, project_path}. project_path is null for browsers with no resolved project owner.")],
                errors: ["invalid_params", "no_focused_project"]
            ),
            handler: { [unowned self] req in self.handleBrowserList(req) }
        ),
        CommandRegistration(
            method: "browser.open",
            descriptor: CommandDescriptor(
                summary: "Open a new browser tab.",
                params: [.init(name: "url", type: "string", required: false, description: "URL to load (default: about:blank).")],
                result: [.init(name: "browser_id", type: "string", description: "Tagged ID of the new tab.")],
                errors: ["not_connected"]
            ),
            handler: { [unowned self] req in self.handleBrowserOpen(req) }
        ),
        CommandRegistration(
            method: "browser.close",
            descriptor: CommandDescriptor(
                summary: "Close a browser tab.",
                params: [.init(name: "browser_id", type: "string", required: true, description: "Tagged or bare UUID of the tab.")],
                result: [.init(name: "closed", type: "boolean", description: "True if closed.")],
                errors: ["browser_not_found"]
            ),
            handler: { [unowned self] req in self.handleBrowserClose(req) }
        ),
        // MARK: VibeSpace
        CommandRegistration(
            method: "vibespace.addProject",
            descriptor: CommandDescriptor(
                summary: "Add a project to the focused vibespace and focus it (F044-R80).",
                params: [
                    .init(name: "path", type: "string", required: true, description: "Absolute path to the project directory."),
                ],
                result: [
                    .init(name: "project_path", type: "string", description: "Resolved absolute path of the added project."),
                    .init(name: "project_name", type: "string", description: "Display name of the added project."),
                    .init(name: "focused", type: "boolean", description: "True — the new project becomes focused per F021-S03."),
                ],
                errors: ["invalid_params", "file_not_found", "vibespace_not_found", "not_connected"]
            ),
            handler: { [unowned self] req in self.handleVibeSpaceAddProject(req) }
        ),
        CommandRegistration(
            method: "vibespace.removeProject",
            descriptor: CommandDescriptor(
                summary: "Remove a project from the focused vibespace, closing all its terminals/browsers (F044-R81).",
                params: [
                    .init(name: "path", type: "string", required: true, description: "Absolute path of the project to remove."),
                ],
                result: [
                    .init(name: "removed_project_path", type: "string", description: "Resolved absolute path of the removed project."),
                ],
                errors: ["invalid_params", "file_not_found", "vibespace_not_found", "not_connected"]
            ),
            handler: { [unowned self] req in self.handleVibeSpaceRemoveProject(req) }
        ),
        CommandRegistration(
            method: "vibespace.parkProject",
            descriptor: CommandDescriptor(
                summary: "Park a project in the focused vibespace, persisting state and terminating sessions (F044-R82).",
                params: [
                    .init(name: "path", type: "string", required: true, description: "Absolute path of the project to park."),
                ],
                result: [
                    .init(name: "parked_project_path", type: "string", description: "Resolved absolute path of the parked project."),
                ],
                errors: ["invalid_params", "file_not_found", "vibespace_not_found", "not_connected"]
            ),
            handler: { [unowned self] req in self.handleVibeSpaceParkProject(req) }
        ),
        // MARK: Comments (F049)
        CommandRegistration(
            method: "comments.add",
            descriptor: CommandDescriptor(
                summary: "Add a file comment at a specific line range (F049-R03).",
                params: [
                    .init(name: "file", type: "string", required: true, description: "File path (absolute or project-relative)."),
                    .init(name: "start_line", type: "integer", required: true, description: "1-based start line."),
                    .init(name: "start_column", type: "integer", required: false, description: "1-based start column.", defaultValue: .int(1)),
                    .init(name: "end_line", type: "integer", required: false, description: "1-based end line (defaults to start line)."),
                    .init(name: "end_column", type: "integer", required: false, description: "1-based end column."),
                    .init(name: "body", type: "string", required: true, description: "Comment body (markdown)."),
                    .init(name: "parent_id", type: "string", required: false, description: "Parent comment ID for threaded replies."),
                ],
                result: [.init(name: "id", type: "string", description: "ID of the created comment.")],
                errors: ["invalid_params", "file_not_found", "internal_error", "not_connected"]
            ),
            handler: { [unowned self] req in await self.handleCommentsAdd(req) }
        ),
        CommandRegistration(
            method: "comments.list",
            descriptor: CommandDescriptor(
                summary: "List comments for a file or across the active vibespace.",
                params: [
                    .init(name: "file", type: "string", required: false, description: "File path filter; omit to list all."),
                    .init(name: "status", type: "string", required: false, description: "Status filter: active, resolved, stale, all.", defaultValue: .string("active")),
                ],
                result: [.init(name: "comments", type: "array", description: "Flat array of comments (replies inline).")],
                errors: ["invalid_params", "file_not_found", "vibespace_not_found", "not_connected"]
            ),
            handler: { [unowned self] req in await self.handleCommentsList(req) }
        ),
        CommandRegistration(
            method: "comments.reply",
            descriptor: CommandDescriptor(
                summary: "Reply to an existing comment thread.",
                params: [
                    .init(name: "id", type: "string", required: true, description: "Parent comment ID."),
                    .init(name: "body", type: "string", required: true, description: "Reply body."),
                ],
                result: [.init(name: "id", type: "string", description: "ID of the created reply.")],
                errors: ["invalid_params", "internal_error", "not_connected"]
            ),
            handler: { [unowned self] req in await self.handleCommentsReply(req) }
        ),
        CommandRegistration(
            method: "comments.update",
            descriptor: CommandDescriptor(
                summary: "Update the body of an existing comment.",
                params: [
                    .init(name: "id", type: "string", required: true, description: "Comment ID."),
                    .init(name: "body", type: "string", required: true, description: "New body."),
                ],
                result: [.init(name: "id", type: "string", description: "ID of the updated comment.")],
                errors: ["invalid_params", "internal_error", "not_connected"]
            ),
            handler: { [unowned self] req in await self.handleCommentsUpdate(req) }
        ),
        CommandRegistration(
            method: "comments.resolve",
            descriptor: CommandDescriptor(
                summary: "Mark a comment thread as resolved (or pass `unresolve: true` to reopen).",
                params: [
                    .init(name: "id", type: "string", required: true, description: "Comment ID."),
                    .init(name: "unresolve", type: "boolean", required: false, description: "Reopen a previously-resolved thread.", defaultValue: .bool(false)),
                ],
                result: [
                    .init(name: "id", type: "string", description: "ID of the comment."),
                    .init(name: "resolvedAt", type: "string", description: "ISO 8601 timestamp, or null when reopened.", nullable: true),
                ],
                errors: ["invalid_params", "internal_error", "not_connected"]
            ),
            handler: { [unowned self] req in await self.handleCommentsResolve(req) }
        ),
        CommandRegistration(
            method: "comments.delete",
            descriptor: CommandDescriptor(
                summary: "Delete a comment (cascades to all replies).",
                params: [.init(name: "id", type: "string", required: true, description: "Comment ID.")],
                result: [
                    .init(name: "id", type: "string", description: "ID of the deleted root."),
                    .init(name: "deletedCount", type: "integer", description: "Number of comments removed (root + replies)."),
                ],
                errors: ["invalid_params", "internal_error", "not_connected"]
            ),
            handler: { [unowned self] req in await self.handleCommentsDelete(req) }
        ),
        CommandRegistration(
            method: "comments.search",
            descriptor: CommandDescriptor(
                summary: "Full-text search comments in the active vibespace.",
                params: [
                    .init(name: "query", type: "string", required: false, description: "Search text."),
                    .init(name: "file_prefix", type: "string", required: false, description: "Restrict to files under this path prefix."),
                    .init(name: "status", type: "string", required: false, description: "Status filter.", defaultValue: .string("active")),
                ],
                result: [.init(name: "comments", type: "array", description: "Matching comments.")],
                errors: ["invalid_params", "internal_error", "not_connected"]
            ),
            handler: { [unowned self] req in await self.handleCommentsSearch(req) }
        ),
    ] + Self.browserForwardedRegistrations

    /// Bulk registrations for the 48 per-tab browser commands forwarded to BrowserAgentAPI.
    private static var browserForwardedRegistrations: [CommandRegistration] {
        let methods: [(String, String)] = [
            ("browser.navigate", "Navigate to a URL. Params: url (string, required)."),
            ("browser.back", "Go back in history."),
            ("browser.forward", "Go forward in history."),
            ("browser.reload", "Reload the page."),
            ("browser.url.get", "Get the current URL."),
            ("browser.get.title", "Get the page title."),
            ("browser.click", "Click an element. Params: selector (string, required)."),
            ("browser.dblclick", "Double-click an element. Params: selector (string, required)."),
            ("browser.hover", "Hover over an element. Params: selector (string, required)."),
            ("browser.focus", "Focus an element. Params: selector (string, required)."),
            ("browser.fill", "Fill an input. Params: selector (string, required), text (string, required)."),
            ("browser.type", "Type text character-by-character. Params: selector (string, required), text (string, required)."),
            ("browser.press", "Press a key. Params: key (string, required)."),
            ("browser.check", "Check a checkbox. Params: selector (string, required)."),
            ("browser.uncheck", "Uncheck a checkbox. Params: selector (string, required)."),
            ("browser.select", "Select an option. Params: selector (string, required), value (string, required)."),
            ("browser.scroll", "Scroll the page. Params: x (int), y (int)."),
            ("browser.scroll_into_view", "Scroll element into view. Params: selector (string, required)."),
            ("browser.get.text", "Get element text. Params: selector (string, required)."),
            ("browser.get.html", "Get element HTML. Params: selector (string, required)."),
            ("browser.get.value", "Get input value. Params: selector (string, required)."),
            ("browser.get.attr", "Get element attribute. Params: selector (string, required), attr (string, required)."),
            ("browser.get.count", "Count matching elements. Params: selector (string, required)."),
            ("browser.get.box", "Get bounding box. Params: selector (string, required)."),
            ("browser.get.styles", "Get computed styles. Params: selector (string, required), properties (array)."),
            ("browser.is.visible", "Check if element is visible. Params: selector (string, required)."),
            ("browser.is.enabled", "Check if element is enabled. Params: selector (string, required)."),
            ("browser.is.checked", "Check if element is checked. Params: selector (string, required)."),
            ("browser.find.role", "Find element by ARIA role. Params: value (string, required)."),
            ("browser.find.text", "Find element by text content. Params: text (string, required)."),
            ("browser.find.label", "Find element by aria-label. Params: value (string, required)."),
            ("browser.find.placeholder", "Find element by placeholder. Params: value (string, required)."),
            ("browser.find.alt", "Find element by alt text. Params: value (string, required)."),
            ("browser.find.title", "Find element by title attribute. Params: value (string, required)."),
            ("browser.find.testid", "Find element by data-testid. Params: value (string, required)."),
            ("browser.find.first", "Find first matching element. Params: selector (string, required)."),
            ("browser.find.last", "Find last matching element. Params: selector (string, required)."),
            ("browser.find.nth", "Find nth matching element. Params: selector (string, required), index (int, required)."),
            ("browser.snapshot", "Get accessibility tree snapshot. Params: max_depth (int, default 12)."),
            ("browser.eval", "Execute JavaScript. Params: script (string, required)."),
            ("browser.wait", "Wait for a condition. Params: selector, text_contains, url_contains, timeout (ms, default 5000)."),
            ("browser.screenshot", "Capture a PNG screenshot. Params: full_page (bool, default false). When true, captures the entire scrollable document; otherwise only the visible viewport. Returns base64-encoded image."),
            ("browser.dialog.accept", "Accept the current dialog."),
            ("browser.dialog.dismiss", "Dismiss the current dialog."),
            ("browser.cookies.get", "Get cookies. Params: name (string, optional filter)."),
            ("browser.cookies.set", "Set a cookie. Params: name, value, domain (all required), path (optional)."),
            ("browser.cookies.clear", "Clear all cookies."),
            ("browser.storage.get", "Get localStorage/sessionStorage. Params: key (string), storage ('local'|'session')."),
        ]
        return methods.map { method, summary in
            CommandRegistration(
                method: method,
                descriptor: CommandDescriptor(
                    summary: summary,
                    params: [.init(name: "browser_id", type: "string", required: true, description: "Tagged or bare UUID of the browser tab.")],
                    result: [],
                    errors: ["browser_not_found", "invalid_params", "js_error"]
                ),
                handler: { _ in fatalError() } // placeholder — dispatch routes these through handleBrowserDispatch
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
