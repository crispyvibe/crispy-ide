use std::collections::{HashMap, HashSet};
use std::ffi::{CString, OsStr};
use std::fs;
use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::Command as ProcessCommand;
use std::time::UNIX_EPOCH;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand, ValueEnum};
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};
use serde_json::Value;

const PROCESS_NAME: &str = "CrispyVibes (external sessions helper)";
const DEFAULT_LIMIT: usize = 500;
const SCAN_TITLE_LINE_LIMIT: usize = 400;
const SEARCH_LINE_LIMIT: usize = 8_000;
const PREVIEW_ENTRY_LIMIT: usize = 2_000;
const KIRO_V2_SOURCE: &str = "v2";
const KIRO_CLASSIC_SOURCE: &str = "classic";
const CRISPY_TITLE_REQUEST_MARKER: &str = "[Crispy internal request: thread-title generation]";
const LEGACY_CRISPY_TITLE_REQUEST_PREFIX: &str = "You write concise thread titles for coding conversations.\nReturn ONLY a JSON object with key: title.";
const LEGACY_CRISPY_TITLE_REQUEST_SINGLE_LINE_PREFIX: &str = "You write concise thread titles for coding conversations. Return ONLY a JSON object with key: title. Keep it short and specific (3-8 words). User message:";

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
        source_path: Option<String>,
        #[arg(long)]
        session_id: Option<String>,
        #[arg(long)]
        session_source: Option<String>,
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

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
struct ExternalSessionSummary {
    provider: String,
    provider_name: String,
    session_id: String,
    session_source: Option<String>,
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

#[derive(Serialize, Clone, Debug)]
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

#[derive(Serialize, Debug)]
#[serde(rename_all = "camelCase")]
struct TranscriptEntry {
    role: String,
    timestamp: String,
    text: String,
    metadata: Value,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum KiroListing {
    Envelopes(Vec<KiroListingEnvelope>),
    Envelope(KiroListingEnvelope),
}

#[derive(Deserialize)]
struct KiroListingEnvelope {
    #[serde(default)]
    complete: bool,
    #[serde(default)]
    cwd: String,
    #[serde(default)]
    sessions: Vec<KiroListingItem>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct KiroListingItem {
    #[serde(default)]
    message_count: usize,
    #[serde(default)]
    session_id: String,
    #[serde(default)]
    source: String,
    #[serde(default)]
    title: String,
    #[serde(default)]
    updated_at: String,
    #[serde(default, rename = "status")]
    _status: Option<Value>,
}

fn main() -> Result<()> {
    apply_process_name();
    let cli = Cli::parse();
    match cli.command {
        Command::Scan { provider, limit } => print_json(&scan(provider, limit))?,
        Command::Search {
            query,
            provider,
            limit,
        } => print_json(&search(&query, provider, limit))?,
        Command::Load {
            provider,
            source_path,
            session_id,
            session_source,
        } => print_json(&load(
            provider,
            source_path.map(PathBuf::from),
            session_id,
            session_source,
        ))?,
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
        sessions.append(&mut discover_provider(provider, &mut diagnostics));
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
    let classic_candidates = response
        .sessions
        .iter()
        .filter(|session| {
            session.provider == Provider::Kiro.id()
                && session.session_source.as_deref() == Some(KIRO_CLASSIC_SOURCE)
                && !session.title.to_lowercase().contains(&needle)
        })
        .cloned()
        .collect::<Vec<_>>();
    let classic_matches = match find_classic_search_matches(&classic_candidates, &needle) {
        Ok(outcome) => {
            response.diagnostics.extend(outcome.diagnostics);
            outcome.matches
        }
        Err(error) => {
            response.diagnostics.push(*error);
            HashMap::new()
        }
    };

    let mut matches = Vec::new();
    for mut session in response.sessions {
        // Paths are deliberately excluded. A title-only match also has no
        // redundant snippet; snippets are reserved for transcript matches.
        if session.title.to_lowercase().contains(&needle) {
            session.search_snippet = None;
            session.search_snippets.clear();
            session.match_count = 1;
            matches.push(session);
        } else {
            let body_match = if session.session_source.as_deref() == Some(KIRO_CLASSIC_SOURCE) {
                classic_matches.get(&session_identity(&session)).cloned()
            } else {
                match find_body_matches(&session, &needle) {
                    Ok(found) => found,
                    Err(error) => {
                        response.diagnostics.push(*error);
                        None
                    }
                }
            };
            if let Some(body_match) = body_match {
                session.search_snippet = body_match.snippets.first().cloned();
                session.search_snippets = body_match.snippets;
                session.match_count = body_match.count;
                matches.push(session);
            }
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

fn load(
    provider: Provider,
    mut source_path: Option<PathBuf>,
    session_id: Option<String>,
    session_source: Option<String>,
) -> TranscriptResponse {
    if provider == Provider::OpenCode {
        let id = session_id
            .as_deref()
            .or_else(|| source_path.as_deref().and_then(Path::to_str))
            .unwrap_or_default();
        return load_opencode(id);
    }
    if provider == Provider::Kiro {
        match session_source.as_deref() {
            Some(KIRO_CLASSIC_SOURCE) => {
                let id = session_id.as_deref().unwrap_or_default();
                let Some(db_path) = kiro_classic_db_path_runtime() else {
                    let error = diagnostic(
                        Provider::Kiro,
                        Path::new("kiro-cli"),
                        None,
                        "kiro.classic.path",
                        "Kiro classic database path could not be resolved",
                    );
                    return empty_transcript(
                        Provider::Kiro,
                        PathBuf::new(),
                        id.to_string(),
                        Some(KIRO_CLASSIC_SOURCE.to_string()),
                        vec![error],
                    );
                };
                return load_kiro_classic(id, &db_path);
            }
            Some(KIRO_V2_SOURCE) => {
                let id = session_id.as_deref().unwrap_or_default();
                let Some(root) = kiro_v2_root_runtime() else {
                    let error = diagnostic(
                        Provider::Kiro,
                        Path::new("kiro-cli"),
                        None,
                        "kiro.sourcePath",
                        "Kiro V2 session root could not be resolved",
                    );
                    return empty_transcript(
                        Provider::Kiro,
                        PathBuf::new(),
                        id.to_string(),
                        Some(KIRO_V2_SOURCE.to_string()),
                        vec![error],
                    );
                };
                match confined_kiro_v2_source_path(&root, id) {
                    Ok(path) => source_path = Some(path),
                    Err(error) => {
                        let diagnostic = diagnostic(
                            Provider::Kiro,
                            &root,
                            None,
                            "kiro.sourcePath",
                            error.to_string(),
                        );
                        return empty_transcript(
                            Provider::Kiro,
                            root,
                            id.to_string(),
                            Some(KIRO_V2_SOURCE.to_string()),
                            vec![diagnostic],
                        );
                    }
                }
            }
            None => {}
            Some(unknown) => {
                let path = source_path.unwrap_or_default();
                let error = diagnostic(
                    Provider::Kiro,
                    &path,
                    None,
                    "kiro.source",
                    format!("unsupported Kiro session source: {unknown}"),
                );
                return empty_transcript(
                    Provider::Kiro,
                    path,
                    session_id.unwrap_or_default(),
                    Some(unknown.to_string()),
                    vec![error],
                );
            }
        }
    }

    let Some(source_path) = source_path.or_else(|| {
        if provider == Provider::Kiro {
            let id = session_id.as_deref()?;
            let root = kiro_v2_root_runtime()?;
            confined_kiro_v2_source_path(&root, id).ok()
        } else {
            None
        }
    }) else {
        let error = diagnostic(
            provider,
            Path::new(""),
            None,
            "load.arguments",
            "source path is required",
        );
        return empty_transcript(
            provider,
            PathBuf::new(),
            session_id.unwrap_or_default(),
            session_source,
            vec![error],
        );
    };

    let mut diagnostics = Vec::new();
    let summary_path = if provider == Provider::Kiro
        && source_path.extension().and_then(OsStr::to_str) == Some("jsonl")
    {
        let sidecar_path = source_path.with_extension("json");
        let sidecar_is_regular = fs::symlink_metadata(&sidecar_path)
            .map(|metadata| metadata.is_file() && !metadata.file_type().is_symlink())
            .unwrap_or(false);
        if sidecar_is_regular {
            sidecar_path
        } else {
            source_path.clone()
        }
    } else {
        source_path.clone()
    };
    let mut summary = summarize_session(provider, &summary_path, &mut diagnostics);
    summary.source_path = source_path.to_string_lossy().to_string();
    if provider == Provider::Kiro {
        summary.session_source = Some(KIRO_V2_SOURCE.to_string());
    }
    if let Some(session_id) = session_id.filter(|id| !id.is_empty()) {
        summary.session_id = session_id;
    } else if summary.session_id.is_empty() {
        summary.session_id = source_path
            .file_stem()
            .and_then(OsStr::to_str)
            .unwrap_or_default()
            .to_string();
    }

    let mut entries = Vec::new();
    let mut parse_errors = diagnostics;
    match open_session_file(provider, &source_path) {
        Ok(file) => {
            for (index, line) in BufReader::new(file).lines().enumerate() {
                if entries.len() >= PREVIEW_ENTRY_LIMIT {
                    break;
                }
                let line_number = index + 1;
                match line {
                    Ok(raw) if raw.trim().is_empty() => {}
                    Ok(raw) => match serde_json::from_str::<Value>(&raw) {
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
                    },
                    Err(error) => parse_errors.push(diagnostic(
                        provider,
                        &source_path,
                        Some(line_number),
                        "read",
                        error.to_string(),
                    )),
                }
            }
        }
        Err(error) => parse_errors.push(diagnostic(
            provider,
            &source_path,
            None,
            "open",
            error.to_string(),
        )),
    }

    summary.parse_status = parse_status(&parse_errors);
    summary.parse_errors = parse_errors.clone();
    TranscriptResponse {
        session: summary,
        entries,
        parse_errors,
    }
}

fn empty_transcript(
    provider: Provider,
    source_path: PathBuf,
    session_id: String,
    session_source: Option<String>,
    parse_errors: Vec<ParseDiagnostic>,
) -> TranscriptResponse {
    let mut session = empty_summary(provider, source_path);
    session.session_id = session_id;
    session.session_source = session_source;
    session.parse_status = parse_status(&parse_errors);
    session.parse_errors = parse_errors.clone();
    TranscriptResponse {
        session: finalize_summary(session),
        entries: Vec::new(),
        parse_errors,
    }
}

fn providers(filter: Option<Provider>) -> Vec<Provider> {
    match filter {
        Some(provider) => vec![provider],
        None => vec![
            Provider::Codex,
            Provider::Claude,
            Provider::Kiro,
            Provider::OpenCode,
            Provider::Pi,
        ],
    }
}

fn discover_provider(
    provider: Provider,
    diagnostics: &mut Vec<ParseDiagnostic>,
) -> Vec<ExternalSessionSummary> {
    if provider == Provider::Kiro {
        return discover_kiro(diagnostics);
    }
    if provider == Provider::OpenCode {
        return discover_opencode(diagnostics);
    }

    let Some(root) = provider_root(provider) else {
        return Vec::new();
    };
    if !root.exists() {
        return Vec::new();
    }
    collect_files(&root, "jsonl")
        .into_iter()
        .map(|path| summarize_session(provider, &path, diagnostics))
        .collect()
}

fn discover_kiro(diagnostics: &mut Vec<ParseDiagnostic>) -> Vec<ExternalSessionSummary> {
    let v2_root = kiro_v2_root_runtime();
    let classic_db = kiro_classic_db_path_runtime();
    discover_kiro_from_listing(
        run_kiro_session_listing(),
        v2_root.as_deref(),
        classic_db.as_deref(),
        diagnostics,
    )
}

fn discover_kiro_from_listing(
    listing: Result<String>,
    v2_root: Option<&Path>,
    classic_db: Option<&Path>,
    diagnostics: &mut Vec<ParseDiagnostic>,
) -> Vec<ExternalSessionSummary> {
    let sessions = match listing {
        Ok(raw) => match parse_kiro_listing(&raw, v2_root, classic_db, diagnostics) {
            Ok(sessions) => sessions,
            Err(error) => {
                diagnostics.push(diagnostic(
                    Provider::Kiro,
                    Path::new("kiro-cli"),
                    None,
                    "kiro.metadata.decode",
                    error.to_string(),
                ));
                discover_kiro_v2_fallback(v2_root, diagnostics)
            }
        },
        Err(error) => {
            diagnostics.push(diagnostic(
                Provider::Kiro,
                Path::new("kiro-cli"),
                None,
                "kiro.metadata.command",
                error.to_string(),
            ));
            discover_kiro_v2_fallback(v2_root, diagnostics)
        }
    };
    exclude_crispy_internal_kiro_sessions(sessions, classic_db, diagnostics)
}

fn run_kiro_session_listing() -> Result<String> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let executable = resolve_kiro_cli(std::env::var_os("PATH").as_deref(), home.as_deref())
        .context("kiro-cli executable not found")?;
    let output = ProcessCommand::new(&executable)
        .args(["chat", "--list-sessions", "--all-cwds", "--format", "json"])
        .output()
        .with_context(|| format!("run {}", executable.display()))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!(
            "kiro-cli session listing failed with {}: {}",
            output.status,
            stderr.trim().chars().take(500).collect::<String>()
        );
    }
    String::from_utf8(output.stdout).context("kiro-cli listing was not UTF-8")
}

fn resolve_kiro_cli(path: Option<&OsStr>, home: Option<&Path>) -> Option<PathBuf> {
    use std::os::unix::fs::PermissionsExt;

    let mut directories = path
        .map(std::env::split_paths)
        .into_iter()
        .flatten()
        .collect::<Vec<_>>();
    if let Some(home) = home {
        directories.push(home.join(".local/bin"));
        directories.push(home.join("bin"));
    }
    directories.extend([
        PathBuf::from("/opt/homebrew/bin"),
        PathBuf::from("/usr/local/bin"),
        PathBuf::from("/usr/bin"),
        PathBuf::from("/bin"),
    ]);

    let mut seen = HashSet::new();
    for directory in directories {
        let directory = if directory.is_absolute() {
            directory
        } else {
            let Ok(current) = std::env::current_dir() else {
                continue;
            };
            current.join(directory)
        };
        let candidate = directory.join("kiro-cli");
        let Ok(metadata) = fs::metadata(&candidate) else {
            continue;
        };
        if !metadata.is_file() || metadata.permissions().mode() & 0o111 == 0 {
            continue;
        }
        let absolute = fs::canonicalize(&candidate).unwrap_or(candidate);
        if seen.insert(absolute.clone()) {
            return Some(absolute);
        }
    }
    None
}

fn confined_kiro_v2_source_path(root: &Path, session_id: &str) -> Result<PathBuf> {
    use std::path::Component;

    let mut components = Path::new(session_id).components();
    let valid_component = matches!(
        (components.next(), components.next()),
        (Some(Component::Normal(_)), None)
    );
    if !valid_component {
        anyhow::bail!("invalid Kiro V2 session id for filesystem lookup");
    }

    let candidate = root.join(format!("{session_id}.jsonl"));
    if !candidate.exists() {
        return Ok(candidate);
    }

    let metadata = fs::symlink_metadata(&candidate).context("inspect Kiro V2 transcript")?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        anyhow::bail!("Kiro V2 transcript is not a regular file");
    }

    let canonical_root = fs::canonicalize(root).context("resolve Kiro V2 session root")?;
    let canonical_candidate = fs::canonicalize(&candidate).context("resolve Kiro V2 transcript")?;
    if !canonical_candidate.starts_with(&canonical_root) {
        anyhow::bail!("Kiro V2 transcript resolves outside the configured session root");
    }
    Ok(canonical_candidate)
}

fn open_session_file(provider: Provider, path: &Path) -> std::io::Result<fs::File> {
    if provider != Provider::Kiro {
        return fs::File::open(path);
    }

    use std::os::unix::fs::OpenOptionsExt;
    fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)
}

fn parse_kiro_listing(
    raw: &str,
    v2_root: Option<&Path>,
    classic_db: Option<&Path>,
    diagnostics: &mut Vec<ParseDiagnostic>,
) -> Result<Vec<ExternalSessionSummary>> {
    let listing: KiroListing = serde_json::from_str(raw).context("parse Kiro session listing")?;
    let envelopes = match listing {
        KiroListing::Envelopes(envelopes) => envelopes,
        KiroListing::Envelope(envelope) => vec![envelope],
    };
    let mut sessions = Vec::new();
    let mut identities = HashSet::new();
    let mut unknown_sources = HashSet::new();
    let mut incomplete = false;

    for envelope in envelopes {
        incomplete |= !envelope.complete;
        for item in envelope.sessions {
            if item.session_id.is_empty() {
                continue;
            }
            let source_path = match item.source.as_str() {
                KIRO_V2_SOURCE => {
                    let Some(root) = v2_root else {
                        diagnostics.push(diagnostic(
                            Provider::Kiro,
                            Path::new("kiro-cli"),
                            None,
                            "kiro.sourcePath",
                            "Kiro V2 session root could not be resolved",
                        ));
                        continue;
                    };
                    match confined_kiro_v2_source_path(root, &item.session_id) {
                        Ok(path) => path,
                        Err(error) => {
                            diagnostics.push(diagnostic(
                                Provider::Kiro,
                                root,
                                None,
                                "kiro.sourcePath",
                                error.to_string(),
                            ));
                            continue;
                        }
                    }
                }
                KIRO_CLASSIC_SOURCE => classic_db.map(Path::to_path_buf).unwrap_or_default(),
                unknown => {
                    unknown_sources.insert(unknown.to_string());
                    continue;
                }
            };
            let identity = format!("{}:{}", item.source, item.session_id);
            if !identities.insert(identity) {
                continue;
            }
            sessions.push(ExternalSessionSummary {
                provider: Provider::Kiro.id().to_string(),
                provider_name: Provider::Kiro.display_name().to_string(),
                session_id: item.session_id,
                session_source: Some(item.source),
                title: if item.title.trim().is_empty() {
                    "Kiro session".to_string()
                } else {
                    item.title
                },
                project_path: envelope.cwd.clone(),
                source_path: source_path.to_string_lossy().to_string(),
                created_at: String::new(),
                updated_at: item.updated_at.clone(),
                modified_at_epoch: epoch_from_timestamp(&item.updated_at)
                    .unwrap_or_else(|| modified_at_epoch(&source_path)),
                message_count: item.message_count,
                has_tool_activity: false,
                parse_status: "ok".to_string(),
                parse_errors: Vec::new(),
                parent_session_id: None,
                search_snippet: None,
                search_snippets: Vec::new(),
                match_count: 0,
            });
        }
    }

    if !unknown_sources.is_empty() {
        let mut names = unknown_sources.into_iter().collect::<Vec<_>>();
        names.sort();
        diagnostics.push(diagnostic(
            Provider::Kiro,
            Path::new("kiro-cli"),
            None,
            "kiro.source",
            format!(
                "skipped unsupported Kiro session source(s): {}",
                names.join(", ")
            ),
        ));
    }
    if incomplete {
        diagnostics.push(diagnostic(
            Provider::Kiro,
            Path::new("kiro-cli"),
            None,
            "kiro.metadata.complete",
            "Kiro CLI reported an incomplete session listing",
        ));
    }
    Ok(sessions)
}

fn discover_kiro_v2_fallback(
    root: Option<&Path>,
    diagnostics: &mut Vec<ParseDiagnostic>,
) -> Vec<ExternalSessionSummary> {
    let Some(root) = root.filter(|root| root.exists()) else {
        return Vec::new();
    };
    collect_files(root, "json")
        .into_iter()
        .map(|path| summarize_kiro(&path, diagnostics))
        .collect()
}

fn exclude_crispy_internal_kiro_sessions(
    sessions: Vec<ExternalSessionSummary>,
    classic_db: Option<&Path>,
    diagnostics: &mut Vec<ParseDiagnostic>,
) -> Vec<ExternalSessionSummary> {
    let classic_ids = sessions
        .iter()
        .filter(|session| session.session_source.as_deref() == Some(KIRO_CLASSIC_SOURCE))
        .map(|session| session.session_id.clone())
        .collect::<HashSet<_>>();
    let mut internal_classic_ids = HashSet::new();

    if !classic_ids.is_empty() {
        if let Some(db_path) = classic_db.filter(|path| path.exists()) {
            let outcome = with_sqlite_snapshot(db_path, "kiro-filter", |connection| {
                let current_pattern = format!("{CRISPY_TITLE_REQUEST_MARKER}%");
                let legacy_pattern = format!("{LEGACY_CRISPY_TITLE_REQUEST_PREFIX}%");
                let single_line_pattern =
                    format!("{LEGACY_CRISPY_TITLE_REQUEST_SINGLE_LINE_PREFIX}%");
                let mut statement = connection.prepare(
                    "SELECT conversation_id
                     FROM conversations_v2
                     WHERE CASE WHEN json_valid(value) THEN
                         json_array_length(value, '$.history') = 1
                         AND (
                             json_extract(value, '$.history[0].user.content.Prompt.prompt') LIKE ?1
                             OR json_extract(
                                 value,
                                 '$.history[0].user.content.Prompt.prompt'
                             ) LIKE ?3
                             OR (
                                 json_extract(value, '$.history[0].user.content.Prompt.prompt') LIKE ?2
                                 AND instr(
                                     json_extract(value, '$.history[0].user.content.Prompt.prompt'),
                                     char(10) || char(10) || 'User message:' || char(10)
                                 ) > 0
                             )
                         )
                     ELSE 0 END",
                )?;
                let rows = statement.query_map(
                    rusqlite::params![current_pattern, legacy_pattern, single_line_pattern],
                    |row| row.get::<_, String>(0),
                )?;
                let mut internal_ids = HashSet::new();
                for session_id in rows.flatten() {
                    if classic_ids.contains(&session_id) {
                        internal_ids.insert(session_id);
                    }
                }
                Ok(internal_ids)
            });
            match outcome {
                Ok(ids) => internal_classic_ids = ids,
                Err(error) => diagnostics.push(diagnostic(
                    Provider::Kiro,
                    db_path,
                    None,
                    "kiro.internalFilter",
                    error.to_string(),
                )),
            }
        }
    }

    sessions
        .into_iter()
        .filter(|session| match session.session_source.as_deref() {
            Some(KIRO_CLASSIC_SOURCE) => !internal_classic_ids.contains(&session.session_id),
            Some(KIRO_V2_SOURCE) => !is_crispy_internal_v2_session(session),
            _ => true,
        })
        .collect()
}

fn is_crispy_internal_v2_session(session: &ExternalSessionSummary) -> bool {
    let title_might_be_internal = session.title.starts_with(CRISPY_TITLE_REQUEST_MARKER)
        || session.title.starts_with("You write concise thread titles");
    if !title_might_be_internal {
        return false;
    }
    let path = Path::new(&session.source_path);
    let Ok(file) = open_session_file(Provider::Kiro, path) else {
        return false;
    };
    for line in BufReader::new(file).lines().take(SCAN_TITLE_LINE_LIMIT) {
        let Ok(raw) = line else {
            continue;
        };
        let Ok(value) = serde_json::from_str::<Value>(&raw) else {
            continue;
        };
        if value["kind"].as_str() != Some("Prompt") {
            continue;
        }
        return first_text(&value["data"])
            .as_deref()
            .is_some_and(is_crispy_title_request);
    }
    false
}

fn is_crispy_title_request(prompt: &str) -> bool {
    prompt.starts_with(CRISPY_TITLE_REQUEST_MARKER)
        || prompt.starts_with(LEGACY_CRISPY_TITLE_REQUEST_SINGLE_LINE_PREFIX)
        || (prompt.starts_with(LEGACY_CRISPY_TITLE_REQUEST_PREFIX)
            && prompt.contains("\n\nUser message:\n"))
}

fn configured_kiro_home(home: Option<&Path>, kiro_home: Option<&OsStr>) -> Option<PathBuf> {
    match kiro_home.filter(|value| !value.is_empty()) {
        Some(path) => Some(PathBuf::from(path)),
        None => home.map(|home| home.join(".kiro")),
    }
}

fn kiro_v2_root_from(home: Option<&Path>, kiro_home: Option<&OsStr>) -> Option<PathBuf> {
    configured_kiro_home(home, kiro_home).map(|root| root.join("sessions/cli"))
}

fn kiro_classic_db_path_from(
    home: Option<&Path>,
    kiro_data_dir: Option<&OsStr>,
) -> Option<PathBuf> {
    match kiro_data_dir.filter(|value| !value.is_empty()) {
        Some(path) => Some(PathBuf::from(path).join("data.sqlite3")),
        None => home.map(|home| home.join("Library/Application Support/kiro-cli/data.sqlite3")),
    }
}

fn kiro_v2_root_runtime() -> Option<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let kiro_home = std::env::var_os("KIRO_HOME");
    kiro_v2_root_from(home.as_deref(), kiro_home.as_deref())
}

fn kiro_classic_db_path_runtime() -> Option<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let data_dir = std::env::var_os("KIRO_DATA_DIR");
    kiro_classic_db_path_from(home.as_deref(), data_dir.as_deref())
}

fn provider_root(provider: Provider) -> Option<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from)?;
    Some(match provider {
        Provider::Codex => home.join(".codex/sessions"),
        Provider::Claude => home.join(".claude/projects"),
        Provider::Kiro => return kiro_v2_root_runtime(),
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
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_dir() {
            collect_files_into(&path, extension, result);
        } else if file_type.is_file() && path.extension().and_then(OsStr::to_str) == Some(extension)
        {
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
        Provider::Kiro => summarize_kiro(path, diagnostics),
        Provider::Codex | Provider::Claude | Provider::Pi => {
            summarize_jsonl(provider, path, diagnostics)
        }
        Provider::OpenCode => empty_summary(provider, path.to_path_buf()),
    }
}

fn summarize_kiro(path: &Path, diagnostics: &mut Vec<ParseDiagnostic>) -> ExternalSessionSummary {
    let provider = Provider::Kiro;
    let mut summary = empty_summary(provider, path.to_path_buf());
    summary.session_source = Some(KIRO_V2_SOURCE.to_string());
    let raw = (|| -> std::io::Result<String> {
        let mut file = open_session_file(provider, path)?;
        let mut raw = String::new();
        file.read_to_string(&mut raw)?;
        Ok(raw)
    })();
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
            .and_then(OsStr::to_str)
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
        .and_then(OsStr::to_str)
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
        session_source: None,
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
    let Ok(file) = open_session_file(provider, path) else {
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
            Provider::Pi => enrich_pi(summary, &value),
            Provider::OpenCode => {}
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
    enrich_from_entry(summary, Provider::Codex, value);
}

fn enrich_claude(summary: &mut ExternalSessionSummary, value: &Value) {
    if let Some(session_id) = value["sessionId"].as_str() {
        summary.session_id = session_id.to_string();
    }
    if let Some(cwd) = value["cwd"].as_str() {
        summary.project_path = cwd.to_string();
    }
    if let Some(parent_uuid) = value["parentUuid"].as_str().filter(|id| !id.is_empty()) {
        summary.parent_session_id = Some(parent_uuid.to_string());
    }
    if value["type"].as_str() == Some("ai-title") {
        if let Some(title) = first_text(value) {
            summary.title = title_from_text(&title);
        }
    }
    enrich_from_entry(summary, Provider::Claude, value);
}

fn enrich_kiro(summary: &mut ExternalSessionSummary, value: &Value) {
    enrich_from_entry(summary, Provider::Kiro, value);
}

fn enrich_from_entry(summary: &mut ExternalSessionSummary, provider: Provider, value: &Value) {
    if let Some(entry) = transcript_entry(provider, value) {
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
                    .and_then(OsStr::to_str)
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
        Provider::Kiro => kiro_v2_entry(value),
        Provider::Pi => pi_entry(value),
        Provider::OpenCode => None,
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

fn kiro_v2_entry(value: &Value) -> Option<TranscriptEntry> {
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
        Provider::Codex | Provider::Claude | Provider::Pi => {
            value["timestamp"].as_str().map(str::to_string)
        }
        Provider::Kiro | Provider::OpenCode => None,
    }
}

fn first_text(value: &Value) -> Option<String> {
    match value {
        Value::String(text) => non_empty(text),
        Value::Array(items) => non_empty(
            &items
                .iter()
                .filter_map(first_text)
                .collect::<Vec<_>>()
                .join("\n"),
        ),
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
    (!trimmed.is_empty()).then(|| trimmed.to_string())
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

#[derive(Clone, Debug)]
struct BodySearchMatch {
    count: usize,
    snippets: Vec<String>,
}

struct ClassicSearchOutcome {
    matches: HashMap<String, BodySearchMatch>,
    diagnostics: Vec<ParseDiagnostic>,
    #[cfg(test)]
    rows_scanned: usize,
}

fn find_body_matches(
    session: &ExternalSessionSummary,
    needle: &str,
) -> Result<Option<BodySearchMatch>, Box<ParseDiagnostic>> {
    if session.provider == Provider::OpenCode.id() {
        return Ok(None);
    }
    let path = PathBuf::from(&session.source_path);
    let provider = provider_from_id(&session.provider).unwrap_or(Provider::Codex);
    let file = open_session_file(provider, &path).map_err(|error| {
        Box::new(diagnostic(
            provider,
            &path,
            None,
            "search.open",
            error.to_string(),
        ))
    })?;
    let mut count = 0;
    let mut snippets = Vec::new();
    for (index, line) in BufReader::new(file).lines().enumerate() {
        if index >= SEARCH_LINE_LIMIT {
            break;
        }
        let raw = line.map_err(|error| {
            Box::new(diagnostic(
                provider,
                &path,
                Some(index + 1),
                "search.read",
                error.to_string(),
            ))
        })?;
        let value: Value = serde_json::from_str(&raw).map_err(|error| {
            Box::new(diagnostic(
                provider,
                &path,
                Some(index + 1),
                "search.jsonl",
                error.to_string(),
            ))
        })?;
        if let Some(entry) = transcript_entry(provider, &value) {
            accumulate_body_match(&entry.text, needle, &mut count, &mut snippets);
        }
    }
    Ok(body_search_result(count, snippets))
}

fn find_classic_search_matches(
    sessions: &[ExternalSessionSummary],
    needle: &str,
) -> Result<ClassicSearchOutcome, Box<ParseDiagnostic>> {
    let Some(db_path) = sessions
        .first()
        .map(|session| PathBuf::from(&session.source_path))
    else {
        return Ok(ClassicSearchOutcome {
            matches: HashMap::new(),
            diagnostics: Vec::new(),
            #[cfg(test)]
            rows_scanned: 0,
        });
    };
    let mut candidate_identities = HashMap::<String, Vec<String>>::new();
    for session in sessions {
        candidate_identities
            .entry(session.session_id.clone())
            .or_default()
            .push(session_identity(session));
    }
    with_sqlite_snapshot(&db_path, "kiro", |connection| {
        let mut matches = HashMap::new();
        let mut diagnostics = Vec::new();
        let mut statement =
            connection.prepare("SELECT conversation_id, value FROM conversations_v2")?;
        let rows = statement.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        #[cfg(test)]
        let mut rows_scanned = 0;
        for (row_index, row) in rows.enumerate() {
            #[cfg(test)]
            {
                rows_scanned += 1;
            }
            let (session_id, raw) = match row {
                Ok(row) => row,
                Err(error) => {
                    diagnostics.push(diagnostic(
                        Provider::Kiro,
                        &db_path,
                        Some(row_index + 1),
                        "kiro.classic.search.row",
                        error.to_string(),
                    ));
                    continue;
                }
            };
            let Some(identities) = candidate_identities.get(&session_id) else {
                continue;
            };
            let value = match serde_json::from_str::<Value>(&raw) {
                Ok(value) => value,
                Err(error) => {
                    diagnostics.push(diagnostic(
                        Provider::Kiro,
                        &db_path,
                        Some(row_index + 1),
                        "kiro.classic.search.json",
                        format!("session {session_id}: {error}"),
                    ));
                    continue;
                }
            };
            let mut count = 0;
            let mut snippets = Vec::new();
            for entry in classic_entries(&value) {
                accumulate_body_match(&entry.text, needle, &mut count, &mut snippets);
            }
            if let Some(found) = body_search_result(count, snippets) {
                for identity in identities {
                    matches.insert(identity.clone(), found.clone());
                }
            }
        }
        Ok(ClassicSearchOutcome {
            matches,
            diagnostics,
            #[cfg(test)]
            rows_scanned,
        })
    })
    .map_err(|error| {
        Box::new(diagnostic(
            Provider::Kiro,
            &db_path,
            None,
            "kiro.classic.search",
            error.to_string(),
        ))
    })
}

fn accumulate_body_match(text: &str, needle: &str, count: &mut usize, snippets: &mut Vec<String>) {
    let lower = text.to_lowercase();
    let entry_count = lower.match_indices(needle).count();
    if entry_count > 0 {
        *count += entry_count;
        if snippets.len() < 3 {
            let snippet = snippet_around(text, needle);
            if !snippets.contains(&snippet) {
                snippets.push(snippet);
            }
        }
    }
}

fn body_search_result(count: usize, snippets: Vec<String>) -> Option<BodySearchMatch> {
    (count > 0).then_some(BodySearchMatch { count, snippets })
}

fn session_identity(session: &ExternalSessionSummary) -> String {
    format!(
        "{}:{}:{}:{}",
        session.provider,
        session.session_source.as_deref().unwrap_or_default(),
        session.source_path,
        session.session_id
    )
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
        .map(|(index, _)| index)
        .unwrap_or(0);
    let end = text[byte_index..]
        .char_indices()
        .nth(needle.chars().count() + 96)
        .map(|(index, _)| byte_index + index)
        .unwrap_or(text.len());
    let mut snippet = text[start..end]
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    if start > 0 {
        snippet.insert(0, '…');
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

fn epoch_from_timestamp(value: &str) -> Option<u64> {
    if let Ok(number) = value.parse::<u64>() {
        return Some(if number > 10_000_000_000 {
            number / 1_000
        } else {
            number
        });
    }
    let bytes = value.as_bytes();
    if bytes.len() < 19 {
        return None;
    }
    let year = value.get(0..4)?.parse::<i64>().ok()?;
    let month = value.get(5..7)?.parse::<i64>().ok()?;
    let day = value.get(8..10)?.parse::<i64>().ok()?;
    let hour = value.get(11..13)?.parse::<i64>().ok()?;
    let minute = value.get(14..16)?.parse::<i64>().ok()?;
    let second = value.get(17..19)?.parse::<i64>().ok()?;
    let year_adjusted = year - i64::from(month <= 2);
    let era = year_adjusted.div_euclid(400);
    let year_of_era = year_adjusted - era * 400;
    let adjusted_month = month + if month > 2 { -3 } else { 9 };
    let day_of_year = (153 * adjusted_month + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    let days = era * 146_097 + day_of_era - 719_468;
    let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second;
    (seconds >= 0).then_some(seconds as u64)
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

fn enrich_pi(summary: &mut ExternalSessionSummary, value: &Value) {
    if value["type"].as_str() == Some("session") {
        if let Some(id) = value["id"].as_str() {
            summary.session_id = id.to_string();
        }
        if let Some(cwd) = value["cwd"].as_str() {
            summary.project_path = cwd.to_string();
        }
        if let Some(timestamp) = value["timestamp"].as_str() {
            if summary.created_at.is_empty() {
                summary.created_at = timestamp.to_string();
            }
            summary.updated_at = timestamp.to_string();
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
    let role = match message["role"].as_str().unwrap_or_default() {
        "user" => "user",
        "assistant" => "assistant",
        "system" => "system",
        "tool" | "tool_result" | "tool_use" => "tool",
        _ => return None,
    };
    Some(TranscriptEntry {
        role: role.to_string(),
        timestamp: value["timestamp"].as_str().unwrap_or_default().to_string(),
        text: first_text(message)?,
        metadata: compact_metadata(value),
    })
}

fn opencode_db_path() -> Option<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from)?;
    Some(home.join(".local/share/opencode/opencode.db"))
}

struct SqliteSnapshot {
    directory: PathBuf,
    database: PathBuf,
}

impl SqliteSnapshot {
    fn create(db_path: &Path, label: &str) -> Result<Self> {
        let unique = format!(
            "crispyvibes-{label}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|duration| duration.as_nanos())
                .unwrap_or(0)
        );
        let directory = std::env::temp_dir().join(unique);
        fs::create_dir_all(&directory).context("create SQLite snapshot directory")?;
        let database = directory.join(
            db_path
                .file_name()
                .filter(|name| !name.is_empty())
                .unwrap_or_else(|| OsStr::new("data.sqlite3")),
        );
        if let Err(error) = fs::copy(db_path, &database).context("copy SQLite database") {
            let _ = fs::remove_dir_all(&directory);
            return Err(error);
        }
        for suffix in ["-wal", "-shm"] {
            let source = PathBuf::from(format!("{}{}", db_path.to_string_lossy(), suffix));
            if source.exists() {
                let destination =
                    PathBuf::from(format!("{}{}", database.to_string_lossy(), suffix));
                if let Err(error) = fs::copy(&source, &destination) {
                    let _ = fs::remove_dir_all(&directory);
                    return Err(error).context("copy SQLite sidecar");
                }
            }
        }
        Ok(Self {
            directory,
            database,
        })
    }
}

impl Drop for SqliteSnapshot {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.directory);
    }
}

fn with_sqlite_snapshot<T>(
    db_path: &Path,
    label: &str,
    body: impl FnOnce(&rusqlite::Connection) -> rusqlite::Result<T>,
) -> Result<T> {
    let snapshot = SqliteSnapshot::create(db_path, label)?;
    let connection = rusqlite::Connection::open_with_flags(
        &snapshot.database,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    )?;
    connection.pragma_update(None, "query_only", true)?;
    body(&connection).map_err(Into::into)
}

fn discover_opencode(diagnostics: &mut Vec<ParseDiagnostic>) -> Vec<ExternalSessionSummary> {
    let Some(db_path) = opencode_db_path().filter(|path| path.exists()) else {
        return Vec::new();
    };
    let outcome = with_sqlite_snapshot(&db_path, "opencode", |connection| {
        let mut statement = connection.prepare(
            "SELECT s.id, s.title, s.directory, s.time_created, s.time_updated,
                    (SELECT COUNT(*) FROM message WHERE session_id = s.id)
             FROM session s ORDER BY s.time_updated DESC",
        )?;
        let rows = statement.query_map([], |row| {
            Ok(opencode_summary(
                row.get::<_, String>(0)?,
                row.get::<_, String>(1).unwrap_or_default(),
                row.get::<_, String>(2).unwrap_or_default(),
                row.get::<_, i64>(3).unwrap_or(0),
                row.get::<_, i64>(4).unwrap_or(0),
                row.get::<_, i64>(5).unwrap_or(0) as usize,
            ))
        })?;
        rows.collect()
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
    ExternalSessionSummary {
        provider: Provider::OpenCode.id().to_string(),
        provider_name: Provider::OpenCode.display_name().to_string(),
        session_id: id.clone(),
        session_source: None,
        title: if title.trim().is_empty() {
            "Untitled session".to_string()
        } else {
            title
        },
        project_path: directory,
        source_path: id,
        created_at: String::new(),
        updated_at: String::new(),
        modified_at_epoch: if updated_ms > 0 {
            (updated_ms / 1_000) as u64
        } else {
            (created_ms / 1_000).max(0) as u64
        },
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
    let Some(db_path) = opencode_db_path() else {
        return empty_opencode_transcript(session_id);
    };
    let outcome = with_sqlite_snapshot(&db_path, "opencode", |connection| {
        let summary = connection.query_row(
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
        let mut statement = connection.prepare(
            "SELECT m.data,
                    (SELECT GROUP_CONCAT(p.data, char(10)) FROM part p WHERE p.message_id = m.id),
                    m.time_created
             FROM message m WHERE m.session_id = ?1 ORDER BY m.time_created ASC",
        )?;
        let rows = statement.query_map([session_id], |row| {
            Ok((
                row.get::<_, String>(0).unwrap_or_default(),
                row.get::<_, Option<String>>(1).unwrap_or(None),
                row.get::<_, i64>(2).unwrap_or(0),
            ))
        })?;
        let mut entries = Vec::new();
        for row in rows {
            let (message_data, parts_data, created_ms) = row?;
            let role = serde_json::from_str::<Value>(&message_data)
                .ok()
                .and_then(|value| value["role"].as_str().map(str::to_string))
                .unwrap_or_else(|| "assistant".to_string());
            let text = opencode_parts_text(parts_data.as_deref());
            if !text.trim().is_empty() {
                entries.push(TranscriptEntry {
                    role,
                    timestamp: created_ms.to_string(),
                    text,
                    metadata: empty_metadata(),
                });
            }
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
            parse_errors: Vec::new(),
        },
        Err(error) => {
            let parse_errors = vec![diagnostic(
                Provider::OpenCode,
                &db_path,
                None,
                "sqlite",
                error.to_string(),
            )];
            let mut response = empty_opencode_transcript(session_id);
            response.session.parse_status = "error".to_string();
            response.parse_errors = parse_errors;
            response
        }
    }
}

fn opencode_parts_text(parts: Option<&str>) -> String {
    let Some(parts) = parts else {
        return String::new();
    };
    parts
        .split('\n')
        .filter_map(|blob| serde_json::from_str::<Value>(blob).ok())
        .filter(|value| matches!(value["type"].as_str(), Some("text" | "reasoning")))
        .filter_map(|value| value["text"].as_str().and_then(non_empty))
        .collect::<Vec<_>>()
        .join("\n")
}

fn empty_opencode_transcript(session_id: &str) -> TranscriptResponse {
    TranscriptResponse {
        session: opencode_summary(
            session_id.to_string(),
            String::new(),
            String::new(),
            0,
            0,
            0,
        ),
        entries: Vec::new(),
        parse_errors: Vec::new(),
    }
}

fn load_kiro_classic(session_id: &str, db_path: &Path) -> TranscriptResponse {
    let outcome = with_sqlite_snapshot(db_path, "kiro", |connection| {
        connection
            .query_row(
                "SELECT key, conversation_id, value, created_at, updated_at
                 FROM conversations_v2 WHERE conversation_id = ?1 LIMIT 1",
                [session_id],
                |row| {
                    Ok((
                        row.get::<_, String>(0).unwrap_or_default(),
                        row.get::<_, String>(1).unwrap_or_default(),
                        row.get::<_, String>(2)?,
                        row.get::<_, i64>(3).unwrap_or(0),
                        row.get::<_, i64>(4).unwrap_or(0),
                    ))
                },
            )
            .optional()
    });
    match outcome {
        Ok(Some((cwd, id, raw, created_ms, updated_ms))) => {
            match serde_json::from_str::<Value>(&raw) {
                Ok(value) => {
                    let entries = classic_entries(&value);
                    let mut summary = empty_summary(Provider::Kiro, db_path.to_path_buf());
                    summary.session_id = id;
                    summary.session_source = Some(KIRO_CLASSIC_SOURCE.to_string());
                    summary.project_path = cwd;
                    summary.created_at = created_ms.to_string();
                    summary.updated_at = updated_ms.to_string();
                    summary.modified_at_epoch = (updated_ms.max(created_ms).max(0) / 1_000) as u64;
                    summary.message_count = entries.len();
                    summary.has_tool_activity = entries.iter().any(|entry| entry.role == "tool");
                    summary.title = entries
                        .iter()
                        .find(|entry| entry.role == "user")
                        .map(|entry| title_from_text(&entry.text))
                        .unwrap_or_default();
                    TranscriptResponse {
                        session: finalize_summary(summary),
                        entries,
                        parse_errors: Vec::new(),
                    }
                }
                Err(error) => {
                    let diagnostic = diagnostic(
                        Provider::Kiro,
                        db_path,
                        None,
                        "kiro.classic.json",
                        error.to_string(),
                    );
                    empty_transcript(
                        Provider::Kiro,
                        db_path.to_path_buf(),
                        session_id.to_string(),
                        Some(KIRO_CLASSIC_SOURCE.to_string()),
                        vec![diagnostic],
                    )
                }
            }
        }
        Ok(None) => {
            let error = diagnostic(
                Provider::Kiro,
                db_path,
                None,
                "kiro.classic.lookup",
                format!("classic Kiro session not found: {session_id}"),
            );
            empty_transcript(
                Provider::Kiro,
                db_path.to_path_buf(),
                session_id.to_string(),
                Some(KIRO_CLASSIC_SOURCE.to_string()),
                vec![error],
            )
        }
        Err(error) => {
            let diagnostic = diagnostic(
                Provider::Kiro,
                db_path,
                None,
                "kiro.classic.sqlite",
                error.to_string(),
            );
            empty_transcript(
                Provider::Kiro,
                db_path.to_path_buf(),
                session_id.to_string(),
                Some(KIRO_CLASSIC_SOURCE.to_string()),
                vec![diagnostic],
            )
        }
    }
}

fn classic_entries(value: &Value) -> Vec<TranscriptEntry> {
    let Some(history) = value["history"].as_array() else {
        return Vec::new();
    };
    let mut entries = Vec::new();
    for turn in history {
        let timestamp = turn["user"]["timestamp"]
            .as_str()
            .unwrap_or_default()
            .to_string();
        append_classic_user_entries(&mut entries, &turn["user"], &timestamp);
        append_classic_assistant_entries(&mut entries, &turn["assistant"], &timestamp);
        if entries.len() >= PREVIEW_ENTRY_LIMIT {
            entries.truncate(PREVIEW_ENTRY_LIMIT);
            break;
        }
    }
    entries
}

fn classic_variants(side: &Value) -> Option<&serde_json::Map<String, Value>> {
    side.get("content")
        .and_then(Value::as_object)
        .or_else(|| side.as_object())
}

fn append_classic_user_entries(entries: &mut Vec<TranscriptEntry>, user: &Value, timestamp: &str) {
    let Some(variants) = classic_variants(user) else {
        return;
    };
    if let Some(prompt) = variants
        .get("Prompt")
        .and_then(|value| value["prompt"].as_str())
        .and_then(non_empty)
    {
        entries.push(classic_entry("user", timestamp, prompt, empty_metadata()));
    }
    for name in ["ToolUseResults", "CancelledToolUses"] {
        let Some(value) = variants.get(name) else {
            continue;
        };
        if let Some(prompt) = value["prompt"].as_str().and_then(non_empty) {
            entries.push(classic_entry("user", timestamp, prompt, empty_metadata()));
        }
        let rendered = render_classic_tool_results(value);
        if !rendered.is_empty() {
            entries.push(classic_entry(
                "tool",
                timestamp,
                rendered,
                metadata_field("toolUseResults", value["tool_use_results"].clone()),
            ));
        }
    }
}

fn append_classic_assistant_entries(
    entries: &mut Vec<TranscriptEntry>,
    assistant: &Value,
    timestamp: &str,
) {
    let Some(variants) = classic_variants(assistant) else {
        return;
    };
    if let Some(response) = variants
        .get("Response")
        .and_then(|value| value["content"].as_str())
        .and_then(non_empty)
    {
        entries.push(classic_entry(
            "assistant",
            timestamp,
            response,
            empty_metadata(),
        ));
    }
    if let Some(tool_use) = variants.get("ToolUse") {
        if let Some(content) = tool_use["content"].as_str().and_then(non_empty) {
            entries.push(classic_entry(
                "assistant",
                timestamp,
                content,
                empty_metadata(),
            ));
        }
        let rendered = render_classic_tool_uses(tool_use);
        if !rendered.is_empty() {
            entries.push(classic_entry(
                "tool",
                timestamp,
                rendered,
                metadata_field("toolUses", tool_use["tool_uses"].clone()),
            ));
        }
    }
}

fn empty_metadata() -> Value {
    Value::Object(serde_json::Map::new())
}

fn metadata_field(name: &str, value: Value) -> Value {
    let mut metadata = serde_json::Map::new();
    metadata.insert(name.to_string(), value);
    Value::Object(metadata)
}

fn classic_entry(role: &str, timestamp: &str, text: String, metadata: Value) -> TranscriptEntry {
    debug_assert!(metadata.is_object());
    TranscriptEntry {
        role: role.to_string(),
        timestamp: timestamp.to_string(),
        text,
        metadata,
    }
}

fn render_classic_tool_uses(value: &Value) -> String {
    value["tool_uses"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|tool| {
            let name = tool["name"]
                .as_str()
                .or_else(|| tool["orig_name"].as_str())
                .unwrap_or("tool");
            let args = tool.get("args").or_else(|| tool.get("orig_args"));
            match args {
                Some(Value::Null) | None => name.to_string(),
                Some(args) => format!("{name}\n{}", json_display(args)),
            }
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

fn render_classic_tool_results(value: &Value) -> String {
    value["tool_use_results"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|result| {
            let id = result["tool_use_id"].as_str().unwrap_or("tool");
            let status = result["status"].as_str().unwrap_or_default();
            let content = result["content"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|item| {
                    item.get("Text")
                        .and_then(Value::as_str)
                        .map(str::to_string)
                        .or_else(|| item.get("Json").map(json_display))
                })
                .collect::<Vec<_>>()
                .join("\n");
            let heading = if status.is_empty() {
                id.to_string()
            } else {
                format!("{id} ({status})")
            };
            if content.trim().is_empty() {
                heading
            } else {
                format!("{heading}\n{content}")
            }
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

fn json_display(value: &Value) -> String {
    serde_json::to_string(value).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::io::Write;
    use std::sync::atomic::{AtomicU64, Ordering};

    static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

    struct TestDirectory(PathBuf);

    impl TestDirectory {
        fn new(label: &str) -> Self {
            let path = std::env::temp_dir().join(format!(
                "crispy-external-test-{label}-{}-{}",
                std::process::id(),
                TEMP_COUNTER.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for TestDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn create_classic_fixture(path: &Path) {
        let connection = rusqlite::Connection::open(path).unwrap();
        connection
            .execute_batch(
                "CREATE TABLE conversations_v2 (
                    key TEXT, conversation_id TEXT, value TEXT,
                    created_at INTEGER, updated_at INTEGER
                 );",
            )
            .unwrap();
        let value = json!({
            "history": [
                {
                    "user": {"content": {"Prompt": {"prompt": "Find the lunar widget"}}, "timestamp": "2026-09-30T10:00:00Z"},
                    "assistant": {"Response": {"content": "I found the widget"}}
                },
                {
                    "user": {"content": {"ToolUseResults": {"tool_use_results": [{
                        "content": [{"Text": "lunar output"}, {"Json": {"matches": 2}}],
                        "status": "success", "tool_use_id": "call-1"
                    }]}}},
                    "assistant": {"ToolUse": {
                        "content": "Checking files", "tool_uses": [{
                            "id": "call-1", "name": "grep", "args": {"pattern": "lunar"},
                            "orig_name": "Grep", "orig_args": {"pattern": "lunar"}
                        }]
                    }}
                },
                {
                    "user": {"content": {"CancelledToolUses": {
                        "prompt": "Stop the search", "tool_use_results": [{
                            "content": [{"Text": "cancelled"}], "status": "cancelled", "tool_use_id": "call-2"
                        }]
                    }}},
                    "assistant": {"Response": {"content": "Stopped"}}
                }
            ]
        });
        connection
            .execute(
                "INSERT INTO conversations_v2 VALUES (?1, ?2, ?3, ?4, ?5)",
                rusqlite::params![
                    "/work/widget",
                    "classic-1",
                    value.to_string(),
                    1_727_690_400_000_i64,
                    1_727_690_500_000_i64
                ],
            )
            .unwrap();
    }

    fn create_v2_fixture(directory: &Path) {
        fs::write(
            directory.join("fallback.json"),
            json!({
                "session_id": "fallback", "cwd": "/work/fallback",
                "title": "Fallback", "updated_at": "2026-09-30T10:00:00Z"
            })
            .to_string(),
        )
        .unwrap();
        fs::write(
            directory.join("fallback.jsonl"),
            format!(
                "{}\n",
                json!({"version": "v1", "kind": "Prompt", "data": {"content": [{"text": "fallback body"}]}})
            ),
        )
        .unwrap();
    }

    #[test]
    fn kiro_listing_accepts_array_and_single_envelopes_and_deduplicates_per_source() {
        let array = json!([
            {"complete": true, "cwd": "/work/a", "sessions": [
                {"messageCount": 2, "sessionId": "same", "source": "v2", "title": "V2", "updatedAt": "2026-09-30T10:00:00Z"},
                {"messageCount": 3, "sessionId": "same", "source": "classic", "title": "Classic", "updatedAt": "2026-09-30T11:00:00Z"}
            ]},
            {"complete": true, "cwd": "/work/a", "sessions": [
                {"messageCount": 2, "sessionId": "same", "source": "v2", "title": "Duplicate", "updatedAt": "2026-09-30T10:00:00Z"}
            ]}
        ]);
        let mut diagnostics = Vec::new();
        let sessions = parse_kiro_listing(
            &array.to_string(),
            Some(Path::new("/kiro/sessions/cli")),
            Some(Path::new("/kiro/data.sqlite3")),
            &mut diagnostics,
        )
        .unwrap();
        assert_eq!(sessions.len(), 2);
        assert_ne!(
            session_identity(&sessions[0]),
            session_identity(&sessions[1])
        );
        assert!(diagnostics.is_empty());

        let single = json!({"complete": true, "cwd": "/single", "sessions": [{
            "messageCount": 1, "sessionId": "one", "source": "v2", "title": "One",
            "updatedAt": "2026-09-30T10:00:00Z", "status": "active"
        }]});
        let sessions = parse_kiro_listing(
            &single.to_string(),
            Some(Path::new("/v2")),
            Some(Path::new("/classic")),
            &mut Vec::new(),
        )
        .unwrap();
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].project_path, "/single");
    }

    #[test]
    fn kiro_v2_source_paths_are_confined_to_the_session_root() {
        use std::os::unix::fs::symlink;

        let directory = TestDirectory::new("kiro-v2-confinement");
        let root = directory.0.join("sessions/cli");
        fs::create_dir_all(&root).unwrap();
        let valid = root.join("valid-session.jsonl");
        fs::write(&valid, "safe").unwrap();

        assert_eq!(
            confined_kiro_v2_source_path(&root, "valid-session").unwrap(),
            fs::canonicalize(&valid).unwrap()
        );
        for unsafe_id in ["../outside", "/absolute", "nested/id", ".", "..", ""] {
            assert!(confined_kiro_v2_source_path(&root, unsafe_id).is_err());
        }

        let outside = directory.0.join("outside.jsonl");
        fs::write(&outside, "outside marker").unwrap();
        let linked = root.join("linked.jsonl");
        symlink(&outside, &linked).unwrap();
        assert!(confined_kiro_v2_source_path(&root, "linked").is_err());
        assert!(open_session_file(Provider::Kiro, &linked).is_err());

        let outside_metadata = directory.0.join("outside.json");
        fs::write(
            &outside_metadata,
            json!({
                "session_id": "outside",
                "title": "outside metadata marker"
            })
            .to_string(),
        )
        .unwrap();
        let linked_metadata = root.join("linked-metadata.json");
        symlink(&outside_metadata, &linked_metadata).unwrap();
        let mut diagnostics = Vec::new();
        let summary = summarize_kiro(&linked_metadata, &mut diagnostics);
        assert!(!diagnostics.is_empty());
        assert!(!summary.title.contains("outside metadata marker"));
        assert!(open_session_file(Provider::Kiro, &linked_metadata).is_err());
    }

    #[test]
    fn kiro_listing_skips_unsafe_v2_ids_without_reading_outside_files() {
        let directory = TestDirectory::new("kiro-v2-listing-confinement");
        let root = directory.0.join("sessions/cli");
        fs::create_dir_all(&root).unwrap();
        fs::write(directory.0.join("outside.jsonl"), "outside marker").unwrap();
        let listing = json!({"complete": true, "cwd": "/work", "sessions": [
            {"sessionId": "../outside", "source": "v2", "title": "Unsafe", "updatedAt": "", "messageCount": 1},
            {"sessionId": "/absolute", "source": "v2", "title": "Absolute", "updatedAt": "", "messageCount": 1},
            {"sessionId": "nested/id", "source": "v2", "title": "Nested", "updatedAt": "", "messageCount": 1}
        ]});
        let mut diagnostics = Vec::new();

        let sessions = parse_kiro_listing(
            &listing.to_string(),
            Some(&root),
            Some(Path::new("/classic/data.sqlite3")),
            &mut diagnostics,
        )
        .unwrap();

        assert!(sessions.is_empty());
        assert_eq!(diagnostics.len(), 3);
        assert!(diagnostics
            .iter()
            .all(|diagnostic| diagnostic.context == "kiro.sourcePath"));
        assert!(diagnostics
            .iter()
            .all(|diagnostic| !diagnostic.message.contains("outside marker")));
    }

    #[test]
    fn crispy_title_helpers_are_filtered_by_prompt_not_repeated_title() {
        let directory = TestDirectory::new("kiro-internal-filter");
        let database = directory.0.join("data.sqlite3");
        let connection = rusqlite::Connection::open(&database).unwrap();
        connection
            .execute_batch(
                "CREATE TABLE conversations_v2 (
                    key TEXT, conversation_id TEXT, value TEXT,
                    created_at INTEGER, updated_at INTEGER
                 );",
            )
            .unwrap();
        let legacy_prompt = format!(
            "{LEGACY_CRISPY_TITLE_REQUEST_PREFIX}\nRules:\n- Keep it short.\n\nUser message:\nFix search"
        );
        let internal_legacy_multiline = json!({"history": [{
            "user": {"content": {"Prompt": {"prompt": legacy_prompt}}},
            "assistant": {"Response": {"content": "{\"title\":\"Fix Search\"}"}}
        }]});
        let internal_current = json!({"history": [{
            "user": {"content": {"Prompt": {"prompt": format!("{CRISPY_TITLE_REQUEST_MARKER}\nGenerate a title")}}},
            "assistant": {"Response": {"content": "{\"title\":\"Current\"}"}}
        }]});
        let internal_legacy_single_line = json!({"history": [{
            "user": {"content": {"Prompt": {"prompt": format!("{LEGACY_CRISPY_TITLE_REQUEST_SINGLE_LINE_PREFIX} Fix search")}}},
            "assistant": {"Response": {"content": "{\"title\":\"Legacy\"}"}}
        }]});
        let legitimate = json!({"history": [{
            "user": {"content": {"Prompt": {"prompt": "A legitimate conversation"}}},
            "assistant": {"Response": {"content": "Normal answer"}}
        }]});
        let continued = json!({"history": [
            {
                "user": {"content": {"Prompt": {"prompt": format!("{CRISPY_TITLE_REQUEST_MARKER}\nGenerate a title")}}},
                "assistant": {"Response": {"content": "First answer"}}
            },
            {
                "user": {"content": {"Prompt": {"prompt": "Continue normally"}}},
                "assistant": {"Response": {"content": "Second answer"}}
            }
        ]});
        for (id, value) in [
            ("internal-legacy-multiline", internal_legacy_multiline),
            ("internal-current", internal_current),
            ("internal-legacy-single-line", internal_legacy_single_line),
            ("legitimate", legitimate),
            ("continued", continued),
        ] {
            connection
                .execute(
                    "INSERT INTO conversations_v2 VALUES ('/work', ?1, ?2, 0, 0)",
                    rusqlite::params![id, value.to_string()],
                )
                .unwrap();
        }
        drop(connection);

        let repeated_title = "You write concise thread titles for coding conversations";
        let listing = json!({"complete": true, "cwd": "/work", "sessions": [
            {"sessionId": "internal-legacy-multiline", "source": "classic", "title": repeated_title, "updatedAt": "", "messageCount": 1},
            {"sessionId": "internal-current", "source": "classic", "title": repeated_title, "updatedAt": "", "messageCount": 1},
            {"sessionId": "internal-legacy-single-line", "source": "classic", "title": repeated_title, "updatedAt": "", "messageCount": 1},
            {"sessionId": "legitimate", "source": "classic", "title": repeated_title, "updatedAt": "", "messageCount": 1},
            {"sessionId": "continued", "source": "classic", "title": repeated_title, "updatedAt": "", "messageCount": 2}
        ]});
        let mut diagnostics = Vec::new();
        let sessions = discover_kiro_from_listing(
            Ok(listing.to_string()),
            Some(Path::new("/unused/v2")),
            Some(&database),
            &mut diagnostics,
        );
        let visible_ids = sessions
            .iter()
            .map(|session| session.session_id.as_str())
            .collect::<HashSet<_>>();

        assert_eq!(visible_ids, HashSet::from(["legitimate", "continued"]));
        assert!(diagnostics.is_empty());
        assert!(is_crispy_title_request(&format!(
            "{CRISPY_TITLE_REQUEST_MARKER}\nGenerate a title"
        )));
        assert!(is_crispy_title_request(&format!(
            "{LEGACY_CRISPY_TITLE_REQUEST_SINGLE_LINE_PREFIX} Fix search"
        )));
    }

    #[test]
    fn unknown_kiro_sources_are_skipped_with_one_diagnostic() {
        let listing = json!({"complete": true, "cwd": "/work", "sessions": [
            {"sessionId": "a", "source": "v3", "title": "A", "updatedAt": "", "messageCount": 1},
            {"sessionId": "b", "source": "future", "title": "B", "updatedAt": "", "messageCount": 1}
        ]});
        let mut diagnostics = Vec::new();
        let sessions = parse_kiro_listing(
            &listing.to_string(),
            Some(Path::new("/v2")),
            Some(Path::new("/classic")),
            &mut diagnostics,
        )
        .unwrap();
        assert!(sessions.is_empty());
        assert_eq!(diagnostics.len(), 1);
        assert!(diagnostics[0].message.contains("future, v3"));
    }

    #[test]
    fn kiro_listing_command_and_decode_failures_use_v2_fallback() {
        let directory = TestDirectory::new("listing-fallback");
        create_v2_fixture(&directory.0);

        for (listing, context) in [
            (Err(anyhow::anyhow!("status 17")), "kiro.metadata.command"),
            (Ok("not-json".to_string()), "kiro.metadata.decode"),
        ] {
            let mut diagnostics = Vec::new();
            let sessions = discover_kiro_from_listing(
                listing,
                Some(&directory.0),
                Some(Path::new("/unused/data.sqlite3")),
                &mut diagnostics,
            );
            assert_eq!(sessions.len(), 1);
            assert_eq!(sessions[0].session_id, "fallback");
            assert_eq!(sessions[0].session_source.as_deref(), Some(KIRO_V2_SOURCE));
            assert_eq!(diagnostics.len(), 1);
            assert_eq!(diagnostics[0].context, context);
        }
    }

    #[test]
    fn v2_metadata_and_version_kind_data_jsonl_remain_compatible() {
        let directory = TestDirectory::new("v2");
        let metadata = directory.0.join("session.json");
        let jsonl = directory.0.join("session.jsonl");
        fs::write(
            &metadata,
            json!({
                "session_id": "v2-1", "cwd": "/work/v2", "created_at": "2026-09-30T10:00:00Z",
                "updated_at": "2026-09-30T10:01:00Z", "title": "V2 fixture"
            })
            .to_string(),
        )
        .unwrap();
        let mut file = fs::File::create(&jsonl).unwrap();
        writeln!(
            file,
            "{}",
            json!({"version": "v1", "kind": "Prompt", "data": {"content": [{"text": "hello V2"}]}})
        )
        .unwrap();
        writeln!(file, "{}", json!({"version": "v1", "kind": "AssistantMessage", "data": {"content": [{"text": "hello back"}]}})).unwrap();

        let mut diagnostics = Vec::new();
        let summary = summarize_kiro(&metadata, &mut diagnostics);
        let transcript = load(Provider::Kiro, Some(jsonl), Some("v2-1".to_string()), None);
        assert_eq!(summary.session_id, "v2-1");
        assert_eq!(summary.session_source.as_deref(), Some(KIRO_V2_SOURCE));
        assert_eq!(summary.message_count, 2);
        assert_eq!(transcript.entries.len(), 2);
        assert!(diagnostics.is_empty());
    }

    #[test]
    fn classic_transcript_parses_prompts_responses_tools_results_and_cancellation() {
        let directory = TestDirectory::new("classic");
        let database = directory.0.join("data.sqlite3");
        create_classic_fixture(&database);

        let transcript = load_kiro_classic("classic-1", &database);
        assert!(transcript.parse_errors.is_empty());
        assert_eq!(
            transcript.session.session_source.as_deref(),
            Some(KIRO_CLASSIC_SOURCE)
        );
        assert!(transcript.session.has_tool_activity);
        assert!(transcript
            .entries
            .iter()
            .any(|entry| entry.role == "user" && entry.text.contains("lunar widget")));
        assert!(transcript
            .entries
            .iter()
            .any(|entry| entry.role == "assistant" && entry.text.contains("found the widget")));
        assert!(transcript
            .entries
            .iter()
            .any(|entry| entry.role == "tool" && entry.text.contains("grep")));
        assert!(transcript
            .entries
            .iter()
            .any(|entry| entry.role == "tool" && entry.text.contains("\"matches\":2")));
        assert!(transcript
            .entries
            .iter()
            .any(|entry| entry.text.contains("Stop the search")));

        let serialized = serde_json::to_value(&transcript).unwrap();
        let entries = serialized["entries"].as_array().unwrap();
        assert!(entries.iter().all(|entry| entry["metadata"].is_object()));
        assert!(entries.iter().any(|entry| {
            entry["metadata"]["toolUseResults"]
                .as_array()
                .is_some_and(|results| !results.is_empty())
        }));
        assert!(entries.iter().any(|entry| {
            entry["metadata"]["toolUses"]
                .as_array()
                .is_some_and(|uses| !uses.is_empty())
        }));
    }

    #[test]
    fn classic_body_search_matches_content_without_matching_path() {
        let directory = TestDirectory::new("classic-search");
        let database = directory.0.join("data.sqlite3");
        create_classic_fixture(&database);
        let mut session = empty_summary(Provider::Kiro, database);
        session.session_id = "classic-1".to_string();
        session.session_source = Some(KIRO_CLASSIC_SOURCE.to_string());
        session.project_path = "/path/ambient-only-token".to_string();

        let found = find_classic_search_matches(&[session.clone()], "lunar").unwrap();
        assert!(found.matches.contains_key(&session_identity(&session)));
        assert!(found.diagnostics.is_empty());
        let not_found = find_classic_search_matches(&[session], "ambient-only-token").unwrap();
        assert!(not_found.matches.is_empty());
    }

    #[test]
    fn classic_search_scans_rows_once_and_isolates_malformed_sessions() {
        let directory = TestDirectory::new("classic-search-isolation");
        let database = directory.0.join("data.sqlite3");
        create_classic_fixture(&database);
        let connection = rusqlite::Connection::open(&database).unwrap();
        connection
            .execute(
                "INSERT INTO conversations_v2 VALUES (?1, ?2, ?3, 0, 0)",
                rusqlite::params!["/work/bad", "bad", "{not-json"],
            )
            .unwrap();
        drop(connection);

        let mut sessions = (0..500)
            .map(|index| {
                let mut session = empty_summary(Provider::Kiro, database.clone());
                session.session_id = format!("missing-{index}");
                session.session_source = Some(KIRO_CLASSIC_SOURCE.to_string());
                session
            })
            .collect::<Vec<_>>();
        for id in ["classic-1", "bad"] {
            let mut session = empty_summary(Provider::Kiro, database.clone());
            session.session_id = id.to_string();
            session.session_source = Some(KIRO_CLASSIC_SOURCE.to_string());
            sessions.push(session);
        }

        let outcome = find_classic_search_matches(&sessions, "lunar").unwrap();
        assert_eq!(outcome.rows_scanned, 2);
        assert_eq!(outcome.matches.len(), 1);
        assert_eq!(outcome.diagnostics.len(), 1);
        assert_eq!(outcome.diagnostics[0].context, "kiro.classic.search.json");
        assert!(outcome.diagnostics[0].message.contains("session bad"));
    }

    #[test]
    fn sqlite_snapshot_leaves_original_immutable_and_cleans_up() {
        let directory = TestDirectory::new("snapshot");
        let database = directory.0.join("data.sqlite3");
        create_classic_fixture(&database);
        let writer = rusqlite::Connection::open(&database).unwrap();
        writer.pragma_update(None, "journal_mode", "WAL").unwrap();
        writer.pragma_update(None, "wal_autocheckpoint", 0).unwrap();
        writer
            .execute(
                "INSERT INTO conversations_v2 VALUES (?1, ?2, ?3, 0, 0)",
                rusqlite::params!["/work/live", "live", json!({"history": []}).to_string()],
            )
            .unwrap();
        let wal = PathBuf::from(format!("{}-wal", database.to_string_lossy()));
        let shm = PathBuf::from(format!("{}-shm", database.to_string_lossy()));
        assert!(wal.exists());
        assert!(shm.exists());
        let before = [
            fs::read(&database).unwrap(),
            fs::read(&wal).unwrap(),
            fs::read(&shm).unwrap(),
        ];
        let snapshot_directory = with_sqlite_snapshot(&database, "test", |connection| {
            assert_eq!(
                connection.query_row("SELECT COUNT(*) FROM conversations_v2", [], |row| row
                    .get::<_, i64>(0))?,
                2
            );
            let path = connection.path().map(PathBuf::from).unwrap();
            assert!(PathBuf::from(format!("{}-wal", path.to_string_lossy())).exists());
            assert!(PathBuf::from(format!("{}-shm", path.to_string_lossy())).exists());
            Ok(path.parent().unwrap().to_path_buf())
        })
        .unwrap();
        assert_eq!(fs::read(&database).unwrap(), before[0]);
        assert_eq!(fs::read(&wal).unwrap(), before[1]);
        assert_eq!(fs::read(&shm).unwrap(), before[2]);
        assert!(!snapshot_directory.exists());
        drop(writer);
    }

    #[test]
    fn sqlite_snapshot_cleans_up_when_query_closure_fails() {
        let directory = TestDirectory::new("snapshot-error");
        let database = directory.0.join("data.sqlite3");
        create_classic_fixture(&database);
        let mut snapshot_directory = None;
        let result: Result<()> = with_sqlite_snapshot(&database, "test-error", |connection| {
            let path = connection.path().map(PathBuf::from).unwrap();
            snapshot_directory = path.parent().map(Path::to_path_buf);
            Err(rusqlite::Error::InvalidQuery)
        });
        assert!(result.is_err());
        assert!(!snapshot_directory.unwrap().exists());
    }

    #[test]
    fn kiro_paths_honor_nonempty_overrides_without_process_environment_mutation() {
        let home = Path::new("/Users/example");
        assert_eq!(
            kiro_v2_root_from(Some(home), Some(OsStr::new("/custom/kiro"))).unwrap(),
            Path::new("/custom/kiro/sessions/cli")
        );
        assert_eq!(
            kiro_v2_root_from(Some(home), Some(OsStr::new(""))).unwrap(),
            Path::new("/Users/example/.kiro/sessions/cli")
        );
        assert_eq!(
            kiro_classic_db_path_from(Some(home), Some(OsStr::new("/custom/data"))).unwrap(),
            Path::new("/custom/data/data.sqlite3")
        );
    }

    #[test]
    fn first_text_prefers_nested_text_content() {
        let value = json!({"message": {"content": [{"type": "text", "text": "hello"}, {"type": "text", "text": "world"}]}});
        assert_eq!(first_text(&value), Some("hello\nworld".to_string()));
    }

    #[test]
    fn title_from_text_normalizes_whitespace_and_truncates() {
        assert_eq!(title_from_text("  one\n two\tthree  "), "one two three");
        let title = title_from_text(&"x".repeat(100));
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

    #[test]
    fn timestamp_parser_handles_rfc3339_and_milliseconds() {
        assert_eq!(epoch_from_timestamp("1970-01-01T00:00:01Z"), Some(1));
        assert_eq!(epoch_from_timestamp("1000000000000"), Some(1_000_000_000));
    }
}
