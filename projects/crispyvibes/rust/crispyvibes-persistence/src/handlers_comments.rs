//! F049 file comments — RPC handlers.
//!
//! All comment data lives in the same encrypted libSQL DB as conversations,
//! scoped per-vibespace by the `vibespace_id` column. Threading uses
//! `parent_id`. Anchors (line/col + content snapshot) live in a sibling
//! `comment_anchors` table.
//!
//! Limits (F049-R17): 1,000 active comments per file, 10,000 chars per body,
//! depth 50.

use anyhow::{anyhow, bail, Result};
use libsql::Connection;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::rpc::Response;
use crate::util::now_iso;

const MAX_BODY_CHARS: usize = 10_000;
const MAX_ACTIVE_PER_FILE: i64 = 1_000;
const MAX_THREAD_DEPTH: i64 = 50;
const MAX_ANCHOR_TEXT_BYTES: usize = 4 * 1024;
const MAX_CONTEXT_BYTES: usize = 64;

/// Sanitize markdown body — strips raw `<script>`/`<iframe>`/etc. and
/// `javascript:` URI schemes. Defense-in-depth alongside the SwiftUI
/// `AttributedString(markdown:)` renderer (F049-T01).
fn sanitize_body(input: &str) -> String {
    let mut s = input.to_string();
    let lower = s.to_lowercase();
    let mut bad: Vec<(usize, usize)> = Vec::new();

    // Remove dangerous tag pairs entirely (opening tag through closing tag)
    let dangerous = ["script", "iframe", "object", "embed", "svg", "math"];
    for tag in dangerous {
        let open_needle = format!("<{}", tag);
        let close_needle = format!("</{}>", tag);
        let mut start = 0;
        while let Some(pos) = lower[start..].find(&open_needle) {
            let abs = start + pos;
            // Find the matching closing tag
            if let Some(close_pos) = lower[abs..].find(&close_needle) {
                let end = abs + close_pos + close_needle.len();
                bad.push((abs, end));
                start = end;
            } else {
                // No closing tag — strip from opening tag to end of string
                bad.push((abs, s.len()));
                break;
            }
        }
    }

    // Sort and remove highest-index ranges first to preserve indices
    bad.sort_by(|a, b| b.0.cmp(&a.0));
    for (start, end) in bad {
        if end <= s.len() {
            s.replace_range(start..end, "");
        }
    }

    // Strip javascript: URIs from markdown links: [text](javascript:...)
    let lower2 = s.to_lowercase();
    if lower2.contains("javascript:") {
        let mut out = String::with_capacity(s.len());
        let mut i = 0;
        let bytes = s.as_bytes();
        let lower_bytes = lower2.as_bytes();
        let needle = b"javascript:";
        while i < bytes.len() {
            if i + needle.len() <= bytes.len() && &lower_bytes[i..i + needle.len()] == needle {
                out.push_str("about:blank");
                i += needle.len();
            } else {
                out.push(bytes[i] as char);
                i += 1;
            }
        }
        s = out;
    }

    s
}

fn hash_text(text: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(text.as_bytes());
    let digest = hasher.finalize();
    format!("{:x}", digest)
}

fn truncate_bytes(input: &str, max_bytes: usize) -> String {
    if input.len() <= max_bytes {
        return input.to_string();
    }
    // walk to a UTF-8 boundary
    let mut end = max_bytes;
    while end > 0 && !input.is_char_boundary(end) {
        end -= 1;
    }
    input[..end].to_string()
}

// --- comment.add ---

pub async fn comment_add(conn: &Connection, id: String, params: Value) -> Response {
    match do_comment_add(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_comment_add(conn: &Connection, p: &Value) -> Result<Value> {
    let comment_id = p["id"].as_str().ok_or_else(|| anyhow!("id required"))?;
    let vibespace_id = p["vibespaceId"]
        .as_str()
        .ok_or_else(|| anyhow!("vibespaceId required"))?;
    let file_path = p["filePath"].as_str().ok_or_else(|| anyhow!("filePath required"))?;
    let parent_id = p["parentId"].as_str();
    let raw_body = p["body"].as_str().ok_or_else(|| anyhow!("body required"))?;

    if raw_body.is_empty() {
        bail!("body must not be empty");
    }
    if raw_body.chars().count() > MAX_BODY_CHARS {
        bail!("limit_exceeded: body exceeds {} characters", MAX_BODY_CHARS);
    }

    let body = sanitize_body(raw_body);
    let author_kind = p["authorKind"].as_str().unwrap_or("user");
    if author_kind != "user" && author_kind != "agent" {
        bail!("authorKind must be 'user' or 'agent'");
    }
    let author_label = p["authorLabel"].as_str();

    // F049-v2: surface_kind discriminates file (default) vs browser. file_path
    // doubles as canonical URL for browser surfaces; the Swift side
    // canonicalizes before sending so the helper can treat it as opaque.
    let surface_kind = p["surfaceKind"].as_str().unwrap_or("file");
    if surface_kind != "file" && surface_kind != "browser" {
        bail!("surfaceKind must be 'file' or 'browser'");
    }

    let start_line = p["anchor"]["startLine"].as_i64().unwrap_or(1);
    let start_column = p["anchor"]["startColumn"].as_i64().unwrap_or(1);
    let end_line = p["anchor"]["endLine"].as_i64().unwrap_or(start_line);
    let end_column = p["anchor"]["endColumn"].as_i64().unwrap_or(start_column);

    let anchor_text_raw = p["anchor"]["anchorText"].as_str().unwrap_or("");
    let anchor_text = truncate_bytes(anchor_text_raw, MAX_ANCHOR_TEXT_BYTES);
    let leading_context = truncate_bytes(p["anchor"]["leadingContext"].as_str().unwrap_or(""), MAX_CONTEXT_BYTES);
    let trailing_context = truncate_bytes(p["anchor"]["trailingContext"].as_str().unwrap_or(""), MAX_CONTEXT_BYTES);
    let anchor_hash = p["anchor"]["anchorHash"]
        .as_str()
        .map(|s| s.to_string())
        .unwrap_or_else(|| hash_text(&anchor_text));

    // F049-v2: optional CSS-selector + text-offset anchor for HTML / browser
    // surfaces. Truncated to keep storage bounded; selectors over 1KB are
    // already worse than line-based fallbacks.
    let dom_selector = p["anchor"]["domSelector"]
        .as_str()
        .map(|s| truncate_bytes(s, 1024));
    let dom_text_offset = p["anchor"]["domTextOffset"].as_i64();
    let dom_text_length = p["anchor"]["domTextLength"].as_i64();
    let dom_fingerprint = p["anchor"]["domFingerprint"]
        .as_str()
        .map(|s| s.to_string());

    // Limit checks: per-file active count (top-level only — replies don't count)
    if parent_id.is_none() {
        let mut rows = conn
            .query(
                "SELECT COUNT(*) FROM comments
                 WHERE vibespace_id = ?1 AND file_path = ?2 AND resolved_at IS NULL AND parent_id IS NULL",
                libsql::params![vibespace_id, file_path],
            )
            .await?;
        let count: i64 = match rows.next().await? {
            Some(row) => row.get::<i64>(0)?,
            None => 0,
        };
        if count >= MAX_ACTIVE_PER_FILE {
            bail!(
                "limit_exceeded: file already has {} active comments (max {})",
                count,
                MAX_ACTIVE_PER_FILE
            );
        }
    } else if let Some(pid) = parent_id {
        // Thread depth check — find depth of parent and clamp to MAX_THREAD_DEPTH.
        // Per R17: replies beyond depth 50 attach to depth 50 — i.e., the parent
        // stays at MAX_THREAD_DEPTH-1, the new reply lands at MAX_THREAD_DEPTH.
        let parent_depth = thread_depth(conn, pid).await?;
        if parent_depth >= MAX_THREAD_DEPTH {
            let clamped_parent =
                clamp_parent_to_depth(conn, pid, MAX_THREAD_DEPTH - 1).await?;
            return insert_comment(
                conn,
                InsertCommentParams {
                    id: comment_id,
                    vibespace_id,
                    file_path,
                    parent_id: Some(&clamped_parent),
                    body: &body,
                    author_kind,
                    author_label,
                    surface_kind,
                    anchor: AnchorParams {
                        start_line,
                        start_column,
                        end_line,
                        end_column,
                        anchor_hash: &anchor_hash,
                        anchor_text: &anchor_text,
                        leading_context: &leading_context,
                        trailing_context: &trailing_context,
                        dom_selector: dom_selector.as_deref(),
                        dom_text_offset,
                        dom_text_length,
                        dom_fingerprint: dom_fingerprint.as_deref(),
                    },
                },
            )
            .await;
        }
    }

    insert_comment(
        conn,
        InsertCommentParams {
            id: comment_id,
            vibespace_id,
            file_path,
            parent_id,
            body: &body,
            author_kind,
            author_label,
            surface_kind,
            anchor: AnchorParams {
                start_line,
                start_column,
                end_line,
                end_column,
                anchor_hash: &anchor_hash,
                anchor_text: &anchor_text,
                leading_context: &leading_context,
                trailing_context: &trailing_context,
                dom_selector: dom_selector.as_deref(),
                dom_text_offset,
                dom_text_length,
                dom_fingerprint: dom_fingerprint.as_deref(),
            },
        },
    )
    .await
}

/// F049-v2: parameters for `insert_comment`. Grouping into a struct avoids
/// the previous 16-argument function signature.
struct InsertCommentParams<'a> {
    id: &'a str,
    vibespace_id: &'a str,
    file_path: &'a str,
    parent_id: Option<&'a str>,
    body: &'a str,
    author_kind: &'a str,
    author_label: Option<&'a str>,
    surface_kind: &'a str,
    anchor: AnchorParams<'a>,
}

struct AnchorParams<'a> {
    start_line: i64,
    start_column: i64,
    end_line: i64,
    end_column: i64,
    anchor_hash: &'a str,
    anchor_text: &'a str,
    leading_context: &'a str,
    trailing_context: &'a str,
    dom_selector: Option<&'a str>,
    dom_text_offset: Option<i64>,
    dom_text_length: Option<i64>,
    dom_fingerprint: Option<&'a str>,
}

async fn insert_comment(conn: &Connection, p: InsertCommentParams<'_>) -> Result<Value> {
    let ts = now_iso();

    conn.execute(
        "INSERT INTO comments (id, vibespace_id, file_path, parent_id, body, author_kind, author_label, surface_kind, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
        libsql::params![p.id, p.vibespace_id, p.file_path, p.parent_id, p.body, p.author_kind, p.author_label, p.surface_kind, ts.clone(), ts.clone()],
    ).await?;

    conn.execute(
        "INSERT INTO comment_anchors (comment_id, start_line, start_column, end_line, end_column, anchor_hash, anchor_text, leading_context, trailing_context, dom_selector, dom_text_offset, dom_text_length, dom_fingerprint)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
        libsql::params![
            p.id,
            p.anchor.start_line, p.anchor.start_column, p.anchor.end_line, p.anchor.end_column,
            p.anchor.anchor_hash, p.anchor.anchor_text, p.anchor.leading_context, p.anchor.trailing_context,
            p.anchor.dom_selector, p.anchor.dom_text_offset, p.anchor.dom_text_length, p.anchor.dom_fingerprint
        ],
    ).await?;

    Ok(json!({
        "id": p.id,
        "vibespaceId": p.vibespace_id,
        "filePath": p.file_path,
        "parentId": p.parent_id,
        "body": p.body,
        "authorKind": p.author_kind,
        "authorLabel": p.author_label,
        "surfaceKind": p.surface_kind,
        "createdAt": ts.clone(),
        "updatedAt": ts,
        "resolvedAt": null,
        "isStale": false,
        "anchor": {
            "startLine": p.anchor.start_line,
            "startColumn": p.anchor.start_column,
            "endLine": p.anchor.end_line,
            "endColumn": p.anchor.end_column,
            "anchorHash": p.anchor.anchor_hash,
            "anchorText": p.anchor.anchor_text,
            "leadingContext": p.anchor.leading_context,
            "trailingContext": p.anchor.trailing_context,
            "domSelector": p.anchor.dom_selector,
            "domTextOffset": p.anchor.dom_text_offset,
            "domTextLength": p.anchor.dom_text_length,
            "domFingerprint": p.anchor.dom_fingerprint,
        }
    }))
}

async fn thread_depth(conn: &Connection, comment_id: &str) -> Result<i64> {
    let mut depth = 0i64;
    let mut current = comment_id.to_string();
    while depth < MAX_THREAD_DEPTH + 1 {
        let mut rows = conn
            .query(
                "SELECT parent_id FROM comments WHERE id = ?1",
                libsql::params![current.clone()],
            )
            .await?;
        match rows.next().await? {
            Some(row) => {
                let parent: Option<String> = row.get(0)?;
                match parent {
                    Some(p) => {
                        depth += 1;
                        current = p;
                    }
                    None => return Ok(depth),
                }
            }
            None => return Ok(depth),
        }
    }
    Ok(depth)
}

async fn clamp_parent_to_depth(conn: &Connection, comment_id: &str, target_depth: i64) -> Result<String> {
    let mut current = comment_id.to_string();
    let mut depth = thread_depth(conn, &current).await?;
    while depth > target_depth {
        let mut rows = conn
            .query(
                "SELECT parent_id FROM comments WHERE id = ?1",
                libsql::params![current.clone()],
            )
            .await?;
        match rows.next().await? {
            Some(row) => {
                let parent: Option<String> = row.get(0)?;
                match parent {
                    Some(p) => {
                        current = p;
                        depth -= 1;
                    }
                    None => return Ok(current),
                }
            }
            None => return Ok(current),
        }
    }
    Ok(current)
}

// --- comment.list ---

pub async fn comment_list(conn: &Connection, id: String, params: Value) -> Response {
    match do_comment_list(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_comment_list(conn: &Connection, p: &Value) -> Result<Value> {
    let vibespace_id = p["vibespaceId"]
        .as_str()
        .ok_or_else(|| anyhow!("vibespaceId required"))?;
    let file_path = p["filePath"].as_str();
    let surface_kind = p["surfaceKind"].as_str();
    let status = p["status"].as_str().unwrap_or("all");

    let mut where_clauses = vec!["c.vibespace_id = ?1".to_string()];
    let mut params_vec: Vec<libsql::Value> = vec![vibespace_id.into()];

    if let Some(fp) = file_path {
        params_vec.push(fp.into());
        where_clauses.push(format!("c.file_path = ?{}", params_vec.len()));
    }
    if let Some(sk) = surface_kind {
        params_vec.push(sk.into());
        where_clauses.push(format!("c.surface_kind = ?{}", params_vec.len()));
    }
    match status {
        "active" => where_clauses.push("c.resolved_at IS NULL AND c.is_stale = 0".to_string()),
        "resolved" => where_clauses.push("c.resolved_at IS NOT NULL".to_string()),
        "stale" => where_clauses.push("c.is_stale = 1".to_string()),
        "all" => {}
        _ => bail!("status must be one of: active, resolved, stale, all"),
    }

    let sql = format!(
        "SELECT c.id, c.vibespace_id, c.file_path, c.parent_id, c.body, c.author_kind, c.author_label,
                c.created_at, c.updated_at, c.resolved_at, c.is_stale, c.surface_kind,
                a.start_line, a.start_column, a.end_line, a.end_column, a.anchor_hash, a.anchor_text,
                a.leading_context, a.trailing_context,
                a.dom_selector, a.dom_text_offset, a.dom_text_length, a.dom_fingerprint
         FROM comments c LEFT JOIN comment_anchors a ON a.comment_id = c.id
         WHERE {} ORDER BY c.file_path, c.created_at ASC",
        where_clauses.join(" AND ")
    );

    let mut rows = conn.query(&sql, libsql::params_from_iter(params_vec)).await?;
    let mut out = Vec::new();
    while let Some(row) = rows.next().await? {
        out.push(row_to_comment_value(&row)?);
    }
    Ok(json!({ "comments": out }))
}

fn row_to_comment_value(row: &libsql::Row) -> Result<Value> {
    Ok(json!({
        "id": row.get::<String>(0)?,
        "vibespaceId": row.get::<String>(1)?,
        "filePath": row.get::<String>(2)?,
        "parentId": row.get::<Option<String>>(3)?,
        "body": row.get::<String>(4)?,
        "authorKind": row.get::<String>(5)?,
        "authorLabel": row.get::<Option<String>>(6)?,
        "createdAt": row.get::<String>(7)?,
        "updatedAt": row.get::<String>(8)?,
        "resolvedAt": row.get::<Option<String>>(9)?,
        "isStale": row.get::<i64>(10)? != 0,
        "surfaceKind": row.get::<String>(11)?,
        "anchor": {
            "startLine": row.get::<Option<i64>>(12)?.unwrap_or(1),
            "startColumn": row.get::<Option<i64>>(13)?.unwrap_or(1),
            "endLine": row.get::<Option<i64>>(14)?.unwrap_or(1),
            "endColumn": row.get::<Option<i64>>(15)?.unwrap_or(1),
            "anchorHash": row.get::<Option<String>>(16)?.unwrap_or_default(),
            "anchorText": row.get::<Option<String>>(17)?.unwrap_or_default(),
            "leadingContext": row.get::<Option<String>>(18)?.unwrap_or_default(),
            "trailingContext": row.get::<Option<String>>(19)?.unwrap_or_default(),
            "domSelector": row.get::<Option<String>>(20)?,
            "domTextOffset": row.get::<Option<i64>>(21)?,
            "domTextLength": row.get::<Option<i64>>(22)?,
            "domFingerprint": row.get::<Option<String>>(23)?,
        }
    }))
}

// --- comment.update ---

pub async fn comment_update(conn: &Connection, id: String, params: Value) -> Response {
    match do_comment_update(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_comment_update(conn: &Connection, p: &Value) -> Result<Value> {
    let comment_id = p["id"].as_str().ok_or_else(|| anyhow!("id required"))?;
    let raw_body = p["body"].as_str().ok_or_else(|| anyhow!("body required"))?;

    if raw_body.is_empty() {
        bail!("body must not be empty");
    }
    if raw_body.chars().count() > MAX_BODY_CHARS {
        bail!("limit_exceeded: body exceeds {} characters", MAX_BODY_CHARS);
    }
    let body = sanitize_body(raw_body);
    let ts = now_iso();

    let affected = conn
        .execute(
            "UPDATE comments SET body = ?1, updated_at = ?2 WHERE id = ?3",
            libsql::params![body.clone(), ts.clone(), comment_id],
        )
        .await?;
    if affected == 0 {
        bail!("comment not found: {}", comment_id);
    }
    Ok(json!({ "id": comment_id, "body": body, "updatedAt": ts }))
}

// --- comment.resolve ---

pub async fn comment_resolve(conn: &Connection, id: String, params: Value) -> Response {
    match do_comment_resolve(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_comment_resolve(conn: &Connection, p: &Value) -> Result<Value> {
    let comment_id = p["id"].as_str().ok_or_else(|| anyhow!("id required"))?;
    let unresolve = p["unresolve"].as_bool().unwrap_or(false);
    let ts = now_iso();

    let new_value: Option<&str> = if unresolve { None } else { Some(ts.as_str()) };
    let affected = conn
        .execute(
            "UPDATE comments SET resolved_at = ?1, updated_at = ?2 WHERE id = ?3",
            libsql::params![new_value, ts.clone(), comment_id],
        )
        .await?;
    if affected == 0 {
        bail!("comment not found: {}", comment_id);
    }
    Ok(json!({
        "id": comment_id,
        "resolvedAt": new_value,
    }))
}

// --- comment.delete ---

pub async fn comment_delete(conn: &Connection, id: String, params: Value) -> Response {
    match do_comment_delete(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_comment_delete(conn: &Connection, p: &Value) -> Result<Value> {
    let comment_id = p["id"].as_str().ok_or_else(|| anyhow!("id required"))?;

    // Count before delete (cascade affects descendants via FK ON DELETE CASCADE)
    let mut rows = conn
        .query(
            "WITH RECURSIVE descendants(id) AS (
                 SELECT id FROM comments WHERE id = ?1
                 UNION ALL
                 SELECT c.id FROM comments c JOIN descendants d ON c.parent_id = d.id
             )
             SELECT COUNT(*) FROM descendants",
            libsql::params![comment_id],
        )
        .await?;
    let total: i64 = match rows.next().await? {
        Some(row) => row.get::<i64>(0)?,
        None => 0,
    };

    if total == 0 {
        bail!("comment not found: {}", comment_id);
    }

    conn.execute(
        "DELETE FROM comments WHERE id = ?1",
        libsql::params![comment_id],
    )
    .await?;

    Ok(json!({
        "id": comment_id,
        "deletedCount": total,
    }))
}

// --- comment.relocate ---

pub async fn comment_relocate(conn: &Connection, id: String, params: Value) -> Response {
    match do_comment_relocate(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_comment_relocate(conn: &Connection, p: &Value) -> Result<Value> {
    let comment_id = p["id"].as_str().ok_or_else(|| anyhow!("id required"))?;
    let start_line = p["startLine"].as_i64().ok_or_else(|| anyhow!("startLine required"))?;
    let start_column = p["startColumn"].as_i64().ok_or_else(|| anyhow!("startColumn required"))?;
    let end_line = p["endLine"].as_i64().ok_or_else(|| anyhow!("endLine required"))?;
    let end_column = p["endColumn"].as_i64().ok_or_else(|| anyhow!("endColumn required"))?;
    let is_stale = p["isStale"].as_bool().unwrap_or(false);
    let ts = now_iso();

    conn.execute(
        "UPDATE comment_anchors SET start_line = ?1, start_column = ?2, end_line = ?3, end_column = ?4
         WHERE comment_id = ?5",
        libsql::params![start_line, start_column, end_line, end_column, comment_id],
    )
    .await?;
    let affected = conn
        .execute(
            "UPDATE comments SET is_stale = ?1, updated_at = ?2 WHERE id = ?3",
            libsql::params![is_stale as i64, ts, comment_id],
        )
        .await?;
    if affected == 0 {
        bail!("comment not found: {}", comment_id);
    }
    Ok(json!({ "id": comment_id, "isStale": is_stale }))
}

// --- comment.search ---

pub async fn comment_search(conn: &Connection, id: String, params: Value) -> Response {
    match do_comment_search(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_comment_search(conn: &Connection, p: &Value) -> Result<Value> {
    let vibespace_id = p["vibespaceId"]
        .as_str()
        .ok_or_else(|| anyhow!("vibespaceId required"))?;
    let query = p["query"].as_str().unwrap_or("");
    let file_prefix = p["filePrefix"].as_str();
    let surface_kind = p["surfaceKind"].as_str();
    let status = p["status"].as_str().unwrap_or("all");

    let mut where_clauses = vec!["c.vibespace_id = ?1".to_string()];
    let mut params_vec: Vec<libsql::Value> = vec![vibespace_id.into()];

    if !query.is_empty() {
        // Use FTS5 join
        params_vec.push(query.into());
        where_clauses.push(format!(
            "c.rowid IN (SELECT rowid FROM comment_fts WHERE comment_fts MATCH ?{})",
            params_vec.len()
        ));
    }
    if let Some(prefix) = file_prefix {
        let pattern = format!("{prefix}%");
        params_vec.push(pattern.into());
        where_clauses.push(format!("c.file_path LIKE ?{}", params_vec.len()));
    }
    if let Some(sk) = surface_kind {
        params_vec.push(sk.into());
        where_clauses.push(format!("c.surface_kind = ?{}", params_vec.len()));
    }
    match status {
        "active" => where_clauses.push("c.resolved_at IS NULL AND c.is_stale = 0".to_string()),
        "resolved" => where_clauses.push("c.resolved_at IS NOT NULL".to_string()),
        "stale" => where_clauses.push("c.is_stale = 1".to_string()),
        "all" => {}
        _ => bail!("status must be one of: active, resolved, stale, all"),
    }

    let sql = format!(
        "SELECT c.id, c.vibespace_id, c.file_path, c.parent_id, c.body, c.author_kind, c.author_label,
                c.created_at, c.updated_at, c.resolved_at, c.is_stale, c.surface_kind,
                a.start_line, a.start_column, a.end_line, a.end_column, a.anchor_hash, a.anchor_text,
                a.leading_context, a.trailing_context,
                a.dom_selector, a.dom_text_offset, a.dom_text_length, a.dom_fingerprint
         FROM comments c LEFT JOIN comment_anchors a ON a.comment_id = c.id
         WHERE {} ORDER BY c.file_path, c.created_at ASC LIMIT 500",
        where_clauses.join(" AND ")
    );

    let mut rows = conn.query(&sql, libsql::params_from_iter(params_vec)).await?;
    let mut out = Vec::new();
    while let Some(row) = rows.next().await? {
        out.push(row_to_comment_value(&row)?);
    }
    Ok(json!({ "comments": out }))
}

// --- comment.movePath ---

/// F049-v2 R13: bulk-rewrite the `file_path` column for matching rows. Used
/// by the file-lifecycle service when files are renamed/moved, and by the
/// browser surface when a canonical URL collapses to a different form.
pub async fn comment_move_path(conn: &Connection, id: String, params: Value) -> Response {
    match do_comment_move_path(conn, &params).await {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, -32000, e.to_string()),
    }
}

async fn do_comment_move_path(conn: &Connection, p: &Value) -> Result<Value> {
    let vibespace_id = p["vibespaceId"]
        .as_str()
        .ok_or_else(|| anyhow!("vibespaceId required"))?;
    let old_path = p["oldPath"].as_str().ok_or_else(|| anyhow!("oldPath required"))?;
    let new_path = p["newPath"].as_str().ok_or_else(|| anyhow!("newPath required"))?;
    let surface_kind = p["surfaceKind"].as_str().unwrap_or("file");

    let affected = conn
        .execute(
            "UPDATE comments SET file_path = ?1
             WHERE vibespace_id = ?2 AND file_path = ?3 AND surface_kind = ?4",
            libsql::params![new_path, vibespace_id, old_path, surface_kind],
        )
        .await?;

    Ok(json!({
        "oldPath": old_path,
        "newPath": new_path,
        "movedCount": affected as i64,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_strips_script_tag() {
        let input = "Hello <script>alert(1)</script> world";
        let out = sanitize_body(input);
        assert!(!out.to_lowercase().contains("<script"));
        assert!(out.contains("Hello"));
        assert!(out.contains("world"));
    }

    #[test]
    fn sanitize_strips_iframe() {
        let input = "before <iframe src=\"x\"></iframe> after";
        let out = sanitize_body(input);
        assert!(!out.to_lowercase().contains("<iframe"));
    }

    #[test]
    fn sanitize_replaces_javascript_uri() {
        let input = "[click](javascript:alert(1))";
        let out = sanitize_body(input);
        assert!(!out.to_lowercase().contains("javascript:"));
        assert!(out.contains("about:blank"));
    }

    #[test]
    fn sanitize_preserves_safe_markdown() {
        let input = "**bold** _italic_ `code` and a [link](https://example.com)";
        let out = sanitize_body(input);
        assert_eq!(out, input);
    }

    #[test]
    fn hash_is_deterministic() {
        let a = hash_text("hello");
        let b = hash_text("hello");
        assert_eq!(a, b);
        assert_ne!(a, hash_text("world"));
        // SHA-256 hex is 64 chars
        assert_eq!(a.len(), 64);
    }

    #[test]
    fn truncate_bytes_respects_utf8_boundaries() {
        // "héllo" — 'é' is 2 bytes in UTF-8 (0xC3 0xA9)
        let s = "héllo";
        // truncate at 2 — should give "h" since byte 2 is in middle of 'é'
        let out = truncate_bytes(s, 2);
        assert_eq!(out, "h");
    }
}
