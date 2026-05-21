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
                summary: "List open browser tabs.",
                params: [.init(name: "query", type: "string", required: false, description: "Filter by title or URL substring.")],
                result: [.init(name: "tabs", type: "array", description: "Array of {browser_id, title, url}.")],
                errors: []
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
