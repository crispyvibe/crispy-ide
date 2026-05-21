use anyhow::Result;
use libsql::Connection;
use serde_json::{json, Value};

use crate::rpc::Response;
use crate::util::{now_iso, validate_json_array, validate_json_object};

pub async fn thread_create(conn: &Connection, id: String, params: Value) -> Response {
    match do_thread_create(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_thread_create(conn: &Connection, p: &Value) -> Result<Value> {
    let id = p["id"].as_str().unwrap_or_default();
    let workspace_id = p["workspaceId"].as_str().unwrap_or_default();
    let project_path = p["projectPath"].as_str().unwrap_or_default();
    let title = p["title"].as_str().unwrap_or_default();
    let agent_id = p["agentId"].as_str().unwrap_or_default();
    let transport_kind = p["transportKind"].as_str().unwrap_or_default();
    let model = p["model"].as_str().unwrap_or("");
    let thread_kind = p["threadKind"].as_str().unwrap_or("conversation");
    let parent_thread_id = p["parentThreadId"].as_str();
    let metadata = p["metadata"].as_str().unwrap_or("{}");
    let tags = p["tags"].as_str().unwrap_or("[]");

    validate_json_object(metadata)?;
    validate_json_array(tags)?;

    let ts = now_iso();
    conn.execute(
        "INSERT INTO threads (id, workspace_id, project_path, title, agent_id, transport_kind, model, thread_kind, parent_thread_id, metadata, tags, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
        libsql::params![id, workspace_id, project_path, title, agent_id, transport_kind, model, thread_kind, parent_thread_id, metadata, tags, ts.clone(), ts.clone()],
    ).await?;

    Ok(json!({"id": id, "createdAt": ts}))
}

pub async fn thread_update(conn: &Connection, id: String, params: Value) -> Response {
    match do_thread_update(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_thread_update(conn: &Connection, p: &Value) -> Result<Value> {
    let tid = p["id"].as_str().unwrap_or_default();
    let ts = now_iso();

    if let Some(title) = p["title"].as_str() {
        conn.execute("UPDATE threads SET title = ?1, updated_at = ?2 WHERE id = ?3",
            libsql::params![title, ts.clone(), tid]).await?;
    }
    if let Some(meta) = p["metadata"].as_str() {
        validate_json_object(meta)?;
        conn.execute("UPDATE threads SET metadata = ?1, updated_at = ?2 WHERE id = ?3",
            libsql::params![meta, ts.clone(), tid]).await?;
    }
    if let Some(tags) = p["tags"].as_str() {
        validate_json_array(tags)?;
        conn.execute("UPDATE threads SET tags = ?1, updated_at = ?2 WHERE id = ?3",
            libsql::params![tags, ts.clone(), tid]).await?;
    }
    if p.get("archivedAt").is_some() {
        let archived = p["archivedAt"].as_str();
        conn.execute("UPDATE threads SET archived_at = ?1, updated_at = ?2 WHERE id = ?3",
            libsql::params![archived, ts, tid]).await?;
    }

    Ok(json!({"ok": true}))
}

pub async fn thread_delete(conn: &Connection, id: String, params: Value) -> Response {
    let tid = params["id"].as_str().unwrap_or_default();
    match conn.execute("DELETE FROM threads WHERE id = ?1", libsql::params![tid]).await {
        Ok(_) => Response::ok(id, json!({"ok": true})),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

pub async fn thread_list(conn: &Connection, id: String, params: Value) -> Response {
    match do_thread_list(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_thread_list(conn: &Connection, p: &Value) -> Result<Value> {
    let workspace_id = p["workspaceId"].as_str();
    let include_archived = p["includeArchived"].as_bool().unwrap_or(false);
    let thread_kind = p["threadKind"].as_str();
    let limit = p["limit"].as_i64().unwrap_or(100);
    let offset = p["offset"].as_i64().unwrap_or(0);

    let mut sql = String::from(
        "SELECT id, workspace_id, project_path, title, agent_id, transport_kind, model,
                thread_kind, parent_thread_id, metadata, tags, created_at, updated_at, archived_at
         FROM threads WHERE 1=1"
    );
    let mut bind_values: Vec<Value> = Vec::new();

    if let Some(ws) = workspace_id {
        bind_values.push(json!(ws));
        sql.push_str(&format!(" AND workspace_id = ?{}", bind_values.len()));
    }
    if !include_archived {
        sql.push_str(" AND archived_at IS NULL");
    }
    if let Some(kind) = thread_kind {
        bind_values.push(json!(kind));
        sql.push_str(&format!(" AND thread_kind = ?{}", bind_values.len()));
    }
    sql.push_str(&format!(" ORDER BY updated_at DESC LIMIT {limit} OFFSET {offset}"));

    let params: Vec<libsql::Value> = bind_values.iter().map(|v| {
        libsql::Value::Text(v.as_str().unwrap_or_default().to_string())
    }).collect();

    let mut rows = conn.query(&sql, libsql::params_from_iter(params)).await?;
    let mut threads = Vec::new();

    while let Some(row) = rows.next().await? {
        threads.push(json!({
            "id": row.get::<String>(0)?,
            "workspaceId": row.get::<String>(1)?,
            "projectPath": row.get::<String>(2)?,
            "title": row.get::<String>(3)?,
            "agentId": row.get::<String>(4)?,
            "transportKind": row.get::<String>(5)?,
            "model": row.get::<String>(6)?,
            "threadKind": row.get::<String>(7)?,
            "parentThreadId": row.get::<Option<String>>(8)?,
            "metadata": row.get::<String>(9)?,
            "tags": row.get::<String>(10)?,
            "createdAt": row.get::<String>(11)?,
            "updatedAt": row.get::<String>(12)?,
            "archivedAt": row.get::<Option<String>>(13)?,
        }));
    }

    Ok(json!({"threads": threads}))
}
