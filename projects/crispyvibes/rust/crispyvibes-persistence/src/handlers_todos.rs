//! F053 quick todos & sticky notes — RPC handlers.
//!
//! Todo records live in the same encrypted libSQL DB as conversations and
//! comments, scoped per-vibespace by `vibespace_id` and optionally per-project
//! by `project_path` (NULL = vibespace-level). `due_at`/`reminder_at` columns
//! are reserved for the later reminders phase and are not written in v1.

use anyhow::{anyhow, bail, Result};
use libsql::Connection;
use serde_json::{json, Value};

use crate::rpc::Response;
use crate::util::now_iso;

const MAX_TITLE_CHARS: usize = 500;
const MAX_BODY_CHARS: usize = 10_000;

// --- todo.add ---

pub async fn todo_add(conn: &Connection, id: String, params: Value) -> Response {
    match do_todo_add(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_todo_add(conn: &Connection, p: &Value) -> Result<Value> {
    let todo_id = p["id"].as_str().ok_or_else(|| anyhow!("id required"))?;
    let vibespace_id = p["vibespaceId"]
        .as_str()
        .ok_or_else(|| anyhow!("vibespaceId required"))?;
    let title = p["title"].as_str().ok_or_else(|| anyhow!("title required"))?;
    if title.trim().is_empty() {
        bail!("title must not be empty");
    }
    if title.chars().count() > MAX_TITLE_CHARS {
        bail!("limit_exceeded: title exceeds {} characters", MAX_TITLE_CHARS);
    }
    let project_path = p["projectPath"].as_str();
    let body = p["body"].as_str();
    if let Some(b) = body {
        if b.chars().count() > MAX_BODY_CHARS {
            bail!("limit_exceeded: body exceeds {} characters", MAX_BODY_CHARS);
        }
    }
    let color_tag = p["colorTag"].as_str();
    let file_path = p["filePath"].as_str();
    let ts = now_iso();

    conn.execute(
        "INSERT INTO todos (id, vibespace_id, project_path, title, body, color_tag, file_path, status, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'active', ?8, ?9)",
        libsql::params![todo_id, vibespace_id, project_path, title, body, color_tag, file_path, ts.clone(), ts.clone()],
    )
    .await?;

    Ok(json!({
        "id": todo_id,
        "vibespaceId": vibespace_id,
        "projectPath": project_path,
        "title": title,
        "body": body,
        "colorTag": color_tag,
        "filePath": file_path,
        "status": "active",
        "dueAt": null,
        "reminderAt": null,
        "createdAt": ts.clone(),
        "updatedAt": ts,
        "completedAt": null,
    }))
}

// --- todo.list ---

pub async fn todo_list(conn: &Connection, id: String, params: Value) -> Response {
    match do_todo_list(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_todo_list(conn: &Connection, p: &Value) -> Result<Value> {
    let vibespace_id = p["vibespaceId"]
        .as_str()
        .ok_or_else(|| anyhow!("vibespaceId required"))?;
    let project_path = p["projectPath"].as_str();
    let status = p["status"].as_str().unwrap_or("all");

    let mut where_clauses = vec!["vibespace_id = ?1".to_string()];
    let mut params_vec: Vec<libsql::Value> = vec![vibespace_id.into()];

    if let Some(pp) = project_path {
        params_vec.push(pp.into());
        where_clauses.push(format!("project_path = ?{}", params_vec.len()));
    }
    match status {
        "active" => where_clauses.push("status = 'active'".to_string()),
        "completed" => where_clauses.push("status = 'completed'".to_string()),
        "all" => {}
        _ => bail!("status must be one of: active, completed, all"),
    }

    let sql = format!(
        "SELECT id, vibespace_id, project_path, title, body, color_tag, file_path, status,
                due_at, reminder_at, created_at, updated_at, completed_at
         FROM todos WHERE {} ORDER BY updated_at DESC",
        where_clauses.join(" AND ")
    );

    let mut rows = conn.query(&sql, libsql::params_from_iter(params_vec)).await?;
    let mut out = Vec::new();
    while let Some(row) = rows.next().await? {
        out.push(row_to_todo_value(&row)?);
    }
    Ok(json!({ "todos": out }))
}

fn row_to_todo_value(row: &libsql::Row) -> Result<Value> {
    Ok(json!({
        "id": row.get::<String>(0)?,
        "vibespaceId": row.get::<String>(1)?,
        "projectPath": row.get::<Option<String>>(2)?,
        "title": row.get::<String>(3)?,
        "body": row.get::<Option<String>>(4)?,
        "colorTag": row.get::<Option<String>>(5)?,
        "filePath": row.get::<Option<String>>(6)?,
        "status": row.get::<String>(7)?,
        "dueAt": row.get::<Option<String>>(8)?,
        "reminderAt": row.get::<Option<String>>(9)?,
        "createdAt": row.get::<String>(10)?,
        "updatedAt": row.get::<String>(11)?,
        "completedAt": row.get::<Option<String>>(12)?,
    }))
}

// --- todo.update ---

pub async fn todo_update(conn: &Connection, id: String, params: Value) -> Response {
    match do_todo_update(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_todo_update(conn: &Connection, p: &Value) -> Result<Value> {
    let todo_id = p["id"].as_str().ok_or_else(|| anyhow!("id required"))?;

    let mut sets: Vec<String> = Vec::new();
    let mut vals: Vec<libsql::Value> = Vec::new();

    if let Some(title) = p["title"].as_str() {
        if title.trim().is_empty() {
            bail!("title must not be empty");
        }
        if title.chars().count() > MAX_TITLE_CHARS {
            bail!("limit_exceeded: title exceeds {} characters", MAX_TITLE_CHARS);
        }
        vals.push(title.into());
        sets.push(format!("title = ?{}", vals.len()));
    }
    if let Some(body) = p["body"].as_str() {
        if body.chars().count() > MAX_BODY_CHARS {
            bail!("limit_exceeded: body exceeds {} characters", MAX_BODY_CHARS);
        }
        vals.push(body.into());
        sets.push(format!("body = ?{}", vals.len()));
    }
    if let Some(color) = p["colorTag"].as_str() {
        vals.push(color.into());
        sets.push(format!("color_tag = ?{}", vals.len()));
    }
    if let Some(file) = p["filePath"].as_str() {
        vals.push(file.into());
        sets.push(format!("file_path = ?{}", vals.len()));
    }

    if sets.is_empty() {
        bail!("no updatable fields provided");
    }

    let ts = now_iso();
    vals.push(ts.clone().into());
    sets.push(format!("updated_at = ?{}", vals.len()));

    vals.push(todo_id.into());
    let sql = format!("UPDATE todos SET {} WHERE id = ?{}", sets.join(", "), vals.len());

    let affected = conn.execute(&sql, libsql::params_from_iter(vals)).await?;
    if affected == 0 {
        bail!("todo not found: {}", todo_id);
    }
    Ok(json!({ "id": todo_id, "updatedAt": ts }))
}

// --- todo.complete ---

pub async fn todo_complete(conn: &Connection, id: String, params: Value) -> Response {
    match do_todo_complete(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_todo_complete(conn: &Connection, p: &Value) -> Result<Value> {
    let todo_id = p["id"].as_str().ok_or_else(|| anyhow!("id required"))?;
    let completed = p["completed"].as_bool().unwrap_or(true);
    let ts = now_iso();
    let (status, completed_at): (&str, Option<&str>) = if completed {
        ("completed", Some(ts.as_str()))
    } else {
        ("active", None)
    };

    let affected = conn
        .execute(
            "UPDATE todos SET status = ?1, completed_at = ?2, updated_at = ?3 WHERE id = ?4",
            libsql::params![status, completed_at, ts.clone(), todo_id],
        )
        .await?;
    if affected == 0 {
        bail!("todo not found: {}", todo_id);
    }
    Ok(json!({ "id": todo_id, "status": status, "completedAt": completed_at, "updatedAt": ts }))
}

// --- todo.delete ---

pub async fn todo_delete(conn: &Connection, id: String, params: Value) -> Response {
    match do_todo_delete(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_todo_delete(conn: &Connection, p: &Value) -> Result<Value> {
    let todo_id = p["id"].as_str().ok_or_else(|| anyhow!("id required"))?;
    let affected = conn
        .execute("DELETE FROM todos WHERE id = ?1", libsql::params![todo_id])
        .await?;
    Ok(json!({ "id": todo_id, "deletedCount": affected as i64 }))
}

// --- todo.show (todo + thread messages) ---

pub async fn todo_show(conn: &Connection, id: String, params: Value) -> Response {
    match do_todo_show(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_todo_show(conn: &Connection, p: &Value) -> Result<Value> {
    let todo_id = p["id"].as_str().ok_or_else(|| anyhow!("id required"))?;
    let todo = fetch_todo(conn, todo_id)
        .await?
        .ok_or_else(|| anyhow!("todo not found: {}", todo_id))?;
    let messages = list_messages(conn, todo_id).await?;
    let mut obj = todo.as_object().cloned().unwrap_or_default();
    obj.insert("messages".to_string(), Value::Array(messages));
    Ok(Value::Object(obj))
}

async fn fetch_todo(conn: &Connection, todo_id: &str) -> Result<Option<Value>> {
    let sql = "SELECT id, vibespace_id, project_path, title, body, color_tag, file_path, status,
                      due_at, reminder_at, created_at, updated_at, completed_at
               FROM todos WHERE id = ?1";
    let mut rows = conn.query(sql, libsql::params![todo_id]).await?;
    match rows.next().await? {
        Some(row) => Ok(Some(row_to_todo_value(&row)?)),
        None => Ok(None),
    }
}

// --- todo.message.add ---

pub async fn todo_message_add(conn: &Connection, id: String, params: Value) -> Response {
    match do_todo_message_add(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_todo_message_add(conn: &Connection, p: &Value) -> Result<Value> {
    let msg_id = p["id"].as_str().ok_or_else(|| anyhow!("id required"))?;
    let todo_id = p["todoId"].as_str().ok_or_else(|| anyhow!("todoId required"))?;
    let body = p["body"].as_str().ok_or_else(|| anyhow!("body required"))?;
    if body.trim().is_empty() {
        bail!("body must not be empty");
    }
    if body.chars().count() > MAX_BODY_CHARS {
        bail!("limit_exceeded: body exceeds {} characters", MAX_BODY_CHARS);
    }
    let author_kind = p["authorKind"].as_str().unwrap_or("user");
    if author_kind != "user" && author_kind != "agent" {
        bail!("authorKind must be 'user' or 'agent'");
    }
    let ts = now_iso();
    // Foreign key (ON DELETE CASCADE, PRAGMA foreign_keys=ON) rejects orphans.
    conn.execute(
        "INSERT INTO todo_messages (id, todo_id, body, author_kind, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        libsql::params![msg_id, todo_id, body, author_kind, ts.clone(), ts.clone()],
    )
    .await?;
    // Bump the parent todo's updated_at so it surfaces in the list.
    conn.execute(
        "UPDATE todos SET updated_at = ?1 WHERE id = ?2",
        libsql::params![ts.clone(), todo_id],
    )
    .await?;
    Ok(json!({
        "id": msg_id,
        "todoId": todo_id,
        "body": body,
        "authorKind": author_kind,
        "createdAt": ts.clone(),
        "updatedAt": ts,
    }))
}

// --- todo.message.list ---

pub async fn todo_message_list(conn: &Connection, id: String, params: Value) -> Response {
    match do_todo_message_list(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_todo_message_list(conn: &Connection, p: &Value) -> Result<Value> {
    let todo_id = p["todoId"].as_str().ok_or_else(|| anyhow!("todoId required"))?;
    Ok(json!({ "messages": list_messages(conn, todo_id).await? }))
}

async fn list_messages(conn: &Connection, todo_id: &str) -> Result<Vec<Value>> {
    let sql = "SELECT id, todo_id, body, author_kind, created_at, updated_at
               FROM todo_messages WHERE todo_id = ?1 ORDER BY created_at ASC";
    let mut rows = conn.query(sql, libsql::params![todo_id]).await?;
    let mut out = Vec::new();
    while let Some(row) = rows.next().await? {
        out.push(json!({
            "id": row.get::<String>(0)?,
            "todoId": row.get::<String>(1)?,
            "body": row.get::<String>(2)?,
            "authorKind": row.get::<String>(3)?,
            "createdAt": row.get::<String>(4)?,
            "updatedAt": row.get::<String>(5)?,
        }));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn test_conn() -> Connection {
        let db = libsql::Builder::new_local(":memory:").build().await.unwrap();
        let conn = db.connect().unwrap();
        crate::schema::run_migrations(&conn).await.unwrap();
        conn
    }

    #[tokio::test]
    async fn add_list_complete_delete_roundtrip() {
        let conn = test_conn().await;

        let added = do_todo_add(
            &conn,
            &json!({"id": "t1", "vibespaceId": "vs1", "projectPath": "/proj", "title": "Ship F053"}),
        )
        .await
        .unwrap();
        assert_eq!(added["title"], "Ship F053");
        assert_eq!(added["status"], "active");

        // vibespace-level todo (no project)
        do_todo_add(&conn, &json!({"id": "t2", "vibespaceId": "vs1", "title": "Vibespace note"}))
            .await
            .unwrap();

        let active = do_todo_list(&conn, &json!({"vibespaceId": "vs1", "status": "active"}))
            .await
            .unwrap();
        assert_eq!(active["todos"].as_array().unwrap().len(), 2);

        // project filter excludes the vibespace-level todo
        let proj = do_todo_list(
            &conn,
            &json!({"vibespaceId": "vs1", "projectPath": "/proj", "status": "all"}),
        )
        .await
        .unwrap();
        assert_eq!(proj["todos"].as_array().unwrap().len(), 1);

        // complete t1 → drops out of the active list
        do_todo_complete(&conn, &json!({"id": "t1", "completed": true})).await.unwrap();
        let still_active = do_todo_list(&conn, &json!({"vibespaceId": "vs1", "status": "active"}))
            .await
            .unwrap();
        assert_eq!(still_active["todos"].as_array().unwrap().len(), 1);

        // update title
        let upd = do_todo_update(&conn, &json!({"id": "t2", "title": "Renamed"})).await.unwrap();
        assert_eq!(upd["id"], "t2");

        // delete t1
        let del = do_todo_delete(&conn, &json!({"id": "t1"})).await.unwrap();
        assert_eq!(del["deletedCount"], 1);

        let all = do_todo_list(&conn, &json!({"vibespaceId": "vs1", "status": "all"}))
            .await
            .unwrap();
        assert_eq!(all["todos"].as_array().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn add_requires_title() {
        let conn = test_conn().await;
        let err = do_todo_add(&conn, &json!({"id": "x", "vibespaceId": "vs1", "title": "  "}))
            .await
            .unwrap_err();
        assert!(err.to_string().contains("title must not be empty"));
    }

    #[tokio::test]
    async fn thread_messages_roundtrip_and_cascade() {
        let conn = test_conn().await;
        do_todo_add(&conn, &json!({"id": "t1", "vibespaceId": "vs1", "title": "Ship it"}))
            .await
            .unwrap();

        do_todo_message_add(&conn, &json!({"id": "m1", "todoId": "t1", "body": "first"}))
            .await
            .unwrap();
        do_todo_message_add(&conn, &json!({"id": "m2", "todoId": "t1", "body": "second", "authorKind": "agent"}))
            .await
            .unwrap();

        // todo.show returns the todo with its ordered thread.
        let shown = do_todo_show(&conn, &json!({"id": "t1"})).await.unwrap();
        assert_eq!(shown["title"], "Ship it");
        let msgs = shown["messages"].as_array().unwrap();
        assert_eq!(msgs.len(), 2);
        assert_eq!(msgs[0]["body"], "first");
        assert_eq!(msgs[1]["authorKind"], "agent");

        // Orphan message is rejected by the FK.
        assert!(do_todo_message_add(&conn, &json!({"id": "m3", "todoId": "missing", "body": "x"}))
            .await
            .is_err());

        // Deleting the todo cascades to its messages.
        do_todo_delete(&conn, &json!({"id": "t1"})).await.unwrap();
        let after = do_todo_message_list(&conn, &json!({"todoId": "t1"})).await.unwrap();
        assert_eq!(after["messages"].as_array().unwrap().len(), 0);
    }
}
