#!/bin/bash
# routine-run.sh — launchd entry point for the ~/.claude scheduled-task routines
# ─────────────────────────────────────────────────────────────────────────────
# IMP-135 (2026-08-22): daily-docs / nightly-observation / weekly-improve ran
# until 2026-08-02 as Cloud-scheduled Claude sessions bound to a cwd that a
# filesystem reorganization renamed — 20 days of totally silent outage, zero
# observable signal anywhere. This script + the plists in scripts/launchd/
# replace that binding with a LOCAL launchd timer bound to ~/.claude (stable,
# on the system disk, present even when the external SSD holding the Bauhof
# working copy is unmounted).
#
# Usage:
#   routine-run.sh <daily-docs|nightly-observation|weekly-improve> [--dry-run]
#
# This script is deliberately a THIN, AUDITABLE TRIGGER. It does not
# interpret routine logic — it hands the task's SKILL.md prose to `claude -p`
# and gets out of the way. All routine logic (fail-loud contracts, run-log
# field shapes, idempotency) lives in the SKILL.md itself and the bin/
# scripts it calls. This runner's only job is: (a) the routine actually gets
# invoked, and (b) a failure to invoke it is NEVER silent (rules/fail-loud.md
# applies to routines, not just to app code).
#
# --dangerously-skip-permissions rationale (agency-bands.md):
#   An unattended launchd run cannot answer an interactive y/n. A routine
#   blocked on a permission prompt would hang until the next launchd tick,
#   indistinguishable from "working" in any log. The deterministic gate
#   layers (guard-unsafe.sh CRITICAL floor, native ask[]/deny[], the bash
#   agency gate, the MCP agency gate) all stay active under this flag — YOLO
#   only widens which REVERSIBLE ops skip a prompt; the irreversible-ops
#   floor is not overridable by mode (agency-bands.md). An unanswerable
#   native `ask` in a headless run fails safe (denied), per that rule's MCP
#   gate note.
#
# Model rationale: sonnet, per api-cost-optimization.md — these are batch
# housekeeping / triage-then-depth routines, not novel cross-file
# architecture decisions, so this sits below the Opus/Fable escalation bar.
#
# Env overrides (testing only — production runs use the fixed defaults):
#   CLAUDE_ROUTINE_LOG_DIR   default: $HOME/.claude/global-observation
#                            Redirects where THIS SCRIPT's own error lines
#                            land, so validation-failure paths (including the
#                            unknown-task-name path) can be exercised without
#                            touching the real run logs. Does NOT affect
#                            where the routine itself (once invoked) writes —
#                            that is hardcoded in each SKILL.md by design.
#   CLAUDE_BIN               default: auto-detected ($HOME/.local/bin/claude,
#                            then PATH). Set to a stub script's path so the
#                            regression suite can capture argv/stdin without
#                            invoking the real `claude` binary. Must point to
#                            an executable file, or the override is ignored
#                            and normal detection runs instead.
#   CLAUDE_ROUTINE_CLAUDE_DIR  default: $HOME/.claude. Only the three fixed
#                            task names are recognized (see the case below),
#                            and each maps to a SKILL_FILE path built from
#                            this dir — a real, non-dry-run test run would
#                            otherwise have to write into the real
#                            $HOME/.claude/scheduled-tasks/ tree to exercise
#                            the exec path. This override lets the
#                            regression suite point at a scratch directory
#                            instead. Left unset, production behavior is
#                            unchanged: --dry-run against the real
#                            installation stays a meaningful, read-only proof
#                            that the wiring is correct.
#
# Exit codes:
#   0 — dry-run completed (validations passed, claude NOT invoked), or
#       claude was invoked and exited 0
#   1 — validation failure (missing ~/.claude, missing SKILL.md, missing
#       claude binary, unknown task name, or another run already holds the
#       concurrency lock)
#   2 — script-level error (jq not found — refuses to hand-write JSON)
#   N — claude's own nonzero exit code, propagated unchanged
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_NAME="routine-run.sh"

# ── jq is required before anything else may safely write a log line ─────────
# (never hand-roll JSON — same discipline as weekly-improve's SKILL.md and
# ledger-append-proposed.sh: an unescaped reason string in a printf-built
# line is exactly the kind of self-inflicted parse failure fail-loud.md
# exists to prevent.)
if ! command -v jq >/dev/null 2>&1; then
  echo "$SCRIPT_NAME: FATAL: jq not found on PATH — refusing to hand-write JSON log lines" >&2
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

CLAUDE_DIR="${CLAUDE_ROUTINE_CLAUDE_DIR:-$HOME/.claude}"
LOG_DIR="${CLAUDE_ROUTINE_LOG_DIR:-$CLAUDE_DIR/global-observation}"

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
  daily-docs)          LOG_BASENAME="daily-docs-log" ;;
  nightly-observation) LOG_BASENAME="nightly-obs-log" ;;
  weekly-improve)      LOG_BASENAME="weekly-improve-log" ;;
  *)
    # No per-task run-log exists for an unrecognized name, so there is no
    # "zugehöriges Run-Log" to append to. Fall back to a generic runner-error
    # log — still under the overridable LOG_DIR, so this path is testable
    # without ever touching the real per-task logs.
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
# CLAUDE_BIN may already be set in the environment (regression-suite stub) —
# honor it only if it is actually executable; otherwise fall through to the
# normal detection so a stray/empty env var can never silently do nothing.
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

# ── Concurrency guard — mkdir is POSIX-atomic. Real runs only (dry-run never
#    invokes claude, so it cannot collide with anything and needs no lock). ──
LOCK_DIR="${TMPDIR:-/tmp}/claude-routine-lock-${TASK}"
LOCK_ACQUIRED=0
release_lock() {
  if [ "$LOCK_ACQUIRED" = "1" ]; then
    rmdir "$LOCK_DIR" 2>/dev/null
  fi
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
  echo "  command:     cd $CLAUDE_DIR && $CLAUDE_BIN -p --model sonnet --dangerously-skip-permissions < $SKILL_FILE"

  # ── Parser-proof (IMP-190) ──────────────────────────────────────────────
  # routine-run-regression.sh's own "Fall D" reproduces the IMP-189 bug
  # against the REAL binary (a SKILL.md's leading "---" frontmatter fence
  # read as an unknown CLI flag) — but that bug was, until now, invisible to
  # --dry-run itself: dry-run only ever PRINTED the command above, it never
  # actually invoked the binary, so a parser regression in the invocation
  # shape (flags + stdin) would pass every --dry-run check and only surface
  # on the next real launchd tick. This proves the shape is accepted WITHOUT
  # performing a real run: --model is deliberately set to an id that cannot
  # exist, so the call fails on THAT — never on argument parsing — and the
  # proof is simply "stderr does not contain 'unknown option'".
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

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log_error "$LOG_FILE" "lock held ($LOCK_DIR) — another run of '$TASK' is already in progress (or a wake-catchup run collided with it)"
  exit 1
fi
LOCK_ACQUIRED=1
trap release_lock EXIT

# ── Execute ───────────────────────────────────────────────────────────────
# The prompt goes to claude via STDIN, not as a positional argument. The
# SKILL.md files all start with a YAML frontmatter fence ("---"), and a
# positional argument starting with "--" is read by claude's own option
# parser as an unknown flag ("error: unknown option '---") before the prompt
# ever reaches the model — every routine run failed on exactly this since
# 2026-08-23. `< "$SKILL_FILE"` reads the file directly, byte-exact, with no
# intermediate shell variable — `$(cat ...)` command substitution would also
# strip the file's trailing newline (release-cli-discipline skill §3 default is
# `printf '%s' "$VALUE" |`, but a direct file redirect is the byte-exact
# form of that same discipline when the value is already a file, not a
# constructed string).
cd "$CLAUDE_DIR" || { log_error "$LOG_FILE" "cd to $CLAUDE_DIR failed"; exit 1; }

"$CLAUDE_BIN" -p --model sonnet --dangerously-skip-permissions < "$SKILL_FILE"
CLAUDE_EXIT=$?

# The routine's own SKILL.md writes its ok/partial/fail line itself (see
# each SKILL.md's "Run log" section) — do not duplicate that here. Only
# append when claude itself failed to complete, which the SKILL.md's own
# steps could never have logged.
if [ "$CLAUDE_EXIT" -ne 0 ]; then
  log_error "$LOG_FILE" "claude exited $CLAUDE_EXIT for $TASK"
fi

exit "$CLAUDE_EXIT"
