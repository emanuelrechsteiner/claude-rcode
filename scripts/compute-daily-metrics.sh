#!/bin/bash
# compute-daily-metrics.sh — Deterministic Step 2 of the nightly observation pipeline
# ─────────────────────────────────────────────────────────────────────────────
# Companion to rotate-signals.sh (Step 1).  Extracted 2026-07-20 after the SAME
# finding three nights running (2026-07-17, -18, -19): Step 1 was a hardened
# script while Step 2 re-derived its numbers with an ad-hoc LLM jq filter every
# night.  Result: intact raw shards, DRIFTING derived metrics — 7 wrong July
# rows, worst case 2026-07-07 recording errors=0/hook_blocks=0 when the shard
# actually held 35.
#
# The rule this enforces (fail-loud.md): what a script can count deterministically
# must not be re-invented per run by an agent, and a value that CANNOT be measured
# is emitted as null — never as a confident 0.
#
# MEASUREMENT SURFACE — read this before trusting any field:
#   observation-capture.sh is registered as PostToolUse with matcher "Edit|Write".
#   Therefore the corpus contains ONLY Edit and Write records.
#     * tool_invocations   = Edit+Write only, despite the generic name.
#     * agent_invocations  = measured from dispatch-capture.jsonl since
#                            2026-08-01 (IMP-115). Still null for any date with
#                            NO dispatch log coverage — absence of a log is not
#                            evidence of zero dispatches. Every historical 0 in
#                            daily-metrics.jsonl before 2026-07-18 was a
#                            fabricated default, not an observation.
#     * hook_blocks        = currently identical to errors by construction (all
#                            captured errors are read-before-edit-block). Counted
#                            independently anyway, so the two diverge honestly if
#                            a new error class ever appears.
#
# Usage:
#   bash ~/.claude/scripts/compute-daily-metrics.sh [YYYY-MM-DD] [--dry-run]
#   (no date argument → yesterday, UTC)
#
# Env overrides (for testing — never touch real files in tests):
#   CLAUDE_ARCHIVE_DIR   default: $HOME/.claude/global-observation/archives
#   CLAUDE_METRICS_FILE  default: $HOME/.claude/global-observation/daily-metrics.jsonl
#   CLAUDE_ALERTS_FILE   default: $HOME/.claude/global-observation/alerts.jsonl
#
# Exit codes:
#   0  — row appended, or already present (idempotent skip), or dry-run
#   1  — shard missing or corrupt → NO row written; blocker alert appended
#   2  — script-level error (missing deps, unwritable paths, bad arguments)
#
# Idempotent: a second run for the same date detects the existing row and exits 0
# without appending. It never rewrites recorded history — backfilling drifted
# rows is a separate, explicitly-confirmed operation.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Paths (env-overridable for testability) ───────────────────────────────────
ARCHIVE_DIR="${CLAUDE_ARCHIVE_DIR:-$HOME/.claude/global-observation/archives}"
METRICS_FILE="${CLAUDE_METRICS_FILE:-$HOME/.claude/global-observation/daily-metrics.jsonl}"
ALERTS="${CLAUDE_ALERTS_FILE:-$HOME/.claude/global-observation/alerts.jsonl}"

log() { echo "[compute-daily-metrics] $*"; }

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in jq gzip gzcat date mktemp mv rm wc grep; do
  if ! command -v "$cmd" &>/dev/null; then
    # gzcat is macOS; zcat is the GNU name — accept either
    if [[ "$cmd" == "gzcat" ]] && command -v zcat &>/dev/null; then continue; fi
    echo "[compute-daily-metrics] FATAL: required command not found: $cmd" >&2
    exit 2
  fi
done
if command -v gzcat &>/dev/null; then GZCAT=gzcat; else GZCAT=zcat; fi

# ── Portable "yesterday, UTC" (BSD date -v vs GNU date -d) ───────────────────
yesterday_utc() {
  date -u -v-1d '+%Y-%m-%d' 2>/dev/null \
    || date -u -d 'yesterday' '+%Y-%m-%d' 2>/dev/null \
    || return 1
}

# ── Argument parsing ──────────────────────────────────────────────────────────
DRY_RUN=0
TARGET_DATE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) TARGET_DATE="$arg" ;;
    *) echo "[compute-daily-metrics] Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [[ -z "$TARGET_DATE" ]]; then
  if ! TARGET_DATE="$(yesterday_utc)"; then
    echo "[compute-daily-metrics] FATAL: could not compute yesterday's date" >&2
    exit 2
  fi
fi

[[ "$DRY_RUN" -eq 1 ]] && log "DRY-RUN mode — no files will be mutated"
log "target date:  $TARGET_DATE"
log "metrics file: $METRICS_FILE"

# ── Emit a blocker alert and exit 1 (fail-loud, no partial row) ──────────────
abort_with_alert() {
  local err_msg="$1"
  log "ABORT: $err_msg — no metrics row written"
  mkdir -p "$(dirname "$ALERTS")"
  printf '{"ts":"%sZ","blocker":true,"error":"%s","script":"compute-daily-metrics.sh","date":"%s"}\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%S')" "$err_msg" "$TARGET_DATE" >> "$ALERTS"
  log "blocker alert written to $ALERTS"
  exit 1
}

# ── IDEMPOTENCY: never write a second row for the same date ──────────────────
if [[ -f "$METRICS_FILE" ]] \
   && grep -q "\"date\":\"$TARGET_DATE\"" "$METRICS_FILE" 2>/dev/null; then
  log "row for $TARGET_DATE already present — idempotent skip (history is never rewritten)"
  exit 0
fi

# ── Locate the shard (gzipped or plain) ──────────────────────────────────────
SHARD_GZ="$ARCHIVE_DIR/signals-${TARGET_DATE}.jsonl.gz"
SHARD_PLAIN="$ARCHIVE_DIR/signals-${TARGET_DATE}.jsonl"

work_file="$(mktemp /tmp/compute-daily-metrics.XXXXXX)"
cleanup() { rm -f "$work_file"; }
trap cleanup EXIT

if [[ -f "$SHARD_GZ" ]]; then
  log "shard: $SHARD_GZ"
  $GZCAT "$SHARD_GZ" > "$work_file" 2>/dev/null || abort_with_alert "shard unreadable: $SHARD_GZ"
elif [[ -f "$SHARD_PLAIN" ]]; then
  log "shard: $SHARD_PLAIN"
  cp "$SHARD_PLAIN" "$work_file"
else
  abort_with_alert "no archive shard for $TARGET_DATE (looked for signals-${TARGET_DATE}.jsonl[.gz])"
fi

# ── Validate: every line must be parseable JSON (corrupt shard → no row) ─────
total_lines=$(wc -l < "$work_file" | tr -d ' ')
set +o pipefail
valid_json=$(jq -c '.' "$work_file" 2>/dev/null | wc -l | tr -d ' ')
set -o pipefail

if [[ "$total_lines" -eq 0 ]]; then
  abort_with_alert "shard for $TARGET_DATE is empty (0 lines)"
fi
if [[ "$valid_json" -ne "$total_lines" ]]; then
  abort_with_alert "shard contains non-JSON lines: total=$total_lines valid=$valid_json"
fi
log "shard validated: $total_lines lines, all parseable JSON"

# ── agent_invocations from the dispatch meter (IMP-115) ──────────────────────
# dispatch-capture.sh (PreToolUse|Task|Agent) is the only surface that sees a
# subagent dispatch. It went live 2026-08-01 — for any earlier date there is no
# coverage, and the honest value is null, NOT 0. Distinguishing "no dispatches"
# from "not observed" is the whole point (fail-loud.md).
DISPATCH_LOG="${CLAUDE_DISPATCH_LOG:-$HOME/.claude/global-observation/dispatch-capture.jsonl}"
DISPATCH_START="2026-08-01"   # first day the meter existed
AGENT_INVOCATIONS="null"
if [[ -f "$DISPATCH_LOG" && "$TARGET_DATE" > "$(date -u -v-1d -j -f %Y-%m-%d "$DISPATCH_START" +%Y-%m-%d 2>/dev/null || echo 2026-07-31)" ]]; then
  # `grep -c` exits 1 when the count is 0. Under this script's `set -euo
  # pipefail` that non-zero status aborts the ENTIRE metrics run — so a day
  # with zero dispatches would have silently produced no row at all. Guarded
  # with `|| true`; the count still lands on stdout either way.
  _cnt=$( { grep -c "\"ts\":\"$TARGET_DATE" "$DISPATCH_LOG" 2>/dev/null || true; } | head -1 | tr -d ' \n')
  [[ "$_cnt" =~ ^[0-9]+$ ]] && AGENT_INVOCATIONS="$_cnt"
  log "dispatch meter: $AGENT_INVOCATIONS dispatches on $TARGET_DATE"
else
  log "dispatch meter: no coverage for $TARGET_DATE (meter live since $DISPATCH_START) → agent_invocations=null"
fi

# ── Compute metrics (single jq pass — the ONLY place numbers are derived) ────
# agent_invocations is deliberately null: the capture surface cannot observe it.
metrics_json=$(jq -s --arg date "$TARGET_DATE" --argjson agents "$AGENT_INVOCATIONS" '
  {
    date: $date,
    tool_invocations: length,
    tool_invocations_by_name: (
      map(.tool // "UNKNOWN")
      | group_by(.)
      | map({key: .[0], value: length})
      | sort_by(-.value)
      | .[0:10]
      | from_entries
    ),
    errors: (map(select(.error != null)) | length),
    agent_invocations: $agents,
    hook_blocks: (
      map(select((.error // "") | test("block"; "i"))) | length
    ),
    sessions: (map(.session_id) | unique | length)
  }
' "$work_file") || abort_with_alert "jq metric computation failed"

# ── Attach provenance so a future reader can tell measured from unmeasurable ──
row=$(printf '%s' "$metrics_json" | jq -c \
  --arg ts "$(date -u '+%s')" \
  --arg src "$(basename "${SHARD_GZ}")" \
  --arg script "compute-daily-metrics.sh" '
  {date: .date, ts: ($ts | tonumber)}
  + (. | del(.date))
  + {_provenance: {
      source: $src,
      computed_by: $script,
      capture_surface: "PostToolUse Edit|Write only",
      tool_invocations_note: "Edit+Write only, not all tools; includes blocked-edit error records (consistent with prior rows)",
      agent_invocations_note: "counted from dispatch-capture.jsonl (PreToolUse Task|Agent, live since 2026-08-01, IMP-115) - NOT from the signal shard, whose matcher is Edit|Write. null means the meter had no coverage for that date, which is not the same as zero dispatches. Rows before 2026-07-18 reported 0, a fabricated default.",
      hook_blocks_note: "counted independently of errors; currently identical because all captured errors are read-before-edit-block"
    }}
') || abort_with_alert "provenance assembly failed"

log "computed: $(printf '%s' "$row" | jq -c 'del(._provenance)')"

# ── DRY-RUN stops here ───────────────────────────────────────────────────────
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY-RUN: would append the row above to $METRICS_FILE — no files mutated"
  exit 0
fi

# ── Append (atomic single-line append) ───────────────────────────────────────
mkdir -p "$(dirname "$METRICS_FILE")"
printf '%s\n' "$row" >> "$METRICS_FILE"
log "row appended to $METRICS_FILE"
log "compute-daily-metrics.sh: DONE — $TARGET_DATE"
exit 0
