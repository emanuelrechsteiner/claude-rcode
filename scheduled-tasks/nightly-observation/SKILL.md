---
name: nightly-observation
description: Nightly housekeeping — calls the safe rotate-signals.sh (archive-then-trim + pre-truncate backup + count-conservation abort), computes daily metrics, health check. Re-enabled 2026-06-21 after IMP-049 fix.
---

Run nightly observation pipeline housekeeping. Batch job — keep tool calls minimal, fail-soft.

## Step 1 — Rotate signals (delegated to the safe script)
Run: `bash ~/.claude/scripts/rotate-signals.sh`
This script does ARCHIVE-THEN-TRIM with hard safety: it makes a timestamped .bak of signals.jsonl BEFORE any mutation, archives each past-date's entries into per-date shards, runs a count-conservation assertion, and ONLY truncates the live file to today's entries if the assertion passes. On any anomaly it ABORTS with exit 1, writes a {"blocker":true} line to alerts.jsonl, and leaves signals.jsonl untouched. It also gzips new shards, prunes archives older than CLAUDE_SIGNALS_RETENTION_DAYS (default 30), and prunes .bak files older than 7 days.
IMPORTANT: this script is the ONLY thing permitted to truncate signals.jsonl. If it exits non-zero, do NOT manually trim or delete anything — record the failure in Step 4 and stop.

## Step 2 — Compute daily metrics
From yesterday's archive (~/.claude/global-observation/archives/signals-<yesterday>.jsonl.gz), compute: tool_invocations (total), tool_invocations_by_name (top 10), errors, agent_invocations, hook_blocks, sessions (distinct session_id). Append ONE row to ~/.claude/global-observation/daily-metrics.jsonl. Idempotent: if a row for that date already exists, skip.

## Step 3 — Health check
Verify signals.jsonl exists and is writable, the archive dir is writable, and daily-metrics.jsonl has a row for yesterday.

## Step 4 — Log result
Append one row to ~/.claude/global-observation/nightly-obs-log.jsonl:
{"date":"YYYY-MM-DD","ts":<unix>,"status":"ok|partial|fail","entries_rotated":N,"error":"..."}

## Step 5 — Notify on failure only
If any step failed (including rotate-signals.sh exiting non-zero), append to ~/.claude/global-observation/alerts.jsonl AND surface it in the next morning's daily-docs entry as a blocker.

## Constraints
- Pure scripting; no destructive manual operations on signals.jsonl.
- Idempotent (re-running same day must not duplicate metrics or re-archive).
- Fail-soft; finish under 60 seconds.