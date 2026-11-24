#!/usr/bin/env bash
# Regression suite for scripts/routine-run.sh — the stdin fix for the
# claude call.
#
# Why this suite exists: all three launchd routines (daily-docs,
# nightly-observation, weekly-improve) have failed with "claude exited 1"
# ever since their very first run on 2026-08-23. Cause: the prompt (the
# full SKILL.md content, starting with the YAML frontmatter "---") was
# passed as a POSITIONAL ARGUMENT. claude's own option parser reads a
# positional argument starting with "--" as an unknown option:
#   claude -p "$(printf -- '---\nname: x\n---\nSag OK')" --model X
#   -> error: unknown option '---
# The fix passes the prompt via STDIN instead
# (`claude -p --model sonnet ... < "$SKILL_FILE"`), which never reaches the
# option parser at all. Reproduced against the real binary (claude 2.1.266,
# 2026-09-09):
#   claude -p "$(printf -- '---\n...')" --model definitiv-kein-modell
#     -> exit 1, "error: unknown option '---"
#   printf -- '---\n...' | claude -p --model definitiv-kein-modell
#     -> exit 1, but ONLY because of the invalid model name — no
#        "unknown option" in stderr. Case D below repeats exactly that.
#
# This suite works EXCLUSIVELY with scratch directories
# (CLAUDE_ROUTINE_CLAUDE_DIR / CLAUDE_ROUTINE_LOG_DIR) and a stub binary
# (CLAUDE_BIN) — it writes nothing under ~/.claude/global-observation/ and
# never triggers a real claude run with a valid model.
#
# Usage: bash scripts/tests/routine-run-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../routine-run.sh"
[ -f "$RUNNER" ] || { echo "routine-run.sh not found: $RUNNER" >&2; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf '  [%s] %s\n' "$1" "$2"; }
check(){ # check <name> <expected> <got>
  if [ "$2" = "$3" ]; then ok; else bad "$1" "expected='$2' got='$3'"; fi
}

ROOT=$(mktemp -d)

# ── Stub claude: writes argv + stdin to files, NEVER calls the real binary.
#    Exit code controllable via STUB_EXIT_CODE (default 0). ────────────────
STUB="$ROOT/claude-stub.sh"
cat > "$STUB" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$@" > "$STUB_ARGV_FILE"
cat > "$STUB_STDIN_FILE"
# STUB_ENV_FILE: record what the runner set for goal tracking (IMP-289).
if [ -n "${STUB_ENV_FILE:-}" ]; then printf '%s\n' "${CLAUDE_GOAL_TRACKING:-unset}" > "$STUB_ENV_FILE"; fi
# STUB_LOG_FILE: play the SKILL's own run-log step (one ok line, ts = now).
if [ -n "${STUB_LOG_FILE:-}" ]; then
  mkdir -p "$(dirname "$STUB_LOG_FILE")"
  jq -nc '{ts: (now | floor), status: "ok"}' >> "$STUB_LOG_FILE"
fi
exit "${STUB_EXIT_CODE:-0}"
STUBEOF
chmod +x "$STUB"

# setup_task <task> -> creates a scratch CLAUDE_DIR with a SKILL.md for <task>
# and sets CDIR/SKILL for the caller.
setup_task() {
  local task="$1"
  CDIR="$ROOT/claude-home-$task"
  mkdir -p "$CDIR/scheduled-tasks/$task"
  SKILL="$CDIR/scheduled-tasks/$task/SKILL.md"
  printf -- '---\nname: %s\ndescription: test routine\n---\nSay OK and stop.\n' "$task" > "$SKILL"
}

# ── A) Stub claude gets the SKILL.md byte-exact via stdin; argv contains
#      NO prompt text and does not start with "---" ────────────────────────
setup_task daily-docs
ARGV_A="$ROOT/argv-a.txt"; STDIN_A="$ROOT/stdin-a.txt"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_A" STUB_STDIN_FILE="$STDIN_A" STUB_EXIT_CODE=0 \
  STUB_LOG_FILE="$CDIR/global-observation/daily-docs-log.jsonl" STUB_ENV_FILE="$ROOT/env-a.txt" \
  bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "stdinform/exit0" 0 "$RC"
check "stdinform/goal-tracking-switched-off-for-the-routine" 0 "$(cat "$ROOT/env-a.txt" 2>/dev/null)"
if [ -f "$STDIN_A" ] && cmp -s "$SKILL" "$STDIN_A"; then ok; else
  bad "stdinform/stdin-byte-exact" "STDIN differs from $SKILL (or is missing)"
fi
check "stdinform/argv-exact" \
  "$(printf '%s\n' -p --model haiku --dangerously-skip-permissions)" \
  "$([ -f "$ARGV_A" ] && cat "$ARGV_A")"
check "stdinform/argv-does-not-start-with-dashdashdash" 0 \
  "$([ -f "$ARGV_A" ] && head -1 "$ARGV_A" | grep -c '^---')"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-daily-docs" 2>/dev/null

# ── B) Stub claude ends with exit 1 -> runner writes the error line to the
#      run log and itself ends with 1 (existing behavior) ──────────────────
setup_task nightly-observation
LOG_DIR_B="$ROOT/logs-b"
ARGV_B="$ROOT/argv-b.txt"; STDIN_B="$ROOT/stdin-b.txt"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_B" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_B" STUB_STDIN_FILE="$STDIN_B" STUB_EXIT_CODE=1 \
  bash "$RUNNER" nightly-observation >/dev/null 2>&1
RC=$?
check "claudefail/exit1" 1 "$RC"
check "modelmap/nightly-observation-real-argv-haiku" \
  "$(printf '%s\n' -p --model haiku --dangerously-skip-permissions)" \
  "$([ -f "$ARGV_B" ] && cat "$ARGV_B")"
check "claudefail/log-line" 1 \
  "$(jq -sr '[.[] | select((.note // "") | startswith("runner: claude exited 1 for nightly-observation; stderr tail: (empty)"))] | length' \
     "$LOG_DIR_B/nightly-obs-log.jsonl" 2>/dev/null)"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-nightly-observation" 2>/dev/null

# ── C) Lock already held -> runner aborts WITHOUT calling claude
#      (existing behavior, unchanged by the stdin fix) ─────────────────────
setup_task weekly-improve
LOG_DIR_C="$ROOT/logs-c"
LOCK_DIR_C="${TMPDIR:-/tmp}/claude-routine-lock-weekly-improve"
mkdir -p "$LOCK_DIR_C"
ARGV_C="$ROOT/argv-c.txt"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_C" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_C" STUB_STDIN_FILE="$ROOT/stdin-c.txt" STUB_EXIT_CODE=0 \
  bash "$RUNNER" weekly-improve >/dev/null 2>&1
RC=$?
check "lockheld/exit1" 1 "$RC"
check "lockheld/claude-not-called" 0 "$([ -f "$ARGV_C" ] && echo 1 || echo 0)"
rm -rf "$CDIR"; rmdir "$LOCK_DIR_C" 2>/dev/null

# ── D) Parser proof against the REAL claude binary (only if present):
#      stdin form + a guaranteed-invalid model -> no "unknown option"
#      in stderr. No real run: the invalid model prevents that. ────────────
if command -v claude >/dev/null 2>&1; then
  REAL_CLAUDE="$(command -v claude)"
  PROBE_SKILL="$ROOT/probe-skill.md"
  printf -- '---\nname: probe\n---\nSay OK\n' > "$PROBE_SKILL"
  # Run from a throwaway cwd ($ROOT), never from the project folder: even with
  # an invalid --model, claude still starts a real session and fires
  # SessionStart hooks in whatever directory it's invoked from — running it
  # here would hijack the Cockpit, which follows the newest session per
  # project folder (observed live: the owner's Cockpit jumped to this dead
  # probe session twice).
  REALOUT=$(cd "$ROOT" && timeout 20 "$REAL_CLAUDE" -p --model definitiv-kein-modell < "$PROBE_SKILL" 2>&1)
  check "realbinary/no-unknown-option" 0 "$(printf '%s' "$REALOUT" | grep -c 'unknown option')"
else
  echo "  [skipped] Case D: no real claude binary found on PATH"
fi

# ── E) --dry-run runs the parser proof (IMP-190): the stub binary
#      is ACTUALLY invoked with --model claude-dry-run-proof-invalid
#      (no real run, that's exactly the point) and reports PASS when
#      stderr contains no "unknown option" — the plain stub above never
#      prints anything to stderr, so the proof line here must say PASS. ────
setup_task daily-docs
ARGV_E="$ROOT/argv-e.txt"; STDIN_E="$ROOT/stdin-e.txt"
DRYOUT_E=$(CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_E" STUB_STDIN_FILE="$STDIN_E" STUB_EXIT_CODE=1 \
  bash "$RUNNER" daily-docs --dry-run 2>&1)
RC=$?
check "dryrun-proof/exit0" 0 "$RC"
check "dryrun-proof/contains-parserproof-section" 1 \
  "$(printf '%s\n' "$DRYOUT_E" | grep -c 'parser_proof:')"
check "dryrun-proof/reports-PASS" 1 \
  "$(printf '%s\n' "$DRYOUT_E" | grep -c 'PASS — CLI parser accepted')"
check "dryrun-proof/stub-actually-called-with-invalid-model" 1 \
  "$([ -f "$ARGV_E" ] && grep -c 'claude-dry-run-proof-invalid' "$ARGV_E")"
rm -rf "$CDIR"

# ── F) If the (stub) binary prints "unknown option" to stderr on EVERY
#      call, the parser proof must report that as FAIL instead of
#      swallowing it — and --dry-run still ends in exit 0 regardless
#      (the proof is advisory, not a gate). ──
setup_task nightly-observation
STUB_F="$ROOT/claude-stub-unknownopt.sh"
cat > "$STUB_F" <<'STUBEOF'
#!/bin/bash
echo "error: unknown option '---" >&2
exit 1
STUBEOF
chmod +x "$STUB_F"
DRYOUT_F=$(CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_BIN="$STUB_F" \
  bash "$RUNNER" nightly-observation --dry-run 2>&1)
RC=$?
check "dryrun-proof-fail/exit0-despite-FAIL" 0 "$RC"
check "dryrun-proof-fail/reports-FAIL" 1 \
  "$(printf '%s\n' "$DRYOUT_F" | grep -c 'FAIL — invocation shape')"
rm -rf "$CDIR"

# ── H) Per-task model map (IMP-255): daily-docs runs haiku, weekly-improve
#      runs opus. Dry-run echo and real run both use the mapped value. ────────
setup_task daily-docs
DRYOUT_H1=$(CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ROOT/argv-h1.txt" STUB_STDIN_FILE="$ROOT/stdin-h1.txt" \
  bash "$RUNNER" daily-docs --dry-run 2>&1)
check "modelmap/daily-dryrun-echo-haiku" 1 \
  "$(printf '%s\n' "$DRYOUT_H1" | grep -c -- '--model haiku --dangerously-skip-permissions < ')"
rm -rf "$CDIR"

setup_task weekly-improve
DRYOUT_H2=$(CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ROOT/argv-h2.txt" STUB_STDIN_FILE="$ROOT/stdin-h2.txt" \
  bash "$RUNNER" weekly-improve --dry-run 2>&1)
check "modelmap/weekly-dryrun-echo-opus" 1 \
  "$(printf '%s\n' "$DRYOUT_H2" | grep -c -- '--model opus --dangerously-skip-permissions < ')"
check "modelmap/weekly-dryrun-no-sonnet" 0 \
  "$(printf '%s\n' "$DRYOUT_H2" | grep -c 'model sonnet')"
ARGV_H="$ROOT/argv-h.txt"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_H" STUB_STDIN_FILE="$ROOT/stdin-h.txt" STUB_EXIT_CODE=0 \
  bash "$RUNNER" weekly-improve >/dev/null 2>&1
check "modelmap/weekly-real-argv-opus" \
  "$(printf '%s\n' -p --model opus --dangerously-skip-permissions)" \
  "$([ -f "$ARGV_H" ] && cat "$ARGV_H")"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-weekly-improve" 2>/dev/null

# ── I) claude exits 0 but the routine wrote no run-log line -> runner logs
#      the gap and exits 1 (IMP-075: silence must never look like success) ──
setup_task daily-docs
LOG_DIR_I="$ROOT/logs-i"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_I" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ROOT/argv-i.txt" STUB_STDIN_FILE="$ROOT/stdin-i.txt" STUB_EXIT_CODE=0 \
  bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "silent-exit0/exit1" 1 "$RC"
check "silent-exit0/log-line" 1 \
  "$(jq -sr '[.[] | select((.note // "") | contains("wrote no run-log line"))] | length' "$LOG_DIR_I/daily-docs-log.jsonl" 2>/dev/null)"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-daily-docs" 2>/dev/null

# ── J) claude exits 0 and the routine wrote its own line -> exit 0 and the
#      runner adds NO error line of its own ───────────────────────────────────
setup_task daily-docs
LOG_DIR_J="$ROOT/logs-j"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_J" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ROOT/argv-j.txt" STUB_STDIN_FILE="$ROOT/stdin-j.txt" STUB_EXIT_CODE=0 \
  STUB_LOG_FILE="$LOG_DIR_J/daily-docs-log.jsonl" \
  bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "routine-wrote-line/exit0" 0 "$RC"
check "routine-wrote-line/no-runner-error-line" 0 \
  "$(jq -sr '[.[] | select(has("note"))] | length' "$LOG_DIR_J/daily-docs-log.jsonl" 2>/dev/null)"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-daily-docs" 2>/dev/null

# ── K) claude exits 3 with 5 stderr lines -> exit code propagated, the note
#      carries exactly the last 3 stderr lines (truncated, jq-escaped) ───────
setup_task daily-docs
STUB_K="$ROOT/claude-stub-stderr.sh"
cat > "$STUB_K" <<'STUBEOF'
#!/bin/bash
cat > /dev/null
for n in 1 2 3 4 5; do echo "stderr-line-$n" >&2; done
exit 3
STUBEOF
chmod +x "$STUB_K"
LOG_DIR_K="$ROOT/logs-k"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_K" CLAUDE_BIN="$STUB_K" \
  bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "stderr-tail/exit-propagated" 3 "$RC"
NOTE_K="$(jq -sr '.[-1].note // ""' "$LOG_DIR_K/daily-docs-log.jsonl" 2>/dev/null)"
check "stderr-tail/last-3-lines" 1 \
  "$(printf '%s' "$NOTE_K" | grep -c 'stderr tail: stderr-line-3 | stderr-line-4 | stderr-line-5$')"
check "stderr-tail/older-lines-excluded" 0 "$(printf '%s' "$NOTE_K" | grep -c 'stderr-line-1')"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-daily-docs" 2>/dev/null

# ── L) SIGTERM during a run (launchd stop/timeout) -> runner logs the signal,
#      exits 1 and releases its lock. bash runs the trap after claude ends. ──
setup_task daily-docs
STUB_L="$ROOT/claude-stub-sleep.sh"
cat > "$STUB_L" <<'STUBEOF'
#!/bin/bash
cat > /dev/null
sleep 2
exit 0
STUBEOF
chmod +x "$STUB_L"
LOG_DIR_L="$ROOT/logs-l"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_L" CLAUDE_BIN="$STUB_L" \
  bash "$RUNNER" daily-docs >/dev/null 2>&1 &
RUNNER_PID=$!
sleep 1
kill -TERM "$RUNNER_PID" 2>/dev/null
wait "$RUNNER_PID"
RC=$?
check "sigterm/exit1" 1 "$RC"
check "sigterm/log-line" 1 \
  "$(jq -sr '[.[] | select((.note // "") | contains("terminated by SIGTERM"))] | length' "$LOG_DIR_L/daily-docs-log.jsonl" 2>/dev/null)"
check "sigterm/lock-released" 0 "$([ -d "${TMPDIR:-/tmp}/claude-routine-lock-daily-docs" ] && echo 1 || echo 0)"
rm -rf "$CDIR"

# ── M) lock left behind by a dead holder (SIGKILL, power cut) -> reclaimed,
#      logged, and the run proceeds ──────────────────────────────────────────
setup_task daily-docs
LOCK_M="${TMPDIR:-/tmp}/claude-routine-lock-daily-docs"
rm -f "$LOCK_M/pid"; rmdir "$LOCK_M" 2>/dev/null; mkdir "$LOCK_M"
( exit 0 ) & DEAD_PID=$!; wait "$DEAD_PID"
echo "$DEAD_PID" > "$LOCK_M/pid"
LOG_DIR_M="$ROOT/logs-m"; ARGV_M="$ROOT/argv-m.txt"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_M" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_M" STUB_STDIN_FILE="$ROOT/stdin-m.txt" STUB_EXIT_CODE=0 \
  STUB_LOG_FILE="$LOG_DIR_M/daily-docs-log.jsonl" \
  bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "stale-lock/run-proceeds-exit0" 0 "$RC"
check "stale-lock/claude-called" 1 "$([ -f "$ARGV_M" ] && echo 1 || echo 0)"
check "stale-lock/reclaim-logged" 1 \
  "$(jq -sr '[.[] | select((.note // "") | contains("reclaimed stale lock"))] | length' "$LOG_DIR_M/daily-docs-log.jsonl" 2>/dev/null)"
rm -rf "$CDIR"

# ── N) lock held by a LIVE holder (this test shell's pid) -> still refused,
#      claude not called, lock left untouched ─────────────────────────────────
setup_task weekly-improve
LOCK_N="${TMPDIR:-/tmp}/claude-routine-lock-weekly-improve"
rm -f "$LOCK_N/pid"; rmdir "$LOCK_N" 2>/dev/null; mkdir "$LOCK_N"; echo $$ > "$LOCK_N/pid"
ARGV_N="$ROOT/argv-n.txt"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$ROOT/logs-n" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ARGV_N" STUB_STDIN_FILE="$ROOT/stdin-n.txt" STUB_EXIT_CODE=0 \
  bash "$RUNNER" weekly-improve >/dev/null 2>&1
RC=$?
check "live-holder/exit1" 1 "$RC"
check "live-holder/claude-not-called" 0 "$([ -f "$ARGV_N" ] && echo 1 || echo 0)"
check "live-holder/lock-kept" 1 "$([ -f "$LOCK_N/pid" ] && echo 1 || echo 0)"
rm -f "$LOCK_N/pid"; rmdir "$LOCK_N" 2>/dev/null; rm -rf "$CDIR"

# ── O) jq missing -> exit 2 AND a fixed log line in routine-run-errors.jsonl
#      (the one exit path that previously wrote no line at all) ──────────────
LOG_DIR_O="$ROOT/logs-o"
env PATH=/bin CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_O" /bin/bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "no-jq/exit2" 2 "$RC"
check "no-jq/errors-line" 1 \
  "$(jq -sr '[.[] | select(.status == "error" and (.note | contains("jq not found")))] | length' "$LOG_DIR_O/routine-run-errors.jsonl" 2>/dev/null)"

# ── P) stale lock reclaimed, routine writes NO line -> the runner's own
#      "reclaimed stale lock" line (fresh numeric ts) must NOT count as the
#      routine's line: the run still fails loud ───────────────────────────────
setup_task daily-docs
LOCK_P="${TMPDIR:-/tmp}/claude-routine-lock-daily-docs"
rm -f "$LOCK_P/pid"; rmdir "$LOCK_P" 2>/dev/null; mkdir "$LOCK_P"
( exit 0 ) & DEAD_P=$!; wait "$DEAD_P"
echo "$DEAD_P" > "$LOCK_P/pid"
LOG_DIR_P="$ROOT/logs-p"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_P" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ROOT/argv-p.txt" STUB_STDIN_FILE="$ROOT/stdin-p.txt" STUB_EXIT_CODE=0 \
  bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "stale-no-line/exit1" 1 "$RC"
check "stale-no-line/reclaim-logged" 1 \
  "$(jq -sr '[.[] | select((.note // "") | contains("reclaimed stale lock"))] | length' "$LOG_DIR_P/daily-docs-log.jsonl" 2>/dev/null)"
check "stale-no-line/reclaim-line-not-counted" 1 \
  "$(jq -sr '[.[] | select((.note // "") | contains("wrote no run-log line"))] | length' "$LOG_DIR_P/daily-docs-log.jsonl" 2>/dev/null)"
rm -rf "$CDIR"; rmdir "$LOCK_P" 2>/dev/null

# ── Q1) ISO8601 timestamps (weekly-improve form). A pre-existing line from
#      2020 AND a line the routine appends during the run with an old ISO ts
#      must both be ignored -> the "wrote no run-log line" error still fires.
#      (A raw `.ts >= n` compare sorts strings after numbers and passes both.) ──
setup_task daily-docs
LOG_DIR_Q1="$ROOT/logs-q1"; mkdir -p "$LOG_DIR_Q1"
printf '%s\n' '{"ts":"2020-01-01T00:00:00Z","status":"ok","task":"daily-docs"}' > "$LOG_DIR_Q1/daily-docs-log.jsonl"
STUB_Q1="$ROOT/claude-stub-iso-old.sh"
cat > "$STUB_Q1" <<'STUBEOF'
#!/bin/bash
cat > /dev/null
jq -nc '{ts: "2020-01-02T00:00:00Z", status: "ok"}' >> "$STUB_LOG_FILE"
exit 0
STUBEOF
chmod +x "$STUB_Q1"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_Q1" CLAUDE_BIN="$STUB_Q1" \
  STUB_LOG_FILE="$LOG_DIR_Q1/daily-docs-log.jsonl" \
  bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "iso-old/exit1" 1 "$RC"
check "iso-old/error-fires" 1 \
  "$(jq -sr '[.[] | select((.note // "") | contains("wrote no run-log line"))] | length' "$LOG_DIR_Q1/daily-docs-log.jsonl" 2>/dev/null)"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-daily-docs" 2>/dev/null

# ── Q2) routine appends a FRESH ISO8601 line during the run -> passes ───────
setup_task daily-docs
LOG_DIR_Q2="$ROOT/logs-q2"
STUB_Q2="$ROOT/claude-stub-iso-fresh.sh"
cat > "$STUB_Q2" <<'STUBEOF'
#!/bin/bash
cat > /dev/null
mkdir -p "$(dirname "$STUB_LOG_FILE")"
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ts: $ts, status: "ok"}' >> "$STUB_LOG_FILE"
exit 0
STUBEOF
chmod +x "$STUB_Q2"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_Q2" CLAUDE_BIN="$STUB_Q2" \
  STUB_LOG_FILE="$LOG_DIR_Q2/daily-docs-log.jsonl" \
  bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "iso-fresh/exit0" 0 "$RC"
check "iso-fresh/no-runner-error-line" 0 \
  "$(jq -sr '[.[] | select(has("note"))] | length' "$LOG_DIR_Q2/daily-docs-log.jsonl" 2>/dev/null)"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-daily-docs" 2>/dev/null

# ── R1) one TRUNCATED line in the log from an earlier write -> the check
#      still reads the file and passes on the routine's fresh line ───────────
setup_task daily-docs
LOG_DIR_R1="$ROOT/logs-r1"; mkdir -p "$LOG_DIR_R1"
printf '%s\n' '{"ts":17' > "$LOG_DIR_R1/daily-docs-log.jsonl"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_R1" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ROOT/argv-r1.txt" STUB_STDIN_FILE="$ROOT/stdin-r1.txt" STUB_EXIT_CODE=0 \
  STUB_LOG_FILE="$LOG_DIR_R1/daily-docs-log.jsonl" \
  bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "truncated-old/exit0" 0 "$RC"
check "truncated-old/no-parse-error" 0 \
  "$(jq -Rr 'fromjson? // empty | select((.note // "") | contains("could not be read"))' "$LOG_DIR_R1/daily-docs-log.jsonl" 2>/dev/null | grep -c .)"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-daily-docs" 2>/dev/null

# ── R2) truncated line and the routine wrote nothing -> the plain
#      "wrote no run-log line" error, NOT a parse-failure error ───────────────
setup_task daily-docs
LOG_DIR_R2="$ROOT/logs-r2"; mkdir -p "$LOG_DIR_R2"
printf '%s\n' '{"ts":17' > "$LOG_DIR_R2/daily-docs-log.jsonl"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_R2" CLAUDE_BIN="$STUB" \
  STUB_ARGV_FILE="$ROOT/argv-r2.txt" STUB_STDIN_FILE="$ROOT/stdin-r2.txt" STUB_EXIT_CODE=0 \
  bash "$RUNNER" daily-docs >/dev/null 2>&1
RC=$?
check "truncated-none/exit1" 1 "$RC"
check "truncated-none/plain-error" 1 \
  "$(jq -Rr 'fromjson? // empty | select((.note // "") | contains("wrote no run-log line")) | .note' "$LOG_DIR_R2/daily-docs-log.jsonl" 2>/dev/null | grep -c .)"
rm -rf "$CDIR"; rmdir "${TMPDIR:-/tmp}/claude-routine-lock-daily-docs" 2>/dev/null

# ── S) two runners reclaim the SAME dead-pid lock with a deterministic
#      interleaving (runner A pauses after reading the dead pid; runner B
#      reclaims and starts claude; A resumes). Exactly one may run claude. ────
setup_task daily-docs
LOCK_S="${TMPDIR:-/tmp}/claude-routine-lock-daily-docs"
rm -f "$LOCK_S/pid"; rmdir "$LOCK_S" 2>/dev/null; mkdir "$LOCK_S"
( exit 0 ) & DEAD_S=$!; wait "$DEAD_S"
echo "$DEAD_S" > "$LOCK_S/pid"
LOG_DIR_S="$ROOT/logs-s"; CALLS_S="$ROOT/calls-s.txt"; : > "$CALLS_S"
STUB_S="$ROOT/claude-stub-race.sh"
cat > "$STUB_S" <<'STUBEOF'
#!/bin/bash
cat > /dev/null
printf 'call\n' >> "$STUB_CALLS_FILE"
sleep 3
jq -nc '{ts: (now | floor), status: "ok"}' >> "$STUB_LOG_FILE"
exit 0
STUBEOF
chmod +x "$STUB_S"
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_S" CLAUDE_BIN="$STUB_S" \
  STUB_CALLS_FILE="$CALLS_S" STUB_LOG_FILE="$LOG_DIR_S/daily-docs-log.jsonl" \
  CLAUDE_ROUTINE_TEST_RECLAIM_PAUSE=2 \
  bash "$RUNNER" daily-docs >/dev/null 2>&1 &
PID_A=$!
sleep 0.5
CLAUDE_ROUTINE_CLAUDE_DIR="$CDIR" CLAUDE_ROUTINE_LOG_DIR="$LOG_DIR_S" CLAUDE_BIN="$STUB_S" \
  STUB_CALLS_FILE="$CALLS_S" STUB_LOG_FILE="$LOG_DIR_S/daily-docs-log.jsonl" \
  bash "$RUNNER" daily-docs >/dev/null 2>&1 &
PID_B=$!
wait "$PID_A"; RC_A=$?
wait "$PID_B"; RC_B=$?
check "reclaim-race/claude-called-once" 1 "$(wc -l < "$CALLS_S" | tr -d ' ')"
OK_A=0; OK_B=0
[ "$RC_A" = 0 ] && OK_A=1
[ "$RC_B" = 0 ] && OK_B=1
check "reclaim-race/exactly-one-success" 1 "$((OK_A + OK_B))"
rm -rf "$CDIR"; rmdir "$LOCK_S" 2>/dev/null

rm -rf "$ROOT"

# ═══════════════════════════════════════════════════════════════════════════
# G) install-routine-timers.sh — render/migration cases (IMP-219)
#
# This group tests scripts/install-routine-timers.sh, not routine-run.sh
# itself — it lives in this file because scripts/tests/routine-run-regression.sh
# is the target named for the render/migration cases in the vault blueprint (P1).
#
# launchctl is NEVER actually invoked: a stub on PATH records every call
# into a log file and always answers with exit 0 (or an empty list for
# "list"). --dry-run must NOT call launchctl AT ALL — a "poison" stub
# checks that by aborting if it is called anyway.
# ═══════════════════════════════════════════════════════════════════════════
INSTALLER="$SCRIPT_DIR/../install-routine-timers.sh"
[ -f "$INSTALLER" ] || { echo "install-routine-timers.sh not found: $INSTALLER" >&2; exit 1; }

GROOT=$(mktemp -d)

# ── G1: --dry-run shows the 3 rendered target paths, does NOT call
#    launchctl (the poison stub aborts and leaves a marker if it is). ───────
G1_HOME="$GROOT/home1"
mkdir -p "$G1_HOME"
POISON_BIN="$GROOT/poison-bin"
mkdir -p "$POISON_BIN"
POISON_MARKER="$GROOT/poison-called"
cat > "$POISON_BIN/launchctl" <<EOF
#!/bin/bash
echo "\$@" >> "$POISON_MARKER"
exit 0
EOF
chmod +x "$POISON_BIN/launchctl"
DRYOUT_G1=$(HOME="$G1_HOME" PATH="$POISON_BIN:$PATH" bash "$INSTALLER" --dry-run 2>&1)
RC_G1=$?
check "install/dryrun-exit0" 0 "$RC_G1"
for t in daily-docs nightly-observation weekly-improve; do
  check "install/dryrun-shows-target-path-$t" 1 \
    "$(printf '%s\n' "$DRYOUT_G1" | grep -c "would write:   $G1_HOME/Library/LaunchAgents/com.claude-code.routine-$t.plist")"
done
check "install/dryrun-never-calls-launchctl" 0 "$([ -f "$POISON_MARKER" ] && echo 1 || echo 0)"

# ── G2: real install (stub launchctl) — precedence satisfied (dummy
#    routine-run.sh present), renders all 3 plists with the real HOME +
#    generic label, boots out the historical label, bootstraps the new one. ──
G2_HOME="$GROOT/home2"
mkdir -p "$G2_HOME/.claude/scripts"
cat > "$G2_HOME/.claude/scripts/routine-run.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$G2_HOME/.claude/scripts/routine-run.sh"

STUB_BIN="$GROOT/stub-bin"
mkdir -p "$STUB_BIN"
LAUNCHCTL_LOG="$GROOT/launchctl.log"
: > "$LAUNCHCTL_LOG"
cat > "$STUB_BIN/launchctl" <<EOF
#!/bin/bash
echo "\$@" >> "$LAUNCHCTL_LOG"
if [ "\$1" = "list" ]; then
  exit 0
fi
exit 0
EOF
chmod +x "$STUB_BIN/launchctl"

OUT_G2=$(HOME="$G2_HOME" PATH="$STUB_BIN:$PATH" bash "$INSTALLER" 2>&1)
RC_G2=$?
check "install/real-exit0" 0 "$RC_G2"
for t in daily-docs nightly-observation weekly-improve; do
  DEST="$G2_HOME/Library/LaunchAgents/com.claude-code.routine-$t.plist"
  if [ -f "$DEST" ] && grep -q "$G2_HOME" "$DEST" && grep -q "com.claude-code.routine-$t" "$DEST" \
     && ! grep -q "__HOME__\|__LABEL__" "$DEST"; then
    ok
  else
    bad "install/rendered-plist-correct-$t" "file missing or still contains a placeholder: $DEST"
  fi
  check "install/bootstrap-called-$t" 1 \
    "$(grep -c "bootstrap gui/$(id -u) $DEST" "$LAUNCHCTL_LOG")"
  check "install/historical-label-booted-out-$t" 1 \
    "$(grep -c "bootout gui/$(id -u)/com.${USER:-$(id -un)}.claude-routine-$t" "$LAUNCHCTL_LOG")"
done

# ── G3: migration — a pre-installed plist under the historical per-user
#    label is removed on install. ───────────────────────────────────────────
G3_HOME="$GROOT/home3"
mkdir -p "$G3_HOME/.claude/scripts" "$G3_HOME/Library/LaunchAgents"
cp "$G2_HOME/.claude/scripts/routine-run.sh" "$G3_HOME/.claude/scripts/routine-run.sh"
chmod +x "$G3_HOME/.claude/scripts/routine-run.sh"
OLD_LABEL="com.${USER:-$(id -un)}.claude-routine-daily-docs"
OLD_PLIST="$G3_HOME/Library/LaunchAgents/${OLD_LABEL}.plist"
echo "<plist/>" > "$OLD_PLIST"
: > "$LAUNCHCTL_LOG"
bash -c "HOME='$G3_HOME' PATH='$STUB_BIN:$PATH' bash '$INSTALLER'" >/dev/null 2>&1
check "install/migration-removes-old-plist" 0 "$([ -f "$OLD_PLIST" ] && echo 1 || echo 0)"
check "install/migration-new-plist-present" 1 \
  "$([ -f "$G3_HOME/Library/LaunchAgents/com.claude-code.routine-daily-docs.plist" ] && echo 1 || echo 0)"

# ── G4: --uninstall (stub launchctl) removes both the new AND the historical
#    label, never actually calls launchctl. ─────────────────────────────────
G4_HOME="$GROOT/home4"
mkdir -p "$G4_HOME/Library/LaunchAgents"
touch "$G4_HOME/Library/LaunchAgents/com.claude-code.routine-daily-docs.plist"
touch "$G4_HOME/Library/LaunchAgents/com.${USER:-$(id -un)}.claude-routine-daily-docs.plist"
: > "$LAUNCHCTL_LOG"
OUT_G4=$(HOME="$G4_HOME" PATH="$STUB_BIN:$PATH" bash "$INSTALLER" --uninstall 2>&1)
RC_G4=$?
check "install/uninstall-exit0" 0 "$RC_G4"
check "install/uninstall-removes-new-plist" 0 \
  "$([ -f "$G4_HOME/Library/LaunchAgents/com.claude-code.routine-daily-docs.plist" ] && echo 1 || echo 0)"
check "install/uninstall-removes-old-plist" 0 \
  "$([ -f "$G4_HOME/Library/LaunchAgents/com.${USER:-$(id -un)}.claude-routine-daily-docs.plist" ] && echo 1 || echo 0)"
check "install/uninstall-only-via-stub" 1 \
  "$([ -s "$LAUNCHCTL_LOG" ] && echo 1 || echo 0)"

rm -rf "$GROOT"

printf '── routine-run-regression: %d passed, %d failed ──\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
