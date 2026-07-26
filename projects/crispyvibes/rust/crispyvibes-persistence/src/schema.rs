use anyhow::{Context, Result};
use libsql::Connection;

pub(crate) const CURRENT_VERSION: i64 = 7;

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
    if version < 2 {
        migrate_v2(conn).await.context("V2 migration")?;
    }
    if version < 3 {
        migrate_v3(conn).await.context("V3 migration")?;
    }
    if version < 4 {
        migrate_v4(conn).await.context("V4 migration")?;
    }
    if version < 5 {
        migrate_v5(conn).await.context("V5 migration")?;
    }
    if version < 6 {
        migrate_v6(conn).await.context("V6 migration")?;
    }
    if version < 7 {
        migrate_v7(conn).await.context("V7 migration")?;
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


/// F049 — File comments. Per-vibespace scoped via the `vibespace_id` column.
/// Anchors stored in a sibling `comment_anchors` table; FTS5 over comment bodies.
async fn migrate_v2(conn: &Connection) -> Result<()> {
    let stmts = [
        "CREATE TABLE IF NOT EXISTS comments (
            id            TEXT PRIMARY KEY,
            vibespace_id  TEXT NOT NULL,
            file_path     TEXT NOT NULL,
            parent_id     TEXT REFERENCES comments(id) ON DELETE CASCADE,
            body          TEXT NOT NULL,
            author_kind   TEXT NOT NULL CHECK (author_kind IN ('user','agent')),
            author_label  TEXT,
            created_at    TEXT NOT NULL,
            updated_at    TEXT NOT NULL,
            resolved_at   TEXT,
            is_stale      INTEGER NOT NULL DEFAULT 0
        )",
        "CREATE INDEX IF NOT EXISTS idx_comments_vs_file ON comments(vibespace_id, file_path, created_at)",
        "CREATE INDEX IF NOT EXISTS idx_comments_parent ON comments(parent_id)",
        "CREATE INDEX IF NOT EXISTS idx_comments_resolved ON comments(vibespace_id, resolved_at)",
        "CREATE INDEX IF NOT EXISTS idx_comments_stale ON comments(vibespace_id, is_stale)",

        "CREATE TABLE IF NOT EXISTS comment_anchors (
            comment_id        TEXT PRIMARY KEY REFERENCES comments(id) ON DELETE CASCADE,
            start_line        INTEGER NOT NULL,
            start_column      INTEGER NOT NULL,
            end_line          INTEGER NOT NULL,
            end_column        INTEGER NOT NULL,
            anchor_hash       TEXT NOT NULL,
            anchor_text       TEXT NOT NULL,
            leading_context   TEXT NOT NULL,
            trailing_context  TEXT NOT NULL
        )",

        "CREATE VIRTUAL TABLE IF NOT EXISTS comment_fts USING fts5(body, content='comments', content_rowid='rowid')",
        "CREATE TRIGGER IF NOT EXISTS comments_ai AFTER INSERT ON comments BEGIN
            INSERT INTO comment_fts(rowid, body) VALUES (new.rowid, new.body);
        END",
        "CREATE TRIGGER IF NOT EXISTS comments_ad AFTER DELETE ON comments BEGIN
            INSERT INTO comment_fts(comment_fts, rowid, body) VALUES ('delete', old.rowid, old.body);
        END",
        "CREATE TRIGGER IF NOT EXISTS comments_au AFTER UPDATE OF body ON comments BEGIN
            INSERT INTO comment_fts(comment_fts, rowid, body) VALUES ('delete', old.rowid, old.body);
            INSERT INTO comment_fts(rowid, body) VALUES (new.rowid, new.body);
        END",

        "INSERT INTO schema_version (version) VALUES (2)",
    ];

    for stmt in stmts {
        conn.execute(stmt, ()).await.with_context(|| {
            let preview: String = stmt.chars().take(60).collect();
            format!("execute: {preview}...")
        })?;
    }

    Ok(())
}


/// F049-v2 — extend comments + comment_anchors with surface-kind discrimination
/// (file / browser) and CSS-selector-based DOM anchoring fields used by HTML
/// previews and browser windows.
async fn migrate_v3(conn: &Connection) -> Result<()> {
    let stmts = [
        // surface_kind: 'file' (existing) or 'browser' (new). file_path doubles
        // as canonical-URL storage when surface_kind='browser'.
        "ALTER TABLE comments ADD COLUMN surface_kind TEXT NOT NULL DEFAULT 'file'",

        // CSS-selector-based anchor for HTML/browser surfaces. NULL = legacy
        // line-based anchor; presence = use selector path with text-content
        // fingerprint fallback.
        "ALTER TABLE comment_anchors ADD COLUMN dom_selector TEXT",
        "ALTER TABLE comment_anchors ADD COLUMN dom_text_offset INTEGER",
        "ALTER TABLE comment_anchors ADD COLUMN dom_text_length INTEGER",
        "ALTER TABLE comment_anchors ADD COLUMN dom_fingerprint TEXT",

        "CREATE INDEX IF NOT EXISTS idx_comments_surface ON comments(vibespace_id, surface_kind, file_path)",

        "INSERT INTO schema_version (version) VALUES (3)",
    ];

    for stmt in stmts {
        conn.execute(stmt, ()).await.with_context(|| {
            let preview: String = stmt.chars().take(60).collect();
            format!("execute: {preview}...")
        })?;
    }

    Ok(())
}


/// F053 — Quick todos & sticky notes. Vibespace-scoped via `vibespace_id`;
/// optionally project-scoped via `project_path` (NULL = vibespace-level).
/// `due_at`/`reminder_at` are reserved for the later reminders phase.
async fn migrate_v4(conn: &Connection) -> Result<()> {
    let stmts = [
        "CREATE TABLE IF NOT EXISTS todos (
            id           TEXT PRIMARY KEY,
            vibespace_id TEXT NOT NULL,
            project_path TEXT,
            title        TEXT NOT NULL,
            body         TEXT,
            color_tag    TEXT,
            file_path    TEXT,
            status       TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed')),
            due_at       TEXT,
            reminder_at  TEXT,
            created_at   TEXT NOT NULL,
            updated_at   TEXT NOT NULL,
            completed_at TEXT
        )",
        "CREATE INDEX IF NOT EXISTS idx_todos_vs ON todos(vibespace_id, status, updated_at DESC)",
        "CREATE INDEX IF NOT EXISTS idx_todos_vs_project ON todos(vibespace_id, project_path, status, updated_at DESC)",
        "CREATE TABLE IF NOT EXISTS todo_messages (
            id          TEXT PRIMARY KEY,
            todo_id     TEXT NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
            body        TEXT NOT NULL,
            author_kind TEXT NOT NULL DEFAULT 'user' CHECK (author_kind IN ('user','agent')),
            created_at  TEXT NOT NULL,
            updated_at  TEXT NOT NULL
        )",
        "CREATE INDEX IF NOT EXISTS idx_todo_messages_todo ON todo_messages(todo_id, created_at)",
        "INSERT INTO schema_version (version) VALUES (4)",
    ];

    for stmt in stmts {
        conn.execute(stmt, ()).await.with_context(|| {
            let preview: String = stmt.chars().take(60).collect();
            format!("execute: {preview}...")
        })?;
    }

    Ok(())
}


/// F060 — Todo lane pipeline. Adds pipeline columns to `todos` (`lane_task_id`
/// links an F059 lane task, `refinement_session_id` a refine session,
/// `triage_json` stores the validated triage result blob) and a `todo_files`
/// table for per-todo file links. The legacy `file_path` column stays; links
/// are additive (read-side merge — no destructive migration).
async fn migrate_v5(conn: &Connection) -> Result<()> {
    let stmts = [
        "ALTER TABLE todos ADD COLUMN lane_task_id TEXT",
        "ALTER TABLE todos ADD COLUMN refinement_session_id TEXT",
        "ALTER TABLE todos ADD COLUMN triage_json TEXT",
        "CREATE TABLE IF NOT EXISTS todo_files (
            id         TEXT PRIMARY KEY,
            todo_id    TEXT NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
            path       TEXT NOT NULL,
            line       INTEGER,
            created_at TEXT NOT NULL
        )",
        "CREATE INDEX IF NOT EXISTS idx_todo_files_todo ON todo_files(todo_id, created_at)",
        "INSERT INTO schema_version (version) VALUES (5)",
    ];

    for stmt in stmts {
        conn.execute(stmt, ()).await.with_context(|| {
            let preview: String = stmt.chars().take(60).collect();
            format!("execute: {preview}...")
        })?;
    }

    Ok(())
}

/// F059/F061 — Automation persistence. Vibes and Vibe Lanes retain every
/// immutable revision. Tasks, Loops, scheduler runtime, and run history are
/// first-class rows in the encrypted database. JSON payload columns contain
/// each Codable aggregate; identity, revision, lifecycle, and relationships
/// remain queryable and constrained by SQL.
async fn migrate_v6(conn: &Connection) -> Result<()> {
    let stmts = [
        "CREATE TABLE IF NOT EXISTS automation_vibes (
            id           TEXT NOT NULL,
            version      INTEGER NOT NULL CHECK (version > 0),
            is_current   INTEGER NOT NULL CHECK (is_current IN (0, 1)),
            name         TEXT NOT NULL,
            category     TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at   TEXT NOT NULL,
            updated_at   TEXT NOT NULL,
            PRIMARY KEY (id, version)
        )",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_automation_vibes_current
            ON automation_vibes(id) WHERE is_current = 1",
        "CREATE INDEX IF NOT EXISTS idx_automation_vibes_category
            ON automation_vibes(category, name) WHERE is_current = 1",

        "CREATE TABLE IF NOT EXISTS automation_lanes (
            id                  TEXT NOT NULL,
            version             INTEGER NOT NULL CHECK (version > 0),
            is_current          INTEGER NOT NULL CHECK (is_current IN (0, 1)),
            name                TEXT NOT NULL,
            seeded_fingerprint  TEXT,
            payload_json        TEXT NOT NULL,
            created_at          TEXT NOT NULL,
            updated_at          TEXT NOT NULL,
            PRIMARY KEY (id, version)
        )",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_automation_lanes_current
            ON automation_lanes(id) WHERE is_current = 1",
        "CREATE INDEX IF NOT EXISTS idx_automation_lanes_name
            ON automation_lanes(name) WHERE is_current = 1",
        "CREATE TABLE IF NOT EXISTS automation_lane_tombstones (
            lane_id     TEXT PRIMARY KEY,
            deleted_at  TEXT NOT NULL
        )",

        "CREATE TABLE IF NOT EXISTS automation_tasks (
            id             TEXT PRIMARY KEY,
            lane_id        TEXT NOT NULL,
            lane_version   INTEGER NOT NULL,
            state          TEXT NOT NULL CHECK (state IN ('running','needsInput','stopped','done')),
            occurrence_id  TEXT UNIQUE,
            project_path   TEXT NOT NULL,
            payload_json   TEXT NOT NULL,
            created_at     TEXT NOT NULL,
            updated_at     TEXT NOT NULL,
            FOREIGN KEY (lane_id, lane_version)
                REFERENCES automation_lanes(id, version)
        )",
        "CREATE INDEX IF NOT EXISTS idx_automation_tasks_state
            ON automation_tasks(state, updated_at DESC)",
        "CREATE INDEX IF NOT EXISTS idx_automation_tasks_lane
            ON automation_tasks(lane_id, lane_version)",
        "CREATE INDEX IF NOT EXISTS idx_automation_tasks_project
            ON automation_tasks(project_path, state)",

        "CREATE TABLE IF NOT EXISTS automation_loops (
            id             TEXT PRIMARY KEY,
            is_enabled     INTEGER NOT NULL CHECK (is_enabled IN (0, 1)),
            lane_id        TEXT NOT NULL,
            lane_version   INTEGER NOT NULL,
            project_path   TEXT NOT NULL,
            payload_json   TEXT NOT NULL,
            created_at     TEXT NOT NULL,
            updated_at     TEXT NOT NULL,
            FOREIGN KEY (lane_id, lane_version)
                REFERENCES automation_lanes(id, version)
        )",
        "CREATE INDEX IF NOT EXISTS idx_automation_loops_enabled
            ON automation_loops(is_enabled, updated_at DESC)",
        "CREATE TABLE IF NOT EXISTS automation_loop_runtime (
            loop_id       TEXT PRIMARY KEY REFERENCES automation_loops(id) ON DELETE CASCADE,
            payload_json  TEXT NOT NULL,
            updated_at    TEXT NOT NULL
        )",
        "CREATE TABLE IF NOT EXISTS automation_loop_runs (
            id             TEXT PRIMARY KEY,
            loop_id        TEXT NOT NULL REFERENCES automation_loops(id) ON DELETE CASCADE,
            scheduled_at   TEXT NOT NULL,
            disposition    TEXT NOT NULL,
            task_id        TEXT REFERENCES automation_tasks(id) ON DELETE SET NULL,
            payload_json   TEXT NOT NULL,
            updated_at     TEXT NOT NULL
        )",
        "CREATE INDEX IF NOT EXISTS idx_automation_loop_runs_history
            ON automation_loop_runs(loop_id, scheduled_at DESC)",

        "CREATE TABLE IF NOT EXISTS automation_skill_references (
            reference      TEXT PRIMARY KEY,
            source_kind    TEXT NOT NULL,
            digest         TEXT,
            payload_json   TEXT NOT NULL,
            updated_at     TEXT NOT NULL
        )",
        "CREATE TABLE IF NOT EXISTS automation_handoffs (
            task_id         TEXT NOT NULL REFERENCES automation_tasks(id) ON DELETE CASCADE,
            checkpoint_key  TEXT NOT NULL,
            file_path       TEXT NOT NULL,
            content_digest  TEXT,
            updated_at      TEXT NOT NULL,
            PRIMARY KEY (task_id, checkpoint_key)
        )",
        "CREATE TABLE IF NOT EXISTS automation_migrations (
            name                 TEXT PRIMARY KEY,
            completed_at         TEXT NOT NULL,
            source_digests_json  TEXT NOT NULL
        )",
        "INSERT INTO schema_version (version) VALUES (6)",
    ];

    for stmt in stmts {
        conn.execute(stmt, ()).await.with_context(|| {
            let preview: String = stmt.chars().take(60).collect();
            format!("execute: {preview}...")
        })?;
    }

    Ok(())
}

/// F059 — materialize each immutable Lane revision's ordered Vibe pins. The
/// aggregate payload remains the Codable source for lane-owned fields, while
/// SQL owns and constrains the cross-entity relationship.
async fn migrate_v7(conn: &Connection) -> Result<()> {
    let stmts = [
        "CREATE TABLE IF NOT EXISTS automation_lane_steps (
            lane_id       TEXT NOT NULL,
            lane_version  INTEGER NOT NULL,
            step_key      TEXT NOT NULL,
            position      INTEGER NOT NULL CHECK (position >= 0),
            vibe_id       TEXT NOT NULL,
            vibe_version  INTEGER NOT NULL,
            PRIMARY KEY (lane_id, lane_version, step_key),
            UNIQUE (lane_id, lane_version, position),
            FOREIGN KEY (lane_id, lane_version)
                REFERENCES automation_lanes(id, version) ON DELETE CASCADE,
            FOREIGN KEY (vibe_id, vibe_version)
                REFERENCES automation_vibes(id, version)
        )",
        "CREATE INDEX IF NOT EXISTS idx_automation_lane_steps_vibe
            ON automation_lane_steps(vibe_id, vibe_version)",
        "INSERT OR IGNORE INTO automation_lane_steps
            (lane_id, lane_version, step_key, position, vibe_id, vibe_version)
         SELECT
            lane.id,
            lane.version,
            json_extract(step.value, '$.key'),
            json_extract(step.value, '$.order'),
            json_extract(step.value, '$.vibeID'),
            json_extract(step.value, '$.vibeVersion')
         FROM automation_lanes AS lane, json_each(lane.payload_json, '$.steps') AS step
         WHERE json_type(step.value, '$.key') = 'text'
           AND json_type(step.value, '$.order') = 'integer'
           AND json_type(step.value, '$.vibeID') = 'text'
           AND json_type(step.value, '$.vibeVersion') = 'integer'",
        "INSERT INTO schema_version (version) VALUES (7)",
    ];

    for stmt in stmts {
        conn.execute(stmt, ()).await.with_context(|| {
            let preview: String = stmt.chars().take(60).collect();
            format!("execute: {preview}...")
        })?;
    }

    Ok(())
}
