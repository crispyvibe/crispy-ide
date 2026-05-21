use anyhow::Result;
use libsql::Connection;
use serde_json::{json, Value};

use crate::rpc::Response;
use crate::util::now_iso;

// --- Messages ---

pub async fn message_append(conn: &Connection, id: String, params: Value) -> Response {
    match do_message_append(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_message_append(conn: &Connection, p: &Value) -> Result<Value> {
    let msg_id = p["id"].as_str().unwrap_or_default();
    let thread_id = p["threadId"].as_str().unwrap_or_default();
    let turn_id = p["turnId"].as_str();
    let role = p["role"].as_str().unwrap_or("user");
    let text = p["text"].as_str().unwrap_or_default();
    let is_streaming = p["isStreaming"].as_bool().unwrap_or(false) as i64;
    let ts = now_iso();

    // Get next sequence number
    let mut rows = conn.query(
        "SELECT COALESCE(MAX(sequence), 0) FROM messages WHERE thread_id = ?1",
        libsql::params![thread_id],
    ).await?;
    let next_seq: i64 = match rows.next().await? {
        Some(row) => row.get::<i64>(0)? + 1,
        None => 1,
    };

    // Upsert: streaming messages get updated when finalized
    conn.execute(
        "INSERT INTO messages (id, thread_id, turn_id, role, text, is_streaming, sequence, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
         ON CONFLICT(id) DO UPDATE SET text = excluded.text, is_streaming = excluded.is_streaming, updated_at = excluded.updated_at",
        libsql::params![msg_id, thread_id, turn_id, role, text, is_streaming, next_seq, ts.clone(), ts.clone()],
    ).await?;

    // Update thread timestamp
    conn.execute(
        "UPDATE threads SET updated_at = ?1 WHERE id = ?2",
        libsql::params![ts, thread_id],
    ).await?;

    // Store embedding if provided
    if let Some(embedding) = p.get("embedding") {
        if embedding.is_array() {
            if let Some(meta) = p.get("embeddingMeta") {
                let model_id = meta["modelId"].as_str().unwrap_or_default();
                let revision = meta["revision"].as_i64().unwrap_or(0);
                let dimension = meta["dimension"].as_i64().unwrap_or(0);
                let language = meta["language"].as_str().unwrap_or("en");
                let vec_str = embedding.to_string();

                conn.execute(
                    "INSERT INTO message_embeddings (message_id, model_id, revision, dimension, language, embedding)
                     VALUES (?1, ?2, ?3, ?4, ?5, vector(?6))
                     ON CONFLICT(message_id) DO UPDATE SET embedding = excluded.embedding, model_id = excluded.model_id",
                    libsql::params![msg_id, model_id, revision, dimension, language, vec_str],
                ).await?;
            }
        }
    }

    Ok(json!({"ok": true}))
}

pub async fn message_list(conn: &Connection, id: String, params: Value) -> Response {
    match do_message_list(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_message_list(conn: &Connection, p: &Value) -> Result<Value> {
    let thread_id = p["threadId"].as_str().unwrap_or_default();
    let limit = p["limit"].as_i64().unwrap_or(2000);
    let after_seq = p["afterSequence"].as_i64().unwrap_or(0);

    // Return latest N messages by getting the tail
    let mut rows = conn.query(
        "SELECT id, thread_id, turn_id, role, text, is_streaming, sequence, created_at, updated_at
         FROM messages WHERE thread_id = ?1 AND sequence > ?2
         ORDER BY sequence DESC LIMIT ?3",
        libsql::params![thread_id, after_seq, limit],
    ).await?;

    let mut messages = Vec::new();
    while let Some(row) = rows.next().await? {
        messages.push(json!({
            "id": row.get::<String>(0)?,
            "threadId": row.get::<String>(1)?,
            "turnId": row.get::<Option<String>>(2)?,
            "role": row.get::<String>(3)?,
            "text": row.get::<String>(4)?,
            "isStreaming": row.get::<i64>(5)? != 0,
            "sequence": row.get::<i64>(6)?,
            "createdAt": row.get::<String>(7)?,
            "updatedAt": row.get::<String>(8)?,
        }));
    }

    // Reverse to get ascending order
    messages.reverse();
    Ok(json!({"messages": messages}))
}

// --- Activities ---

pub async fn activity_append(conn: &Connection, id: String, params: Value) -> Response {
    match do_activity_append(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_activity_append(conn: &Connection, p: &Value) -> Result<Value> {
    let act_id = p["id"].as_str().unwrap_or_default();
    let thread_id = p["threadId"].as_str().unwrap_or_default();
    let turn_id = p["turnId"].as_str();
    let kind = p["kind"].as_str().unwrap_or_default();
    let item_type = p["itemType"].as_str();
    let summary = p["summary"].as_str().unwrap_or_default();
    let payload_json = p["payloadJson"].as_str();
    let ts = now_iso();

    let mut rows = conn.query(
        "SELECT COALESCE(MAX(sequence), 0) FROM activities WHERE thread_id = ?1",
        libsql::params![thread_id],
    ).await?;
    let next_seq: i64 = match rows.next().await? {
        Some(row) => row.get::<i64>(0)? + 1,
        None => 1,
    };

    conn.execute(
        "INSERT INTO activities (id, thread_id, turn_id, kind, item_type, summary, payload_json, sequence, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
        libsql::params![act_id, thread_id, turn_id, kind, item_type, summary, payload_json, next_seq, ts],
    ).await?;

    Ok(json!({"ok": true}))
}

pub async fn activity_list(conn: &Connection, id: String, params: Value) -> Response {
    match do_activity_list(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_activity_list(conn: &Connection, p: &Value) -> Result<Value> {
    let thread_id = p["threadId"].as_str().unwrap_or_default();
    let turn_id = p["turnId"].as_str();

    let (sql, params): (String, Vec<libsql::Value>) = if let Some(tid) = turn_id {
        (
            "SELECT id, thread_id, turn_id, kind, summary, payload_json, sequence, created_at
             FROM activities WHERE thread_id = ?1 AND turn_id = ?2 ORDER BY sequence ASC".into(),
            vec![thread_id.into(), tid.into()],
        )
    } else {
        (
            "SELECT id, thread_id, turn_id, kind, summary, payload_json, sequence, created_at
             FROM activities WHERE thread_id = ?1 ORDER BY sequence ASC".into(),
            vec![thread_id.into()],
        )
    };

    let mut rows = conn.query(&sql, libsql::params_from_iter(params)).await?;
    let mut activities = Vec::new();

    while let Some(row) = rows.next().await? {
        activities.push(json!({
            "id": row.get::<String>(0)?,
            "threadId": row.get::<String>(1)?,
            "turnId": row.get::<Option<String>>(2)?,
            "kind": row.get::<String>(3)?,
            "summary": row.get::<String>(4)?,
            "payloadJson": row.get::<Option<String>>(5)?,
            "sequence": row.get::<i64>(6)?,
            "createdAt": row.get::<String>(7)?,
        }));
    }

    Ok(json!({"activities": activities}))
}
