#!/bin/bash
# routine-run.sh — launchd entry point for the ~/.claude scheduled-task routines
# ─────────────────────────────────────────────────────────────────────────────
# IMP-135 (2026-08-22): daily-docs / nightly-observation / weekly-improve ran
# until 2026-08-02 as Cloud-scheduled Claude sessions bound to a cwd that a
# filesystem reorganization renamed — 20 days of totally silent outage, zero
# observable signal anywhere. This script + the plists in scripts/launchd/
# replace that binding with a LOCAL launchd timer bound to ~/.claude.
#
# Usage:
#   routine-run.sh <daily-docs|nightly-observation|weekly-improve> [--dry-run]
#
# This script is deliberately a THIN, AUDITABLE TRIGGER. It hands the task's
# SKILL.md prose to `claude -p` and gets out of the way. All routine logic
# lives in the SKILL.md itself. The runner's job: (a) the routine is invoked,
# and (b) every exit path of a real run leaves a run-log line (IMP-075): either
# the routine's own line, or one written here.
#
# Exit paths of a real run (each one writes a run-log line):
#   jq missing ............................ fixed literal line in routine-run-errors.jsonl
#   unknown task / ~/.claude / SKILL / claude / cd ... log_error (task log or errors log)
#   lock held ............................. log_error; a dead holder's lock is reclaimed (logged)
#   SIGTERM / SIGINT / SIGHUP ............. on_signal logs, EXIT trap releases the lock
#   claude exit N != 0 ................... log_error + last 3 stderr lines of claude
#   claude exit 0, no line since start ... log_error (routine skipped its run-log step)
#
# --dangerously-skip-permissions rationale (agency-bands.md): an unattended
#   launchd run cannot answer an interactive y/n. The deterministic gate layers
#   (guard-unsafe.sh floor, native ask[]/deny[], bash and MCP agency gates) stay
#   active under this flag; an unanswerable native `ask` fails safe (denied).
#
# Model map (IMP-255; docs/reference/delegation.md, Model tiers): haiku for every routine
#   except weekly-improve (meta-observer, opus-pinned) -> opus.
#
# Env overrides (testing only — production runs use the fixed defaults):
#   CLAUDE_ROUTINE_LOG_DIR     default: $HOME/.claude/global-observation (runner's own lines)
#   CLAUDE_BIN                 default: $HOME/.local/bin/claude, then PATH. Must be executable.
#   CLAUDE_ROUTINE_CLAUDE_DIR  default: $HOME/.claude (SKILL.md lookup root).
#   CLAUDE_ROUTINE_TEST_RECLAIM_PAUSE  seconds to sleep between reading a dead
#                            holder's pid and renaming the lock (race test only).
#
# Exit codes:
#   0 — dry-run completed, or claude exited 0 AND wrote its run-log line
#   1 — validation failure, lock held, signal, or claude exited 0 without a run-log line
#   2 — jq not found (refuses to hand-write JSON)
#   N — claude's own nonzero exit code, propagated unchanged
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_NAME="routine-run.sh"

# Env-derived paths first: the jq check below needs LOG_DIR for its one line.
CLAUDE_DIR="${CLAUDE_ROUTINE_CLAUDE_DIR:-$HOME/.claude}"
LOG_DIR="${CLAUDE_ROUTINE_LOG_DIR:-$CLAUDE_DIR/global-observation}"

# ── jq is required before anything else may safely write a log line ─────────
if ! command -v jq >/dev/null 2>&1; then
  echo "$SCRIPT_NAME: FATAL: jq not found on PATH — refusing to hand-write JSON log lines" >&2
  # Fixed literal, no interpolated text: the one path that cannot use jq still leaves a line.
  mkdir -p "$LOG_DIR" 2>/dev/null
  printf '{"ts":%s,"status":"error","note":"runner: jq not found on PATH - no run started"}\n' \
    "$(date +%s)" >> "$LOG_DIR/routine-run-errors.jsonl"
  exit 2
fi

# ── Argument parsing — task name is positional, --dry-run may appear anywhere
DRY_RUN=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done
TASK="${POSITIONAL[0]:-}"

# ── log_error: stderr line + fail-loud JSON line. Never silent. ─────────────
log_error() {
  local logfile="$1" reason="$2"
  echo "$SCRIPT_NAME: ERROR: $reason" >&2
  mkdir -p "$(dirname "$logfile")" 2>/dev/null
  jq -nc --argjson ts "$(date +%s)" --arg note "runner: $reason" \
    '{ts: $ts, status: "error", note: $note}' >> "$logfile"
}

# ── Task-name → run-log mapping — the ONLY three tasks this runner knows ────
case "$TASK" in
  daily-docs)          LOG_BASENAME="daily-docs-log";  ROUTINE_MODEL="haiku" ;;
  nightly-observation) LOG_BASENAME="nightly-obs-log"; ROUTINE_MODEL="haiku" ;;
  weekly-improve)      LOG_BASENAME="weekly-improve-log"; ROUTINE_MODEL="opus" ;;
  *)
    # No per-task run-log exists for an unrecognized name: generic errors log.
    log_error "$LOG_DIR/routine-run-errors.jsonl" \
      "unknown task name '${TASK:-<empty>}' — expected one of: daily-docs, nightly-observation, weekly-improve"
    exit 1
    ;;
esac
LOG_FILE="$LOG_DIR/${LOG_BASENAME}.jsonl"

# ── Validation 1 — ~/.claude exists ──────────────────────────────────────────
if [ ! -d "$CLAUDE_DIR" ]; then
  log_error "$LOG_FILE" "\$HOME/.claude does not exist ($CLAUDE_DIR)"
  exit 1
fi

# ── Validation 2 — SKILL.md exists for this task ────────────────────────────
SKILL_FILE="$CLAUDE_DIR/scheduled-tasks/$TASK/SKILL.md"
if [ ! -f "$SKILL_FILE" ]; then
  log_error "$LOG_FILE" "SKILL.md missing for task '$TASK' (expected $SKILL_FILE)"
  exit 1
fi

# ── Validation 3 — claude binary findable (~/.local/bin/claude first) ──────
if [ -n "${CLAUDE_BIN:-}" ] && [ -x "$CLAUDE_BIN" ]; then
  : # use the env-provided override as-is
elif [ -x "$HOME/.local/bin/claude" ]; then
  CLAUDE_BIN="$HOME/.local/bin/claude"
elif command -v claude >/dev/null 2>&1; then
  CLAUDE_BIN="$(command -v claude)"
else
  log_error "$LOG_FILE" "claude binary not found in \$HOME/.local/bin/claude or \$PATH"
  exit 1
fi

# ── Concurrency guard — mkdir is POSIX-atomic. Real runs only. ──────────────
LOCK_DIR="${TMPDIR:-/tmp}/claude-routine-lock-${TASK}"
LOCK_ACQUIRED=0
STDERR_FILE=""

# cleanup — EXIT trap: release our own lock (pid file first, then the dir) and
# drop the stderr capture. rmdir alone would leave the pid file behind.
cleanup() {
  if [ "$LOCK_ACQUIRED" = "1" ]; then
    rm -f "$LOCK_DIR/pid" 2>/dev/null
    rmdir "$LOCK_DIR" 2>/dev/null
  fi
  if [ -n "$STDERR_FILE" ]; then rm -f "$STDERR_FILE" 2>/dev/null; fi
}

# acquire_lock — take the lock, or reclaim it when its recorded holder is dead.
# A lock with no readable pid is treated as HELD (fail closed): we cannot prove
# the holder is gone. A SIGKILLed or power-cut run leaves a dir with a dead pid.
acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"; LOCK_ACQUIRED=1; return 0
  fi
  local holder
  holder="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ "$holder" =~ ^[0-9]+$ ]] && ! kill -0 "$holder" 2>/dev/null; then
    # Reclaim by atomic rename, not remove+recreate: two runners that read the
    # same dead pid cannot both delete-and-recreate. Only one mv of LOCK_DIR
    # succeeds; the moved dir is then verified to hold the DEAD pid.
    [ -n "${CLAUDE_ROUTINE_TEST_RECLAIM_PAUSE:-}" ] && sleep "$CLAUDE_ROUTINE_TEST_RECLAIM_PAUSE"
    local grave="$LOCK_DIR.stale-$$"
    if mv "$LOCK_DIR" "$grave" 2>/dev/null; then
      if [ "$(cat "$grave/pid" 2>/dev/null || true)" = "$holder" ]; then
        rm -f "$grave/pid" 2>/dev/null; rmdir "$grave" 2>/dev/null
        if mkdir "$LOCK_DIR" 2>/dev/null; then
          echo $$ > "$LOCK_DIR/pid"; LOCK_ACQUIRED=1
          log_error "$LOG_FILE" "reclaimed stale lock ($LOCK_DIR): holder pid $holder is not running"
          return 0
        fi
      else
        # ABA: between our read and our rename, a live lock was created and we
        # moved IT. Put it back; if the path was re-taken meanwhile, say so.
        if [ ! -e "$LOCK_DIR" ] && mv "$grave" "$LOCK_DIR" 2>/dev/null; then
          :
        else
          log_error "$LOG_FILE" "lock ownership conflict on $LOCK_DIR during reclaim: a live lock was moved to $grave and could not be restored - run refused"
        fi
      fi
    fi
  fi
  log_error "$LOG_FILE" "lock held ($LOCK_DIR) — another run of '$TASK' is already in progress (or a wake-catchup run collided with it)"
  return 1
}

# on_signal — launchd stop/timeout, reboot or Ctrl-C must not vanish silently.
# bash runs a trap only after a foreground child (claude) has exited.
on_signal() {
  log_error "$LOG_FILE" "terminated by SIG$1 during a '$TASK' run (launchd stop/timeout, reboot or interrupt); the routine did not finish its run-log step"
  exit 1
}

if [ "$DRY_RUN" = "1" ]; then
  echo "$SCRIPT_NAME: --dry-run — validations passed, claude NOT executed"
  echo "  task:        $TASK"
  echo "  claude_dir:  $CLAUDE_DIR (exists)"
  echo "  skill_file:  $SKILL_FILE (exists, $(wc -c < "$SKILL_FILE" | tr -d ' ') bytes)"
  echo "  claude_bin:  $CLAUDE_BIN"
  echo "  log_file:    $LOG_FILE (written by the SKILL.md's own steps on a real run — not by this runner, except on error)"
  echo "  lock_dir:    $LOCK_DIR (not acquired in --dry-run)"
  echo "  cwd:         $CLAUDE_DIR"
  echo "  command:     cd $CLAUDE_DIR && $CLAUDE_BIN -p --model $ROUTINE_MODEL --dangerously-skip-permissions < $SKILL_FILE"

  # ── Parser-proof (IMP-190): proves the invocation shape is accepted WITHOUT a
  # real run — --model is an id that cannot exist, so the call fails on THAT,
  # never on argument parsing. Proof = stderr has no 'unknown option'.
  echo "  parser_proof:"
  if [ -z "${CLAUDE_BIN:-}" ] || [ ! -x "$CLAUDE_BIN" ]; then
    echo "    SKIP — claude binary not available for the parser-proof"
  else
    if command -v timeout >/dev/null 2>&1; then
      PROOF_TIMEOUT_BIN="timeout"
    elif command -v gtimeout >/dev/null 2>&1; then
      PROOF_TIMEOUT_BIN="gtimeout"
    else
      PROOF_TIMEOUT_BIN=""
    fi
    PROOF_PROMPT="dry-run parser-proof (IMP-190) — not a real run"
    if [ -n "$PROOF_TIMEOUT_BIN" ]; then
      PROOF_OUT=$(printf '%s' "$PROOF_PROMPT" \
        | "$PROOF_TIMEOUT_BIN" 20 "$CLAUDE_BIN" -p --model claude-dry-run-proof-invalid --dangerously-skip-permissions 2>&1)
    else
      PROOF_OUT=$(printf '%s' "$PROOF_PROMPT" \
        | "$CLAUDE_BIN" -p --model claude-dry-run-proof-invalid --dangerously-skip-permissions 2>&1)
    fi
    if printf '%s' "$PROOF_OUT" | grep -qi 'unknown option'; then
      echo "    FAIL — invocation shape itself was rejected (stderr contains 'unknown option'): $PROOF_OUT"
    else
      echo "    PASS — CLI parser accepted the invocation shape (stdin + flags); no 'unknown option' in stderr"
    fi
  fi

  exit 0
fi

acquire_lock || exit 1
trap cleanup EXIT
trap 'on_signal TERM' TERM
trap 'on_signal INT' INT
trap 'on_signal HUP' HUP

# stderr_tail — last 3 lines of claude's stderr, each cut to 200 characters.
# jq slices codepoints, so a UTF-8 cut cannot split a character.
stderr_tail() {
  if [ ! -s "$1" ]; then echo "(empty)"; return 0; fi
  local tail_text
  if ! tail_text="$(tail -n 3 "$1" | jq -Rrs 'split("\n") | map(select(length > 0) | .[0:200]) | join(" | ")')"; then
    echo "(stderr tail unreadable: jq failed)"; return 0
  fi
  if [ -z "$tail_text" ]; then echo "(empty)"; else echo "$tail_text"; fi
}

# runlog_bytes FILE -> byte size (0 if missing). Taken BEFORE claude starts.
runlog_bytes() {
  if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else echo 0; fi
}

# runlog_routine_lines FILE OFFSET START_TS -> count of lines appended after
# byte OFFSET whose ts is >= START_TS. Two guards, both needed:
#  - OFFSET: lines written before claude started (including this runner's own
#    reclaim line, which carries a fresh numeric ts) can never count.
#  - ts normalized like hooks/routine-liveness-check.sh: number | numeric string |
#    ISO8601 UTC. A raw jq compare would sort strings after numbers and pass
#    every ISO line. Unparseable lines/ts are ignored, so one truncated line
#    cannot break the check (fromjson?, not a whole-file parse).
runlog_routine_lines() {
  [ -f "$1" ] || { echo 0; return 0; }
  tail -c +"$(( $2 + 1 ))" "$1" | jq -Rn --argjson since "$3" '
    def epoch:
      if type == "number" then .
      elif type == "string" and test("^[0-9]+$") then tonumber
      elif type == "string" then (try (strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) catch null)
      else null end;
    [inputs | fromjson? // empty | select(type == "object") | (.ts | epoch)
      | select(. != null and . >= $since)] | length'
}

# ── Execute ───────────────────────────────────────────────────────────────
# The prompt goes to claude via STDIN, not as a positional argument: SKILL.md
# starts with a YAML frontmatter fence ("---"), which claude's option parser
# reads as an unknown flag when passed positionally (every run failed on that
# from 2026-08-23 until the stdin fix). `< "$SKILL_FILE"` is byte-exact.
cd "$CLAUDE_DIR" || { log_error "$LOG_FILE" "cd to $CLAUDE_DIR failed"; exit 1; }

START_TS="$(date +%s)"
LOG_BYTES_BEFORE="$(runlog_bytes "$LOG_FILE")"
STDERR_FILE="$(mktemp "${TMPDIR:-/tmp}/routine-run-stderr.XXXXXX")" || {
  log_error "$LOG_FILE" "mktemp for claude stderr capture failed"; exit 1; }

# A scheduled routine carries its plan in its SKILL.md and has no one to report to at the
# end of a turn: no goal seed, no goal rows, no stop check (IMP-289).
CLAUDE_GOAL_TRACKING=0 "$CLAUDE_BIN" -p --model "$ROUTINE_MODEL" --dangerously-skip-permissions < "$SKILL_FILE" 2>"$STDERR_FILE"
CLAUDE_EXIT=$?
cat "$STDERR_FILE" >&2  # launchd's stderr log keeps the full stream, as before

if [ "$CLAUDE_EXIT" -ne 0 ]; then
  log_error "$LOG_FILE" "claude exited $CLAUDE_EXIT for $TASK; stderr tail: $(stderr_tail "$STDERR_FILE")"
  exit "$CLAUDE_EXIT"
fi

# Exit 0 is not proof of a run: the routine must have written its own line.
if ! LINES_SINCE="$(runlog_routine_lines "$LOG_FILE" "$LOG_BYTES_BEFORE" "$START_TS")"; then
  log_error "$LOG_FILE" "claude exited 0 for $TASK and the run log could not be read to verify its line"
  exit 1
fi
if [ "$LINES_SINCE" -eq 0 ]; then
  log_error "$LOG_FILE" "claude exited 0 for $TASK but wrote no run-log line since $START_TS (routine skipped its run-log step)"
  exit 1
fi

exit 0
