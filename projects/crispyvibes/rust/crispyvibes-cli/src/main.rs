use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::Duration;

use clap::{Parser, Subcommand};
use serde_json::{json, Value};

#[derive(Parser, Debug)]
#[command(
    name = "crispy",
    version,
    about = "Crispy IDE agent CLI",
    // The user-facing `help` subcommand is hand-defined below as the `Help` variant
    // (it forwards to the IDE's `help` JSON-RPC method, returning the live command
    // schema). Disable clap's auto-generated `help` subcommand to avoid a duplicate
    // command-name conflict that trips clap's debug-assert (the release build
    // skipped the assert, but the bug was always present).
    disable_help_subcommand = true,
)]
struct Cli {
    /// Override the Unix socket path (default: $CRISPY_SOCKET or bundle-scoped path).
    #[arg(long, global = true)]
    socket: Option<PathBuf>,

    /// Print machine-readable JSON instead of a human-readable summary.
    #[arg(long, global = true)]
    json: bool,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Health check; returns app version and protocol version.
    Ping,
    /// Returns the channel client's resolved context (surface, vibespace, project).
    Whoami,
    /// List every command category, one category's commands, or one method's schema.
    Help {
        /// A category name (e.g. `lane`) or an exact method name. Omit to list all categories.
        topic: Option<String>,
    },
    /// Shelf operations.
    #[command(subcommand)]
    Shelf(ShelfCommand),
    /// Terminal operations.
    #[command(subcommand)]
    Terminal(TerminalCommand),
    /// File operations.
    #[command(subcommand)]
    File(FileCommand),
    /// Shortcut operations.
    #[command(subcommand)]
    Shortcut(ShortcutCommand),
    /// Browser operations.
    #[command(subcommand)]
    Browser(BrowserCommand),
    /// VibeSpace project operations.
    #[command(subcommand)]
    Vibespace(VibespaceCommand),
    /// File comment operations (F049).
    #[command(subcommand)]
    Comments(CommentsCommand),
    /// Quick todo / sticky note operations (F053).
    #[command(subcommand)]
    Todo(TodoCommand),
    /// Vibe Lane authoring and task operations.
    #[command(subcommand)]
    Lane(LaneCommand),
    /// Vibe authoring operations.
    #[command(subcommand)]
    Vibe(VibeCommand),
    /// Skill package operations.
    #[command(subcommand)]
    Skill(SkillCommand),
    /// Automation schedule operations.
    #[command(subcommand)]
    Schedule(ScheduleCommand),
}

/// F049: file commenting CRUD.
#[derive(Subcommand, Debug)]
enum CommentsCommand {
    /// Add a comment to a file at a specific line range.
    Add {
        /// File path (absolute or project-relative).
        #[arg(long)]
        file: String,
        /// 1-based line number where the comment starts.
        #[arg(long)]
        line: u32,
        /// 1-based start column (default 1).
        #[arg(long)]
        column: Option<u32>,
        /// 1-based end line (defaults to start line — line-only comment).
        #[arg(long)]
        end_line: Option<u32>,
        /// 1-based end column (defaults to end of start line).
        #[arg(long)]
        end_column: Option<u32>,
        /// Comment body (markdown supported).
        #[arg(long)]
        comment: String,
        /// Parent comment ID for replies.
        #[arg(long)]
        parent: Option<String>,
    },
    /// List comments for a file (or all comments in the vibespace).
    List {
        /// File path (absolute or project-relative). Omit to list all in vibespace.
        #[arg(long)]
        file: Option<String>,
        /// Filter by status: active, resolved, stale, all.
        #[arg(long, default_value = "active")]
        status: String,
    },
    /// Reply to an existing comment thread.
    Reply {
        /// Parent comment ID.
        #[arg(long)]
        id: String,
        /// Reply body.
        #[arg(long)]
        comment: String,
    },
    /// Update the body of a comment.
    Update {
        /// Comment ID.
        #[arg(long)]
        id: String,
        /// New body.
        #[arg(long)]
        comment: String,
    },
    /// Mark a comment thread as resolved (or pass --unresolve to reopen).
    Resolve {
        /// Comment ID.
        #[arg(long)]
        id: String,
        /// Reopen a resolved thread.
        #[arg(long)]
        unresolve: bool,
    },
    /// Delete a comment (cascades to all replies).
    Delete {
        /// Comment ID.
        #[arg(long)]
        id: String,
    },
    /// Search comments by content / file / status.
    Search {
        /// FTS5 query string (matches comment body).
        #[arg(long)]
        query: Option<String>,
        /// File-path prefix filter.
        #[arg(long)]
        file_prefix: Option<String>,
        /// Status filter.
        #[arg(long, default_value = "active")]
        status: String,
    },
}

/// F053: quick todos / sticky notes.
#[derive(Subcommand, Debug)]
enum TodoCommand {
    /// Create a todo / sticky note.
    Add {
        /// Todo title.
        text: String,
        /// Project path to scope to (defaults to $CRISPY_PROJECT_PATH; omit for vibespace-level).
        #[arg(long)]
        project: Option<String>,
        /// Optional longer note body.
        #[arg(long)]
        body: Option<String>,
        /// Optional color tag.
        #[arg(long)]
        color: Option<String>,
        /// Optional related file path.
        #[arg(long)]
        file: Option<String>,
    },
    /// List todos (active by default).
    List {
        /// Project path filter (defaults to $CRISPY_PROJECT_PATH).
        #[arg(long)]
        project: Option<String>,
        /// Status filter: active, completed, all.
        #[arg(long, default_value = "active")]
        status: String,
        /// Ownership scope: "project" (default, todos for the caller's project)
        /// or "vibespace" (all todos across every project in the active
        /// vibespace, opt-in for cross-project listings).
        #[arg(long, default_value = "project")]
        scope: String,
    },
    /// Mark a todo completed.
    Complete {
        /// Todo ID.
        id: String,
    },
    /// Reopen a completed todo.
    Reopen {
        /// Todo ID.
        id: String,
    },
    /// Update a todo's text, body, or color.
    Update {
        /// Todo ID.
        id: String,
        #[arg(long)]
        text: Option<String>,
        #[arg(long)]
        body: Option<String>,
        #[arg(long)]
        color: Option<String>,
    },
    /// Delete a todo.
    Remove {
        /// Todo ID.
        id: String,
    },
    /// Show a todo with its full thread.
    Show {
        /// Todo ID.
        id: String,
    },
    /// Thread message operations.
    #[command(subcommand)]
    Message(TodoMessageCommand),
    /// File link operations (F060).
    #[command(subcommand)]
    File(TodoFileCommand),
    /// Triage operations (F060).
    #[command(subcommand)]
    Triage(TodoTriageCommand),
    /// Dispatch a todo to a lane, creating a lane task (F060).
    Dispatch {
        /// Todo ID.
        id: String,
        /// Lane name or UUID.
        #[arg(long)]
        lane: String,
        /// Input override as key=value (repeatable).
        #[arg(long = "input", value_name = "KEY=VALUE")]
        input: Vec<String>,
        /// Dispatch even when required inputs are unresolved.
        #[arg(long)]
        allow_unresolved: bool,
    },
}

/// F060: todo file links.
#[derive(Subcommand, Debug)]
enum TodoFileCommand {
    /// Link a file to a todo.
    Add {
        /// Todo ID.
        id: String,
        /// File path (absolute or project-relative).
        #[arg(long)]
        path: String,
    },
    /// Unlink a file from a todo.
    Remove {
        /// Todo ID.
        id: String,
        /// File path (matches the path used when adding).
        #[arg(long)]
        path: String,
    },
    /// List files linked to a todo.
    List {
        /// Todo ID.
        id: String,
    },
}

/// F060: todo triage.
#[derive(Subcommand, Debug)]
enum TodoTriageCommand {
    /// Show the triage result for a todo.
    Show {
        /// Todo ID.
        id: String,
    },
}

/// F053: todo thread messages.
#[derive(Subcommand, Debug)]
enum TodoMessageCommand {
    /// Append a markdown message to a todo's thread.
    Add {
        /// Todo ID.
        id: String,
        /// Message body (markdown).
        #[arg(long)]
        text: String,
    },
}

/// F044-R80–R82: project lifecycle in the focused vibespace.
#[derive(Subcommand, Debug)]
enum VibespaceCommand {
    /// Add a project folder to the focused vibespace and focus it.
    AddProject {
        /// Absolute path to the project directory.
        path: String,
    },
    /// Remove a project from the focused vibespace, closing its terminals/browsers.
    RemoveProject {
        /// Absolute path of the project to remove.
        path: String,
    },
    /// Park a project in the focused vibespace, persisting state and terminating sessions.
    ParkProject {
        /// Absolute path of the project to park.
        path: String,
    },
    /// Activate (unpark) a parked project in the focused vibespace and focus it.
    ActivateProject {
        /// Absolute path of the parked project to activate.
        path: String,
    },
    /// List active, parked, and unresolved projects in the focused vibespace.
    ListProjects,
}

#[derive(Subcommand, Debug)]
enum BrowserCommand {
    /// List open browser tabs in the focused vibespace.
    List {
        /// Filter by title or URL substring.
        #[arg(long)]
        query: Option<String>,
        /// Filter by ownership scope: "project" (default, only browsers owned
        /// by CRISPY_PROJECT_PATH / focused project) or "vibespace" (all
        /// browsers in the vibespace, opt-in for cross-project listings).
        #[arg(long, default_value = "project")]
        scope: String,
    },
    /// Open a new browser tab.
    Open {
        /// URL to load.
        url: Option<String>,
    },
    /// Close a browser tab.
    Close {
        /// Browser ID (from `browser list`).
        browser_id: String,
    },
    /// Navigate to a URL.
    Navigate {
        /// Browser ID.
        browser_id: String,
        /// URL to navigate to.
        url: String,
    },
    /// Go back in history.
    Back { browser_id: String },
    /// Go forward in history.
    Forward { browser_id: String },
    /// Reload the page.
    Reload { browser_id: String },
    /// Get the current URL.
    Url { browser_id: String },
    /// Get the page title.
    Title { browser_id: String },
    /// Click an element.
    Click {
        browser_id: String,
        /// CSS selector.
        #[arg(long)]
        selector: String,
    },
    /// Fill an input field.
    Fill {
        browser_id: String,
        /// CSS selector.
        #[arg(long)]
        selector: String,
        /// Text to fill.
        #[arg(long)]
        text: String,
    },
    /// Type text character-by-character.
    Type {
        browser_id: String,
        #[arg(long)]
        selector: String,
        #[arg(long)]
        text: String,
    },
    /// Press a key.
    Press {
        browser_id: String,
        /// Key name (e.g. Enter, Tab, Escape).
        key: String,
    },
    /// Get accessibility tree snapshot.
    Snapshot {
        browser_id: String,
        /// Max DOM depth (default 12).
        #[arg(long)]
        max_depth: Option<i64>,
    },
    /// Execute JavaScript.
    Eval {
        browser_id: String,
        /// JavaScript code.
        script: String,
    },
    /// Wait for a condition.
    Wait {
        browser_id: String,
        /// CSS selector to wait for.
        #[arg(long)]
        selector: Option<String>,
        /// Text to wait for.
        #[arg(long)]
        text: Option<String>,
        /// URL substring to wait for.
        #[arg(long)]
        url_contains: Option<String>,
        /// Timeout in milliseconds.
        #[arg(long, default_value = "5000")]
        timeout: i64,
    },
    /// Capture a screenshot.
    Screenshot {
        /// Browser tab ID (tagged or bare UUID).
        browser_id: String,
        /// Capture the entire scrollable document. Default captures only the visible viewport.
        #[arg(long)]
        full_page: bool,
    },
    /// Send any browser.* method with raw JSON params.
    Raw {
        /// Full method name (e.g. browser.get.text).
        method: String,
        /// JSON params string.
        #[arg(long, default_value = "{}")]
        params: String,
    },
}

#[derive(Subcommand, Debug)]
enum FileCommand {
    /// Open a file in the editor.
    Open {
        /// File path (absolute or project-relative).
        path: String,
        /// 1-based line to scroll to.
        #[arg(long)]
        line: Option<u32>,
        /// 1-based column (requires --line).
        #[arg(long)]
        column: Option<u32>,
    },
}

#[derive(Subcommand, Debug)]
enum ShortcutCommand {
    /// List saved terminal shortcuts.
    List,
    /// Register a new terminal shortcut.
    Add {
        /// Display name.
        #[arg(long)]
        name: String,
        /// Command line to run.
        #[arg(long)]
        command: String,
        /// One of: currentTerminal, newPermanentTerminal, newTemporaryTerminal.
        #[arg(long, default_value = "newPermanentTerminal")]
        launch_behavior: String,
        /// "vibespace" (default) or "project".
        #[arg(long, default_value = "vibespace")]
        scope: String,
    },
    /// Remove a shortcut by ID.
    Remove {
        /// UUID of the shortcut (from `shortcut list` output).
        id: String,
    },
}

#[derive(Subcommand, Debug)]
enum TerminalCommand {
    /// List all terminals in the focused vibespace.
    List,
    /// Spawn a new terminal.
    Create {
        /// Absolute path for the working directory.
        #[arg(long)]
        cwd: Option<String>,
        /// Custom tab title.
        #[arg(long)]
        name: Option<String>,
    },
    /// Inject text into a terminal.
    Send {
        /// Text to send.
        text: String,
        /// Tagged or bare terminal UUID (required).
        #[arg(long)]
        terminal_id: String,
        /// Append newline after text.
        #[arg(long)]
        submit: bool,
    },
    /// Send a named key event (Enter, Ctrl+C, Tab, arrows, etc.).
    SendKey {
        /// Key name.
        key: String,
        /// Tagged or bare terminal UUID (required).
        #[arg(long)]
        terminal_id: String,
    },
    /// Close a terminal.
    Close {
        /// Tagged or bare terminal UUID (required).
        #[arg(long)]
        terminal_id: String,
    },
    /// Block until output matches text or the process exits.
    Wait {
        /// Wait until this substring appears in output.
        #[arg(long)]
        text: Option<String>,
        /// Wait until the terminal process exits.
        #[arg(long, name = "exit")]
        wait_exit: bool,
        /// Seconds to wait (1-600).
        #[arg(long, default_value = "30")]
        timeout: u32,
        /// Tagged or bare terminal UUID.
        #[arg(long)]
        terminal_id: Option<String>,
    },
}

#[derive(Subcommand, Debug)]
enum ShelfCommand {
    /// Add a file or folder to the shelf.
    Add {
        /// Path to add. Absolute, or relative to $CRISPY_PROJECT_PATH.
        path: String,
        /// Make this the selected shelf item.
        #[arg(long)]
        select: bool,
    },
    /// List all shelf entries.
    List,
    /// Remove a file or folder from the shelf.
    Remove {
        /// Path to remove (matches the path used when adding).
        path: String,
    },
}

/// Vibe Lane authoring and task control.
#[derive(Subcommand, Debug)]
enum LaneCommand {
    /// List authored lanes.
    List,
    /// Show a lane by UUID or unambiguous name.
    Show { lane: String },
    /// Validate a lane JSON document without saving it.
    Validate {
        #[arg(long)]
        file: PathBuf,
    },
    /// Create a lane from a JSON document.
    Create {
        #[arg(long)]
        file: PathBuf,
    },
    /// Update a lane from a JSON document.
    Update {
        lane: String,
        #[arg(long)]
        file: PathBuf,
        #[arg(long)]
        expected_version: i64,
    },
    /// Delete a lane at the expected version.
    Delete {
        lane: String,
        #[arg(long)]
        expected_version: i64,
    },
    /// Restore missing starter lanes and refresh pristine starters.
    RestoreStarters,
    /// Lane task operations.
    #[command(subcommand)]
    Task(LaneTaskCommand),
}

/// Runtime operations for tasks executing through Vibe Lanes.
#[derive(Subcommand, Debug)]
enum LaneTaskCommand {
    /// Create and start a lane task.
    Create {
        lane: String,
        #[arg(long)]
        input: String,
        #[arg(long)]
        project: Option<String>,
        #[arg(long)]
        agent: Option<String>,
        /// Initial carry-forward value as key=value (repeatable).
        #[arg(long = "value", value_name = "KEY=VALUE")]
        values: Vec<String>,
    },
    /// List lane tasks, optionally filtered by state or project.
    List {
        #[arg(long)]
        state: Option<String>,
        #[arg(long)]
        project: Option<String>,
    },
    /// Show a lane task.
    Show { id: String },
    /// Answer the task's currently open request.
    Answer {
        id: String,
        /// Supply answer as key=value (repeatable).
        #[arg(long = "value", value_name = "KEY=VALUE")]
        values: Vec<String>,
        #[arg(long)]
        guidance: Option<String>,
        #[arg(long)]
        approve: Option<bool>,
        #[arg(long)]
        feedback: Option<String>,
        #[arg(long)]
        advance: Option<bool>,
    },
    /// Stop a running or needs-input task.
    Stop { id: String },
    /// Delete a task and its persisted handoff files.
    Delete { id: String },
}

/// Central Vibe authoring operations.
#[derive(Subcommand, Debug)]
enum VibeCommand {
    /// List Vibes.
    List {
        #[arg(long)]
        category: Option<String>,
        #[arg(long)]
        status: Option<String>,
    },
    /// Show a Vibe by UUID or unambiguous name.
    Show { id: String },
    /// Validate a Vibe JSON document without saving it.
    Validate {
        #[arg(long)]
        file: PathBuf,
    },
    /// Create a Vibe from a JSON document.
    Create {
        #[arg(long)]
        file: PathBuf,
    },
    /// Update a Vibe from a JSON document.
    Update {
        id: String,
        #[arg(long)]
        file: PathBuf,
        #[arg(long)]
        expected_version: i64,
    },
    /// Delete a Vibe at the expected version.
    Delete {
        id: String,
        #[arg(long)]
        expected_version: i64,
    },
}

/// Skill package discovery and lifecycle operations.
#[derive(Subcommand, Debug)]
enum SkillCommand {
    /// List Skills.
    List {
        #[arg(long)]
        source: Option<String>,
        #[arg(long)]
        role: Option<String>,
    },
    /// Show a Skill by canonical reference.
    Show {
        reference: String,
        #[arg(long)]
        include_body: bool,
    },
    /// Validate a package path or canonical Skill reference.
    Validate { reference: String },
    /// Import a Skill package or package collection.
    Import {
        path: String,
        /// Explicitly copy the package into Crispy (the default).
        #[arg(long, conflicts_with = "link")]
        copy: bool,
        /// Link the external package instead of copying it.
        #[arg(long, conflicts_with = "copy")]
        link: bool,
    },
    /// Duplicate a Skill into an editable personal package.
    Duplicate { reference: String },
    /// Remove or unlink a Skill.
    Remove { reference: String },
}

/// Automation schedule authoring and runtime operations.
#[derive(Subcommand, Debug)]
enum ScheduleCommand {
    /// List schedules.
    List {
        #[arg(long)]
        status: Option<String>,
    },
    /// Show a schedule by UUID or unambiguous name.
    Show { id: String },
    /// Create a schedule from a JSON document.
    Create {
        #[arg(long)]
        file: PathBuf,
        #[arg(long)]
        confirm_full_trust: bool,
    },
    /// Update a schedule from a JSON document.
    Update {
        id: String,
        #[arg(long)]
        file: PathBuf,
        #[arg(long)]
        confirm_full_trust: bool,
    },
    /// Pause a schedule.
    Pause { id: String },
    /// Enable a schedule for unattended Full Trust execution.
    Enable {
        id: String,
        #[arg(long)]
        confirm_full_trust: bool,
    },
    /// Adopt a newer lane snapshot.
    AdoptLane {
        id: String,
        #[arg(long)]
        lane: String,
        #[arg(long)]
        confirm_full_trust: bool,
    },
    /// Start an immediate run without moving the next scheduled occurrence.
    RunNow { id: String },
    /// List a schedule's run history.
    Runs {
        id: String,
        #[arg(long)]
        limit: Option<u32>,
    },
    /// Delete a schedule, optionally choosing what to do with an active run.
    Delete {
        id: String,
        #[arg(long, conflicts_with = "keep_active")]
        stop_active: bool,
        #[arg(long, conflicts_with = "stop_active")]
        keep_active: bool,
    },
    /// Validate recurrence and preview upcoming occurrences without saving.
    Preview {
        #[arg(long)]
        file: PathBuf,
        #[arg(long)]
        count: Option<u32>,
    },
}

fn main() {
    let cli = Cli::parse();
    match run(cli) {
        Ok(()) => {}
        Err(err) => {
            eprintln!("crispy: {err}");
            std::process::exit(1);
        }
    }
}

fn run(cli: Cli) -> Result<(), String> {
    let socket_path = resolve_socket_path(cli.socket.as_ref())?;
    let env = ChannelClientEnv::from_environment();

    let (method, params): (&str, Value) = if let Some(mapping) = automation_rpc(&cli.command) {
        mapping?
    } else {
        match cli.command {
            Command::Ping => ("ping", json!({})),
            Command::Whoami => ("whoami", json!({})),
            Command::Help { topic } => match topic {
                Some(t) => ("help", json!({ "topic": t })),
                None => ("help", json!({})),
            },
            Command::Shelf(ShelfCommand::Add { path, select }) => {
                ("shelf.add", json!({ "path": path, "select": select }))
            }
            Command::Shelf(ShelfCommand::List) => ("shelf.list", json!({})),
            Command::Shelf(ShelfCommand::Remove { path }) => {
                ("shelf.remove", json!({ "path": path }))
            }
            Command::Terminal(TerminalCommand::List) => ("terminal.list", json!({})),
            Command::Terminal(TerminalCommand::Create { cwd, name }) => {
                ("terminal.create", json!({ "cwd": cwd, "name": name }))
            }
            Command::Terminal(TerminalCommand::Send {
                text,
                terminal_id,
                submit,
            }) => (
                "terminal.send",
                json!({ "text": text, "terminal_id": terminal_id, "submit": submit }),
            ),
            Command::Terminal(TerminalCommand::SendKey { key, terminal_id }) => (
                "terminal.send_key",
                json!({ "key": key, "terminal_id": terminal_id }),
            ),
            Command::Terminal(TerminalCommand::Close { terminal_id }) => {
                ("terminal.close", json!({ "terminal_id": terminal_id }))
            }
            Command::Terminal(TerminalCommand::Wait {
                text,
                wait_exit,
                timeout,
                terminal_id,
            }) => (
                "terminal.wait",
                json!({ "text": text, "exit": wait_exit, "timeout": timeout, "terminal_id": terminal_id }),
            ),
            Command::File(FileCommand::Open { path, line, column }) => (
                "file.open",
                json!({ "path": path, "line": line, "column": column }),
            ),
            Command::Shortcut(ShortcutCommand::List) => ("shortcut.list", json!({})),
            Command::Shortcut(ShortcutCommand::Add {
                name,
                command,
                launch_behavior,
                scope,
            }) => (
                "shortcut.add",
                json!({ "name": name, "command": command, "launch_behavior": launch_behavior, "scope": scope }),
            ),
            Command::Shortcut(ShortcutCommand::Remove { id }) => {
                ("shortcut.remove", json!({ "id": id }))
            }
            Command::Browser(BrowserCommand::List { query, scope }) => (
                "browser.list",
                json!({ "query": query.unwrap_or_default(), "scope": scope }),
            ),
            Command::Browser(BrowserCommand::Open { url }) => {
                ("browser.open", json!({ "url": url.unwrap_or_default() }))
            }
            Command::Browser(BrowserCommand::Close { browser_id }) => {
                ("browser.close", json!({ "browser_id": browser_id }))
            }
            Command::Browser(BrowserCommand::Navigate { browser_id, url }) => (
                "browser.navigate",
                json!({ "browser_id": browser_id, "url": url }),
            ),
            Command::Browser(BrowserCommand::Back { browser_id }) => {
                ("browser.back", json!({ "browser_id": browser_id }))
            }
            Command::Browser(BrowserCommand::Forward { browser_id }) => {
                ("browser.forward", json!({ "browser_id": browser_id }))
            }
            Command::Browser(BrowserCommand::Reload { browser_id }) => {
                ("browser.reload", json!({ "browser_id": browser_id }))
            }
            Command::Browser(BrowserCommand::Url { browser_id }) => {
                ("browser.url.get", json!({ "browser_id": browser_id }))
            }
            Command::Browser(BrowserCommand::Title { browser_id }) => {
                ("browser.get.title", json!({ "browser_id": browser_id }))
            }
            Command::Browser(BrowserCommand::Click {
                browser_id,
                selector,
            }) => (
                "browser.click",
                json!({ "browser_id": browser_id, "selector": selector }),
            ),
            Command::Browser(BrowserCommand::Fill {
                browser_id,
                selector,
                text,
            }) => (
                "browser.fill",
                json!({ "browser_id": browser_id, "selector": selector, "text": text }),
            ),
            Command::Browser(BrowserCommand::Type {
                browser_id,
                selector,
                text,
            }) => (
                "browser.type",
                json!({ "browser_id": browser_id, "selector": selector, "text": text }),
            ),
            Command::Browser(BrowserCommand::Press { browser_id, key }) => (
                "browser.press",
                json!({ "browser_id": browser_id, "key": key }),
            ),
            Command::Browser(BrowserCommand::Snapshot {
                browser_id,
                max_depth,
            }) => (
                "browser.snapshot",
                json!({ "browser_id": browser_id, "max_depth": max_depth }),
            ),
            Command::Browser(BrowserCommand::Eval { browser_id, script }) => (
                "browser.eval",
                json!({ "browser_id": browser_id, "script": script }),
            ),
            Command::Browser(BrowserCommand::Wait {
                browser_id,
                selector,
                text,
                url_contains,
                timeout,
            }) => (
                "browser.wait",
                json!({ "browser_id": browser_id, "selector": selector, "text_contains": text, "url_contains": url_contains, "timeout": timeout }),
            ),
            Command::Browser(BrowserCommand::Screenshot {
                browser_id,
                full_page,
            }) => (
                "browser.screenshot",
                json!({ "browser_id": browser_id, "full_page": full_page }),
            ),
            Command::Browser(BrowserCommand::Raw { method, params }) => {
                let base: Value = serde_json::from_str(&params).unwrap_or(json!({}));
                (Box::leak(method.into_boxed_str()) as &str, base)
            }
            Command::Vibespace(VibespaceCommand::AddProject { path }) => {
                ("vibespace.addProject", json!({ "path": path }))
            }
            Command::Vibespace(VibespaceCommand::RemoveProject { path }) => {
                ("vibespace.removeProject", json!({ "path": path }))
            }
            Command::Vibespace(VibespaceCommand::ParkProject { path }) => {
                ("vibespace.parkProject", json!({ "path": path }))
            }
            Command::Vibespace(VibespaceCommand::ActivateProject { path }) => {
                ("vibespace.activateProject", json!({ "path": path }))
            }
            Command::Vibespace(VibespaceCommand::ListProjects) => {
                ("vibespace.listProjects", json!({}))
            }
            Command::Comments(CommentsCommand::Add {
                file,
                line,
                column,
                end_line,
                end_column,
                comment,
                parent,
            }) => (
                "comments.add",
                json!({
                    "file": file,
                    "start_line": line,
                    "start_column": column.unwrap_or(1),
                    "end_line": end_line.unwrap_or(line),
                    "end_column": end_column,
                    "body": comment,
                    "parent_id": parent,
                }),
            ),
            Command::Comments(CommentsCommand::List { file, status }) => {
                ("comments.list", json!({ "file": file, "status": status }))
            }
            Command::Comments(CommentsCommand::Reply { id, comment }) => {
                ("comments.reply", json!({ "id": id, "body": comment }))
            }
            Command::Comments(CommentsCommand::Update { id, comment }) => {
                ("comments.update", json!({ "id": id, "body": comment }))
            }
            Command::Comments(CommentsCommand::Resolve { id, unresolve }) => (
                "comments.resolve",
                json!({ "id": id, "unresolve": unresolve }),
            ),
            Command::Comments(CommentsCommand::Delete { id }) => {
                ("comments.delete", json!({ "id": id }))
            }
            Command::Comments(CommentsCommand::Search {
                query,
                file_prefix,
                status,
            }) => (
                "comments.search",
                json!({ "query": query, "file_prefix": file_prefix, "status": status }),
            ),
            Command::Todo(TodoCommand::Add {
                text,
                project,
                body,
                color,
                file,
            }) => (
                "todo.add",
                json!({ "text": text, "project": project, "body": body, "color": color, "file": file }),
            ),
            Command::Todo(TodoCommand::List {
                project,
                status,
                scope,
            }) => (
                "todo.list",
                json!({ "project": project, "status": status, "scope": scope }),
            ),
            Command::Todo(TodoCommand::Complete { id }) => ("todo.complete", json!({ "id": id })),
            Command::Todo(TodoCommand::Reopen { id }) => ("todo.reopen", json!({ "id": id })),
            Command::Todo(TodoCommand::Update {
                id,
                text,
                body,
                color,
            }) => (
                "todo.update",
                json!({ "id": id, "text": text, "body": body, "color": color }),
            ),
            Command::Todo(TodoCommand::Remove { id }) => ("todo.remove", json!({ "id": id })),
            Command::Todo(TodoCommand::Show { id }) => ("todo.show", json!({ "id": id })),
            Command::Todo(TodoCommand::Message(TodoMessageCommand::Add { id, text })) => {
                ("todo.message.add", json!({ "id": id, "text": text }))
            }
            Command::Todo(TodoCommand::File(TodoFileCommand::Add { id, path })) => {
                ("todo.file.add", json!({ "id": id, "path": path }))
            }
            Command::Todo(TodoCommand::File(TodoFileCommand::Remove { id, path })) => {
                ("todo.file.remove", json!({ "id": id, "path": path }))
            }
            Command::Todo(TodoCommand::File(TodoFileCommand::List { id })) => {
                ("todo.file.list", json!({ "id": id }))
            }
            Command::Todo(TodoCommand::Triage(TodoTriageCommand::Show { id })) => {
                ("todo.triage.show", json!({ "id": id }))
            }
            Command::Todo(TodoCommand::Dispatch {
                id,
                lane,
                input,
                allow_unresolved,
            }) => (
                "todo.dispatch",
                dispatch_params(id, lane, &input, allow_unresolved)?,
            ),
            Command::Lane(_) | Command::Vibe(_) | Command::Skill(_) | Command::Schedule(_) => {
                unreachable!("automation commands are mapped before legacy commands")
            }
        }
    };

    let response = send_request(&socket_path, method, params, &env)?;

    if cli.json {
        println!("{}", render_json_output(&response));
    } else {
        print_human(method, &response);
    }
    Ok(())
}

/// Maps typed Automation commands to their JSON-RPC method and params.
fn automation_rpc(command: &Command) -> Option<Result<(&'static str, Value), String>> {
    if !matches!(
        command,
        Command::Lane(_) | Command::Vibe(_) | Command::Skill(_) | Command::Schedule(_)
    ) {
        return None;
    }
    let mapped = (|| -> Result<(&'static str, Value), String> {
        let mapped = match command {
            Command::Lane(command) => match command {
                LaneCommand::List => ("lane.list", json!({})),
                LaneCommand::Show { lane } => ("lane.show", json!({ "lane": lane })),
                LaneCommand::Validate { file } => (
                    "lane.validate",
                    json!({ "document": load_json_document(file)? }),
                ),
                LaneCommand::Create { file } => (
                    "lane.create",
                    json!({ "document": load_json_document(file)? }),
                ),
                LaneCommand::Update {
                    lane,
                    file,
                    expected_version,
                } => (
                    "lane.update",
                    json!({
                        "lane": lane,
                        "document": load_json_document(file)?,
                        "expectedVersion": expected_version,
                    }),
                ),
                LaneCommand::Delete {
                    lane,
                    expected_version,
                } => (
                    "lane.delete",
                    json!({ "lane": lane, "expectedVersion": expected_version }),
                ),
                LaneCommand::RestoreStarters => ("lane.restoreStarters", json!({})),
                LaneCommand::Task(command) => match command {
                    LaneTaskCommand::Create {
                        lane,
                        input,
                        project,
                        agent,
                        values,
                    } => (
                        "lane.task.create",
                        json!({
                            "lane": lane,
                            "input": input,
                            "project": project,
                            "agent": agent,
                            "inputs": key_value_object(values)?,
                        }),
                    ),
                    LaneTaskCommand::List { state, project } => (
                        "lane.task.list",
                        json!({ "state": state, "project": project }),
                    ),
                    LaneTaskCommand::Show { id } => ("lane.task.show", json!({ "id": id })),
                    LaneTaskCommand::Answer {
                        id,
                        values,
                        guidance,
                        approve,
                        feedback,
                        advance,
                    } => (
                        "lane.task.answer",
                        json!({
                            "id": id,
                            "values": key_value_object(values)?,
                            "guidance": guidance,
                            "approve": approve,
                            "feedback": feedback,
                            "advance": advance,
                        }),
                    ),
                    LaneTaskCommand::Stop { id } => ("lane.task.stop", json!({ "id": id })),
                    LaneTaskCommand::Delete { id } => ("lane.task.delete", json!({ "id": id })),
                },
            },
            Command::Vibe(command) => match command {
                VibeCommand::List { category, status } => (
                    "vibe.list",
                    json!({ "category": category, "status": status }),
                ),
                VibeCommand::Show { id } => ("vibe.show", json!({ "id": id })),
                VibeCommand::Validate { file } => (
                    "vibe.validate",
                    json!({ "document": load_json_document(file)? }),
                ),
                VibeCommand::Create { file } => (
                    "vibe.create",
                    json!({ "document": load_json_document(file)? }),
                ),
                VibeCommand::Update {
                    id,
                    file,
                    expected_version,
                } => (
                    "vibe.update",
                    json!({
                        "id": id,
                        "document": load_json_document(file)?,
                        "expectedVersion": expected_version,
                    }),
                ),
                VibeCommand::Delete {
                    id,
                    expected_version,
                } => (
                    "vibe.delete",
                    json!({ "id": id, "expectedVersion": expected_version }),
                ),
            },
            Command::Skill(command) => match command {
                SkillCommand::List { source, role } => {
                    ("skill.list", json!({ "source": source, "role": role }))
                }
                SkillCommand::Show {
                    reference,
                    include_body,
                } => (
                    "skill.show",
                    json!({ "reference": reference, "includeBody": include_body }),
                ),
                SkillCommand::Validate { reference } => {
                    ("skill.validate", json!({ "reference": reference }))
                }
                SkillCommand::Import {
                    path,
                    copy: _,
                    link,
                } => (
                    "skill.import",
                    json!({ "path": path, "mode": if *link { "link" } else { "copy" } }),
                ),
                SkillCommand::Duplicate { reference } => {
                    ("skill.duplicate", json!({ "reference": reference }))
                }
                SkillCommand::Remove { reference } => {
                    ("skill.remove", json!({ "reference": reference }))
                }
            },
            Command::Schedule(command) => match command {
                ScheduleCommand::List { status } => ("schedule.list", json!({ "status": status })),
                ScheduleCommand::Show { id } => ("schedule.show", json!({ "id": id })),
                ScheduleCommand::Create {
                    file,
                    confirm_full_trust,
                } => (
                    "schedule.create",
                    json!({
                        "document": load_json_document(file)?,
                        "confirmFullTrust": confirm_full_trust,
                    }),
                ),
                ScheduleCommand::Update {
                    id,
                    file,
                    confirm_full_trust,
                } => (
                    "schedule.update",
                    json!({
                        "id": id,
                        "document": load_json_document(file)?,
                        "confirmFullTrust": confirm_full_trust,
                    }),
                ),
                ScheduleCommand::Pause { id } => ("schedule.pause", json!({ "id": id })),
                ScheduleCommand::Enable {
                    id,
                    confirm_full_trust,
                } => (
                    "schedule.enable",
                    json!({
                        "id": id,
                        "confirmFullTrust": confirm_full_trust,
                    }),
                ),
                ScheduleCommand::AdoptLane {
                    id,
                    lane,
                    confirm_full_trust,
                } => (
                    "schedule.adopt-lane",
                    json!({
                        "id": id,
                        "lane": lane,
                        "confirmFullTrust": confirm_full_trust,
                    }),
                ),
                ScheduleCommand::RunNow { id } => ("schedule.run-now", json!({ "id": id })),
                ScheduleCommand::Runs { id, limit } => {
                    ("schedule.runs", json!({ "id": id, "limit": limit }))
                }
                ScheduleCommand::Delete {
                    id,
                    stop_active,
                    keep_active,
                } => {
                    let stop_active = if *stop_active {
                        Some(true)
                    } else if *keep_active {
                        Some(false)
                    } else {
                        None
                    };
                    (
                        "schedule.delete",
                        json!({
                            "id": id,
                            "stopActive": stop_active,
                        }),
                    )
                }
                ScheduleCommand::Preview { file, count } => (
                    "schedule.preview",
                    json!({ "document": load_json_document(file)?, "count": count }),
                ),
            },
            _ => unreachable!("non-Automation commands returned before mapping"),
        };
        Ok(mapped)
    })();
    Some(mapped)
}

/// Reads one JSON document from a file, or from stdin when `path` is `-`.
fn load_json_document(path: &PathBuf) -> Result<Value, String> {
    if path.as_os_str() == "-" {
        load_json_document_from_reader(std::io::stdin().lock(), "stdin")
    } else {
        let file = std::fs::File::open(path)
            .map_err(|error| format!("could not read JSON document {}: {error}", path.display()))?;
        load_json_document_from_reader(file, &path.display().to_string())
    }
}

fn load_json_document_from_reader<R: Read>(reader: R, source: &str) -> Result<Value, String> {
    serde_json::from_reader(reader)
        .map_err(|error| format!("invalid JSON document from {source}: {error}"))
}

fn key_value_object(values: &[String]) -> Result<Value, String> {
    let mut object = serde_json::Map::new();
    for raw in values {
        let (key, value) = raw
            .split_once('=')
            .ok_or_else(|| format!("invalid value {raw:?}: expected key=value"))?;
        if key.is_empty() {
            return Err(format!("invalid value {raw:?}: key cannot be empty"));
        }
        object.insert(key.to_string(), Value::String(value.to_string()));
    }
    Ok(Value::Object(object))
}

/// F060: builds the `todo.dispatch` params. `--input` values are split on the
/// FIRST `=` into key/value pairs and sent as an `inputs` object only when at
/// least one was given; `allowUnresolved` is included only when the flag is set.
fn dispatch_params(
    id: String,
    lane: String,
    inputs: &[String],
    allow_unresolved: bool,
) -> Result<Value, String> {
    let mut params = json!({ "id": id, "lane": lane });
    if !inputs.is_empty() {
        let mut object = serde_json::Map::new();
        for raw in inputs {
            let (key, value) = raw
                .split_once('=')
                .ok_or_else(|| format!("invalid --input {raw:?}: expected key=value"))?;
            object.insert(key.to_string(), Value::String(value.to_string()));
        }
        params["inputs"] = Value::Object(object);
    }
    if allow_unresolved {
        params["allowUnresolved"] = Value::Bool(true);
    }
    Ok(params)
}

fn resolve_socket_path(explicit: Option<&PathBuf>) -> Result<PathBuf, String> {
    if let Some(path) = explicit {
        return Ok(path.clone());
    }
    if let Ok(env) = std::env::var("CRISPY_SOCKET") {
        if !env.is_empty() {
            return Ok(PathBuf::from(env));
        }
    }
    let home = std::env::var("HOME")
        .map_err(|_| "HOME not set; cannot resolve default socket path".to_string())?;
    // Crispy injects CRISPY_SOCKET (and CRISPY_BUNDLE_ID) into every terminal
    // it spawns. When those are absent (CLI invoked from a context that didn't
    // inherit the env), derive the bundle ID from this binary's own location so
    // the bundled `crispy` always targets ITS app: the local build talks to the
    // local socket and the released build to the released socket, with no
    // hardcoded cross-build bias. Only fall back to the production ID if the
    // owning bundle can't be resolved at all.
    let bundle = std::env::var("CRISPY_BUNDLE_ID")
        .ok()
        .filter(|s| !s.is_empty())
        .or_else(bundle_id_from_own_location)
        .unwrap_or_else(|| "com.crispyvibe.app".to_string());
    Ok(PathBuf::from(home)
        .join("Library/Application Support")
        .join(&bundle)
        .join("crispy.sock"))
}

/// Resolves the owning app's bundle identifier from this binary's own path.
///
/// The bundled CLI lives at `<App>.app/Contents/Resources/bin/crispy`, so the
/// `Info.plist` is three directories up from the executable's parent. `plutil`
/// is used because app-bundle plists are typically binary-encoded. Returns
/// `None` if the binary isn't inside an app bundle (e.g. a standalone build).
fn bundle_id_from_own_location() -> Option<String> {
    let exe = std::fs::canonicalize(std::env::current_exe().ok()?).ok()?;
    // exe -> bin -> Resources -> Contents
    let contents = exe.parent()?.parent()?.parent()?;
    let info_plist = contents.join("Info.plist");
    if !info_plist.exists() {
        return None;
    }
    let output = std::process::Command::new("/usr/bin/plutil")
        .args(["-extract", "CFBundleIdentifier", "raw", "-o", "-"])
        .arg(&info_plist)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let id = String::from_utf8(output.stdout).ok()?.trim().to_string();
    if id.is_empty() {
        None
    } else {
        Some(id)
    }
}

#[derive(Debug, Default)]
struct ChannelClientEnv {
    /// Tagged ID of the calling process: `terminal.<uuid>` or `acpchat.<uuid>`.
    context: Option<String>,
    /// Tagged ID of the vibespace: `vibespace.<uuid>`.
    vibespace: Option<String>,
    project_path: Option<String>,
}

impl ChannelClientEnv {
    fn from_environment() -> Self {
        Self {
            context: std::env::var("CRISPY_CONTEXT")
                .ok()
                .filter(|s| !s.is_empty()),
            vibespace: std::env::var("CRISPY_VIBESPACE")
                .ok()
                .filter(|s| !s.is_empty()),
            project_path: std::env::var("CRISPY_PROJECT_PATH")
                .ok()
                .filter(|s| !s.is_empty()),
        }
    }

    fn to_json(&self) -> Value {
        json!({
            "context": self.context,
            "vibespace": self.vibespace,
            "project_path": self.project_path,
        })
    }
}

fn send_request(
    socket_path: &PathBuf,
    method: &str,
    params: Value,
    env: &ChannelClientEnv,
) -> Result<Value, String> {
    let mut stream = UnixStream::connect(socket_path).map_err(|err| {
        format!(
            "could not connect to {}: {} (is Crispy running and Agent CLI enabled?)",
            socket_path.display(),
            err
        )
    })?;
    stream.set_read_timeout(Some(Duration::from_secs(30))).ok();
    stream.set_write_timeout(Some(Duration::from_secs(5))).ok();

    let request_id = uuid::Uuid::new_v4().to_string();
    let request = json!({
        "id": request_id,
        "method": method,
        "params": params,
        "_env": env.to_json(),
    });

    let mut serialized = serde_json::to_vec(&request).map_err(|e| format!("encode error: {e}"))?;
    serialized.push(b'\n');
    stream
        .write_all(&serialized)
        .map_err(|e| format!("write error: {e}"))?;

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader
        .read_line(&mut line)
        .map_err(|e| format!("read error: {e}"))?;
    if line.is_empty() {
        return Err("server closed connection without response".to_string());
    }
    let response: Value = serde_json::from_str(line.trim_end())
        .map_err(|e| format!("server returned invalid JSON: {e}; payload was: {line:?}"))?;

    if !response.get("ok").and_then(Value::as_bool).unwrap_or(false) {
        let code = response
            .get("error")
            .and_then(|e| e.get("code"))
            .and_then(Value::as_str)
            .unwrap_or("unknown");
        let message = response
            .get("error")
            .and_then(|e| e.get("message"))
            .and_then(Value::as_str)
            .unwrap_or("(no message)");
        return Err(format!("{code}: {message}"));
    }

    Ok(response.get("result").cloned().unwrap_or(Value::Null))
}

fn render_json_output(result: &Value) -> String {
    serde_json::to_string(result).unwrap_or_default()
}

fn automation_human_output(method: &str, result: &Value) -> Option<String> {
    fn text<'a>(value: &'a Value, key: &str, fallback: &'a str) -> &'a str {
        value.get(key).and_then(Value::as_str).unwrap_or(fallback)
    }
    fn named_line(value: &Value, kind: &str) -> String {
        format!(
            "{kind} {}  {}",
            text(value, "id", text(value, "reference", "?")),
            text(value, "name", "")
        )
        .trim_end()
        .to_string()
    }
    fn list_lines(values: Option<&Vec<Value>>, kind: &str, empty: &str) -> String {
        let Some(values) = values else {
            return empty.to_string();
        };
        if values.is_empty() {
            return empty.to_string();
        }
        values
            .iter()
            .map(|value| match kind {
                "lane" => format!(
                    "{}  v{}  {}",
                    text(value, "id", "?"),
                    value.get("version").and_then(Value::as_i64).unwrap_or(0),
                    text(value, "name", "")
                ),
                "vibe" => format!(
                    "{}  v{}  [{}]  {}",
                    text(value, "id", "?"),
                    value.get("version").and_then(Value::as_i64).unwrap_or(0),
                    if value.get("ready").and_then(Value::as_bool).unwrap_or(false) {
                        "ready"
                    } else {
                        "needs-setup"
                    },
                    text(value, "name", "")
                ),
                "skill" => {
                    let source = text(value, "source", "?");
                    let mutability = match source {
                        "personal" => "editable",
                        "linked" => "externally-mutable",
                        _ => "read-only",
                    };
                    format!(
                        "{}  [{source}, {mutability}, {}]  {}",
                        text(value, "reference", "?"),
                        text(value, "validation", "?"),
                        text(value, "name", "")
                    )
                }
                "schedule" => format!(
                    "{}  [{}; full-trust={}]  {}",
                    text(value, "id", "?"),
                    text(value, "status", "?"),
                    if value
                        .get("enabled")
                        .and_then(Value::as_bool)
                        .unwrap_or(false)
                    {
                        "enabled"
                    } else {
                        "inactive"
                    },
                    text(value, "name", "")
                ),
                "task" => format!(
                    "{}  [{}]  {}",
                    text(value, "id", "?"),
                    text(value, "state", "?"),
                    text(value, "title", "")
                ),
                "run" => format!(
                    "{}  [{}]  {}",
                    text(value, "id", "?"),
                    text(value, "disposition", "?"),
                    text(value, "scheduledAt", "")
                ),
                _ => named_line(value, kind),
            })
            .collect::<Vec<_>>()
            .join("\n")
    }
    fn validation(result: &Value) -> String {
        let valid = result
            .get("valid")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let issues = result
            .get("issues")
            .and_then(Value::as_array)
            .map(|values| {
                values
                    .iter()
                    .filter_map(Value::as_str)
                    .map(|issue| format!("  - {issue}"))
                    .collect::<Vec<_>>()
                    .join("\n")
            })
            .unwrap_or_default();
        if valid {
            "valid".to_string()
        } else if issues.is_empty() {
            "invalid".to_string()
        } else {
            format!("invalid\n{issues}")
        }
    }
    fn detail(result: &Value, key: &str, kind: &str) -> String {
        let Some(value) = result.get(key) else {
            return format!("{kind}: ?");
        };
        match kind {
            "lane" => format!(
                "{}\nversion: {}\ncheckpoints: {}",
                named_line(value, kind),
                value.get("version").and_then(Value::as_i64).unwrap_or(0),
                value
                    .get("checkpointCount")
                    .and_then(Value::as_i64)
                    .unwrap_or_else(|| {
                        value
                            .get("checkpoints")
                            .and_then(Value::as_array)
                            .map_or(0, |v| v.len() as i64)
                    })
            ),
            "vibe" => format!(
                "{}\nversion: {}\nstatus: {}",
                named_line(value, kind),
                value.get("version").and_then(Value::as_i64).unwrap_or(0),
                if value.get("ready").and_then(Value::as_bool).unwrap_or(false) {
                    "ready"
                } else {
                    "needs-setup"
                }
            ),
            "skill" => {
                let source = text(value, "source", "?");
                let mutability = match source {
                    "personal" => "editable in Crispy",
                    "linked" => "external package; source changes are reflected",
                    _ => "read-only bundled package",
                };
                format!(
                    "{}\nsource: {source} ({mutability})\nvalidation: {}",
                    named_line(value, kind),
                    text(value, "validation", "?")
                )
            }
            "schedule" => format!(
                "{}\nstatus: {}\nenabled: {} (Full Trust {})\nnext: {}",
                named_line(value, kind),
                text(value, "status", "?"),
                value
                    .get("enabled")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                if value
                    .get("enabled")
                    .and_then(Value::as_bool)
                    .unwrap_or(false)
                {
                    "acknowledged"
                } else {
                    "not active"
                },
                text(value, "nextRunAt", "none")
            ),
            "task" => format!(
                "{}\nstate: {}",
                named_line(value, kind),
                text(value, "state", "?")
            ),
            "run" => format!(
                "{}\ndisposition: {}",
                named_line(value, kind),
                text(value, "disposition", "?")
            ),
            _ => named_line(value, kind),
        }
    }

    match method {
        "lane.list" => Some(list_lines(
            result.get("lanes").and_then(Value::as_array),
            "lane",
            "(no lanes)",
        )),
        "lane.show" | "lane.create" | "lane.update" => Some(detail(result, "lane", "lane")),
        "lane.delete" => Some(format!("deleted lane: {}", text(result, "id", "?"))),
        "lane.restoreStarters" => Some(list_lines(
            result.get("lanes").and_then(Value::as_array),
            "lane",
            "(no lanes)",
        )),
        "lane.task.list" => Some(list_lines(
            result.get("tasks").and_then(Value::as_array),
            "task",
            "(no lane tasks)",
        )),
        "lane.task.show" | "lane.task.create" | "lane.task.answer" | "lane.task.stop" => {
            Some(detail(result, "task", "task"))
        }
        "lane.task.delete" => Some(format!("deleted lane task: {}", text(result, "id", "?"))),
        "vibe.list" => Some(list_lines(
            result.get("vibes").and_then(Value::as_array),
            "vibe",
            "(no vibes)",
        )),
        "vibe.show" | "vibe.create" | "vibe.update" => Some(detail(result, "vibe", "vibe")),
        "vibe.validate" | "skill.validate" | "lane.validate" => Some(validation(result)),
        "vibe.delete" => Some(format!("deleted vibe: {}", text(result, "id", "?"))),
        "skill.list" | "skill.import" => Some(list_lines(
            result.get("skills").and_then(Value::as_array),
            "skill",
            "(no skills)",
        )),
        "skill.show" | "skill.duplicate" => Some(detail(result, "skill", "skill")),
        "skill.remove" => Some(format!("removed skill: {}", text(result, "reference", "?"))),
        "schedule.list" => Some(list_lines(
            result.get("schedules").and_then(Value::as_array),
            "schedule",
            "(no schedules)",
        )),
        "schedule.show"
        | "schedule.create"
        | "schedule.update"
        | "schedule.pause"
        | "schedule.enable"
        | "schedule.adoptLane"
        | "schedule.adopt-lane" => Some(detail(result, "schedule", "schedule")),
        "schedule.runNow" | "schedule.run-now" => Some(detail(result, "run", "run")),
        "schedule.runs" => Some(list_lines(
            result.get("runs").and_then(Value::as_array),
            "run",
            "(no schedule runs)",
        )),
        "schedule.delete" => Some(format!("deleted schedule: {}", text(result, "id", "?"))),
        "schedule.preview" => {
            let occurrences = result
                .get("occurrences")
                .and_then(Value::as_array)
                .map(|values| {
                    values
                        .iter()
                        .filter_map(Value::as_str)
                        .collect::<Vec<_>>()
                        .join("\n")
                })
                .unwrap_or_default();
            Some(if occurrences.is_empty() {
                "(no occurrences)".to_string()
            } else {
                occurrences
            })
        }
        _ => None,
    }
}

fn print_human(method: &str, result: &Value) {
    if let Some(output) = automation_human_output(method, result) {
        println!("{output}");
        return;
    }
    match method {
        "ping" => {
            let app = result.get("app").and_then(Value::as_str).unwrap_or("?");
            let version = result.get("version").and_then(Value::as_str).unwrap_or("?");
            let build = result.get("build").and_then(Value::as_str).unwrap_or("?");
            let proto = result
                .get("protocol_version")
                .and_then(Value::as_i64)
                .unwrap_or(0);
            println!("ok  {app} {version} (build {build})  protocol={proto}");
        }
        "whoami" => {
            let pretty = serde_json::to_string_pretty(result).unwrap_or_default();
            println!("{pretty}");
        }
        "help" => {
            // Detailed mode: a single full descriptor wrapped in `commands`.
            if let Some(commands) = result.get("commands").and_then(Value::as_array) {
                if let Some(cmd) = commands.first() {
                    if cmd.get("params").is_some() {
                        let pretty = serde_json::to_string_pretty(cmd).unwrap_or_default();
                        println!("{pretty}");
                        return;
                    }
                }
            }
            // List mode: app overview, concepts, then category-grouped commands.
            // A single-category response omits `app`, so print only the category.
            let is_single_category = result.get("app").is_none();
            if !is_single_category {
                let app = result
                    .get("app")
                    .and_then(Value::as_str)
                    .unwrap_or("Crispy");
                let summary = result.get("summary").and_then(Value::as_str).unwrap_or("");
                println!("{app}");
                if !summary.is_empty() {
                    println!("  {summary}");
                }
            }
            if let Some(concepts) = result.get("concepts").and_then(Value::as_array) {
                if !concepts.is_empty() {
                    println!();
                    println!("Concepts");
                    for c in concepts {
                        let term = c.get("term").and_then(Value::as_str).unwrap_or("?");
                        let def = c.get("definition").and_then(Value::as_str).unwrap_or("");
                        println!("  {term:<14}  {def}");
                    }
                }
            }
            if let Some(domains) = result.get("domains").and_then(Value::as_array) {
                let multiple = domains.len() > 1;
                for domain in domains {
                    println!();
                    let name = domain.get("name").and_then(Value::as_str).unwrap_or("?");
                    let desc = domain
                        .get("description")
                        .and_then(Value::as_str)
                        .unwrap_or("");
                    println!("{name}");
                    println!("  {desc}");
                    if let Some(cmds) = domain.get("commands").and_then(Value::as_array) {
                        for cmd in cmds {
                            let method = cmd.get("method").and_then(Value::as_str).unwrap_or("?");
                            let summary = cmd.get("summary").and_then(Value::as_str).unwrap_or("");
                            println!("    {method:<22}  {summary}");
                        }
                    }
                }
                if multiple {
                    println!();
                    println!("Run `crispy help <category>` for one category, or `crispy help <method>` for a method's full schema.");
                }
            }
        }
        "shelf.add" => {
            let path = result.get("path").and_then(Value::as_str).unwrap_or("?");
            let kind = result.get("kind").and_then(Value::as_str).unwrap_or("?");
            let added = result
                .get("added")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let selected = result
                .get("selected")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let action = if added { "added" } else { "already shelved" };
            let sel_marker = if selected { " (selected)" } else { "" };
            println!("{action}: {path} [{kind}]{sel_marker}");
        }
        "shelf.list" => {
            if let Some(items) = result.get("items").and_then(Value::as_array) {
                if items.is_empty() {
                    println!("(shelf is empty)");
                } else {
                    for item in items {
                        let path = item.get("path").and_then(Value::as_str).unwrap_or("?");
                        let kind = item.get("kind").and_then(Value::as_str).unwrap_or("?");
                        let exists = item.get("exists").and_then(Value::as_bool).unwrap_or(true);
                        let selected = item
                            .get("selected")
                            .and_then(Value::as_bool)
                            .unwrap_or(false);
                        let mark_sel = if selected { "*" } else { " " };
                        let mark_missing = if exists { "" } else { "  (missing)" };
                        println!("{mark_sel} [{kind}] {path}{mark_missing}");
                    }
                }
            }
        }
        "shelf.remove" => {
            let removed = result
                .get("removed")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            println!("{}", if removed { "removed" } else { "not in shelf" });
        }
        "terminal.list" => {
            if let Some(terminals) = result.get("terminals").and_then(Value::as_array) {
                if terminals.is_empty() {
                    println!("(no terminals)");
                } else {
                    for t in terminals {
                        let id = t.get("terminal_id").and_then(Value::as_str).unwrap_or("?");
                        let title = t.get("title").and_then(Value::as_str).unwrap_or("?");
                        let cwd = t.get("cwd").and_then(Value::as_str).unwrap_or("?");
                        let focused = t.get("focused").and_then(Value::as_bool).unwrap_or(false);
                        let caller = t.get("is_caller").and_then(Value::as_bool).unwrap_or(false);
                        let marks = format!(
                            "{}{}",
                            if focused { "*" } else { " " },
                            if caller { "@" } else { " " }
                        );
                        println!("{marks} {id}  {title}  {cwd}");
                    }
                }
            }
        }
        "terminal.create" => {
            let id = result
                .get("terminal_id")
                .and_then(Value::as_str)
                .unwrap_or("?");
            println!("created: {id}");
        }
        "terminal.send" | "terminal.send_key" | "terminal.close" => {
            println!("ok");
        }
        "terminal.wait" => {
            let matched = result
                .get("matched")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            if matched {
                if let Some(text) = result.get("text").and_then(Value::as_str) {
                    println!("matched: {text}");
                } else if let Some(code) = result.get("exit_code").and_then(Value::as_i64) {
                    println!("exited: {code}");
                } else {
                    println!("matched");
                }
            } else {
                println!("timeout");
            }
        }
        "file.open" => {
            let path = result.get("path").and_then(Value::as_str).unwrap_or("?");
            let line = result.get("line").and_then(Value::as_i64);
            match line {
                Some(l) => println!("opened: {path}:{l}"),
                None => println!("opened: {path}"),
            }
        }
        "shortcut.list" => {
            if let Some(shortcuts) = result.get("shortcuts").and_then(Value::as_array) {
                if shortcuts.is_empty() {
                    println!("(no shortcuts)");
                } else {
                    for s in shortcuts {
                        let name = s.get("name").and_then(Value::as_str).unwrap_or("?");
                        let cmd = s.get("command").and_then(Value::as_str).unwrap_or("?");
                        let scope = s.get("scope").and_then(Value::as_str).unwrap_or("?");
                        println!("  [{scope}] {name}: {cmd}");
                    }
                }
            }
        }
        "shortcut.add" => {
            let name = result.get("name").and_then(Value::as_str).unwrap_or("?");
            let scope = result.get("scope").and_then(Value::as_str).unwrap_or("?");
            println!("added [{scope}]: {name}");
        }
        "shortcut.remove" => {
            let removed = result
                .get("removed")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            println!("{}", if removed { "removed" } else { "not found" });
        }
        "browser.list" => {
            if let Some(tabs) = result.get("tabs").and_then(Value::as_array) {
                if tabs.is_empty() {
                    println!("(no browser tabs)");
                } else {
                    for tab in tabs {
                        let id = tab.get("browser_id").and_then(Value::as_str).unwrap_or("?");
                        let title = tab.get("title").and_then(Value::as_str).unwrap_or("");
                        let url = tab.get("url").and_then(Value::as_str).unwrap_or("");
                        println!("{id}  {title}  {url}");
                    }
                }
            }
        }
        "browser.open" => {
            let id = result
                .get("browser_id")
                .and_then(Value::as_str)
                .unwrap_or("?");
            println!("opened: {id}");
        }
        "browser.close" => println!("closed"),
        "browser.url.get" => {
            let url = result.get("url").and_then(Value::as_str).unwrap_or("");
            println!("{url}");
        }
        "browser.get.title" => {
            let title = result.get("title").and_then(Value::as_str).unwrap_or("");
            println!("{title}");
        }
        "browser.snapshot" => {
            let snap = result
                .get("snapshot")
                .and_then(Value::as_str)
                .unwrap_or("(empty)");
            println!("{snap}");
        }
        "browser.eval" => {
            if let Some(v) = result.get("value") {
                if let Some(s) = v.as_str() {
                    println!("{s}");
                } else {
                    println!("{}", serde_json::to_string_pretty(v).unwrap_or_default());
                }
            } else {
                println!("OK");
            }
        }
        "browser.screenshot" => {
            let size = result.get("size").and_then(Value::as_i64).unwrap_or(0);
            println!("screenshot captured ({size} bytes)");
        }
        m if m.starts_with("browser.") => {
            // Generic OK for all other browser commands
            println!("OK");
        }
        "comments.list" | "comments.search" => {
            if let Some(comments) = result.get("comments").and_then(Value::as_array) {
                if comments.is_empty() {
                    println!("(no comments)");
                } else {
                    for c in comments {
                        let id = c.get("id").and_then(Value::as_str).unwrap_or("?");
                        let file = c.get("filePath").and_then(Value::as_str).unwrap_or("?");
                        let body = c.get("body").and_then(Value::as_str).unwrap_or("");
                        let kind = c
                            .get("authorKind")
                            .and_then(Value::as_str)
                            .unwrap_or("user");
                        let stale = c.get("isStale").and_then(Value::as_bool).unwrap_or(false);
                        let resolved = c.get("resolvedAt").and_then(Value::as_str).is_some();
                        let line = c
                            .get("anchor")
                            .and_then(|a| a.get("startLine"))
                            .and_then(Value::as_i64)
                            .unwrap_or(0);
                        let mut tags = String::new();
                        if resolved {
                            tags.push_str(" [resolved]");
                        }
                        if stale {
                            tags.push_str(" [stale]");
                        }
                        if kind == "agent" {
                            tags.push_str(" [agent]");
                        }
                        println!("{id}  {file}:{line}{tags}");
                        for line_text in body.lines().take(3) {
                            println!("    {line_text}");
                        }
                    }
                }
            }
        }
        "comments.add" | "comments.reply" => {
            let id = result.get("id").and_then(Value::as_str).unwrap_or("?");
            println!("created: {id}");
        }
        "comments.update" => {
            let id = result.get("id").and_then(Value::as_str).unwrap_or("?");
            println!("updated: {id}");
        }
        "comments.resolve" => {
            let id = result.get("id").and_then(Value::as_str).unwrap_or("?");
            let resolved = result.get("resolvedAt").and_then(Value::as_str);
            match resolved {
                Some(_) => println!("resolved: {id}"),
                None => println!("reopened: {id}"),
            }
        }
        "comments.delete" => {
            let id = result.get("id").and_then(Value::as_str).unwrap_or("?");
            let count = result
                .get("deletedCount")
                .and_then(Value::as_i64)
                .unwrap_or(0);
            println!("deleted {count} comment(s) starting at {id}");
        }
        "todo.add" => {
            let id = result.get("id").and_then(Value::as_str).unwrap_or("?");
            let title = result.get("title").and_then(Value::as_str).unwrap_or("");
            println!("created: {id}  {title}");
        }
        "todo.list" => {
            if let Some(todos) = result.get("todos").and_then(Value::as_array) {
                if todos.is_empty() {
                    println!("(no todos)");
                } else {
                    for t in todos {
                        let id = t.get("id").and_then(Value::as_str).unwrap_or("?");
                        let title = t.get("title").and_then(Value::as_str).unwrap_or("");
                        let status = t.get("status").and_then(Value::as_str).unwrap_or("active");
                        let mark = if status == "completed" { "[x]" } else { "[ ]" };
                        println!("{mark} {id}  {title}");
                    }
                }
            }
        }
        "todo.complete" | "todo.reopen" => {
            let id = result.get("id").and_then(Value::as_str).unwrap_or("?");
            let status = result.get("status").and_then(Value::as_str).unwrap_or("?");
            println!("{id}: {status}");
        }
        "todo.update" => {
            let id = result.get("id").and_then(Value::as_str).unwrap_or("?");
            println!("updated: {id}");
        }
        "todo.remove" => {
            let id = result.get("id").and_then(Value::as_str).unwrap_or("?");
            println!("removed: {id}");
        }
        "todo.show" => {
            let title = result.get("title").and_then(Value::as_str).unwrap_or("");
            let status = result
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or("active");
            let mark = if status == "completed" { "[x]" } else { "[ ]" };
            println!("{mark} {title}");
            if let Some(body) = result.get("body").and_then(Value::as_str) {
                if !body.is_empty() {
                    println!("\n{body}");
                }
            }
            if let Some(msgs) = result.get("messages").and_then(Value::as_array) {
                if !msgs.is_empty() {
                    println!("\n--- thread ---");
                    for m in msgs {
                        let who = m
                            .get("authorKind")
                            .and_then(Value::as_str)
                            .unwrap_or("user");
                        let b = m.get("body").and_then(Value::as_str).unwrap_or("");
                        println!("[{who}] {b}");
                    }
                }
            }
        }
        "todo.message.add" => {
            let id = result.get("id").and_then(Value::as_str).unwrap_or("?");
            println!("message added: {id}");
        }
        "todo.file.add" => {
            let path = result.get("path").and_then(Value::as_str).unwrap_or("?");
            println!("linked: {path}");
        }
        "todo.file.remove" => {
            let removed = result
                .get("removed")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            println!("{}", if removed { "unlinked" } else { "not linked" });
        }
        "todo.file.list" => {
            if let Some(files) = result.get("files").and_then(Value::as_array) {
                if files.is_empty() {
                    println!("(no linked files)");
                } else {
                    for f in files {
                        let path = f.get("path").and_then(Value::as_str).unwrap_or("?");
                        let missing = f.get("missing").and_then(Value::as_bool).unwrap_or(false);
                        let mark_missing = if missing { "  (missing)" } else { "" };
                        match f.get("line").and_then(Value::as_i64) {
                            Some(line) => println!("{path}:{line}{mark_missing}"),
                            None => println!("{path}{mark_missing}"),
                        }
                    }
                }
            }
        }
        "todo.triage.show" => {
            if let Some(triage) = result.get("triage").and_then(Value::as_str) {
                // The triage payload arrives as an encoded JSON string; pretty-print it.
                match serde_json::from_str::<Value>(triage) {
                    Ok(v) => println!("{}", serde_json::to_string_pretty(&v).unwrap_or_default()),
                    Err(_) => println!("{triage}"),
                }
            } else {
                println!("(no triage)");
            }
        }
        "todo.dispatch" => {
            let task_id = result.get("taskId").and_then(Value::as_str).unwrap_or("?");
            println!("dispatched: {task_id}");
        }
        _ => {
            let pretty = serde_json::to_string_pretty(result).unwrap_or_default();
            println!("{pretty}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dispatch_params_minimal_omits_inputs_and_allow_unresolved() {
        let params = dispatch_params("t1".into(), "build".into(), &[], false).unwrap();
        assert_eq!(params, json!({ "id": "t1", "lane": "build" }));
    }

    #[test]
    fn dispatch_params_splits_inputs_on_first_equals() {
        let inputs = vec!["branch=feature/x".to_string(), "note=a=b=c".to_string()];
        let params = dispatch_params("t1".into(), "build".into(), &inputs, false).unwrap();
        assert_eq!(
            params["inputs"],
            json!({ "branch": "feature/x", "note": "a=b=c" })
        );
    }

    #[test]
    fn dispatch_params_includes_allow_unresolved_only_when_set() {
        let params = dispatch_params("t1".into(), "build".into(), &[], true).unwrap();
        assert_eq!(params["allowUnresolved"], json!(true));
    }

    #[test]
    fn dispatch_params_rejects_input_without_equals() {
        let inputs = vec!["missing-separator".to_string()];
        let err = dispatch_params("t1".into(), "build".into(), &inputs, false).unwrap_err();
        assert!(
            err.contains("expected key=value"),
            "unexpected error: {err}"
        );
    }

    fn assert_automation_rpc(command: Command, method: &str, params: Value) {
        let (actual_method, actual_params) = automation_rpc(&command).unwrap().unwrap();
        assert_eq!(actual_method, method);
        assert_eq!(actual_params, params);
    }

    fn document_file() -> PathBuf {
        let path =
            std::env::temp_dir().join(format!("crispy-cli-document-{}.json", uuid::Uuid::new_v4()));
        std::fs::write(&path, r#"{"name":"automation"}"#).unwrap();
        path
    }

    #[test]
    fn json_document_reader_accepts_valid_json_and_rejects_malformed_json() {
        let document = load_json_document_from_reader(
            std::io::Cursor::new(br#"{"name":"test","enabled":false}"#),
            "stdin",
        )
        .unwrap();
        assert_eq!(document, json!({ "name": "test", "enabled": false }));

        let error =
            load_json_document_from_reader(std::io::Cursor::new(b"{"), "stdin").unwrap_err();
        assert!(error.contains("invalid JSON document from stdin"));
    }

    #[test]
    fn json_document_file_helper_reads_file() {
        let path = document_file();
        let document = load_json_document(&path).unwrap();
        std::fs::remove_file(path).unwrap();
        assert_eq!(document, json!({ "name": "automation" }));
    }

    #[test]
    fn lane_commands_map_to_registered_methods_and_named_params() {
        let file = document_file();
        let document = json!({ "name": "automation" });
        assert_automation_rpc(Command::Lane(LaneCommand::List), "lane.list", json!({}));
        assert_automation_rpc(
            Command::Lane(LaneCommand::Show {
                lane: "release".into(),
            }),
            "lane.show",
            json!({ "lane": "release" }),
        );
        assert_automation_rpc(
            Command::Lane(LaneCommand::Validate { file: file.clone() }),
            "lane.validate",
            json!({ "document": document }),
        );
        assert_automation_rpc(
            Command::Lane(LaneCommand::Create { file: file.clone() }),
            "lane.create",
            json!({ "document": document }),
        );
        assert_automation_rpc(
            Command::Lane(LaneCommand::Update {
                lane: "lane-id".into(),
                file: file.clone(),
                expected_version: 4,
            }),
            "lane.update",
            json!({ "lane": "lane-id", "document": document, "expectedVersion": 4 }),
        );
        assert_automation_rpc(
            Command::Lane(LaneCommand::Delete {
                lane: "lane-id".into(),
                expected_version: 5,
            }),
            "lane.delete",
            json!({ "lane": "lane-id", "expectedVersion": 5 }),
        );
        assert_automation_rpc(
            Command::Lane(LaneCommand::RestoreStarters),
            "lane.restoreStarters",
            json!({}),
        );
        std::fs::remove_file(file).unwrap();
    }

    #[test]
    fn lane_task_commands_map_to_registered_methods_and_named_params() {
        assert_automation_rpc(
            Command::Lane(LaneCommand::Task(LaneTaskCommand::Create {
                lane: "release".into(),
                input: "ship it".into(),
                project: Some("/tmp/project".into()),
                agent: Some("agent".into()),
                values: vec!["branch=main".into()],
            })),
            "lane.task.create",
            json!({
                "lane": "release", "input": "ship it", "project": "/tmp/project",
                "agent": "agent", "inputs": { "branch": "main" }
            }),
        );
        assert_automation_rpc(
            Command::Lane(LaneCommand::Task(LaneTaskCommand::List {
                state: Some("running".into()),
                project: None,
            })),
            "lane.task.list",
            json!({ "state": "running", "project": null }),
        );
        assert_automation_rpc(
            Command::Lane(LaneCommand::Task(LaneTaskCommand::Show { id: "t1".into() })),
            "lane.task.show",
            json!({ "id": "t1" }),
        );
        assert_automation_rpc(
            Command::Lane(LaneCommand::Task(LaneTaskCommand::Answer {
                id: "t1".into(),
                values: vec!["artifact=a=b".into()],
                guidance: None,
                approve: Some(false),
                feedback: Some("retry".into()),
                advance: None,
            })),
            "lane.task.answer",
            json!({
                "id": "t1", "values": { "artifact": "a=b" }, "guidance": null,
                "approve": false, "feedback": "retry", "advance": null
            }),
        );
        assert_automation_rpc(
            Command::Lane(LaneCommand::Task(LaneTaskCommand::Stop { id: "t1".into() })),
            "lane.task.stop",
            json!({ "id": "t1" }),
        );
        assert_automation_rpc(
            Command::Lane(LaneCommand::Task(LaneTaskCommand::Delete {
                id: "t1".into(),
            })),
            "lane.task.delete",
            json!({ "id": "t1" }),
        );
    }

    #[test]
    fn vibe_commands_map_documents_versions_and_filters() {
        let file = document_file();
        let document = json!({ "name": "automation" });
        assert_automation_rpc(
            Command::Vibe(VibeCommand::List {
                category: Some("release".into()),
                status: Some("ready".into()),
            }),
            "vibe.list",
            json!({ "category": "release", "status": "ready" }),
        );
        assert_automation_rpc(
            Command::Vibe(VibeCommand::Show { id: "v1".into() }),
            "vibe.show",
            json!({ "id": "v1" }),
        );
        assert_automation_rpc(
            Command::Vibe(VibeCommand::Validate { file: file.clone() }),
            "vibe.validate",
            json!({ "document": document }),
        );
        assert_automation_rpc(
            Command::Vibe(VibeCommand::Create { file: file.clone() }),
            "vibe.create",
            json!({ "document": document }),
        );
        assert_automation_rpc(
            Command::Vibe(VibeCommand::Update {
                id: "v1".into(),
                file: file.clone(),
                expected_version: 2,
            }),
            "vibe.update",
            json!({ "id": "v1", "document": document, "expectedVersion": 2 }),
        );
        assert_automation_rpc(
            Command::Vibe(VibeCommand::Delete {
                id: "v1".into(),
                expected_version: 3,
            }),
            "vibe.delete",
            json!({ "id": "v1", "expectedVersion": 3 }),
        );
        std::fs::remove_file(file).unwrap();
    }

    #[test]
    fn skill_commands_map_references_and_import_mode() {
        assert_automation_rpc(
            Command::Skill(SkillCommand::List {
                source: Some("personal".into()),
                role: Some("review".into()),
            }),
            "skill.list",
            json!({ "source": "personal", "role": "review" }),
        );
        assert_automation_rpc(
            Command::Skill(SkillCommand::Show {
                reference: "reviewer".into(),
                include_body: true,
            }),
            "skill.show",
            json!({ "reference": "reviewer", "includeBody": true }),
        );
        assert_automation_rpc(
            Command::Skill(SkillCommand::Validate {
                reference: "./skill".into(),
            }),
            "skill.validate",
            json!({ "reference": "./skill" }),
        );
        assert_automation_rpc(
            Command::Skill(SkillCommand::Import {
                path: "./skill".into(),
                copy: false,
                link: true,
            }),
            "skill.import",
            json!({ "path": "./skill", "mode": "link" }),
        );
        assert_automation_rpc(
            Command::Skill(SkillCommand::Duplicate {
                reference: "reviewer".into(),
            }),
            "skill.duplicate",
            json!({ "reference": "reviewer" }),
        );
        assert_automation_rpc(
            Command::Skill(SkillCommand::Remove {
                reference: "reviewer".into(),
            }),
            "skill.remove",
            json!({ "reference": "reviewer" }),
        );
    }

    #[test]
    fn schedule_commands_map_documents_and_confirmations() {
        let file = document_file();
        let document = json!({ "name": "automation" });
        assert_automation_rpc(
            Command::Schedule(ScheduleCommand::List {
                status: Some("paused".into()),
            }),
            "schedule.list",
            json!({ "status": "paused" }),
        );
        assert_automation_rpc(
            Command::Schedule(ScheduleCommand::Show { id: "s1".into() }),
            "schedule.show",
            json!({ "id": "s1" }),
        );
        assert_automation_rpc(
            Command::Schedule(ScheduleCommand::Create {
                file: file.clone(),
                confirm_full_trust: true,
            }),
            "schedule.create",
            json!({ "document": document, "confirmFullTrust": true }),
        );
        assert_automation_rpc(
            Command::Schedule(ScheduleCommand::Update {
                id: "s1".into(),
                file: file.clone(),
                confirm_full_trust: false,
            }),
            "schedule.update",
            json!({
                "id": "s1", "document": document,
                "confirmFullTrust": false
            }),
        );
        assert_automation_rpc(
            Command::Schedule(ScheduleCommand::Pause { id: "s1".into() }),
            "schedule.pause",
            json!({ "id": "s1" }),
        );
        assert_automation_rpc(
            Command::Schedule(ScheduleCommand::Enable {
                id: "s1".into(),
                confirm_full_trust: true,
            }),
            "schedule.enable",
            json!({ "id": "s1", "confirmFullTrust": true }),
        );
        assert_automation_rpc(
            Command::Schedule(ScheduleCommand::AdoptLane {
                id: "s1".into(),
                lane: "lane-id".into(),
                confirm_full_trust: true,
            }),
            "schedule.adopt-lane",
            json!({
                "id": "s1", "lane": "lane-id",
                "confirmFullTrust": true
            }),
        );
        assert_automation_rpc(
            Command::Schedule(ScheduleCommand::RunNow { id: "s1".into() }),
            "schedule.run-now",
            json!({ "id": "s1" }),
        );
        assert_automation_rpc(
            Command::Schedule(ScheduleCommand::Runs {
                id: "s1".into(),
                limit: Some(10),
            }),
            "schedule.runs",
            json!({ "id": "s1", "limit": 10 }),
        );
        assert_automation_rpc(
            Command::Schedule(ScheduleCommand::Delete {
                id: "s1".into(),
                stop_active: false,
                keep_active: true,
            }),
            "schedule.delete",
            json!({ "id": "s1", "stopActive": false }),
        );
        assert_automation_rpc(
            Command::Schedule(ScheduleCommand::Preview {
                file: file.clone(),
                count: Some(8),
            }),
            "schedule.preview",
            json!({ "document": document, "count": 8 }),
        );
        std::fs::remove_file(file).unwrap();
    }

    #[test]
    fn automation_human_output_covers_all_families_and_safety_signals() {
        let lane = automation_human_output(
            "lane.update",
            &json!({ "lane": { "id": "l1", "name": "Release", "version": 2, "checkpoints": [] } }),
        )
        .unwrap();
        assert!(lane.contains("lane l1  Release"));
        assert!(lane.contains("version: 2"));

        let vibe = automation_human_output(
            "vibe.list",
            &json!({ "vibes": [{ "id": "v1", "name": "Build", "version": 3, "ready": false }] }),
        )
        .unwrap();
        assert!(vibe.contains("[needs-setup]"));

        let skill = automation_human_output(
            "skill.show",
            &json!({ "skill": { "reference": "/tmp/review/SKILL.md", "name": "Review", "source": "linked", "validation": "ready" } }),
        )
        .unwrap();
        assert!(skill.contains("source changes are reflected"));

        let schedule = automation_human_output(
            "schedule.enable",
            &json!({ "schedule": { "id": "s1", "name": "Nightly", "status": "scheduled", "enabled": true } }),
        )
        .unwrap();
        assert!(schedule.contains("Full Trust acknowledged"));

        let validation = automation_human_output(
            "vibe.validate",
            &json!({ "valid": false, "issues": ["skill not found"] }),
        )
        .unwrap();
        assert_eq!(validation, "invalid\n  - skill not found");

        let lane_validation =
            automation_human_output("lane.validate", &json!({ "valid": true, "issues": [] }))
                .unwrap();
        assert_eq!(lane_validation, "valid");

        let preview = automation_human_output(
            "schedule.preview",
            &json!({ "occurrences": ["2026-10-01T12:00:00Z", "2026-10-02T12:00:00Z"] }),
        )
        .unwrap();
        assert_eq!(preview.lines().count(), 2);
    }

    #[test]
    fn json_output_remains_compact_machine_readable_json() {
        let result = json!({
            "schedule": { "id": "s1", "enabled": true },
            "occurrences": ["2026-10-01T12:00:00Z"]
        });
        let rendered = render_json_output(&result);
        assert_eq!(serde_json::from_str::<Value>(&rendered).unwrap(), result);
        assert!(!rendered.contains('\n'));
    }

    #[test]
    fn clap_parses_lane_validate_file_and_global_json() {
        let cli = Cli::try_parse_from([
            "crispy",
            "lane",
            "validate",
            "--file",
            "lane.json",
            "--json",
        ])
        .unwrap();
        assert!(cli.json);
        assert!(matches!(
            cli.command,
            Command::Lane(LaneCommand::Validate { file }) if file == PathBuf::from("lane.json")
        ));
    }

    #[test]
    fn clap_preserves_global_json_for_nested_automation_commands() {
        let cli =
            Cli::try_parse_from(["crispy", "lane", "task", "show", "task-id", "--json"]).unwrap();
        assert!(cli.json);
        assert!(matches!(
            cli.command,
            Command::Lane(LaneCommand::Task(LaneTaskCommand::Show { id })) if id == "task-id"
        ));
    }
}
