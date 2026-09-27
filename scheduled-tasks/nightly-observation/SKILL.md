---
name: nightly-observation
description: Nightly housekeeping — calls the safe rotate-signals.sh (archive-then-trim + pre-truncate backup + count-conservation abort), then compute-daily-metrics.sh for the metrics row, health check. Re-enabled 2026-06-21 after IMP-049 fix.
---

<!-- Expected cwd: ~/.claude · Timer: launchd com.claude-code.routine-nightly-observation (since 2026-08-22, IMP-135; label made generic since IMP-219, 2026-09-25; before that an unversioned cloud binding to a directory renamed on 2026-08-02 — 20 days of silent failure). -->

Run nightly observation pipeline housekeeping. Batch job — keep tool calls minimal, fail-soft.

## Step 1 — Rotate signals (delegated to the safe script)
Run: `bash ~/.claude/scripts/rotate-signals.sh`
This script does ARCHIVE-THEN-TRIM with hard safety: it makes a timestamped .bak of signals.jsonl BEFORE any mutation, archives each past-date's entries into per-date shards (UTC days), runs a count-conservation assertion, merges each new plain shard into any existing .gz and recompresses it (STEP 3c, IMP-226 — a late entry never overwrites an archived day), and ONLY THEN truncates the live file to today's entries. A day with zero signals gets a valid, content-empty .gz shard (IMP-221), not a missing one. It prunes archives older than CLAUDE_SIGNALS_RETENTION_DAYS (default 30) and .bak files older than 7 days.
Exit codes (the script's header is the authority; every non-zero exit writes one alert line): **0** ok (or nothing to do) · **1** content check refused, nothing mutated · **2** script error (the alert says in which stage and whether the live file was already trimmed) · **3** continuity of signals.jsonl NOT proven — rotation completed, only the empty-shard fill was skipped, so the affected days stay without a shard on purpose.
IMPORTANT: this script is the ONLY thing permitted to truncate signals.jsonl. On any non-zero exit never trim, delete, merge or back-fill shards by hand — record the exit code in Step 4. On 1 or 2 stop. On 3 continue with Step 2 (a consumer abort for a shard-less day is the intended loud outcome).

## Step 2 — Compute daily metrics (delegated to the script, IMP-227)
Run: `bash ~/.claude/scripts/compute-daily-metrics.sh "$(date -u -v-1d +%Y-%m-%d)"`
The argument is yesterday in UTC (`YYYY-MM-DD`; also the script's default when omitted — same day boundary as Step 1). The script is the ONLY place these numbers are derived — do not compute or patch any metric yourself. It appends one row to daily-metrics.jsonl and is idempotent (an existing row for the date → skip, exit 0). A row with `"shard_state":"empty_verified"` and all-zero counts is expected on a zero-signal day (gzip-verified empty shard) — not an error.
Exit **1** = shard missing, corrupt, or a 0-byte plain shard (blocker alert already written, no row); exit **2** = script error. On any non-zero exit record it in Step 4 and never work around it (no hand-written row, no re-run against another file).

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
- **Pseudonymization (IMP-219):** this routine today only writes to
  `~/.claude/global-observation/*` (runtime files, not versioned) — no
  step here reaches a versioned file. A future extension that writes
  a ledger entry goes through `ledger-append-proposed.sh`, which
  tokenizes every text field as a net (`scripts/vault/vault.sh`) and
  refuses to write on a remaining structural finding.
- **Counts need their command (IMP-221):** any count you record about a transcript (tool
  calls, Edit/Write events, sessions) must be followed by the exact command that produced it.
  A count without its command is not a finding and must not be carried into a later run's notes.