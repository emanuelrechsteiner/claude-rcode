---
name: nightly-observation
description: Nightly housekeeping — calls the safe rotate-signals.sh (archive-then-trim + pre-truncate backup + count-conservation abort), computes daily metrics, health check. Re-enabled 2026-06-21 after IMP-049 fix.
---

<!-- Erwartetes cwd: ~/.claude · Zeitgeber: launchd com.claude-code.routine-nightly-observation (seit 2026-08-22, IMP-135; Label generisch seit IMP-219, 2026-09-25; davor unversionierte Cloud-Bindung an ein 2026-08-02 umbenanntes Verzeichnis — 20 Tage stiller Ausfall). -->

Run nightly observation pipeline housekeeping. Batch job — keep tool calls minimal, fail-soft.

## Step 1 — Rotate signals (delegated to the safe script)
Run: `bash ~/.claude/scripts/rotate-signals.sh`
This script does ARCHIVE-THEN-TRIM with hard safety: it makes a timestamped .bak of signals.jsonl BEFORE any mutation, archives each past-date's entries into per-date shards, runs a count-conservation assertion, and ONLY truncates the live file to today's entries if the assertion passes. On any anomaly it ABORTS with exit 1, writes a {"blocker":true} line to alerts.jsonl, and leaves signals.jsonl untouched. It also gzips new shards, prunes archives older than CLAUDE_SIGNALS_RETENTION_DAYS (default 30), and prunes .bak files older than 7 days.
IMPORTANT: this script is the ONLY thing permitted to truncate signals.jsonl. If it exits non-zero, do NOT manually trim or delete anything — record the failure in Step 4 and stop.

## Step 2 — Compute daily metrics
From yesterday's archive (~/.claude/global-observation/archives/signals-<yesterday>.jsonl.gz), compute: tool_invocations (total), tool_invocations_by_name (top 10), errors, agent_invocations, hook_blocks, sessions (distinct session_id). Append ONE row to ~/.claude/global-observation/daily-metrics.jsonl. Idempotent: if a row for that date already exists, skip.

## Step 2b — Trim the dispatch meter (IMP-115)
`dispatch-capture.jsonl` (PreToolUse Task|Agent, live since 2026-08-01) is the source for
`agent_invocations`. It grows ~115 bytes per dispatch — small, but unbounded. Keep the last
50,000 lines; that is years of history at the observed rate, and the trim is free here rather
than costing latency in the hook:

```bash
L=~/.claude/global-observation/dispatch-capture.jsonl
if [ -f "$L" ] && [ "$(wc -l < "$L")" -gt 50000 ]; then
  tail -n 50000 "$L" > "$L.tmp" && mv "$L.tmp" "$L"
fi
```

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
- **Pseudonymisierung (IMP-219):** diese Routine schreibt heute nur nach
  `~/.claude/global-observation/*` (Laufzeitdateien, nicht versioniert) — kein
  Schritt hier erreicht eine versionierte Datei. Eine künftige Erweiterung, die
  einen Ledger-Eintrag schreibt, geht über `ledger-append-proposed.sh`, das
  jedes Textfeld als Netz tokenisiert (`scripts/vault/vault.sh`) und bei einem
  verbleibenden strukturellen Fund das Schreiben verweigert.