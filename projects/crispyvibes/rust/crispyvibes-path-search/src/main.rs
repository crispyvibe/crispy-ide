use std::collections::HashMap;
use std::ffi::CString;
use std::io::BufRead;
use std::io::BufReader;
use std::io::BufWriter;
use std::io::Write;
use std::num::NonZero;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::AtomicBool;
use std::sync::atomic::Ordering;

use anyhow::Context;
use crispyvibes_path_search as file_search;
use serde::Deserialize;
use serde::Serialize;

const MATCH_LIMIT: usize = 50;
const MAX_THREADS: usize = 12;
const PROCESS_NAME: &str = "CrispyVibes (path search helper)";

#[derive(Deserialize)]
#[serde(tag = "method", content = "params", rename_all = "camelCase")]
enum Request {
    Start(StartParams),
    Update(UpdateParams),
    Stop(StopParams),
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct StartParams {
    session_id: String,
    roots: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct UpdateParams {
    session_id: String,
    query: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct StopParams {
    session_id: String,
}

#[derive(Serialize)]
#[serde(tag = "method", content = "params", rename_all = "camelCase")]
enum Notification {
    SessionUpdated(SessionUpdatedNotification),
    SessionCompleted(SessionCompletedNotification),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SessionUpdatedNotification {
    session_id: String,
    query: String,
    files: Vec<file_search::FileMatch>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SessionCompletedNotification {
    session_id: String,
    query: String,
}

struct SearchSession {
    session: file_search::FileSearchSession,
    shared: Arc<SessionShared>,
}

impl SearchSession {
    fn update_query(&self, query: String) {
        if self.shared.canceled.load(Ordering::Relaxed) {
            return;
        }
        {
            let mut latest_query = self.shared.latest_query.lock().expect("latest query lock");
            *latest_query = query.clone();
        }
        self.session.update_query(&query);
    }
}

impl Drop for SearchSession {
    fn drop(&mut self) {
        self.shared.canceled.store(true, Ordering::Relaxed);
    }
}

struct SessionShared {
    session_id: String,
    latest_query: Mutex<String>,
    writer: Arc<Mutex<BufWriter<std::io::Stdout>>>,
    canceled: Arc<AtomicBool>,
}

struct SessionReporterImpl {
    shared: Arc<SessionShared>,
}

impl SessionReporterImpl {
    fn send_notification(&self, notification: Notification) {
        if self.shared.canceled.load(Ordering::Relaxed) {
            return;
        }

        let mut writer = self.shared.writer.lock().expect("stdout writer lock");
        if serde_json::to_writer(&mut *writer, &notification).is_ok() {
            let _ = writer.write_all(b"\n");
            let _ = writer.flush();
        }
    }

    fn send_snapshot(&self, snapshot: &file_search::FileSearchSnapshot) {
        if self.shared.canceled.load(Ordering::Relaxed) {
            return;
        }

        let query = {
            let latest_query = self.shared.latest_query.lock().expect("latest query lock");
            latest_query.clone()
        };

        if snapshot.query != query || query.is_empty() {
            return;
        }

        let mut files = snapshot.matches.clone();
        files.sort_by(file_search::cmp_by_score_desc_then_directory_then_path_asc::<
            file_search::FileMatch,
            _,
            _,
            _,
        >(
            |item| item.score,
            |item| item.match_type == file_search::MatchType::Directory,
            |item| item.path.to_str().unwrap_or_default(),
        ));

        self.send_notification(Notification::SessionUpdated(SessionUpdatedNotification {
            session_id: self.shared.session_id.clone(),
            query,
            files,
        }));
    }

    fn send_complete(&self) {
        let query = {
            let latest_query = self.shared.latest_query.lock().expect("latest query lock");
            latest_query.clone()
        };
        self.send_notification(Notification::SessionCompleted(
            SessionCompletedNotification {
                session_id: self.shared.session_id.clone(),
                query,
            },
        ));
    }
}

impl file_search::SessionReporter for SessionReporterImpl {
    fn on_update(&self, snapshot: &file_search::FileSearchSnapshot) {
        self.send_snapshot(snapshot);
    }

    fn on_complete(&self) {
        self.send_complete();
    }
}

fn start_session(
    session_id: String,
    roots: Vec<String>,
    writer: Arc<Mutex<BufWriter<std::io::Stdout>>>,
) -> anyhow::Result<SearchSession> {
    let limit = NonZero::new(MATCH_LIMIT).expect("non-zero match limit");
    let cores = std::thread::available_parallelism()
        .map(NonZero::get)
        .unwrap_or(1);
    let threads = NonZero::new(cores.min(MAX_THREADS).max(1)).expect("non-zero thread count");
    let search_directories: Vec<PathBuf> = roots.iter().map(PathBuf::from).collect();
    let canceled = Arc::new(AtomicBool::new(false));

    let shared = Arc::new(SessionShared {
        session_id,
        latest_query: Mutex::new(String::new()),
        writer,
        canceled: canceled.clone(),
    });

    let reporter = Arc::new(SessionReporterImpl {
        shared: shared.clone(),
    });

    let session = file_search::create_session(
        search_directories,
        file_search::FileSearchOptions {
            limit,
            threads,
            compute_indices: true,
            ..Default::default()
        },
        reporter,
        Some(canceled),
    )?;

    Ok(SearchSession { session, shared })
}

fn main() -> anyhow::Result<()> {
    apply_process_name();

    let stdin = std::io::stdin();
    let stdout = std::io::stdout();
    let reader = BufReader::new(stdin.lock());
    let writer = Arc::new(Mutex::new(BufWriter::new(stdout)));
    let mut sessions: HashMap<String, SearchSession> = HashMap::new();

    for line in reader.lines() {
        let line = line.context("failed reading stdin")?;
        if line.trim().is_empty() {
            continue;
        }

        let request: Request = serde_json::from_str(&line)
            .with_context(|| format!("failed to decode request: {line}"))?;

        match request {
            Request::Start(StartParams { session_id, roots }) => {
                sessions.remove(&session_id);
                let session = start_session(session_id.clone(), roots, writer.clone())
                    .with_context(|| format!("failed to start session {session_id}"))?;
                sessions.insert(session_id, session);
            }
            Request::Update(UpdateParams { session_id, query }) => {
                if let Some(session) = sessions.get(&session_id) {
                    session.update_query(query);
                }
            }
            Request::Stop(StopParams { session_id }) => {
                sessions.remove(&session_id);
            }
        }
    }

    sessions.clear();
    Ok(())
}

#[cfg(any(target_os = "macos", target_os = "ios", target_os = "freebsd"))]
fn apply_process_name() {
    let Ok(name) = CString::new(PROCESS_NAME) else {
        return;
    };

    // SAFETY: `name` is a valid NUL-terminated string for the duration of the call.
    unsafe {
        libc::setprogname(name.as_ptr());
    }
}

#[cfg(target_os = "linux")]
fn apply_process_name() {
    let truncated = PROCESS_NAME.chars().take(15).collect::<String>();
    let Ok(name) = CString::new(truncated) else {
        return;
    };

    // SAFETY: `name` is a valid NUL-terminated string for the duration of the call.
    unsafe {
        libc::prctl(libc::PR_SET_NAME, name.as_ptr() as libc::c_ulong, 0, 0, 0);
    }
}

#[cfg(not(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "freebsd",
    target_os = "linux"
)))]
fn apply_process_name() {}
