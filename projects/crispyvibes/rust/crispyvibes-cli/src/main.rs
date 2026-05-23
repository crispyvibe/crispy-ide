use std::io::{BufRead, BufReader, Write};
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
    /// List all supported methods, or describe one when METHOD is given.
    Help {
        /// When provided, returns the full schema for just that method.
        method: Option<String>,
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

    let (method, params): (&str, Value) = match cli.command {
        Command::Ping => ("ping", json!({})),
        Command::Whoami => ("whoami", json!({})),
        Command::Help { method } => match method {
            Some(m) => ("help", json!({ "method": m })),
            None => ("help", json!({})),
        },
        Command::Shelf(ShelfCommand::Add { path, select }) => (
            "shelf.add",
            json!({ "path": path, "select": select }),
        ),
        Command::Shelf(ShelfCommand::List) => ("shelf.list", json!({})),
        Command::Shelf(ShelfCommand::Remove { path }) => (
            "shelf.remove",
            json!({ "path": path }),
        ),
        Command::Terminal(TerminalCommand::List) => ("terminal.list", json!({})),
        Command::Terminal(TerminalCommand::Create { cwd, name }) => (
            "terminal.create",
            json!({ "cwd": cwd, "name": name }),
        ),
        Command::Terminal(TerminalCommand::Send { text, terminal_id, submit }) => (
            "terminal.send",
            json!({ "text": text, "terminal_id": terminal_id, "submit": submit }),
        ),
        Command::Terminal(TerminalCommand::SendKey { key, terminal_id }) => (
            "terminal.send_key",
            json!({ "key": key, "terminal_id": terminal_id }),
        ),
        Command::Terminal(TerminalCommand::Close { terminal_id }) => (
            "terminal.close",
            json!({ "terminal_id": terminal_id }),
        ),
        Command::Terminal(TerminalCommand::Wait { text, wait_exit, timeout, terminal_id }) => (
            "terminal.wait",
            json!({ "text": text, "exit": wait_exit, "timeout": timeout, "terminal_id": terminal_id }),
        ),
        Command::File(FileCommand::Open { path, line, column }) => (
            "file.open",
            json!({ "path": path, "line": line, "column": column }),
        ),
        Command::Shortcut(ShortcutCommand::List) => ("shortcut.list", json!({})),
        Command::Shortcut(ShortcutCommand::Add { name, command, launch_behavior, scope }) => (
            "shortcut.add",
            json!({ "name": name, "command": command, "launch_behavior": launch_behavior, "scope": scope }),
        ),
        Command::Shortcut(ShortcutCommand::Remove { id }) => (
            "shortcut.remove",
            json!({ "id": id }),
        ),
        Command::Browser(BrowserCommand::List { query, scope }) => (
            "browser.list",
            json!({ "query": query.unwrap_or_default(), "scope": scope }),
        ),
        Command::Browser(BrowserCommand::Open { url }) => (
            "browser.open",
            json!({ "url": url.unwrap_or_default() }),
        ),
        Command::Browser(BrowserCommand::Close { browser_id }) => (
            "browser.close",
            json!({ "browser_id": browser_id }),
        ),
        Command::Browser(BrowserCommand::Navigate { browser_id, url }) => (
            "browser.navigate",
            json!({ "browser_id": browser_id, "url": url }),
        ),
        Command::Browser(BrowserCommand::Back { browser_id }) => (
            "browser.back",
            json!({ "browser_id": browser_id }),
        ),
        Command::Browser(BrowserCommand::Forward { browser_id }) => (
            "browser.forward",
            json!({ "browser_id": browser_id }),
        ),
        Command::Browser(BrowserCommand::Reload { browser_id }) => (
            "browser.reload",
            json!({ "browser_id": browser_id }),
        ),
        Command::Browser(BrowserCommand::Url { browser_id }) => (
            "browser.url.get",
            json!({ "browser_id": browser_id }),
        ),
        Command::Browser(BrowserCommand::Title { browser_id }) => (
            "browser.get.title",
            json!({ "browser_id": browser_id }),
        ),
        Command::Browser(BrowserCommand::Click { browser_id, selector }) => (
            "browser.click",
            json!({ "browser_id": browser_id, "selector": selector }),
        ),
        Command::Browser(BrowserCommand::Fill { browser_id, selector, text }) => (
            "browser.fill",
            json!({ "browser_id": browser_id, "selector": selector, "text": text }),
        ),
        Command::Browser(BrowserCommand::Type { browser_id, selector, text }) => (
            "browser.type",
            json!({ "browser_id": browser_id, "selector": selector, "text": text }),
        ),
        Command::Browser(BrowserCommand::Press { browser_id, key }) => (
            "browser.press",
            json!({ "browser_id": browser_id, "key": key }),
        ),
        Command::Browser(BrowserCommand::Snapshot { browser_id, max_depth }) => (
            "browser.snapshot",
            json!({ "browser_id": browser_id, "max_depth": max_depth }),
        ),
        Command::Browser(BrowserCommand::Eval { browser_id, script }) => (
            "browser.eval",
            json!({ "browser_id": browser_id, "script": script }),
        ),
        Command::Browser(BrowserCommand::Wait { browser_id, selector, text, url_contains, timeout }) => (
            "browser.wait",
            json!({ "browser_id": browser_id, "selector": selector, "text_contains": text, "url_contains": url_contains, "timeout": timeout }),
        ),
        Command::Browser(BrowserCommand::Screenshot { browser_id, full_page }) => (
            "browser.screenshot",
            json!({ "browser_id": browser_id, "full_page": full_page }),
        ),
        Command::Browser(BrowserCommand::Raw { method, params }) => {
            let base: Value = serde_json::from_str(&params).unwrap_or(json!({}));
            (Box::leak(method.into_boxed_str()) as &str, base)
        },
        Command::Vibespace(VibespaceCommand::AddProject { path }) => (
            "vibespace.addProject",
            json!({ "path": path }),
        ),
        Command::Vibespace(VibespaceCommand::RemoveProject { path }) => (
            "vibespace.removeProject",
            json!({ "path": path }),
        ),
        Command::Vibespace(VibespaceCommand::ParkProject { path }) => (
            "vibespace.parkProject",
            json!({ "path": path }),
        ),
    };

    let response = send_request(&socket_path, method, params, &env)?;

    if cli.json {
        println!("{}", serde_json::to_string(&response).unwrap_or_default());
    } else {
        print_human(method, &response);
    }
    Ok(())
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
    // it spawns, so this fallback only fires when the CLI is invoked from a
    // non-Crispy context — where the F044-R02 ancestry check would reject the
    // connection regardless. Default to the production bundle ID so the error
    // message points at the conventional location.
    let bundle = std::env::var("CRISPY_BUNDLE_ID")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "com.crispyvibe.app".to_string());
    Ok(PathBuf::from(home)
        .join("Library/Application Support")
        .join(&bundle)
        .join("crispy.sock"))
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
            context: std::env::var("CRISPY_CONTEXT").ok().filter(|s| !s.is_empty()),
            vibespace: std::env::var("CRISPY_VIBESPACE").ok().filter(|s| !s.is_empty()),
            project_path: std::env::var("CRISPY_PROJECT_PATH").ok().filter(|s| !s.is_empty()),
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
    stream
        .set_read_timeout(Some(Duration::from_secs(30)))
        .ok();
    stream
        .set_write_timeout(Some(Duration::from_secs(5)))
        .ok();

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
    let response: Value = serde_json::from_str(line.trim_end()).map_err(|e| {
        format!("server returned invalid JSON: {e}; payload was: {line:?}")
    })?;

    if !response
        .get("ok")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
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

fn print_human(method: &str, result: &Value) {
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
            // List mode: app overview, concepts, then domain-grouped commands.
            let app = result.get("app").and_then(Value::as_str).unwrap_or("Crispy");
            let summary = result.get("summary").and_then(Value::as_str).unwrap_or("");
            println!("{app}");
            if !summary.is_empty() {
                println!("  {summary}");
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
                for domain in domains {
                    println!();
                    let name = domain.get("name").and_then(Value::as_str).unwrap_or("?");
                    let desc = domain.get("description").and_then(Value::as_str).unwrap_or("");
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
            }
        }
        "shelf.add" => {
            let path = result.get("path").and_then(Value::as_str).unwrap_or("?");
            let kind = result.get("kind").and_then(Value::as_str).unwrap_or("?");
            let added = result.get("added").and_then(Value::as_bool).unwrap_or(false);
            let selected = result.get("selected").and_then(Value::as_bool).unwrap_or(false);
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
                        let selected = item.get("selected").and_then(Value::as_bool).unwrap_or(false);
                        let mark_sel = if selected { "*" } else { " " };
                        let mark_missing = if exists { "" } else { "  (missing)" };
                        println!("{mark_sel} [{kind}] {path}{mark_missing}");
                    }
                }
            }
        }
        "shelf.remove" => {
            let removed = result.get("removed").and_then(Value::as_bool).unwrap_or(false);
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
            let id = result.get("terminal_id").and_then(Value::as_str).unwrap_or("?");
            println!("created: {id}");
        }
        "terminal.send" | "terminal.send_key" | "terminal.close" => {
            println!("ok");
        }
        "terminal.wait" => {
            let matched = result.get("matched").and_then(Value::as_bool).unwrap_or(false);
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
            let removed = result.get("removed").and_then(Value::as_bool).unwrap_or(false);
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
            let id = result.get("browser_id").and_then(Value::as_str).unwrap_or("?");
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
            let snap = result.get("snapshot").and_then(Value::as_str).unwrap_or("(empty)");
            println!("{snap}");
        }
        "browser.eval" => {
            if let Some(v) = result.get("value") {
                if let Some(s) = v.as_str() { println!("{s}"); }
                else { println!("{}", serde_json::to_string_pretty(v).unwrap_or_default()); }
            } else { println!("OK"); }
        }
        "browser.screenshot" => {
            let size = result.get("size").and_then(Value::as_i64).unwrap_or(0);
            println!("screenshot captured ({size} bytes)");
        }
        m if m.starts_with("browser.") => {
            // Generic OK for all other browser commands
            println!("OK");
        }
        _ => {
            let pretty = serde_json::to_string_pretty(result).unwrap_or_default();
            println!("{pretty}");
        }
    }
}
