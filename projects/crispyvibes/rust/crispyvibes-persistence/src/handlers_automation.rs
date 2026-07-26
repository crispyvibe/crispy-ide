//! Durable Automation persistence for Vibes, Vibe Lanes, tasks, and Loops.
//!
//! Aggregate payloads remain encoded with Swift's Codable schema. SQL owns
//! identity, immutable revisions, lifecycle indexes, relationships, and all
//! multi-entity transactions.

use anyhow::{anyhow, bail, Context, Result};
use libsql::{Connection, Transaction, TransactionBehavior};
use serde_json::{json, Value};

use crate::rpc::Response;
use crate::util::now_iso;

const LEGACY_MIGRATION: &str = "automation-json-to-libsql-v1";

pub async fn snapshot_load(conn: &Connection, id: String) -> Response {
    match do_snapshot_load(conn).await {
        Ok(value) => Response::ok(id, value),
        Err(error) => Response::err(id, -32000, error.to_string()),
    }
}

async fn do_snapshot_load(conn: &Connection) -> Result<Value> {
    Ok(json!({
        "vibes": load_payloads(conn, "SELECT payload_json FROM automation_vibes WHERE is_current = 1 ORDER BY name, id").await?,
        "vibeRevisions": load_payloads(conn, "SELECT payload_json FROM automation_vibes WHERE is_current = 0 ORDER BY id, version").await?,
        "lanes": load_payloads(conn, "SELECT payload_json FROM automation_lanes WHERE is_current = 1 ORDER BY name, id").await?,
        "laneRevisions": load_payloads(conn, "SELECT payload_json FROM automation_lanes WHERE is_current = 0 ORDER BY id, version").await?,
        "laneTombstones": load_strings(conn, "SELECT lane_id FROM automation_lane_tombstones ORDER BY lane_id").await?,
        "tasks": load_payloads(conn, "SELECT payload_json FROM automation_tasks ORDER BY updated_at DESC, id").await?,
        "loopDefinitions": load_payloads(conn, "SELECT payload_json FROM automation_loops ORDER BY updated_at DESC, id").await?,
        "loopRuntimeStates": load_payloads(conn, "SELECT payload_json FROM automation_loop_runtime ORDER BY loop_id").await?,
        "loopRunRecords": load_payloads(conn, "SELECT payload_json FROM automation_loop_runs ORDER BY scheduled_at DESC, id").await?,
        "skillReferences": load_payloads(conn, "SELECT payload_json FROM automation_skill_references ORDER BY reference").await?,
        "legacyMigrationComplete": migration_complete(conn).await?,
    }))
}

pub async fn migration_status(conn: &Connection, id: String) -> Response {
    match migration_complete(conn).await {
        Ok(complete) => Response::ok(
            id,
            json!({
                "name": LEGACY_MIGRATION,
                "complete": complete,
            }),
        ),
        Err(error) => Response::err(id, -32000, error.to_string()),
    }
}

async fn migration_complete(conn: &Connection) -> Result<bool> {
    let mut rows = conn
        .query(
            "SELECT 1 FROM automation_migrations WHERE name = ?1 LIMIT 1",
            libsql::params![LEGACY_MIGRATION],
        )
        .await?;
    Ok(rows.next().await?.is_some())
}

pub async fn migration_import(conn: &Connection, id: String, params: Value) -> Response {
    match do_migration_import(conn, &params).await {
        Ok(value) => Response::ok(id, value),
        Err(error) => Response::err(id, -32000, error.to_string()),
    }
}

async fn do_migration_import(conn: &Connection, params: &Value) -> Result<Value> {
    let transaction = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .await?;

    if transaction_has_migration(&transaction).await? {
        transaction.rollback().await?;
        return Ok(json!({"imported": false, "alreadyComplete": true}));
    }

    ensure_automation_empty(&transaction).await?;

    for payload in array(params, "vibeRevisions")? {
        insert_vibe(&transaction, payload, false, true).await?;
    }
    for payload in array(params, "vibes")? {
        insert_vibe(&transaction, payload, true, true).await?;
    }
    for payload in array(params, "laneRevisions")? {
        insert_lane(&transaction, payload, false, true).await?;
    }
    for payload in array(params, "lanes")? {
        insert_lane(&transaction, payload, true, true).await?;
    }
    for lane_id in string_array(params, "laneTombstones")? {
        transaction
            .execute(
                "INSERT INTO automation_lane_tombstones (lane_id, deleted_at) VALUES (?1, ?2)",
                libsql::params![lane_id, now_iso()],
            )
            .await?;
    }
    for payload in array(params, "tasks")? {
        insert_task(&transaction, payload, true).await?;
    }
    for payload in array(params, "handoffs")? {
        insert_handoff(&transaction, payload).await?;
    }
    for payload in array(params, "loopDefinitions")? {
        insert_loop(&transaction, payload).await?;
    }
    for payload in array(params, "loopRuntimeStates")? {
        insert_loop_runtime(&transaction, payload).await?;
    }
    for payload in array(params, "loopRunRecords")? {
        insert_loop_run(&transaction, payload).await?;
    }
    for payload in array(params, "skillReferences")? {
        insert_skill_reference(&transaction, payload).await?;
    }

    let source_digests = params
        .get("sourceDigests")
        .cloned()
        .unwrap_or_else(|| json!({}));
    transaction
        .execute(
            "INSERT INTO automation_migrations (name, completed_at, source_digests_json)
             VALUES (?1, ?2, ?3)",
            libsql::params![
                LEGACY_MIGRATION,
                now_iso(),
                serde_json::to_string(&source_digests)?
            ],
        )
        .await?;
    transaction.commit().await?;

    Ok(json!({"imported": true, "alreadyComplete": false}))
}

pub async fn vibe_save(conn: &Connection, id: String, params: Value) -> Response {
    match object_param(&params, "vibe") {
        Ok(vibe) => {
            let result = async {
                let transaction = conn
                    .transaction_with_behavior(TransactionBehavior::Immediate)
                    .await?;
                save_vibe(&transaction, vibe).await?;
                transaction.commit().await?;
                Ok::<_, anyhow::Error>(json!({"saved": true}))
            }
            .await;
            response(id, result)
        }
        Err(error) => Response::invalid_params(id, error.to_string()),
    }
}

pub async fn vibe_delete(conn: &Connection, id: String, params: Value) -> Response {
    let result = async {
        let vibe_id = required_string(&params, "id")?;
        let affected = conn
            .execute(
                "UPDATE automation_vibes SET is_current = 0 WHERE id = ?1 AND is_current = 1",
                libsql::params![vibe_id],
            )
            .await?;
        Ok(json!({"deleted": affected > 0}))
    }
    .await;
    response(id, result)
}

pub async fn lane_save(conn: &Connection, id: String, params: Value) -> Response {
    match object_param(&params, "lane") {
        Ok(lane) => {
            let result = async {
                let transaction = conn
                    .transaction_with_behavior(TransactionBehavior::Immediate)
                    .await?;
                save_lane(&transaction, lane).await?;
                transaction.commit().await?;
                Ok::<_, anyhow::Error>(json!({"saved": true}))
            }
            .await;
            response(id, result)
        }
        Err(error) => Response::invalid_params(id, error.to_string()),
    }
}

pub async fn lane_delete(conn: &Connection, id: String, params: Value) -> Response {
    let result = async {
        let lane_id = required_string(&params, "id")?;
        let tombstone = params["tombstone"].as_bool().unwrap_or(false);
        let transaction = conn
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .await?;
        let affected = transaction
            .execute(
                "UPDATE automation_lanes SET is_current = 0 WHERE id = ?1 AND is_current = 1",
                libsql::params![lane_id],
            )
            .await?;
        if tombstone {
            transaction
                .execute(
                    "INSERT INTO automation_lane_tombstones (lane_id, deleted_at)
                     VALUES (?1, ?2)
                     ON CONFLICT(lane_id) DO UPDATE SET deleted_at = excluded.deleted_at",
                    libsql::params![lane_id, now_iso()],
                )
                .await?;
        }
        transaction.commit().await?;
        Ok(json!({"deleted": affected > 0}))
    }
    .await;
    response(id, result)
}

pub async fn lane_tombstones_clear(conn: &Connection, id: String) -> Response {
    response(
        id,
        async {
            let affected = conn
                .execute("DELETE FROM automation_lane_tombstones", ())
                .await?;
            Ok(json!({"cleared": affected}))
        }
        .await,
    )
}

pub async fn starters_apply(conn: &Connection, id: String, params: Value) -> Response {
    let result = async {
        let transaction = conn
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .await?;
        if params["clearTombstones"].as_bool().unwrap_or(false) {
            transaction
                .execute("DELETE FROM automation_lane_tombstones", ())
                .await?;
        }
        for vibe in array(&params, "vibeRevisions")? {
            insert_vibe(&transaction, vibe, false, false).await?;
        }
        for vibe in array(&params, "vibes")? {
            save_vibe(&transaction, vibe).await?;
        }
        for lane in array(&params, "lanes")? {
            save_lane(&transaction, lane).await?;
        }
        let mut retired = 0_u64;
        if params.get("retireVibeIDs").is_some() {
            for vibe_id in string_array(&params, "retireVibeIDs")? {
                retired += transaction
                    .execute(
                        "UPDATE automation_vibes
                         SET is_current = 0
                         WHERE id = ?1 AND is_current = 1",
                        libsql::params![vibe_id],
                    )
                    .await?;
            }
        }
        transaction.commit().await?;
        Ok(json!({"saved": true, "retiredVibes": retired}))
    }
    .await;
    response(id, result)
}

pub async fn task_save(conn: &Connection, id: String, params: Value) -> Response {
    match object_param(&params, "task") {
        Ok(task) => response(
            id,
            async {
                let transaction = conn
                    .transaction_with_behavior(TransactionBehavior::Immediate)
                    .await?;
                upsert_task(&transaction, task).await?;
                let task_id = required_string(task, "id")?;
                transaction
                    .execute(
                        "DELETE FROM automation_handoffs WHERE task_id = ?1",
                        libsql::params![task_id],
                    )
                    .await?;
                for handoff in array(&params, "handoffs")? {
                    insert_handoff(&transaction, handoff).await?;
                }
                transaction.commit().await?;
                Ok(json!({"saved": true}))
            }
            .await,
        ),
        Err(error) => Response::invalid_params(id, error.to_string()),
    }
}

pub async fn task_delete(conn: &Connection, id: String, params: Value) -> Response {
    response(
        id,
        async {
            let task_id = required_string(&params, "id")?;
            let affected = conn
                .execute(
                    "DELETE FROM automation_tasks WHERE id = ?1",
                    libsql::params![task_id],
                )
                .await?;
            Ok(json!({"deleted": affected > 0}))
        }
        .await,
    )
}

pub async fn loops_replace(conn: &Connection, id: String, params: Value) -> Response {
    let result = async {
        let transaction = conn
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .await?;
        transaction
            .execute("DELETE FROM automation_loop_runs", ())
            .await?;
        transaction
            .execute("DELETE FROM automation_loop_runtime", ())
            .await?;
        transaction
            .execute("DELETE FROM automation_loops", ())
            .await?;
        for payload in array(&params, "definitions")? {
            insert_loop(&transaction, payload).await?;
        }
        for payload in array(&params, "runtimeStates")? {
            insert_loop_runtime(&transaction, payload).await?;
        }
        for payload in array(&params, "runRecords")? {
            insert_loop_run(&transaction, payload).await?;
        }
        transaction.commit().await?;
        Ok(json!({"saved": true}))
    }
    .await;
    response(id, result)
}

pub async fn skill_references_replace(conn: &Connection, id: String, params: Value) -> Response {
    let result = async {
        let transaction = conn
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .await?;
        transaction
            .execute("DELETE FROM automation_skill_references", ())
            .await?;
        for payload in array(&params, "references")? {
            insert_skill_reference(&transaction, payload).await?;
        }
        transaction.commit().await?;
        Ok(json!({"saved": true}))
    }
    .await;
    response(id, result)
}

async fn transaction_has_migration(transaction: &Transaction) -> Result<bool> {
    let mut rows = transaction
        .query(
            "SELECT 1 FROM automation_migrations WHERE name = ?1 LIMIT 1",
            libsql::params![LEGACY_MIGRATION],
        )
        .await?;
    Ok(rows.next().await?.is_some())
}

async fn ensure_automation_empty(transaction: &Transaction) -> Result<()> {
    for table in [
        "automation_vibes",
        "automation_lanes",
        "automation_lane_tombstones",
        "automation_tasks",
        "automation_loops",
        "automation_loop_runtime",
        "automation_loop_runs",
        "automation_skill_references",
        "automation_handoffs",
    ] {
        let sql = format!("SELECT 1 FROM {table} LIMIT 1");
        let mut rows = transaction.query(&sql, ()).await?;
        if rows.next().await?.is_some() {
            bail!("automation database is not empty before legacy import");
        }
    }
    Ok(())
}

async fn save_vibe(transaction: &Transaction, payload: &Value) -> Result<()> {
    let vibe_id = required_string(payload, "id")?;
    transaction
        .execute(
            "UPDATE automation_vibes SET is_current = 0 WHERE id = ?1",
            libsql::params![vibe_id],
        )
        .await?;
    insert_vibe(transaction, payload, true, false).await
}

async fn save_lane(transaction: &Transaction, payload: &Value) -> Result<()> {
    let lane_id = required_string(payload, "id")?;
    transaction
        .execute(
            "UPDATE automation_lanes SET is_current = 0 WHERE id = ?1",
            libsql::params![lane_id],
        )
        .await?;
    insert_lane(transaction, payload, true, false).await?;
    transaction
        .execute(
            "DELETE FROM automation_lane_tombstones WHERE lane_id = ?1",
            libsql::params![lane_id],
        )
        .await?;
    Ok(())
}

async fn insert_vibe(
    transaction: &Transaction,
    payload: &Value,
    current: bool,
    replace: bool,
) -> Result<()> {
    let id = required_string(payload, "id")?;
    let version = required_i64(payload, "version")?;
    let name = required_string(payload, "name")?;
    let category = required_string(payload, "category")?;
    let verb = if replace {
        "INSERT OR REPLACE"
    } else {
        "INSERT"
    };
    let sql = format!(
        "{verb} INTO automation_vibes
         (id, version, is_current, name, category, payload_json, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)"
    );
    let now = now_iso();
    transaction
        .execute(
            &sql,
            libsql::params![
                id,
                version,
                current,
                name,
                category,
                serde_json::to_string(payload)?,
                now.clone(),
                now
            ],
        )
        .await?;
    Ok(())
}

async fn insert_lane(
    transaction: &Transaction,
    payload: &Value,
    current: bool,
    replace: bool,
) -> Result<()> {
    let id = required_string(payload, "id")?;
    let version = required_i64(payload, "version")?;
    let name = required_string(payload, "name")?;
    let seeded_fingerprint = payload["seededFingerprint"].as_str();
    let verb = if replace {
        "INSERT OR REPLACE"
    } else {
        "INSERT"
    };
    let sql = format!(
        "{verb} INTO automation_lanes
         (id, version, is_current, name, seeded_fingerprint, payload_json, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)"
    );
    let now = now_iso();
    transaction
        .execute(
            &sql,
            libsql::params![
                id,
                version,
                current,
                name,
                seeded_fingerprint,
                serde_json::to_string(payload)?,
                now.clone(),
                now
            ],
        )
        .await?;
    insert_lane_steps(transaction, payload).await?;
    Ok(())
}

async fn insert_lane_steps(transaction: &Transaction, payload: &Value) -> Result<()> {
    let Some(steps) = payload.get("steps") else {
        return Ok(());
    };
    let steps = steps
        .as_array()
        .ok_or_else(|| anyhow!("steps array required"))?;
    let lane_id = required_string(payload, "id")?;
    let lane_version = required_i64(payload, "version")?;
    for step in steps {
        transaction
            .execute(
                "INSERT INTO automation_lane_steps
                 (lane_id, lane_version, step_key, position, vibe_id, vibe_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                libsql::params![
                    lane_id,
                    lane_version,
                    required_string(step, "key")?,
                    required_i64(step, "order")?,
                    required_string(step, "vibeID")?,
                    required_i64(step, "vibeVersion")?
                ],
            )
            .await?;
    }
    Ok(())
}

async fn upsert_task(transaction: &Transaction, payload: &Value) -> Result<()> {
    let id = required_string(payload, "id")?;
    let lane_id = required_string(payload, "laneID")?;
    let lane_version = required_i64(payload, "laneVersion")?;
    let state = required_string(payload, "state")?;
    let project_path = required_string(payload, "projectPath")?;
    let occurrence_id = occurrence_id(payload);
    let created_at = required_string(payload, "createdAt")?;
    let updated_at = required_string(payload, "updatedAt")?;
    transaction
        .execute(
        "INSERT INTO automation_tasks
         (id, lane_id, lane_version, state, occurrence_id, project_path, payload_json, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
         ON CONFLICT(id) DO UPDATE SET
            lane_id = excluded.lane_id,
            lane_version = excluded.lane_version,
            state = excluded.state,
            occurrence_id = excluded.occurrence_id,
            project_path = excluded.project_path,
            payload_json = excluded.payload_json,
            updated_at = excluded.updated_at",
        libsql::params![
            id,
            lane_id,
            lane_version,
            state,
            occurrence_id,
            project_path,
            serde_json::to_string(payload)?,
            created_at,
            updated_at
        ],
        )
        .await?;
    Ok(())
}

async fn insert_task(transaction: &Transaction, payload: &Value, replace: bool) -> Result<()> {
    let id = required_string(payload, "id")?;
    let lane_id = required_string(payload, "laneID")?;
    let lane_version = required_i64(payload, "laneVersion")?;
    let state = required_string(payload, "state")?;
    let project_path = required_string(payload, "projectPath")?;
    let occurrence_id = occurrence_id(payload);
    let created_at = required_string(payload, "createdAt")?;
    let updated_at = required_string(payload, "updatedAt")?;
    let verb = if replace {
        "INSERT OR REPLACE"
    } else {
        "INSERT"
    };
    let sql = format!(
        "{verb} INTO automation_tasks
         (id, lane_id, lane_version, state, occurrence_id, project_path, payload_json, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)"
    );
    transaction
        .execute(
            &sql,
            libsql::params![
                id,
                lane_id,
                lane_version,
                state,
                occurrence_id,
                project_path,
                serde_json::to_string(payload)?,
                created_at,
                updated_at
            ],
        )
        .await?;
    Ok(())
}

async fn insert_loop(transaction: &Transaction, payload: &Value) -> Result<()> {
    transaction
        .execute(
            "INSERT INTO automation_loops
             (id, is_enabled, lane_id, lane_version, project_path, payload_json, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            libsql::params![
                required_string(payload, "id")?,
                required_bool(payload, "isEnabled")?,
                required_string(payload, "laneID")?,
                required_i64(payload, "laneVersion")?,
                required_string(payload, "projectPath")?,
                serde_json::to_string(payload)?,
                required_string(payload, "createdAt")?,
                required_string(payload, "updatedAt")?
            ],
        )
        .await?;
    Ok(())
}

async fn insert_loop_runtime(transaction: &Transaction, payload: &Value) -> Result<()> {
    transaction
        .execute(
            "INSERT INTO automation_loop_runtime (loop_id, payload_json, updated_at)
             VALUES (?1, ?2, ?3)",
            libsql::params![
                required_string(payload, "loopID")?,
                serde_json::to_string(payload)?,
                now_iso()
            ],
        )
        .await?;
    Ok(())
}

async fn insert_loop_run(transaction: &Transaction, payload: &Value) -> Result<()> {
    transaction
        .execute(
            "INSERT INTO automation_loop_runs
             (id, loop_id, scheduled_at, disposition, task_id, payload_json, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            libsql::params![
                required_string(payload, "id")?,
                required_string(payload, "loopID")?,
                required_string(payload, "scheduledAt")?,
                required_string(payload, "disposition")?,
                payload["taskID"].as_str(),
                serde_json::to_string(payload)?,
                payload["taskUpdatedAt"].as_str().unwrap_or_else(|| ""),
            ],
        )
        .await?;
    Ok(())
}

async fn insert_skill_reference(transaction: &Transaction, payload: &Value) -> Result<()> {
    transaction
        .execute(
            "INSERT INTO automation_skill_references
             (reference, source_kind, digest, payload_json, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            libsql::params![
                required_string(payload, "reference")?,
                payload["sourceKind"].as_str().unwrap_or("linked"),
                payload["digest"].as_str(),
                serde_json::to_string(payload)?,
                now_iso()
            ],
        )
        .await?;
    Ok(())
}

async fn insert_handoff(transaction: &Transaction, payload: &Value) -> Result<()> {
    transaction
        .execute(
            "INSERT INTO automation_handoffs
             (task_id, checkpoint_key, file_path, content_digest, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            libsql::params![
                required_string(payload, "taskID")?,
                required_string(payload, "checkpointKey")?,
                required_string(payload, "filePath")?,
                payload["contentDigest"].as_str(),
                required_string(payload, "updatedAt")?
            ],
        )
        .await?;
    Ok(())
}

fn occurrence_id(payload: &Value) -> Option<&str> {
    payload["origin"]
        .get("loop")
        .and_then(|loop_value| loop_value.get("occurrenceID"))
        .and_then(Value::as_str)
        .or_else(|| {
            payload["origin"]
                .get("occurrenceID")
                .and_then(Value::as_str)
        })
}

async fn load_payloads(conn: &Connection, sql: &str) -> Result<Vec<Value>> {
    let mut rows = conn.query(sql, ()).await?;
    let mut values = Vec::new();
    while let Some(row) = rows.next().await? {
        let payload = row.get::<String>(0)?;
        values.push(serde_json::from_str(&payload).context("decode stored automation payload")?);
    }
    Ok(values)
}

async fn load_strings(conn: &Connection, sql: &str) -> Result<Vec<String>> {
    let mut rows = conn.query(sql, ()).await?;
    let mut values = Vec::new();
    while let Some(row) = rows.next().await? {
        values.push(row.get::<String>(0)?);
    }
    Ok(values)
}

fn array<'a>(params: &'a Value, key: &str) -> Result<&'a Vec<Value>> {
    params
        .get(key)
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("{key} array required"))
}

fn string_array<'a>(params: &'a Value, key: &str) -> Result<Vec<&'a str>> {
    array(params, key)?
        .iter()
        .map(|value| {
            value
                .as_str()
                .ok_or_else(|| anyhow!("{key} must contain only strings"))
        })
        .collect()
}

fn object_param<'a>(params: &'a Value, key: &str) -> Result<&'a Value> {
    let value = params.get(key).ok_or_else(|| anyhow!("{key} required"))?;
    if !value.is_object() {
        bail!("{key} object required");
    }
    Ok(value)
}

fn required_string<'a>(value: &'a Value, key: &str) -> Result<&'a str> {
    value
        .get(key)
        .and_then(Value::as_str)
        .filter(|candidate| !candidate.is_empty())
        .ok_or_else(|| anyhow!("{key} required"))
}

fn required_i64(value: &Value, key: &str) -> Result<i64> {
    value
        .get(key)
        .and_then(Value::as_i64)
        .ok_or_else(|| anyhow!("{key} integer required"))
}

fn required_bool(value: &Value, key: &str) -> Result<bool> {
    value
        .get(key)
        .and_then(Value::as_bool)
        .ok_or_else(|| anyhow!("{key} boolean required"))
}

fn response(id: String, result: Result<Value>) -> Response {
    match result {
        Ok(value) => Response::ok(id, value),
        Err(error) => Response::err(id, -32000, error.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn test_conn() -> Connection {
        let db = libsql::Builder::new_local(":memory:")
            .build()
            .await
            .unwrap();
        let conn = db.connect().unwrap();
        conn.execute("PRAGMA foreign_keys = ON", ()).await.unwrap();
        crate::schema::run_migrations(&conn).await.unwrap();
        conn
    }

    fn vibe_with_id(id: &str, version: i64, name: &str) -> Value {
        json!({
            "id": id,
            "version": version,
            "name": name,
            "category": "engineering"
        })
    }

    fn vibe(version: i64, name: &str) -> Value {
        vibe_with_id("00000000-0000-0000-0000-000000000001", version, name)
    }

    fn lane(version: i64, name: &str) -> Value {
        json!({
            "id": "00000000-0000-0000-0000-000000000002",
            "schemaVersion": 1,
            "version": version,
            "name": name,
            "steerLimit": 1,
            "checkpoints": []
        })
    }

    fn lane_with_step(version: i64, name: &str, vibe_id: &str) -> Value {
        json!({
            "id": "00000000-0000-0000-0000-000000000002",
            "schemaVersion": 1,
            "version": version,
            "name": name,
            "steerLimit": 1,
            "steps": [{
                "key": "build",
                "order": 0,
                "vibeID": vibe_id,
                "vibeVersion": 1
            }]
        })
    }

    fn empty_import(vibes: Vec<Value>, lanes: Vec<Value>) -> Value {
        json!({
            "vibes": vibes,
            "vibeRevisions": [],
            "lanes": lanes,
            "laneRevisions": [],
            "laneTombstones": [],
            "tasks": [],
            "handoffs": [],
            "loopDefinitions": [],
            "loopRuntimeStates": [],
            "loopRunRecords": [],
            "skillReferences": [],
            "sourceDigests": {}
        })
    }

    #[tokio::test]
    async fn legacy_import_is_atomic_and_idempotent() {
        let conn = test_conn().await;
        let params = empty_import(vec![vibe(1, "Build")], vec![lane(1, "Ship")]);

        let imported = do_migration_import(&conn, &params).await.unwrap();
        assert_eq!(imported["imported"], true);
        assert!(migration_complete(&conn).await.unwrap());

        let repeated = do_migration_import(&conn, &params).await.unwrap();
        assert_eq!(repeated["alreadyComplete"], true);

        let snapshot = do_snapshot_load(&conn).await.unwrap();
        assert_eq!(snapshot["vibes"].as_array().unwrap().len(), 1);
        assert_eq!(snapshot["lanes"].as_array().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn saving_new_revision_retains_the_previous_revision() {
        let conn = test_conn().await;
        do_migration_import(
            &conn,
            &empty_import(vec![vibe(1, "Build")], vec![lane(1, "Ship")]),
        )
        .await
        .unwrap();

        let response =
            vibe_save(&conn, "save".into(), json!({"vibe": vibe(2, "Build well")})).await;
        assert!(response.error.is_none());

        let snapshot = do_snapshot_load(&conn).await.unwrap();
        assert_eq!(snapshot["vibes"][0]["version"], 2);
        assert_eq!(snapshot["vibeRevisions"][0]["version"], 1);
    }

    #[tokio::test]
    async fn starter_apply_retires_superseded_vibe_as_a_revision() {
        let conn = test_conn().await;
        let old_vibe_id = "00000000-0000-0000-0000-000000000001";
        let current_vibe_id = "00000000-0000-0000-0000-000000000003";
        do_migration_import(
            &conn,
            &empty_import(
                vec![vibe_with_id(old_vibe_id, 1, "Align")],
                vec![lane_with_step(1, "Starter", old_vibe_id)],
            ),
        )
        .await
        .unwrap();

        let response = starters_apply(
            &conn,
            "starter".into(),
            json!({
                "vibes": [vibe_with_id(current_vibe_id, 1, "Align")],
                "vibeRevisions": [],
                "lanes": [lane_with_step(2, "Starter", current_vibe_id)],
                "retireVibeIDs": [old_vibe_id],
                "clearTombstones": false
            }),
        )
        .await;
        assert!(response.error.is_none());

        let snapshot = do_snapshot_load(&conn).await.unwrap();
        assert_eq!(snapshot["vibes"].as_array().unwrap().len(), 1);
        assert_eq!(snapshot["vibes"][0]["id"], current_vibe_id);
        assert_eq!(snapshot["vibeRevisions"].as_array().unwrap().len(), 1);
        assert_eq!(snapshot["vibeRevisions"][0]["id"], old_vibe_id);
        assert_eq!(snapshot["laneRevisions"][0]["version"], 1);
        assert_eq!(snapshot["lanes"][0]["version"], 2);
    }

    #[tokio::test]
    async fn failed_import_does_not_write_the_marker_or_partial_state() {
        let conn = test_conn().await;
        let invalid = empty_import(
            vec![vibe(1, "Build")],
            vec![json!({"id": "missing-fields"})],
        );

        assert!(do_migration_import(&conn, &invalid).await.is_err());
        assert!(!migration_complete(&conn).await.unwrap());
        let snapshot = do_snapshot_load(&conn).await.unwrap();
        assert!(snapshot["vibes"].as_array().unwrap().is_empty());
        assert!(snapshot["lanes"].as_array().unwrap().is_empty());
    }

    #[tokio::test]
    async fn lane_steps_are_materialized_as_constrained_relationships() {
        let conn = test_conn().await;
        let vibe_id = "00000000-0000-0000-0000-000000000001";
        do_migration_import(
            &conn,
            &empty_import(
                vec![vibe(1, "Build")],
                vec![lane_with_step(1, "Ship", vibe_id)],
            ),
        )
        .await
        .unwrap();

        let mut rows = conn
            .query(
                "SELECT step_key, position, vibe_id, vibe_version
                 FROM automation_lane_steps",
                (),
            )
            .await
            .unwrap();
        let row = rows.next().await.unwrap().unwrap();
        assert_eq!(row.get::<String>(0).unwrap(), "build");
        assert_eq!(row.get::<i64>(1).unwrap(), 0);
        assert_eq!(row.get::<String>(2).unwrap(), vibe_id);
        assert_eq!(row.get::<i64>(3).unwrap(), 1);
    }

    #[tokio::test]
    async fn starter_apply_rolls_back_vibes_when_a_lane_reference_is_invalid() {
        let conn = test_conn().await;
        do_migration_import(
            &conn,
            &empty_import(vec![vibe(1, "Build")], vec![lane(1, "Ship")]),
        )
        .await
        .unwrap();

        let new_vibe_id = "00000000-0000-0000-0000-000000000003";
        let new_vibe = json!({
            "id": new_vibe_id,
            "version": 1,
            "name": "Review",
            "category": "engineering"
        });
        let invalid_lane = lane_with_step(2, "Ship safely", "00000000-0000-0000-0000-000000000099");
        let response = starters_apply(
            &conn,
            "starter".into(),
            json!({
                "vibes": [new_vibe],
                "vibeRevisions": [],
                "lanes": [invalid_lane],
                "clearTombstones": false
            }),
        )
        .await;
        assert!(response.error.is_some());

        let mut rows = conn
            .query(
                "SELECT COUNT(*) FROM automation_vibes WHERE id = ?1",
                libsql::params![new_vibe_id],
            )
            .await
            .unwrap();
        assert_eq!(
            rows.next().await.unwrap().unwrap().get::<i64>(0).unwrap(),
            0
        );
        let snapshot = do_snapshot_load(&conn).await.unwrap();
        assert_eq!(snapshot["lanes"][0]["version"], 1);
    }

    #[tokio::test]
    async fn task_and_handoff_metadata_commit_atomically() {
        let conn = test_conn().await;
        do_migration_import(
            &conn,
            &empty_import(vec![vibe(1, "Build")], vec![lane(1, "Ship")]),
        )
        .await
        .unwrap();
        let task = json!({
            "id": "00000000-0000-0000-0000-000000000010",
            "laneID": "00000000-0000-0000-0000-000000000002",
            "laneVersion": 1,
            "state": "running",
            "projectPath": "/tmp/project",
            "createdAt": "2026-07-22T00:00:00Z",
            "updatedAt": "2026-07-22T00:00:01Z"
        });
        let handoff = json!({
            "taskID": "00000000-0000-0000-0000-000000000010",
            "checkpointKey": "build",
            "filePath": "/tmp/handoffs/build.md",
            "contentDigest": "abc123",
            "updatedAt": "2026-07-22T00:00:01Z"
        });
        let saved = task_save(
            &conn,
            "task".into(),
            json!({"task": task, "handoffs": [handoff]}),
        )
        .await;
        assert!(saved.error.is_none());

        let mut changed_task = task.clone();
        changed_task["state"] = json!("done");
        let rejected = task_save(
            &conn,
            "task-invalid".into(),
            json!({"task": changed_task, "handoffs": [{"taskID": task["id"]}]}),
        )
        .await;
        assert!(rejected.error.is_some());

        let mut rows = conn
            .query(
                "SELECT state, (
                    SELECT COUNT(*) FROM automation_handoffs
                    WHERE task_id = automation_tasks.id
                 ) FROM automation_tasks WHERE id = ?1",
                libsql::params![task["id"].as_str().unwrap()],
            )
            .await
            .unwrap();
        let row = rows.next().await.unwrap().unwrap();
        assert_eq!(row.get::<String>(0).unwrap(), "running");
        assert_eq!(row.get::<i64>(1).unwrap(), 1);
    }
}
