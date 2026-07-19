# Historical Signals v2 — Architecture

## Why SQLite (not JSONL)

The v1 pipeline stored signals as one-JSON-per-line. Six of the seven Phase X3 analyses
require joins, window functions, or indices that are awkward in jq:
- Co-Edit-Graphs: self-join on (session_id, file)
- Tool-Use-Sequences: LAG/LEAD window functions
- Error-Pattern-Extraction: tool_use ↔ tool_result join
- Diff-Size aggregation: GROUP BY edit_type, percentiles

SQLite (Python stdlib `sqlite3`) gives us these for free, with one portable .db file.

## Storage layout

Path: `~/.claude/global-observation/historical-signals.db`

Coexists with v1 `historical-signals-2023-2026.jsonl` (not deprecated). v1 remains the
"flat aggregate stream" for meta-observer's existing workflow; v2 is for deep queries.

## Schema (v2.0.0)

See `scripts/schema.sql` for the canonical definition. Tables:
- `sessions` — one row per Claude JSONL file
- `tool_uses` — one row per tool invocation across all session turns
- `tool_results` — one row per tool_result block, paired to tool_use by `tool_use_uuid`
- `edits` — one row per Edit/Write/MultiEdit/NotebookEdit, with diff sizes
- `prompts` — one row per user-typed prompt (filtered to remove `<local-command-*>` boilerplate)
- `cursor_ai_commits` (added in Phase 3) — pre-aggregated AI-% commits from Cursor SQLite

## Out of scope

- Real-time updates (this is a batch tool, run on-demand)
- Live signals.jsonl mirroring (the live hook stays as-is)
- Multi-machine sync (single-machine workflow)
