mod handlers_board;
mod handlers_comments;
mod handlers_message;
mod handlers_session;
mod handlers_thread;
mod handlers_todos;
mod rpc;
mod schema;
mod util;

use std::ffi::CString;
use std::io::Write;

use anyhow::Context;
use serde_json::json;
use tokio::io::{AsyncBufReadExt, BufReader};

use rpc::{Request, Response};

const PROCESS_NAME: &str = "CrispyVibes (persistence helper)";

#[tokio::main(flavor = "current_thread")]
async fn main() -> anyhow::Result<()> {
    apply_process_name();

    let stdin = BufReader::new(tokio::io::stdin());
    let stdout = std::io::stdout();
    let mut out = std::io::BufWriter::new(stdout.lock());
    let mut lines = stdin.lines();

    // First message must be init
    let conn = match wait_for_init(&mut lines, &mut out).await {
        Ok(c) => c,
        Err(e) => {
            let resp = Response::err("init".into(), -32000, e.to_string());
            write_response(&mut out, &resp);
            return Err(e);
        }
    };

    // Main loop
    while let Ok(Some(line)) = lines.next_line().await {
        if line.trim().is_empty() {
            continue;
        }

        let req: Request = match serde_json::from_str(&line) {
            Ok(r) => r,
            Err(e) => {
                let resp = Response::err("?".into(), -32700, format!("parse error: {e}"));
                write_response(&mut out, &resp);
                continue;
            }
        };

        let resp = dispatch(&conn, req).await;
        write_response(&mut out, &resp);
    }

    Ok(())
}

async fn wait_for_init(
    lines: &mut tokio::io::Lines<BufReader<tokio::io::Stdin>>,
    out: &mut std::io::BufWriter<std::io::StdoutLock<'_>>,
) -> anyhow::Result<libsql::Connection> {
    while let Ok(Some(line)) = lines.next_line().await {
        if line.trim().is_empty() {
            continue;
        }

        let req: Request = serde_json::from_str(&line).context("parse init request")?;
        if req.method != "init" {
            let resp = Response::err(req.id, -32000, "first message must be init");
            write_response(out, &resp);
            continue;
        }

        let db_path = req.params["dbPath"].as_str().unwrap_or_default().to_string();
        let mut hex_key = req.params["hexKey"].as_str().unwrap_or_default().to_string();

        // Ensure parent directory exists
        if let Some(parent) = std::path::Path::new(&db_path).parent() {
            std::fs::create_dir_all(parent).context("create db directory")?;
        }

        let db = libsql::Builder::new_local(&db_path)
            .encryption_config(libsql::EncryptionConfig::new(
                libsql::Cipher::Aes256Cbc,
                hex_key.clone().into(),
            ))
            .build()
            .await;

        // Zero the key from memory immediately after use
        zeroize::Zeroize::zeroize(&mut hex_key);
        drop(hex_key);

        let db = db
            .context("open database")?;

        let conn = db.connect().context("connect to database")?;

        // WAL mode and foreign keys
        conn.query("PRAGMA journal_mode = WAL", ()).await.context("set WAL mode")?;
        conn.execute("PRAGMA foreign_keys = ON", ()).await.context("enable foreign keys")?;

        let version = schema::run_migrations(&conn).await.context("run migrations")?;

        let resp = Response::ok(req.id, json!({"ready": true, "schemaVersion": version}));
        write_response(out, &resp);

        return Ok(conn);
    }

    anyhow::bail!("stdin closed before init")
}

async fn dispatch(conn: &libsql::Connection, req: Request) -> Response {
    let id = req.id;
    let params = req.params;

    match req.method.as_str() {
        // Thread
        "thread.create" => handlers_thread::thread_create(conn, id, params).await,
        "thread.update" => handlers_thread::thread_update(conn, id, params).await,
        "thread.delete" => handlers_thread::thread_delete(conn, id, params).await,
        "thread.list" => handlers_thread::thread_list(conn, id, params).await,

        // Message
        "message.append" => handlers_message::message_append(conn, id, params).await,
        "message.list" => handlers_message::message_list(conn, id, params).await,

        // Activity
        "activity.append" => handlers_message::activity_append(conn, id, params).await,
        "activity.list" => handlers_message::activity_list(conn, id, params).await,

        // Session
        "session.upsert" => handlers_session::session_upsert(conn, id, params).await,
        "session.get" => handlers_session::session_get(conn, id, params).await,

        // Search
        "search.keyword" => handlers_session::search_keyword(conn, id, params).await,
        "search.vector" => handlers_session::search_vector(conn, id, params).await,

        // Export
        "export.markdown" => handlers_session::export_markdown(conn, id, params).await,
        "export.json" => handlers_session::export_json(conn, id, params).await,

        // Maintenance
        "maintenance.cleanup" => handlers_session::maintenance_cleanup(conn, id, params).await,

        // F049 — File comments
        "comment.add" => handlers_comments::comment_add(conn, id, params).await,
        "comment.list" => handlers_comments::comment_list(conn, id, params).await,
        "comment.update" => handlers_comments::comment_update(conn, id, params).await,
        "comment.resolve" => handlers_comments::comment_resolve(conn, id, params).await,
        "comment.delete" => handlers_comments::comment_delete(conn, id, params).await,
        "comment.relocate" => handlers_comments::comment_relocate(conn, id, params).await,
        "comment.search" => handlers_comments::comment_search(conn, id, params).await,
        "comment.movePath" => handlers_comments::comment_move_path(conn, id, params).await,

        // F053 — Quick todos & sticky notes
        "todo.add" => handlers_todos::todo_add(conn, id, params).await,
        "todo.list" => handlers_todos::todo_list(conn, id, params).await,
        "todo.update" => handlers_todos::todo_update(conn, id, params).await,
        "todo.complete" => handlers_todos::todo_complete(conn, id, params).await,
        "todo.delete" => handlers_todos::todo_delete(conn, id, params).await,
        "todo.show" => handlers_todos::todo_show(conn, id, params).await,
        "todo.message.add" => handlers_todos::todo_message_add(conn, id, params).await,
        "todo.message.list" => handlers_todos::todo_message_list(conn, id, params).await,

        // F060 — Todo lane pipeline
        "todo.file.add" => handlers_todos::todo_file_add(conn, id, params).await,
        "todo.file.remove" => handlers_todos::todo_file_remove(conn, id, params).await,
        "todo.file.list" => handlers_todos::todo_file_list(conn, id, params).await,
        "todo.pipeline.set" => handlers_todos::todo_pipeline_set(conn, id, params).await,

        // Board stubs
        m if m.starts_with("board.") => handlers_board::stub(id, m),

        // Unknown
        m => Response::method_not_found(id, m),
    }
}

fn write_response(out: &mut std::io::BufWriter<std::io::StdoutLock<'_>>, resp: &Response) {
    if let Ok(json) = serde_json::to_string(resp) {
        let _ = out.write_all(json.as_bytes());
        let _ = out.write_all(b"\n");
        let _ = out.flush();
    }
}

#[cfg(any(target_os = "macos", target_os = "ios", target_os = "freebsd"))]
fn apply_process_name() {
    let Ok(name) = CString::new(PROCESS_NAME) else { return };
    unsafe { libc::setprogname(name.as_ptr()) };
}

#[cfg(target_os = "linux")]
fn apply_process_name() {
    let truncated: String = PROCESS_NAME.chars().take(15).collect();
    let Ok(name) = CString::new(truncated) else { return };
    unsafe { libc::prctl(libc::PR_SET_NAME, name.as_ptr() as libc::c_ulong, 0, 0, 0) };
}

#[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "freebsd", target_os = "linux")))]
fn apply_process_name() {}
