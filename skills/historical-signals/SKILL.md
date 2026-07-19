---
name: historical-signals
description: "Convert historical Claude Code JSONL session files into signals.jsonl format for meta-observer ingestion. Use when running historical observation analysis, ingesting past session data into the improvement pipeline, performing multi-month/year deep-dive aggregations, or comparing cross-project tool-use trends. Triggers on 'historical analysis', 'analyze past sessions', 'cross-project aggregation', 'multi-year signal trends', 'ingest session history'."
context: fork
model: haiku
allowed-tools: Bash, Read, Write, Glob
---

# Historical Signals Converter

Converts Claude Code session JSONL files (`~/.claude/projects/*/*.jsonl` or older snapshots) into the `signals.jsonl` schema that meta-observer consumes. Enables retrospective analysis over weeks/months/years of session history.

## When To Use

- **Periodic deep-dive analysis** — beyond meta-observer's normal 30-day window
- **Comparing historical periods** — "tool-use evolution 2024 → 2026"
- **Cross-project pattern hunting** — "which files do I edit most across all projects?"
- **Validation runs** — testing meta-observer on known-shape historical data

Do **not** use for daily/weekly meta-observer runs — those should consume the live `signals.jsonl` produced by `observation-capture.sh`.

## Quick Start

### Convert one session

```bash
~/.claude/skills/historical-signals/scripts/convert-claude-jsonl.sh \
    ~/.claude/projects/<dir>/<session>.jsonl
```

Output: one signal per line on stdout, signals.jsonl schema with added `source` field.

### Bulk-convert a directory tree

```bash
OUT=~/.claude/global-observation/historical-signals-$(date +%Y-%m-%d).jsonl
> "$OUT"

find ~/.claude/projects/ -name "*.jsonl" -type f -not -path "*/sessions/*" 2>/dev/null | \
    while read f; do
        ~/.claude/skills/historical-signals/scripts/convert-claude-jsonl.sh "$f" >> "$OUT"
    done

# Sort by timestamp for chronological analysis
jq -s 'sort_by(.ts)' "$OUT" | jq -c '.[]' > "$OUT.sorted"
mv "$OUT.sorted" "$OUT"

echo "Total signals: $(wc -l < $OUT)"
echo "Date range: $(jq -r '.ts' $OUT | head -1) → $(jq -r '.ts' $OUT | tail -1)"
```

## Output Schema

Each output line matches `signals.jsonl` plus an extra `source` field:

```json
{
  "ts": "2026-04-15T14:23:01Z",
  "cwd": "/Users/.../project-root",
  "intent": "fix|refactor|feature|edit",
  "file": "/absolute/path/edited.ts",
  "branch": "",
  "rcode": true,
  "source": "claude_jsonl_historical"
}
```

`branch` stays empty — historical JSONLs don't carry git branch info reliably.
`source` distinguishes historical from live signals so meta-observer can weight them.

## How It Works

### Intent inference (per tool use)

For each Edit/Write/MultiEdit/NotebookEdit in an assistant turn:
1. Look back at the **5 most recent user messages** before this assistant turn
2. Take the most recent non-empty user text
3. Match keyword groups:
   - `fix|bug|hotfix|repair|broken|crash|error|fail|issue|fehler|behoben` → **fix**
   - `refactor|restructure|cleanup|extract|simplify|reorganize|umstrukturieren` → **refactor**
   - `add|implement|create|new|build|feature|implementiere|erstelle` → **feature**
   - default → **edit**

This is **per-tool-use** classification — different signals in the same session can have different intents (improvement over the v1 prototype which session-classified uniformly).

### cwd derivation

Walks up the directory tree from the **first file_path** in the session:
- Stops at `.git`, `package.json`, `.claude`, `.rcode`, `Package.swift`, or `*.xcodeproj`
- Falls back to `dirname(first_file_path)` if no marker found
- Falls back to lossy project-dir-name decode if no file_path in session

Beats the v1 prototype's pure project-name decode that mangled underscores (`CPI_Gaming` → `/CPI/Gaming`).

### R.Code detection

Content-based regex over the entire JSONL:
- `.rcode` (directory reference)
- `/issue`, `/phase-gate`, `/decompose`, `/brainstorm` (slash commands)
- `PROJECT-STATUS.md` (R.Code artifact)

Any match → `rcode: true`. Detects adoption even when the session cwd isn't inside a `.rcode/` project.

## Caveats

- **Branch field always empty** — Claude JSONLs don't reliably record git branch
- **Intent inference is heuristic** — short user messages or off-topic chitchat may misclassify; absent context defaults to `edit`
- **Older JSONLs may have schema variations** — script silently skips parse errors per file
- **cwd accuracy depends on filesystem state** — for very old sessions whose files no longer exist, falls back to `dirname` (less project-grouped)

## Idempotency

Safe to re-run. The converter writes to stdout only; the caller decides where output goes. Recommended pattern: truncate then repopulate (`> "$OUT"` then `>> "$OUT"`).

## Related

- `[[meta-observer]]` — consumes the historical-signals output for synthesis
- `[[observation-capture]]` (hook) — produces the **live** signals.jsonl this skill mirrors
- See `~/claude-framework-consolidation/02-triage/META-OBSERVER-SAMPLE-REPORT.md` for the v1 prototype that motivated this skill (IMP-D)
