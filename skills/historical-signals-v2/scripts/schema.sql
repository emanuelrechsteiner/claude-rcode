-- Historical Signals v2 schema (2.0.0)
-- Coexists with v1 signals.jsonl pipeline; does not replace it.

CREATE TABLE IF NOT EXISTS schema_version (
    version TEXT NOT NULL PRIMARY KEY,
    created_at TEXT NOT NULL
);
INSERT OR IGNORE INTO schema_version (version, created_at)
    VALUES ('2.0.0', datetime('now'));

CREATE TABLE IF NOT EXISTS sessions (
    session_id TEXT PRIMARY KEY,
    jsonl_path TEXT NOT NULL,
    cwd TEXT,
    started_at TEXT,
    ended_at TEXT,
    rcode INTEGER DEFAULT 0,
    source TEXT NOT NULL,                 -- 'active' | 'improvment_dump'
    n_turns INTEGER DEFAULT 0,
    ingested_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS prompts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(session_id),
    ts TEXT,                              -- nullable: older session formats lack a timestamp on user/last-prompt entries
    source_type TEXT NOT NULL,            -- 'last_prompt' | 'user_message'
    text TEXT NOT NULL,                   -- cleaned user prompt
    text_length INTEGER DEFAULT 0,
    cluster_label TEXT                    -- populated in Phase 2.6 (NEW_FEATURE/BUG_FIX/etc.)
);
CREATE INDEX IF NOT EXISTS idx_prompts_session ON prompts(session_id);
CREATE INDEX IF NOT EXISTS idx_prompts_cluster ON prompts(cluster_label);

CREATE TABLE IF NOT EXISTS tool_uses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(session_id),
    tool_use_uuid TEXT,                   -- from JSONL .message.content[].id
    ts TEXT NOT NULL,
    tool_name TEXT NOT NULL,              -- Bash, Read, Edit, Write, ...
    tool_input_json TEXT,                 -- raw JSON of .input
    intent TEXT,                          -- fix|feature|refactor|edit (inferred)
    prompt_id INTEGER REFERENCES prompts(id),
    file_path TEXT,                       -- denormalized: .input.file_path|.notebook_path|NULL
    command TEXT,                         -- denormalized: .input.command (Bash only)
    UNIQUE(session_id, ts, tool_name, tool_use_uuid)
);
CREATE INDEX IF NOT EXISTS idx_tool_uses_session ON tool_uses(session_id);
CREATE INDEX IF NOT EXISTS idx_tool_uses_name ON tool_uses(tool_name);
CREATE INDEX IF NOT EXISTS idx_tool_uses_file ON tool_uses(file_path);
CREATE INDEX IF NOT EXISTS idx_tool_uses_intent ON tool_uses(intent);

CREATE TABLE IF NOT EXISTS tool_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_use_id INTEGER NOT NULL REFERENCES tool_uses(id),
    ts TEXT,
    is_error INTEGER DEFAULT 0,           -- 0 or 1
    output_summary TEXT,                  -- first 500 chars
    output_length INTEGER DEFAULT 0       -- full output char count
);
CREATE INDEX IF NOT EXISTS idx_tool_results_use ON tool_results(tool_use_id);
CREATE INDEX IF NOT EXISTS idx_tool_results_error ON tool_results(is_error);

CREATE TABLE IF NOT EXISTS edits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_use_id INTEGER NOT NULL REFERENCES tool_uses(id),
    file_path TEXT NOT NULL,
    edit_type TEXT NOT NULL,              -- 'edit'|'write'|'multi_edit'|'notebook'
    old_string_len INTEGER DEFAULT 0,
    new_string_len INTEGER DEFAULT 0,
    is_rewrite INTEGER DEFAULT 0          -- 1 = Write or old_string empty
);
CREATE INDEX IF NOT EXISTS idx_edits_file ON edits(file_path);
CREATE INDEX IF NOT EXISTS idx_edits_use ON edits(tool_use_id);

CREATE TABLE IF NOT EXISTS cursor_ai_commits (
    -- Populated in Phase 3 from ~/.cursor/ai-tracking/ai-code-tracking.db.
    -- Composite PK matches the source schema: same commit can appear on multiple branches.
    commit_hash TEXT NOT NULL,
    branch_name TEXT NOT NULL,
    scored_at TEXT,
    lines_added INTEGER DEFAULT 0,
    lines_deleted INTEGER DEFAULT 0,
    v1_ai_percentage REAL,
    v2_ai_percentage REAL,
    model TEXT,
    workspace_root TEXT,
    PRIMARY KEY (commit_hash, branch_name)
);
