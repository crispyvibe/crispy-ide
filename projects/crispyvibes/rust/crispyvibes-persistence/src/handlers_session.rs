use anyhow::Result;
use libsql::Connection;
use serde_json::{json, Value};

use crate::rpc::Response;
use crate::util::now_iso;

// --- Sessions ---

pub async fn session_upsert(conn: &Connection, id: String, params: Value) -> Response {
    match do_session_upsert(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_session_upsert(conn: &Connection, p: &Value) -> Result<Value> {
    let thread_id = p["threadId"].as_str().unwrap_or_default();
    let provider = p["provider"].as_str().unwrap_or_default();
    let transport_kind = p["transportKind"].as_str().unwrap_or_default();
    let status = p["status"].as_str().unwrap_or("disconnected");
    let resume_strategy = p["resumeStrategy"].as_str().unwrap_or("none");
    let capabilities = p["capabilities"].as_str();
    let provider_session_id = p["providerSessionId"].as_str();
    let resume_cursor_json = p["resumeCursorJson"].as_str();
    let runtime_mode = p["runtimeMode"].as_str().unwrap_or("direct");
    let ts = now_iso();

    conn.execute(
        "INSERT INTO sessions (thread_id, provider, transport_kind, status, resume_strategy, capabilities, provider_session_id, resume_cursor_json, runtime_mode, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
         ON CONFLICT(thread_id) DO UPDATE SET
            provider = excluded.provider, transport_kind = excluded.transport_kind,
            status = excluded.status, resume_strategy = excluded.resume_strategy,
            capabilities = excluded.capabilities, provider_session_id = excluded.provider_session_id,
            resume_cursor_json = excluded.resume_cursor_json, runtime_mode = excluded.runtime_mode,
            updated_at = excluded.updated_at",
        libsql::params![thread_id, provider, transport_kind, status, resume_strategy, capabilities, provider_session_id, resume_cursor_json, runtime_mode, ts],
    ).await?;

    Ok(json!({"ok": true}))
}

pub async fn session_get(conn: &Connection, id: String, params: Value) -> Response {
    match do_session_get(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_session_get(conn: &Connection, p: &Value) -> Result<Value> {
    let thread_id = p["threadId"].as_str().unwrap_or_default();

    let mut rows = conn.query(
        "SELECT thread_id, provider, transport_kind, status, resume_strategy, capabilities, provider_session_id, resume_cursor_json, runtime_mode, updated_at
         FROM sessions WHERE thread_id = ?1",
        libsql::params![thread_id],
    ).await?;

    match rows.next().await? {
        Some(row) => Ok(json!({
            "threadId": row.get::<String>(0)?,
            "provider": row.get::<String>(1)?,
            "transportKind": row.get::<String>(2)?,
            "status": row.get::<String>(3)?,
            "resumeStrategy": row.get::<String>(4)?,
            "capabilities": row.get::<Option<String>>(5)?,
            "providerSessionId": row.get::<Option<String>>(6)?,
            "resumeCursorJson": row.get::<Option<String>>(7)?,
            "runtimeMode": row.get::<String>(8)?,
            "updatedAt": row.get::<String>(9)?,
        })),
        None => Ok(json!(null)),
    }
}

// --- Search ---

pub async fn search_keyword(conn: &Connection, id: String, params: Value) -> Response {
    match do_search_keyword(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_search_keyword(conn: &Connection, p: &Value) -> Result<Value> {
    let query = p["query"].as_str().unwrap_or_default();
    let workspace_id = p["workspaceId"].as_str();
    let limit = p["limit"].as_i64().unwrap_or(50);

    if query.is_empty() {
        return Ok(json!({"matches": []}));
    }

    let (sql, params): (String, Vec<libsql::Value>) = if let Some(ws) = workspace_id {
        (
            format!(
                "SELECT m.thread_id, m.id, snippet(message_fts, 0, '<b>', '</b>', '...', 32) as snip,
                        t.title, bm25(message_fts) as rank, t.agent_id, t.project_path, t.updated_at
                 FROM message_fts
                 JOIN messages m ON m.rowid = message_fts.rowid
                 JOIN threads t ON t.id = m.thread_id
                 WHERE message_fts MATCH ?1 AND t.workspace_id = ?2
                 ORDER BY rank LIMIT {limit}"
            ),
            vec![query.into(), ws.into()],
        )
    } else {
        (
            format!(
                "SELECT m.thread_id, m.id, snippet(message_fts, 0, '<b>', '</b>', '...', 32) as snip,
                        t.title, bm25(message_fts) as rank, t.agent_id, t.project_path, t.updated_at
                 FROM message_fts
                 JOIN messages m ON m.rowid = message_fts.rowid
                 JOIN threads t ON t.id = m.thread_id
                 WHERE message_fts MATCH ?1
                 ORDER BY rank LIMIT {limit}"
            ),
            vec![query.into()],
        )
    };

    let mut rows = conn.query(&sql, libsql::params_from_iter(params)).await?;
    let mut matches = Vec::new();

    while let Some(row) = rows.next().await? {
        matches.push(json!({
            "threadId": row.get::<String>(0)?,
            "messageId": row.get::<String>(1)?,
            "snippet": row.get::<String>(2)?,
            "threadTitle": row.get::<String>(3)?,
            "rank": row.get::<f64>(4)?,
            "agentId": row.get::<String>(5)?,
            "projectPath": row.get::<String>(6)?,
            "updatedAt": row.get::<String>(7)?,
        }));
    }

    Ok(json!({"matches": matches}))
}

pub async fn search_vector(conn: &Connection, id: String, params: Value) -> Response {
    match do_search_vector(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_search_vector(conn: &Connection, p: &Value) -> Result<Value> {
    let embedding = &p["embedding"];
    let limit = p["limit"].as_i64().unwrap_or(20);

    if !embedding.is_array() {
        return Ok(json!({"matches": []}));
    }

    let vec_str = embedding.to_string();

    let mut rows = conn.query(
        &format!(
            "SELECT me.message_id, m.thread_id, m.text, t.title,
                    vector_distance_cos(me.embedding, vector(?1)) as dist
             FROM message_embeddings me
             JOIN messages m ON m.id = me.message_id
             JOIN threads t ON t.id = m.thread_id
             ORDER BY dist ASC LIMIT {limit}"
        ),
        libsql::params![vec_str],
    ).await?;

    let mut matches = Vec::new();
    while let Some(row) = rows.next().await? {
        let text: String = row.get(2)?;
        let snippet: String = text.chars().take(200).collect();
        matches.push(json!({
            "messageId": row.get::<String>(0)?,
            "threadId": row.get::<String>(1)?,
            "snippet": snippet,
            "threadTitle": row.get::<String>(3)?,
            "distance": row.get::<f64>(4)?,
        }));
    }

    Ok(json!({"matches": matches}))
}

// --- Export ---

pub async fn export_markdown(conn: &Connection, id: String, params: Value) -> Response {
    match do_export_markdown(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_export_markdown(conn: &Connection, p: &Value) -> Result<Value> {
    let thread_id = p["threadId"].as_str().unwrap_or_default();

    // Get thread title
    let mut rows = conn.query("SELECT title FROM threads WHERE id = ?1", libsql::params![thread_id]).await?;
    let title = match rows.next().await? {
        Some(row) => row.get::<String>(0)?,
        None => return Ok(json!({"markdown": ""})),
    };

    // Get all messages (no cap)
    let mut rows = conn.query(
        "SELECT role, text, created_at FROM messages WHERE thread_id = ?1 ORDER BY sequence ASC",
        libsql::params![thread_id],
    ).await?;

    let mut md = format!("# {title}\n\n");
    while let Some(row) = rows.next().await? {
        let role: String = row.get(0)?;
        let text: String = row.get(1)?;
        let ts: String = row.get(2)?;
        let label = match role.as_str() {
            "user" => "User",
            "assistant" => "Assistant",
            _ => "System",
        };
        md.push_str(&format!("**{label}** ({ts}):\n{text}\n\n---\n\n"));
    }

    Ok(json!({"markdown": md}))
}

pub async fn export_json(conn: &Connection, id: String, params: Value) -> Response {
    match do_export_json(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_export_json(conn: &Connection, p: &Value) -> Result<Value> {
    let thread_id = p["threadId"].as_str().unwrap_or_default();

    // Thread
    let mut rows = conn.query(
        "SELECT id, workspace_id, project_path, title, agent_id, transport_kind, model, thread_kind, metadata, tags, created_at, updated_at
         FROM threads WHERE id = ?1",
        libsql::params![thread_id],
    ).await?;
    let thread = match rows.next().await? {
        Some(row) => json!({
            "id": row.get::<String>(0)?, "workspaceId": row.get::<String>(1)?,
            "projectPath": row.get::<String>(2)?, "title": row.get::<String>(3)?,
            "agentId": row.get::<String>(4)?, "transportKind": row.get::<String>(5)?,
            "model": row.get::<String>(6)?, "threadKind": row.get::<String>(7)?,
            "metadata": row.get::<String>(8)?, "tags": row.get::<String>(9)?,
            "createdAt": row.get::<String>(10)?, "updatedAt": row.get::<String>(11)?,
        }),
        None => return Ok(json!({"thread": null, "messages": [], "activities": []})),
    };

    // All messages (no cap)
    let mut rows = conn.query(
        "SELECT id, turn_id, role, text, sequence, created_at FROM messages WHERE thread_id = ?1 ORDER BY sequence ASC",
        libsql::params![thread_id],
    ).await?;
    let mut messages = Vec::new();
    while let Some(row) = rows.next().await? {
        messages.push(json!({
            "id": row.get::<String>(0)?, "turnId": row.get::<Option<String>>(1)?,
            "role": row.get::<String>(2)?, "text": row.get::<String>(3)?,
            "sequence": row.get::<i64>(4)?, "createdAt": row.get::<String>(5)?,
        }));
    }

    // All activities
    let mut rows = conn.query(
        "SELECT id, turn_id, kind, summary, payload_json, sequence, created_at FROM activities WHERE thread_id = ?1 ORDER BY sequence ASC",
        libsql::params![thread_id],
    ).await?;
    let mut activities = Vec::new();
    while let Some(row) = rows.next().await? {
        activities.push(json!({
            "id": row.get::<String>(0)?, "turnId": row.get::<Option<String>>(1)?,
            "kind": row.get::<String>(2)?, "summary": row.get::<String>(3)?,
            "payloadJson": row.get::<Option<String>>(4)?, "sequence": row.get::<i64>(5)?,
            "createdAt": row.get::<String>(6)?,
        }));
    }

    Ok(json!({"thread": thread, "messages": messages, "activities": activities}))
}

// --- Maintenance ---

pub async fn maintenance_cleanup(conn: &Connection, id: String, params: Value) -> Response {
    match do_cleanup(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_cleanup(conn: &Connection, p: &Value) -> Result<Value> {
    let retention_days = p["retentionDays"].as_i64();

    let days = match retention_days {
        Some(d) if d > 0 => d,
        _ => return Ok(json!({"deletedThreads": 0, "deletedMessages": 0})),
    };

    // Count before delete
    let mut rows = conn.query(
        &format!(
            "SELECT COUNT(*) FROM threads WHERE updated_at < datetime('now', '-{days} days')"
        ),
        (),
    ).await?;
    let thread_count: i64 = match rows.next().await? {
        Some(row) => row.get(0)?,
        None => 0,
    };

    let mut rows = conn.query(
        &format!(
            "SELECT COUNT(*) FROM messages WHERE thread_id IN (SELECT id FROM threads WHERE updated_at < datetime('now', '-{days} days'))"
        ),
        (),
    ).await?;
    let msg_count: i64 = match rows.next().await? {
        Some(row) => row.get(0)?,
        None => 0,
    };

    // Cascade delete
    conn.execute(
        &format!("DELETE FROM threads WHERE updated_at < datetime('now', '-{days} days')"),
        (),
    ).await?;

    Ok(json!({"deletedThreads": thread_count, "deletedMessages": msg_count}))
}
