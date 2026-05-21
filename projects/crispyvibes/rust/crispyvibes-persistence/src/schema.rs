use anyhow::{Context, Result};
use libsql::Connection;

const CURRENT_VERSION: i64 = 1;

pub async fn run_migrations(conn: &Connection) -> Result<i64> {
    conn.execute(
        "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)",
        (),
    )
    .await
    .context("create schema_version table")?;

    let version = current_version(conn).await?;

    if version < 1 {
        migrate_v1(conn).await.context("V1 migration")?;
    }

    Ok(CURRENT_VERSION)
}

async fn current_version(conn: &Connection) -> Result<i64> {
    let mut rows = conn
        .query("SELECT version FROM schema_version ORDER BY version DESC LIMIT 1", ())
        .await
        .context("query schema_version")?;
    match rows.next().await? {
        Some(row) => Ok(row.get::<i64>(0)?),
        None => Ok(0),
    }
}

async fn migrate_v1(conn: &Connection) -> Result<()> {
    let stmts = [
        // -- Conversation threads --
        "CREATE TABLE IF NOT EXISTS threads (
            id                TEXT PRIMARY KEY,
            workspace_id      TEXT NOT NULL,
            project_path      TEXT NOT NULL,
            title             TEXT NOT NULL,
            agent_id          TEXT NOT NULL,
            transport_kind    TEXT NOT NULL,
            model             TEXT NOT NULL,
            thread_kind       TEXT NOT NULL DEFAULT 'conversation',
            parent_thread_id  TEXT REFERENCES threads(id) ON DELETE SET NULL,
            metadata          TEXT NOT NULL DEFAULT '{}',
            tags              TEXT NOT NULL DEFAULT '[]',
            created_at        TEXT NOT NULL,
            updated_at        TEXT NOT NULL,
            archived_at       TEXT
        )",
        "CREATE INDEX IF NOT EXISTS idx_threads_workspace ON threads(workspace_id, updated_at DESC)",
        "CREATE INDEX IF NOT EXISTS idx_threads_project ON threads(workspace_id, project_path, updated_at DESC)",
        "CREATE INDEX IF NOT EXISTS idx_threads_kind ON threads(thread_kind)",
        "CREATE INDEX IF NOT EXISTS idx_threads_parent ON threads(parent_thread_id)",

        // -- Messages --
        "CREATE TABLE IF NOT EXISTS messages (
            id           TEXT PRIMARY KEY,
            thread_id    TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
            turn_id      TEXT,
            role         TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
            text         TEXT NOT NULL,
            is_streaming INTEGER NOT NULL DEFAULT 0,
            sequence     INTEGER NOT NULL,
            created_at   TEXT NOT NULL,
            updated_at   TEXT NOT NULL
        )",
        "CREATE INDEX IF NOT EXISTS idx_messages_thread_seq ON messages(thread_id, sequence ASC)",
        "CREATE INDEX IF NOT EXISTS idx_messages_thread_turn ON messages(thread_id, turn_id)",

        // -- FTS5 --
        "CREATE VIRTUAL TABLE IF NOT EXISTS message_fts USING fts5(text, content='messages', content_rowid='rowid')",
        "CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
            INSERT INTO message_fts(rowid, text) VALUES (new.rowid, new.text);
        END",
        "CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
            INSERT INTO message_fts(message_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
        END",
        "CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE OF text ON messages BEGIN
            INSERT INTO message_fts(message_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
            INSERT INTO message_fts(rowid, text) VALUES (new.rowid, new.text);
        END",

        // -- Vector embeddings --
        "CREATE TABLE IF NOT EXISTS message_embeddings (
            message_id TEXT PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
            model_id   TEXT NOT NULL,
            revision   INTEGER NOT NULL,
            dimension  INTEGER NOT NULL,
            language   TEXT NOT NULL,
            embedding  F32_BLOB(512)
        )",

        // -- Activities --
        "CREATE TABLE IF NOT EXISTS activities (
            id           TEXT PRIMARY KEY,
            thread_id    TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
            turn_id      TEXT,
            kind         TEXT NOT NULL,
            item_type    TEXT,
            summary      TEXT NOT NULL,
            payload_json TEXT,
            sequence     INTEGER NOT NULL,
            created_at   TEXT NOT NULL
        )",
        "CREATE INDEX IF NOT EXISTS idx_activities_thread_seq ON activities(thread_id, sequence ASC)",
        "CREATE INDEX IF NOT EXISTS idx_activities_thread_turn ON activities(thread_id, turn_id)",

        // -- Sessions --
        "CREATE TABLE IF NOT EXISTS sessions (
            thread_id           TEXT PRIMARY KEY REFERENCES threads(id) ON DELETE CASCADE,
            provider            TEXT NOT NULL,
            transport_kind      TEXT NOT NULL,
            status              TEXT NOT NULL CHECK (status IN ('connecting', 'ready', 'running', 'interrupted', 'error', 'disconnected')),
            resume_strategy     TEXT NOT NULL CHECK (resume_strategy IN ('native_resume', 'transcript_replay', 'none')),
            capabilities        TEXT,
            provider_session_id TEXT,
            resume_cursor_json  TEXT,
            runtime_mode        TEXT NOT NULL,
            updated_at          TEXT NOT NULL
        )",

        // -- Workflow templates --
        "CREATE TABLE IF NOT EXISTS workflow_templates (
            id          TEXT PRIMARY KEY,
            name        TEXT NOT NULL,
            scope       TEXT NOT NULL CHECK (scope IN ('builtin', 'workspace', 'project')),
            phases_json TEXT NOT NULL,
            policy_json TEXT NOT NULL,
            created_at  TEXT NOT NULL,
            updated_at  TEXT NOT NULL
        )",

        // -- Work cards --
        "CREATE TABLE IF NOT EXISTS work_cards (
            id                     TEXT PRIMARY KEY,
            board_id               TEXT NOT NULL,
            workspace_id           TEXT NOT NULL,
            project_identifier     TEXT NOT NULL,
            title                  TEXT NOT NULL,
            description            TEXT,
            status                 TEXT NOT NULL CHECK (status IN ('ready', 'running', 'needs_input', 'blocked', 'failed', 'verified', 'done', 'archived')),
            workflow_template_id   TEXT NOT NULL REFERENCES workflow_templates(id),
            workflow_instance_json TEXT NOT NULL,
            current_phase_key      TEXT,
            automation_state_json  TEXT NOT NULL DEFAULT '{}',
            metadata               TEXT NOT NULL DEFAULT '{}',
            tags                   TEXT NOT NULL DEFAULT '[]',
            created_at             TEXT NOT NULL,
            updated_at             TEXT NOT NULL,
            archived_at            TEXT
        )",
        "CREATE INDEX IF NOT EXISTS idx_work_cards_board ON work_cards(board_id, status, updated_at DESC)",
        "CREATE INDEX IF NOT EXISTS idx_work_cards_workspace ON work_cards(workspace_id, updated_at DESC)",

        // -- Phase runs --
        "CREATE TABLE IF NOT EXISTS phase_runs (
            id             TEXT PRIMARY KEY,
            card_id        TEXT NOT NULL REFERENCES work_cards(id) ON DELETE CASCADE,
            phase_key      TEXT NOT NULL,
            attempt        INTEGER NOT NULL DEFAULT 1,
            status         TEXT NOT NULL CHECK (status IN ('pending', 'running', 'waiting', 'succeeded', 'failed', 'cancelled', 'skipped')),
            summary        TEXT,
            failure_reason TEXT,
            started_at     TEXT,
            completed_at   TEXT,
            created_at     TEXT NOT NULL
        )",
        "CREATE INDEX IF NOT EXISTS idx_phase_runs_card ON phase_runs(card_id, phase_key, attempt)",

        // -- Artifact links --
        "CREATE TABLE IF NOT EXISTS artifact_links (
            id            TEXT PRIMARY KEY,
            phase_run_id  TEXT NOT NULL REFERENCES phase_runs(id) ON DELETE CASCADE,
            artifact_kind TEXT NOT NULL,
            artifact_id   TEXT NOT NULL,
            metadata      TEXT NOT NULL DEFAULT '{}',
            created_at    TEXT NOT NULL
        )",
        "CREATE INDEX IF NOT EXISTS idx_artifact_links_run ON artifact_links(phase_run_id)",
        "CREATE INDEX IF NOT EXISTS idx_artifact_links_artifact ON artifact_links(artifact_kind, artifact_id)",

        // -- Record version --
        "INSERT INTO schema_version (version) VALUES (1)",
    ];

    for stmt in stmts {
        conn.execute(stmt, ()).await.with_context(|| {
            let preview: String = stmt.chars().take(60).collect();
            format!("execute: {preview}...")
        })?;
    }

    Ok(())
}
