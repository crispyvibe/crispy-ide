use std::ffi::CString;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand, ValueEnum};
use serde::Serialize;
use serde_json::Value;

const PROCESS_NAME: &str = "CrispyVibes (external sessions helper)";
const DEFAULT_LIMIT: usize = 500;
const SCAN_TITLE_LINE_LIMIT: usize = 400;
const SEARCH_LINE_LIMIT: usize = 8_000;
const PREVIEW_ENTRY_LIMIT: usize = 2_000;

#[derive(Parser)]
#[command(author, version, about)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    Scan {
        #[arg(long, value_enum)]
        provider: Option<Provider>,
        #[arg(long, default_value_t = DEFAULT_LIMIT)]
        limit: usize,
    },
    Search {
        query: String,
        #[arg(long, value_enum)]
        provider: Option<Provider>,
        #[arg(long, default_value_t = 100)]
        limit: usize,
    },
    Load {
        #[arg(long, value_enum)]
        provider: Provider,
        #[arg(long)]
        source_path: String,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, ValueEnum)]
#[serde(rename_all = "lowercase")]
enum Provider {
    Codex,
    Claude,
    Kiro,
    #[value(name = "opencode")]
    OpenCode,
    Pi,
}

impl Provider {
    fn id(self) -> &'static str {
        match self {
            Provider::Codex => "codex",
            Provider::Claude => "claude",
            Provider::Kiro => "kiro",
            Provider::OpenCode => "opencode",
            Provider::Pi => "pi",
        }
    }

    fn display_name(self) -> &'static str {
        match self {
            Provider::Codex => "Codex",
            Provider::Claude => "Claude Code",
            Provider::Kiro => "Kiro CLI",
            Provider::OpenCode => "OpenCode",
            Provider::Pi => "Pi",
        }
    }
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct ExternalSessionSummary {
    provider: String,
    provider_name: String,
    session_id: String,
    title: String,
    project_path: String,
    source_path: String,
    created_at: String,
    updated_at: String,
    modified_at_epoch: u64,
    message_count: usize,
    has_tool_activity: bool,
    parse_status: String,
    parse_errors: Vec<ParseDiagnostic>,
    parent_session_id: Option<String>,
    search_snippet: Option<String>,
    search_snippets: Vec<String>,
    match_count: usize,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct ParseDiagnostic {
    provider: String,
    source_path: String,
    parser: String,
    line: Option<usize>,
    context: String,
    message: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ScanResponse {
    sessions: Vec<ExternalSessionSummary>,
    diagnostics: Vec<ParseDiagnostic>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct TranscriptResponse {
    session: ExternalSessionSummary,
    entries: Vec<TranscriptEntry>,
    parse_errors: Vec<ParseDiagnostic>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct TranscriptEntry {
    role: String,
    timestamp: String,
    text: String,
    metadata: Value,
}

fn main() -> Result<()> {
    apply_process_name();
    let cli = Cli::parse();
    match cli.command {
        Command::Scan { provider, limit } => {
            let response = scan(provider, limit);
            print_json(&response)?;
        }
        Command::Search {
            query,
            provider,
            limit,
        } => {
            let response = search(&query, provider, limit);
            print_json(&response)?;
        }
        Command::Load {
            provider,
            source_path,
        } => {
            let response = load(provider, PathBuf::from(source_path));
            print_json(&response)?;
        }
    }
    Ok(())
}

fn print_json<T: Serialize>(value: &T) -> Result<()> {
    let stdout = std::io::stdout();
    serde_json::to_writer(stdout.lock(), value).context("write JSON response")?;
    println!();
    Ok(())
}

fn scan(provider_filter: Option<Provider>, limit: usize) -> ScanResponse {
    let mut sessions = Vec::new();
    let mut diagnostics = Vec::new();
    for provider in providers(provider_filter) {
        let mut provider_sessions = discover_provider(provider, &mut diagnostics);
        sessions.append(&mut provider_sessions);
    }

    sessions.sort_by(|lhs, rhs| {
        rhs.modified_at_epoch
            .cmp(&lhs.modified_at_epoch)
            .then_with(|| rhs.updated_at.cmp(&lhs.updated_at))
            .then_with(|| lhs.provider.cmp(&rhs.provider))
            .then_with(|| lhs.title.cmp(&rhs.title))
    });
    sessions.truncate(limit);
    ScanResponse {
        sessions,
        diagnostics,
    }
}

fn search(query: &str, provider_filter: Option<Provider>, limit: usize) -> ScanResponse {
    let needle = query.trim().to_lowercase();
    if needle.is_empty() {
        return ScanResponse {
            sessions: Vec::new(),
            diagnostics: Vec::new(),
        };
    }

    let mut response = scan(provider_filter, usize::MAX);
    let mut matches = Vec::new();
    for mut session in response.sessions {
        // Match the query against the TITLE only. The ambient directory path is
        // deliberately excluded — otherwise every session living under a folder
        // like "crispyvibe" matches a query of "vibe" even when its content has
        // nothing to do with it.
        if session.title.to_lowercase().contains(&needle) {
            // The title is already the row's primary line; don't echo it back as
            // a snippet (that produced a duplicated second line). Real context
            // snippets come from body matches below.
            session.search_snippet = None;
            session.search_snippets = Vec::new();
            session.match_count = 1;
            matches.push(session);
            continue;
        }

        match find_body_matches(&session, &needle) {
            Ok(Some(body_match)) => {
                session.search_snippet = body_match.snippets.first().cloned();
                session.search_snippets = body_match.snippets;
                session.match_count = body_match.count;
                matches.push(session);
            }
            Ok(None) => {}
            Err(error) => response.diagnostics.push(error),
        }

        if matches.len() >= limit {
            break;
        }
    }

    ScanResponse {
        sessions: matches,
        diagnostics: response.diagnostics,
    }
}

fn load(provider: Provider, source_path: PathBuf) -> TranscriptResponse {
    if provider == Provider::OpenCode {
        return load_opencode(&source_path.to_string_lossy());
    }
    let mut diagnostics = Vec::new();
    let summary_path = if provider == Provider::Kiro
        && source_path.extension().and_then(|value| value.to_str()) == Some("jsonl")
    {
        let sidecar_path = source_path.with_extension("json");
        if sidecar_path.exists() {
            sidecar_path
        } else {
            source_path.clone()
        }
    } else {
        source_path.clone()
    };
    let mut summary = summarize_session(provider, &summary_path, &mut diagnostics);
    summary.source_path = source_path.to_string_lossy().to_string();
    if summary.session_id.is_empty() {
        summary.session_id = source_path
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string();
    }

    let mut entries = Vec::new();
    let mut parse_errors = diagnostics.clone();
    if let Ok(file) = fs::File::open(&source_path) {
        for (index, line) in BufReader::new(file).lines().enumerate() {
            if entries.len() >= PREVIEW_ENTRY_LIMIT {
                break;
            }
            let line_number = index + 1;
            match line {
                Ok(raw) => {
                    if raw.trim().is_empty() {
                        continue;
                    }
                    match serde_json::from_str::<Value>(&raw) {
                        Ok(value) => {
                            if let Some(entry) = transcript_entry(provider, &value) {
                                if !entry.text.trim().is_empty() {
                                    entries.push(entry);
                                }
                            }
                        }
                        Err(error) => parse_errors.push(diagnostic(
                            provider,
                            &source_path,
                            Some(line_number),
                            "jsonl",
                            error.to_string(),
                        )),
                    }
                }
                Err(error) => parse_errors.push(diagnostic(
                    provider,
                    &source_path,
                    Some(line_number),
                    "read",
                    error.to_string(),
                )),
            }
        }
    } else {
        parse_errors.push(diagnostic(
            provider,
            &source_path,
            None,
            "open",
            "source file could not be opened",
        ));
    }

    summary.parse_status = parse_status(&parse_errors);
    summary.parse_errors = parse_errors.clone();
    TranscriptResponse {
        session: summary,
        entries,
        parse_errors,
    }
}

fn providers(filter: Option<Provider>) -> Vec<Provider> {
    match filter {
        Some(provider) => vec![provider],
        None => vec![Provider::Codex, Provider::Claude, Provider::Kiro, Provider::OpenCode, Provider::Pi],
    }
}

fn discover_provider(
    provider: Provider,
    diagnostics: &mut Vec<ParseDiagnostic>,
) -> Vec<ExternalSessionSummary> {
    // OpenCode stores sessions in a SQLite DB, not per-session files.
    if provider == Provider::OpenCode {
        return discover_opencode(diagnostics);
    }

    let Some(root) = provider_root(provider) else {
        return Vec::new();
    };
    if !root.exists() {
        return Vec::new();
    }

    let paths = match provider {
        Provider::Codex | Provider::Claude | Provider::Pi => collect_files(&root, "jsonl"),
        Provider::Kiro => collect_files(&root, "json"),
        Provider::OpenCode => Vec::new(),
    };

    paths
        .into_iter()
        .filter_map(|path| {
            if provider == Provider::Kiro
                && path
                    .file_name()
                    .and_then(|v| v.to_str())
                    .is_some_and(|name| name.ends_with(".jsonl"))
            {
                return None;
            }
            Some(summarize_session(provider, &path, diagnostics))
        })
        .collect()
}

fn provider_root(provider: Provider) -> Option<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from)?;
    Some(match provider {
        Provider::Codex => home.join(".codex/sessions"),
        Provider::Claude => home.join(".claude/projects"),
        Provider::Kiro => home.join(".kiro/sessions/cli"),
        Provider::OpenCode => home.join(".local/share/opencode/opencode.db"),
        Provider::Pi => home.join(".pi/agent/sessions"),
    })
}

fn collect_files(root: &Path, extension: &str) -> Vec<PathBuf> {
    let mut result = Vec::new();
    collect_files_into(root, extension, &mut result);
    result
}

fn collect_files_into(path: &Path, extension: &str, result: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(path) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_files_into(&path, extension, result);
        } else if path.extension().and_then(|value| value.to_str()) == Some(extension) {
            result.push(path);
        }
    }
}

fn summarize_session(
    provider: Provider,
    path: &Path,
    diagnostics: &mut Vec<ParseDiagnostic>,
) -> ExternalSessionSummary {
    match provider {
        Provider::Codex => summarize_jsonl(provider, path, diagnostics),
        Provider::Claude => summarize_jsonl(provider, path, diagnostics),
        Provider::Kiro => summarize_kiro(path, diagnostics),
        Provider::OpenCode => empty_summary(provider, path.to_path_buf()),
        Provider::Pi => summarize_jsonl(provider, path, diagnostics),
    }
}

fn summarize_kiro(path: &Path, diagnostics: &mut Vec<ParseDiagnostic>) -> ExternalSessionSummary {
    let provider = Provider::Kiro;
    let mut summary = empty_summary(provider, path.to_path_buf());
    let raw = fs::read_to_string(path);
    match raw {
        Ok(raw) => match serde_json::from_str::<Value>(&raw) {
            Ok(value) => {
                summary.session_id = value["session_id"].as_str().unwrap_or_default().to_string();
                summary.project_path = value["cwd"].as_str().unwrap_or_default().to_string();
                summary.created_at = value["created_at"].as_str().unwrap_or_default().to_string();
                summary.updated_at = value["updated_at"].as_str().unwrap_or_default().to_string();
                summary.title = value["title"].as_str().unwrap_or_default().to_string();
            }
            Err(error) => diagnostics.push(diagnostic(
                provider,
                path,
                None,
                "metadata",
                error.to_string(),
            )),
        },
        Err(error) => diagnostics.push(diagnostic(
            provider,
            path,
            None,
            "metadata",
            error.to_string(),
        )),
    }

    let jsonl_path = path.with_extension("jsonl");
    if jsonl_path.exists() {
        summary.source_path = jsonl_path.to_string_lossy().to_string();
        enrich_from_jsonl(
            provider,
            &jsonl_path,
            &mut summary,
            diagnostics,
            SCAN_TITLE_LINE_LIMIT,
        );
    }

    if summary.session_id.is_empty() {
        summary.session_id = path
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string();
    }
    finalize_summary(summary)
}

fn summarize_jsonl(
    provider: Provider,
    path: &Path,
    diagnostics: &mut Vec<ParseDiagnostic>,
) -> ExternalSessionSummary {
    let mut summary = empty_summary(provider, path.to_path_buf());
    summary.session_id = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_string();
    enrich_from_jsonl(
        provider,
        path,
        &mut summary,
        diagnostics,
        SCAN_TITLE_LINE_LIMIT,
    );
    finalize_summary(summary)
}

fn empty_summary(provider: Provider, source_path: PathBuf) -> ExternalSessionSummary {
    ExternalSessionSummary {
        provider: provider.id().to_string(),
        provider_name: provider.display_name().to_string(),
        session_id: String::new(),
        title: String::new(),
        project_path: String::new(),
        source_path: source_path.to_string_lossy().to_string(),
        created_at: String::new(),
        updated_at: String::new(),
        modified_at_epoch: modified_at_epoch(&source_path),
        message_count: 0,
        has_tool_activity: false,
        parse_status: "ok".to_string(),
        parse_errors: Vec::new(),
        parent_session_id: None,
        search_snippet: None,
        search_snippets: Vec::new(),
        match_count: 0,
    }
}

fn enrich_from_jsonl(
    provider: Provider,
    path: &Path,
    summary: &mut ExternalSessionSummary,
    diagnostics: &mut Vec<ParseDiagnostic>,
    line_limit: usize,
) {
    let Ok(file) = fs::File::open(path) else {
        diagnostics.push(diagnostic(
            provider,
            path,
            None,
            "open",
            "source file could not be opened",
        ));
        return;
    };

    for (index, line) in BufReader::new(file).lines().enumerate() {
        if index >= line_limit {
            break;
        }
        let line_number = index + 1;
        let Ok(raw) = line else {
            diagnostics.push(diagnostic(
                provider,
                path,
                Some(line_number),
                "read",
                "line could not be read",
            ));
            continue;
        };
        if raw.trim().is_empty() {
            continue;
        }
        let value: Value = match serde_json::from_str(&raw) {
            Ok(value) => value,
            Err(error) => {
                diagnostics.push(diagnostic(
                    provider,
                    path,
                    Some(line_number),
                    "jsonl",
                    error.to_string(),
                ));
                continue;
            }
        };

        if let Some(timestamp) = timestamp_for(provider, &value) {
            if summary.created_at.is_empty() {
                summary.created_at = timestamp.clone();
            }
            summary.updated_at = timestamp;
        }

        match provider {
            Provider::Codex => enrich_codex(summary, &value),
            Provider::Claude => enrich_claude(summary, &value),
            Provider::Kiro => enrich_kiro(summary, &value),
            Provider::OpenCode => {}
            Provider::Pi => enrich_pi(summary, &value),
        }
    }
}

fn enrich_codex(summary: &mut ExternalSessionSummary, value: &Value) {
    if value["type"].as_str() == Some("session_meta") {
        let payload = &value["payload"];
        if let Some(id) = payload["id"].as_str() {
            summary.session_id = id.to_string();
        }
        if let Some(cwd) = payload["cwd"].as_str() {
            summary.project_path = cwd.to_string();
        }
    }

    if let Some(entry) = transcript_entry(Provider::Codex, value) {
        summary.message_count += 1;
        if summary.title.is_empty() && entry.role == "user" && !is_bootstrap_text(&entry.text) {
            summary.title = title_from_text(&entry.text);
        }
        if entry.role == "tool" {
            summary.has_tool_activity = true;
        }
    }
}

fn enrich_claude(summary: &mut ExternalSessionSummary, value: &Value) {
    if let Some(session_id) = value["sessionId"].as_str() {
        summary.session_id = session_id.to_string();
    }
    if let Some(cwd) = value["cwd"].as_str() {
        summary.project_path = cwd.to_string();
    }
    if let Some(parent_uuid) = value["parentUuid"].as_str() {
        if !parent_uuid.is_empty() {
            summary.parent_session_id = Some(parent_uuid.to_string());
        }
    }
    if value["type"].as_str() == Some("ai-title") {
        if let Some(title) = first_text(value) {
            summary.title = title_from_text(&title);
        }
    }

    if let Some(entry) = transcript_entry(Provider::Claude, value) {
        summary.message_count += 1;
        if summary.title.is_empty() && entry.role == "user" && !is_bootstrap_text(&entry.text) {
            summary.title = title_from_text(&entry.text);
        }
        if entry.role == "tool" {
            summary.has_tool_activity = true;
        }
    }
}

fn enrich_kiro(summary: &mut ExternalSessionSummary, value: &Value) {
    if let Some(entry) = transcript_entry(Provider::Kiro, value) {
        summary.message_count += 1;
        if summary.title.is_empty() && entry.role == "user" && !is_bootstrap_text(&entry.text) {
            summary.title = title_from_text(&entry.text);
        }
        if entry.role == "tool" {
            summary.has_tool_activity = true;
        }
    }
}

fn finalize_summary(mut summary: ExternalSessionSummary) -> ExternalSessionSummary {
    if summary.title.trim().is_empty() {
        summary.title = if !summary.project_path.is_empty() {
            format!(
                "{} session",
                Path::new(&summary.project_path)
                    .file_name()
                    .and_then(|v| v.to_str())
                    .unwrap_or("External")
            )
        } else {
            "External session".to_string()
        };
    }
    if summary.updated_at.is_empty() {
        summary.updated_at = summary.created_at.clone();
    }
    summary.parse_status = parse_status(&summary.parse_errors);
    summary
}

fn transcript_entry(provider: Provider, value: &Value) -> Option<TranscriptEntry> {
    match provider {
        Provider::Codex => codex_entry(value),
        Provider::Claude => claude_entry(value),
        Provider::Kiro => kiro_entry(value),
        Provider::OpenCode => None,
        Provider::Pi => pi_entry(value),
    }
}

fn codex_entry(value: &Value) -> Option<TranscriptEntry> {
    let timestamp = value["timestamp"].as_str().unwrap_or_default().to_string();
    let payload = &value["payload"];
    let payload_type = payload["type"].as_str().unwrap_or_default();
    let role = payload["role"].as_str().unwrap_or(payload_type);
    let text = first_text(payload)?;
    let role = match role {
        "user" => "user",
        "assistant" => "assistant",
        "developer" | "system" => "system",
        "tool_call" | "function_call" | "tool_result" => "tool",
        _ if payload_type.contains("tool") => "tool",
        _ => return None,
    };
    Some(TranscriptEntry {
        role: role.to_string(),
        timestamp,
        text,
        metadata: compact_metadata(value),
    })
}

fn claude_entry(value: &Value) -> Option<TranscriptEntry> {
    let timestamp = value["timestamp"].as_str().unwrap_or_default().to_string();
    let event_type = value["type"].as_str().unwrap_or_default();
    let message = &value["message"];
    let role = message["role"].as_str().unwrap_or(event_type);
    let text = first_text(message).or_else(|| first_text(value))?;
    let role = match role {
        "user" => "user",
        "assistant" => "assistant",
        "system" => "system",
        "tool" | "tool_result" | "tool_use" => "tool",
        _ if event_type.contains("tool") => "tool",
        _ if event_type == "queue-operation" => return None,
        _ => role,
    };
    Some(TranscriptEntry {
        role: role.to_string(),
        timestamp,
        text,
        metadata: compact_metadata(value),
    })
}

fn kiro_entry(value: &Value) -> Option<TranscriptEntry> {
    let kind = value["kind"].as_str().unwrap_or_default();
    let data = &value["data"];
    let text = first_text(data)?;
    let role = match kind {
        "Prompt" => "user",
        "AssistantMessage" => "assistant",
        "ToolResults" => "tool",
        _ if kind.contains("Tool") => "tool",
        _ => return None,
    };
    Some(TranscriptEntry {
        role: role.to_string(),
        timestamp: String::new(),
        text,
        metadata: compact_metadata(value),
    })
}

fn timestamp_for(provider: Provider, value: &Value) -> Option<String> {
    match provider {
        Provider::Codex => value["timestamp"].as_str().map(str::to_string),
        Provider::Claude => value["timestamp"].as_str().map(str::to_string),
        Provider::Kiro => None,
        Provider::OpenCode => None,
        Provider::Pi => value["timestamp"].as_str().map(str::to_string),
    }
}

fn first_text(value: &Value) -> Option<String> {
    match value {
        Value::String(text) => non_empty(text),
        Value::Array(items) => {
            let text = items
                .iter()
                .filter_map(first_text)
                .collect::<Vec<_>>()
                .join("\n");
            non_empty(&text)
        }
        Value::Object(map) => {
            for key in ["text", "data", "content", "message", "result"] {
                if let Some(found) = map.get(key).and_then(first_text) {
                    return Some(found);
                }
            }
            None
        }
        _ => None,
    }
}

fn non_empty(text: &str) -> Option<String> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn title_from_text(text: &str) -> String {
    let normalized = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut title = normalized.chars().take(80).collect::<String>();
    if normalized.chars().count() > 80 {
        title.push('…');
    }
    title
}

fn is_bootstrap_text(text: &str) -> bool {
    let trimmed = text.trim_start();
    trimmed.starts_with("# AGENTS.md instructions")
        || trimmed.starts_with("<environment_context>")
        || trimmed.starts_with("<permissions instructions>")
        || trimmed.starts_with("Knowledge cutoff:")
}

fn compact_metadata(value: &Value) -> Value {
    let mut metadata = serde_json::Map::new();
    for key in [
        "type",
        "kind",
        "sessionId",
        "uuid",
        "parentUuid",
        "cwd",
        "timestamp",
    ] {
        if let Some(found) = value.get(key) {
            metadata.insert(key.to_string(), found.clone());
        }
    }
    Value::Object(metadata)
}

struct BodySearchMatch {
    count: usize,
    snippets: Vec<String>,
}

fn find_body_matches(
    session: &ExternalSessionSummary,
    needle: &str,
) -> Result<Option<BodySearchMatch>, ParseDiagnostic> {
    // OpenCode has no session file to grep; title/directory matching (handled by
    // the caller's haystack) is the search surface for it.
    if session.provider == Provider::OpenCode.id() {
        return Ok(None);
    }
    let path = PathBuf::from(&session.source_path);
    let provider = provider_from_id(&session.provider).unwrap_or(Provider::Codex);
    let file = fs::File::open(&path)
        .map_err(|error| diagnostic(provider, &path, None, "search.open", error.to_string()))?;
    let mut count = 0;
    let mut snippets = Vec::new();
    for (index, line) in BufReader::new(file).lines().enumerate() {
        if index >= SEARCH_LINE_LIMIT {
            break;
        }
        let raw = line.map_err(|error| {
            diagnostic(
                provider,
                &path,
                Some(index + 1),
                "search.read",
                error.to_string(),
            )
        })?;
        let value: Value = serde_json::from_str(&raw).map_err(|error| {
            diagnostic(
                provider,
                &path,
                Some(index + 1),
                "search.jsonl",
                error.to_string(),
            )
        })?;
        if let Some(entry) = transcript_entry(provider, &value) {
            let text = entry.text;
            let lower = text.to_lowercase();
            let entry_count = lower.match_indices(needle).count();
            if entry_count > 0 {
                count += entry_count;
                if snippets.len() < 3 {
                    let snippet = snippet_around(&text, needle);
                    if !snippets.contains(&snippet) {
                        snippets.push(snippet);
                    }
                }
            }
        }
    }
    if count == 0 {
        Ok(None)
    } else {
        Ok(Some(BodySearchMatch { count, snippets }))
    }
}

fn provider_from_id(id: &str) -> Option<Provider> {
    match id {
        "codex" => Some(Provider::Codex),
        "claude" => Some(Provider::Claude),
        "kiro" => Some(Provider::Kiro),
        "opencode" => Some(Provider::OpenCode),
        "pi" => Some(Provider::Pi),
        _ => None,
    }
}

fn snippet_around(text: &str, needle: &str) -> String {
    let lower = text.to_lowercase();
    let Some(byte_index) = lower.find(needle) else {
        return title_from_text(text);
    };
    let start = text[..byte_index]
        .char_indices()
        .rev()
        .nth(48)
        .map(|(i, _)| i)
        .unwrap_or(0);
    let end = text[byte_index..]
        .char_indices()
        .nth(needle.chars().count() + 96)
        .map(|(i, _)| byte_index + i)
        .unwrap_or(text.len());
    let mut snippet = text[start..end]
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    if start > 0 {
        snippet.insert_str(0, "…");
    }
    if end < text.len() {
        snippet.push('…');
    }
    snippet
}

fn modified_at_epoch(path: &Path) -> u64 {
    fs::metadata(path)
        .and_then(|metadata| metadata.modified())
        .ok()
        .and_then(|modified| modified.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_secs())
        .unwrap_or_default()
}

fn parse_status(errors: &[ParseDiagnostic]) -> String {
    if errors.is_empty() {
        "ok".to_string()
    } else {
        "warning".to_string()
    }
}

fn diagnostic(
    provider: Provider,
    source_path: &Path,
    line: Option<usize>,
    context: impl Into<String>,
    message: impl Into<String>,
) -> ParseDiagnostic {
    ParseDiagnostic {
        provider: provider.id().to_string(),
        source_path: source_path.to_string_lossy().to_string(),
        parser: "crispyvibes-external-sessions-helper/0.1.0".to_string(),
        line,
        context: context.into(),
        message: message.into(),
    }
}

#[cfg(any(target_os = "macos", target_os = "ios", target_os = "freebsd"))]
fn apply_process_name() {
    let Ok(name) = CString::new(PROCESS_NAME) else {
        return;
    };
    unsafe { libc::setprogname(name.as_ptr()) };
}

#[cfg(target_os = "linux")]
fn apply_process_name() {
    let truncated: String = PROCESS_NAME.chars().take(15).collect();
    let Ok(name) = CString::new(truncated) else {
        return;
    };
    unsafe { libc::prctl(libc::PR_SET_NAME, name.as_ptr() as libc::c_ulong, 0, 0, 0) };
}

#[cfg(not(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "freebsd",
    target_os = "linux"
)))]
fn apply_process_name() {}

// ---- Pi support (JSONL) --------------------------------------------------
//
// Pi stores sessions as `~/.pi/agent/sessions/<encoded-cwd>/<ts>_<uuid>.jsonl`.
// The first line is `{"type":"session","id":…,"cwd":…,"timestamp":…}`; message
// lines are `{"type":"message","message":{"role":…,"content":[{"text":…}]}}`.
// Resume is `pi --session <id>` (built on the Swift side).

fn enrich_pi(summary: &mut ExternalSessionSummary, value: &Value) {
    if value["type"].as_str() == Some("session") {
        if let Some(id) = value["id"].as_str() {
            summary.session_id = id.to_string();
        }
        if let Some(cwd) = value["cwd"].as_str() {
            summary.project_path = cwd.to_string();
        }
        if let Some(ts) = value["timestamp"].as_str() {
            if summary.created_at.is_empty() {
                summary.created_at = ts.to_string();
            }
            summary.updated_at = ts.to_string();
        }
    }

    if let Some(entry) = transcript_entry(Provider::Pi, value) {
        summary.message_count += 1;
        if summary.title.is_empty() && entry.role == "user" && !is_bootstrap_text(&entry.text) {
            summary.title = title_from_text(&entry.text);
        }
        if entry.role == "tool" {
            summary.has_tool_activity = true;
        }
        if !entry.timestamp.is_empty() {
            summary.updated_at = entry.timestamp;
        }
    }
}

fn pi_entry(value: &Value) -> Option<TranscriptEntry> {
    if value["type"].as_str() != Some("message") {
        return None;
    }
    let message = &value["message"];
    let role = message["role"].as_str().unwrap_or_default();
    let text = first_text(message)?;
    let role = match role {
        "user" => "user",
        "assistant" => "assistant",
        "system" => "system",
        "tool" | "tool_result" | "tool_use" => "tool",
        _ => return None,
    };
    let timestamp = value["timestamp"].as_str().unwrap_or_default().to_string();
    Some(TranscriptEntry {
        role: role.to_string(),
        timestamp,
        text,
        metadata: compact_metadata(value),
    })
}

// ---- OpenCode (SQLite) support -------------------------------------------
//
// Unlike the file-based agents, OpenCode stores every session in one SQLite DB
// (`~/.local/share/opencode/opencode.db`, tables `session` / `message` / `part`).
// We snapshot-copy the (possibly live/WAL) DB and read it read-only, mirroring
// how cmux reads it. Resume is `opencode --session <id>` (built on the Swift side).

fn opencode_db_path() -> Option<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from)?;
    Some(home.join(".local/share/opencode/opencode.db"))
}

/// Copy the DB (plus `-wal`/`-shm` sidecars) to a temp dir and open read-only,
/// so a live OpenCode process can't lock us out or hand us a half-written page.
fn with_opencode_readonly<T>(
    db_path: &Path,
    body: impl FnOnce(&rusqlite::Connection) -> rusqlite::Result<T>,
) -> Result<T> {
    let unique = format!(
        "crispyvibes-opencode-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    );
    let tmp_dir = std::env::temp_dir().join(unique);
    fs::create_dir_all(&tmp_dir).context("create opencode snapshot dir")?;
    let snapshot = tmp_dir.join("opencode.db");
    fs::copy(db_path, &snapshot).context("copy opencode.db")?;
    for sidecar in ["-wal", "-shm"] {
        let src = PathBuf::from(format!("{}{}", db_path.to_string_lossy(), sidecar));
        if src.exists() {
            let dst = PathBuf::from(format!("{}{}", snapshot.to_string_lossy(), sidecar));
            let _ = fs::copy(&src, &dst);
        }
    }
    let result = (|| -> rusqlite::Result<T> {
        let conn = rusqlite::Connection::open_with_flags(
            &snapshot,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
        )?;
        body(&conn)
    })();
    let _ = fs::remove_dir_all(&tmp_dir);
    result.map_err(|error| anyhow::anyhow!(error.to_string()))
}

fn discover_opencode(diagnostics: &mut Vec<ParseDiagnostic>) -> Vec<ExternalSessionSummary> {
    let Some(db_path) = opencode_db_path() else {
        return Vec::new();
    };
    if !db_path.exists() {
        return Vec::new();
    }
    let outcome = with_opencode_readonly(&db_path, |conn| {
        let mut stmt = conn.prepare(
            "SELECT s.id, s.title, s.directory, s.time_created, s.time_updated,
                    (SELECT COUNT(*) FROM message WHERE session_id = s.id) AS msg_count
             FROM session s
             ORDER BY s.time_updated DESC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(opencode_summary(
                row.get::<_, String>(0)?,
                row.get::<_, String>(1).unwrap_or_default(),
                row.get::<_, String>(2).unwrap_or_default(),
                row.get::<_, i64>(3).unwrap_or(0),
                row.get::<_, i64>(4).unwrap_or(0),
                row.get::<_, i64>(5).unwrap_or(0) as usize,
            ))
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    });
    match outcome {
        Ok(sessions) => sessions,
        Err(error) => {
            diagnostics.push(diagnostic(
                Provider::OpenCode,
                &db_path,
                None,
                "sqlite",
                error.to_string(),
            ));
            Vec::new()
        }
    }
}

fn opencode_summary(
    id: String,
    title: String,
    directory: String,
    created_ms: i64,
    updated_ms: i64,
    message_count: usize,
) -> ExternalSessionSummary {
    let epoch_secs = if updated_ms > 0 {
        (updated_ms / 1000) as u64
    } else {
        (created_ms / 1000).max(0) as u64
    };
    ExternalSessionSummary {
        provider: Provider::OpenCode.id().to_string(),
        provider_name: Provider::OpenCode.display_name().to_string(),
        session_id: id.clone(),
        title: if title.trim().is_empty() {
            "Untitled session".to_string()
        } else {
            title
        },
        project_path: directory,
        // OpenCode has no per-session file; the session id is the stable handle
        // used by `load` and the `opencode --session <id>` resume command.
        source_path: id,
        created_at: String::new(),
        updated_at: String::new(),
        modified_at_epoch: epoch_secs,
        message_count,
        has_tool_activity: false,
        parse_status: "ok".to_string(),
        parse_errors: Vec::new(),
        parent_session_id: None,
        search_snippet: None,
        search_snippets: Vec::new(),
        match_count: 0,
    }
}

fn load_opencode(session_id: &str) -> TranscriptResponse {
    let mut parse_errors = Vec::new();
    let Some(db_path) = opencode_db_path() else {
        return empty_opencode_transcript(session_id);
    };
    let outcome = with_opencode_readonly(&db_path, |conn| {
        let summary = conn.query_row(
            "SELECT s.id, s.title, s.directory, s.time_created, s.time_updated,
                    (SELECT COUNT(*) FROM message WHERE session_id = s.id)
             FROM session s WHERE s.id = ?1",
            [session_id],
            |row| {
                Ok(opencode_summary(
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1).unwrap_or_default(),
                    row.get::<_, String>(2).unwrap_or_default(),
                    row.get::<_, i64>(3).unwrap_or(0),
                    row.get::<_, i64>(4).unwrap_or(0),
                    row.get::<_, i64>(5).unwrap_or(0) as usize,
                ))
            },
        )?;

        let mut stmt = conn.prepare(
            "SELECT m.data,
                    (SELECT GROUP_CONCAT(p.data, char(10)) FROM part p WHERE p.message_id = m.id),
                    m.time_created
             FROM message m WHERE m.session_id = ?1
             ORDER BY m.time_created ASC",
        )?;
        let rows = stmt.query_map([session_id], |row| {
            Ok((
                row.get::<_, String>(0).unwrap_or_default(),
                row.get::<_, Option<String>>(1).unwrap_or(None),
                row.get::<_, i64>(2).unwrap_or(0),
            ))
        })?;
        let mut entries = Vec::new();
        for row in rows {
            let (msg_data, parts_data, created_ms) = row?;
            let role = serde_json::from_str::<Value>(&msg_data)
                .ok()
                .and_then(|value| value["role"].as_str().map(str::to_string))
                .unwrap_or_else(|| "assistant".to_string());
            let text = opencode_parts_text(parts_data.as_deref());
            if text.trim().is_empty() {
                continue;
            }
            entries.push(TranscriptEntry {
                role,
                timestamp: created_ms.to_string(),
                text,
                metadata: Value::Null,
            });
            if entries.len() >= PREVIEW_ENTRY_LIMIT {
                break;
            }
        }
        Ok((summary, entries))
    });

    match outcome {
        Ok((session, entries)) => TranscriptResponse {
            session,
            entries,
            parse_errors,
        },
        Err(error) => {
            parse_errors.push(diagnostic(
                Provider::OpenCode,
                &db_path,
                None,
                "sqlite",
                error.to_string(),
            ));
            let mut response = empty_opencode_transcript(session_id);
            response.session.parse_status = "error".to_string();
            response.parse_errors = parse_errors;
            response
        }
    }
}

/// Extract readable text from a message's concatenated `part` JSON blobs.
/// `part.data` is compact single-line JSON, joined by newlines via GROUP_CONCAT.
fn opencode_parts_text(parts: Option<&str>) -> String {
    let Some(parts) = parts else {
        return String::new();
    };
    let mut out: Vec<String> = Vec::new();
    for blob in parts.split('\n') {
        if let Ok(value) = serde_json::from_str::<Value>(blob) {
            let kind = value["type"].as_str().unwrap_or("");
            if kind == "text" || kind == "reasoning" {
                if let Some(text) = value["text"].as_str() {
                    let trimmed = text.trim();
                    if !trimmed.is_empty() {
                        out.push(trimmed.to_string());
                    }
                }
            }
        }
    }
    out.join("\n")
}

fn empty_opencode_transcript(session_id: &str) -> TranscriptResponse {
    TranscriptResponse {
        session: opencode_summary(session_id.to_string(), String::new(), String::new(), 0, 0, 0),
        entries: Vec::new(),
        parse_errors: Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn first_text_prefers_nested_text_content() {
        let value = json!({
            "message": {
                "content": [
                    {"type": "text", "text": "hello"},
                    {"type": "text", "text": "world"}
                ]
            }
        });

        assert_eq!(first_text(&value), Some("hello\nworld".to_string()));
    }

    #[test]
    fn title_from_text_normalizes_whitespace_and_truncates() {
        let title = title_from_text("  one\n two\tthree  ");
        assert_eq!(title, "one two three");

        let long = "x".repeat(100);
        let title = title_from_text(&long);
        assert_eq!(title.chars().count(), 81);
        assert!(title.ends_with('…'));
    }

    #[test]
    fn bootstrap_text_is_not_used_as_title() {
        assert!(is_bootstrap_text("# AGENTS.md instructions for /tmp/app"));
        assert!(is_bootstrap_text(
            "<environment_context>\n  <cwd>/tmp/app</cwd>"
        ));
        assert!(!is_bootstrap_text("fix the auth bug"));
    }

    #[test]
    fn snippet_around_marks_truncated_context() {
        let text = format!("{} auth {}", "before ".repeat(80), "after ".repeat(80));
        let snippet = snippet_around(&text, "auth");

        assert!(snippet.starts_with('…'));
        assert!(snippet.ends_with('…'));
        assert!(snippet.contains("auth"));
    }
}
