---
name: historical-signals-v2
description: "Enriched historical signal extraction with full tool-use coverage (Bash, Read, Edit, etc.), tool-results, and SQLite storage. Use for deep retrospective analyses requiring relational queries (co-edit graphs, tool-use sequences, error patterns). Triggers on 'deep historical analysis', 'tool-use sequences', 'co-edit graph', 'error pattern extraction', 'cross-source signal join'."
context: fork
model: haiku
allowed-tools: Bash, Read, Write, Edit, Glob
---

# Historical Signals v2

Enriched, SQLite-backed successor to `historical-signals` (v1). Captures full
tool-use coverage (not just Edit/Write), tool_results with error flags, edit diff
sizes, user prompts, and cross-source Cursor commit data. Designed for relational
queries that v1's flat JSONL stream can't answer efficiently.

## When to use this skill (v2) vs. v1

| Task | Use |
|------|-----|
| Quick per-day/per-tool/per-project trend counts | **v1** (`historical-signals-2023-2026.jsonl`) |
| Tool-use sequences (e.g. fail→edit→pass loops) | **v2** (needs window functions) |
| Error-rate per tool, error-cluster files | **v2** (needs tool_use↔tool_result join) |
| Co-edit graphs (which files are edited together) | **v2** (needs self-join on session_id) |
| Diff-size distribution / rewrite-heaviness | **v2** (needs edit-level diff stats) |
| Cursor AI-tracking cross-source | **v2** (needs cursor_ai_commits) |
| Synthesis report generation (Phase X-class) | **v2** for the data, **planning-agent** for the report |

v1 stays alive; this skill does not deprecate it. Coexist.

## Quick start

### 1. Initial batch ingest (5-15 min, one-time per data refresh)

```bash
bash ~/.claude/skills/historical-signals-v2/scripts/batch-ingest.sh
```

Reads all JSONL files under `~/.claude/projects/` by default. To also ingest
historical session archives from other locations, set `CLAUDE_HISTORICAL_SOURCES`
(colon-separated list of directories):

```bash
export CLAUDE_HISTORICAL_SOURCES="$HOME/archive/claude-jsonl:/Volumes/External/old-sessions"
bash ~/.claude/skills/historical-signals-v2/scripts/batch-ingest.sh
```

Populates `~/.claude/global-observation/historical-signals.db` (size depends on
input volume — ~80MB at ~1274 input files). Idempotent: rerunning wipes and rebuilds.

### 2. Run all canned analyses (~5s)

```bash
bash ~/.claude/skills/historical-signals-v2/scripts/run-analyses.sh
```

Writes 5 finding files into `~/claude-framework-consolidation/02-triage/x3-findings/`:
- `01-bash-commands.txt` — top Bash commands, top failing commands
- `02-sequences.txt` — consecutive tool-pair counts, fail→edit→pass triples
- `03-errors.txt` — recurring error heads, per-tool error rate, files with most errors
- `04-co-edits.txt` — top co-edited file pairs (architectural-neighbor graph)
- `05-diff-sizes.txt` — edit-type distribution, top files by chars written, rewrite-heaviness

(Findings #06 prompt-clusters and #07 cursor-cross-source are produced by separate scripts; see below.)

### 3. Cursor cross-source ingest (~1s)

```bash
python3 ~/.claude/skills/historical-signals-v2/scripts/cursor_ingest.py \
    ~/.claude/global-observation/historical-signals.db
```

Ingests Cursor's `~/.cursor/ai-tracking/ai-code-tracking.db` (~659 commits) into
`cursor_ai_commits` table. Source schema lacks model column and stores AI percentages as
TEXT (often empty) — adapter handles this gracefully.

### 4. Prompt clustering (LLM-based, ~$3-8, ~25 min)

```bash
ANTHROPIC_API_KEY=sk-... python3 ~/.claude/skills/historical-signals-v2/scripts/cluster_prompts.py
```

Sequential Haiku 4.5 classification of all prompts (text_length > 20) into 10
categories. Updates `prompts.cluster_label`. Skippable; the structural analyses
work without it.

## Schema overview

7 tables in `~/.claude/global-observation/historical-signals.db`:

- `sessions` — one row per Claude JSONL file (deduped by session_id; older identical sessions overwritten)
- `tool_uses` — one row per tool invocation; denormalizes file_path (Edit/Write/Read) and command (Bash); links to prompts via `prompt_id` and exposes `intent` (regex-inferred: fix/refactor/feature/edit)
- `tool_results` — paired to tool_use by uuid; `is_error` flag + `output_summary` (first 500 chars) + `output_length`
- `edits` — one row per Edit/Write/MultiEdit/NotebookEdit with old/new string lengths and `is_rewrite` flag
- `prompts` — deduped within a session (first occurrence wins across user-message + last-prompt entries); `cluster_label` populated by `cluster_prompts.py`
- `cursor_ai_commits` — Cursor scored_commits with composite PK (commit_hash, branch_name)
- `schema_version` — single row, currently `2.0.0`

See `scripts/schema.sql` for full DDL.

## Caveats

- **Extra sources heavily overlap active sessions** via session_id dedup (e.g. ~1274 input files may collapse to ~290 unique sessions)
- **Prompts.ts is nullable** — older session formats omit timestamps on user/last-prompt entries
- **Cursor v2_ai_percentage is ~98.5% NULL in real data** — Cursor's scorer doesn't populate most commits
- **Cluster_label has ~11.5% UNCLEAR rate** — Haiku rebels when prompt content contains its own instructions; UNCLEAR also captures Claude Code's auto-compaction "create a detailed summary" system prompts that the extractor incorrectly treats as user input
- **Same-session deduplication is destructive** — if you need to track which JSONL file contributed which sessions, that information is lost after the second copy is ingested (only the most-recent jsonl_path is stored)

## Adding a new analysis

1. Write the SQL as a heredoc or `.sql` file under `scripts/`
2. Run via `sqlite3 ~/.claude/global-observation/historical-signals.db -header -column < query.sql`
3. Save output to a new `~/claude-framework-consolidation/02-triage/x3-findings/0X-name.txt`
4. Append your interpretation bullets to the same file
5. Update `aggregates-v2.txt` (concat) before next synthesis

## Provenance

Built during Phase X3 of the framework-consolidation project (2026-05-24).
Plan, execution log, and output report live in the author's working artifacts
directory (`~/claude-framework-consolidation/02-triage/`) — not shipped with
this skill, but referenced for historical IMP-033..042 traceability.
