#!/bin/bash
# rotate-signals.sh — Archive-then-trim for signals.jsonl
# ─────────────────────────────────────────────────────────────────────────────
# IMP-049 + IMP-064: Replaces the inline nightly logic that caused a ~5149-entry
# data loss.  Root cause of the original loss: trim-to-today assumed a prior
# daily rotation had already moved yesterday's entries, so "keep today forward"
# silently discarded everything up to the current day.
#
# This script implements the correct ARCHIVE-FIRST, THEN-TRIM flow:
#   1. BACKUP   — copy the live file to a timestamped .bak before any mutation
#   2. ARCHIVE  — append past-date entries to per-date files in ARCHIVE_DIR
#   3. ASSERT   — verify past_count + today_count == original_count (fail-loud)
#   4. TRIM     — rewrite live file to today-only (atomic temp+mv)
#   5. COMPRESS — gzip new archive shards; prune old .gz and .bak files
#
# Usage:
#   bash ~/.claude/scripts/rotate-signals.sh [--dry-run]
#
# Env overrides (for testing — never touch real files in tests):
#   CLAUDE_SIGNALS_FILE      default: $HOME/.claude/global-observation/signals.jsonl
#   CLAUDE_ARCHIVE_DIR       default: $HOME/.claude/global-observation/archives
#   CLAUDE_ALERTS_FILE       default: $HOME/.claude/global-observation/alerts.jsonl
#   CLAUDE_SIGNALS_RETENTION_DAYS   default: 30
#
# Exit codes:
#   0  — clean run (or dry-run, or nothing to do)
#   1  — count assertion failed → live file NOT truncated; alert written
#   2  — script-level error (missing deps, unwritable paths, etc.)
#
# Idempotent: a second same-day run finds no past-date entries → no-op; the
# count assertion holds trivially (past=0, today=original_count).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Paths (env-overridable for testability) ───────────────────────────────────
SIGNALS_FILE="${CLAUDE_SIGNALS_FILE:-$HOME/.claude/global-observation/signals.jsonl}"
ARCHIVE_DIR="${CLAUDE_ARCHIVE_DIR:-$HOME/.claude/global-observation/archives}"
ALERTS="${CLAUDE_ALERTS_FILE:-$HOME/.claude/global-observation/alerts.jsonl}"
RETENTION="${CLAUDE_SIGNALS_RETENTION_DAYS:-30}"

# ── Argument parsing ──────────────────────────────────────────────────────────
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "[rotate-signals] Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in jq gzip date mktemp mv cp rm wc sort; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "[rotate-signals] FATAL: required command not found: $cmd" >&2
    exit 2
  fi
done

# ── Graceful early exit if file missing or empty ─────────────────────────────
if [[ ! -f "$SIGNALS_FILE" ]]; then
  echo "[rotate-signals] signals file not found ($SIGNALS_FILE) — nothing to rotate"
  exit 0
fi
if [[ ! -s "$SIGNALS_FILE" ]]; then
  echo "[rotate-signals] signals file is empty — nothing to rotate"
  exit 0
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
log() { echo "[rotate-signals] $*"; }

# UTC date helpers: macOS date -u vs GNU date -u are both "-u +%FT%TZ"
utc_ts() { date -u '+%Y%m%dT%H%M%SZ'; }
today_utc() { date -u '+%Y-%m-%d'; }

today="$(today_utc)"
ts_now="$(utc_ts)"

# ── Announce mode ─────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY-RUN mode — no files will be mutated"
fi
log "today (UTC): $today"
log "signals file: $SIGNALS_FILE"
log "archive dir:  $ARCHIVE_DIR"

# ── Count original lines ──────────────────────────────────────────────────────
original_count=$(wc -l < "$SIGNALS_FILE" | tr -d ' ')
log "original line count: $original_count"

# ── Validate JSON and count categories ───────────────────────────────────────
# NOTE: must use -c (compact, one JSON object per output line) so wc -l counts
# records, not pretty-printed tokens. -r would expand objects across many lines.
# Suppress jq stderr + wrap in { cmd; } || true so set -e doesn't fire on
# parse errors. The valid_json_count assertion detects corruption afterward.

# Count valid JSON lines (jq '.' accepts all valid objects, skips on error)
# Temporarily disable pipefail around the jq | wc pipe to tolerate parse errors.
set +o pipefail
valid_json_count=$(jq -c '.' "$SIGNALS_FILE" 2>/dev/null | wc -l | tr -d ' ')
past_count=$(jq -c 'select(.ts != null and (.ts[0:10] < "'"$today"'"))' \
  "$SIGNALS_FILE" 2>/dev/null | wc -l | tr -d ' ')
today_count=$(jq -c 'select(.ts != null and (.ts[0:10] >= "'"$today"'"))' \
  "$SIGNALS_FILE" 2>/dev/null | wc -l | tr -d ' ')
null_ts_count=$(jq -c 'select(.ts == null)' "$SIGNALS_FILE" 2>/dev/null \
  | wc -l | tr -d ' ')
set -o pipefail

log "past-date entries:  $past_count"
log "today entries:      $today_count"
log "null-ts entries:    $null_ts_count"
log "valid-JSON lines:   $valid_json_count (of $original_count total)"

# Early abort if the file has non-JSON lines — file is corrupt / truncated mid-write
if [[ "$valid_json_count" -ne "$original_count" ]]; then
  err_msg="file contains non-JSON lines: total=$original_count but valid-JSON=$valid_json_count ($(( original_count - valid_json_count )) bad lines)"
  log "ABORTING: $err_msg — live file NOT modified"
  mkdir -p "$(dirname "$ALERTS")"
  alert_line=$(printf '{"ts":"%sZ","blocker":true,"error":"%s","script":"rotate-signals.sh"}' \
    "$(date -u '+%Y-%m-%dT%H:%M:%S')" "$err_msg")
  echo "$alert_line" >> "$ALERTS"
  log "blocker alert written to $ALERTS"
  exit 1
fi

# ── DRY-RUN: report and exit ──────────────────────────────────────────────────
if [[ "$DRY_RUN" -eq 1 ]]; then
  if [[ "$past_count" -eq 0 ]]; then
    log "DRY-RUN: no past-date entries found — would be a no-op"
  else
    log "DRY-RUN: would archive $past_count past-date entries into per-date files under $ARCHIVE_DIR"
    log "DRY-RUN: would trim live file to $today_count entries (today) + $null_ts_count entries (null-ts)"
    # Show which date shards would be created
    jq -r 'select(.ts != null and (.ts[0:10] < "'"$today"'")) | .ts[0:10]' "$SIGNALS_FILE" \
      | sort | uniq -c | while read -r cnt date; do
        log "DRY-RUN:   → $ARCHIVE_DIR/signals-$date.jsonl  ($cnt entries)"
      done
  fi
  log "DRY-RUN: no files mutated — exiting cleanly"
  exit 0
fi

# ── No past entries → idempotent no-op ───────────────────────────────────────
if [[ "$past_count" -eq 0 ]]; then
  log "no past-date entries found — nothing to rotate (idempotent no-op)"
  exit 0
fi

# ── STEP 1: BACKUP (the guard that was missing in the original logic) ─────────
mkdir -p "$ARCHIVE_DIR"
backup_path="$ARCHIVE_DIR/signals.jsonl.bak-${ts_now}"
log "STEP 1: backing up to $backup_path"
cp "$SIGNALS_FILE" "$backup_path"
log "STEP 1: backup written ($(wc -l < "$backup_path" | tr -d ' ') lines)"

# ── STEP 2: ARCHIVE per-date shards ──────────────────────────────────────────
log "STEP 2: archiving past-date entries by date..."

# Extract unique past dates into a temp file (bash 3 compat — no mapfile)
past_dates_file="$(mktemp /tmp/rotate-signals-dates.XXXXXX)"
jq -r 'select(.ts != null and (.ts[0:10] < "'"$today"'")) | .ts[0:10]' \
  "$SIGNALS_FILE" | sort -u > "$past_dates_file"

while IFS= read -r entry_date; do
  [[ -z "$entry_date" ]] && continue
  shard="$ARCHIVE_DIR/signals-${entry_date}.jsonl"
  # Append entries for this date (new entries only on this run), then dedup
  jq -c 'select(.ts != null and (.ts[0:10] == "'"$entry_date"'"))' "$SIGNALS_FILE" \
    >> "$shard"
  # Dedup the shard (sort -u for idempotency: safe, all lines are compact JSON)
  sort -u "$shard" -o "$shard"
  shard_count=$(wc -l < "$shard" | tr -d ' ')
  log "STEP 2:   $shard ($shard_count lines, after dedup)"
done < "$past_dates_file"
rm -f "$past_dates_file"

# Re-derive the actual past_count from the original file for the assertion.
# Must use -c so wc -l counts records, not pretty-printed tokens.
set +o pipefail
actual_past=$(jq -c 'select(.ts != null and (.ts[0:10] < "'"$today"'"))' \
  "$SIGNALS_FILE" 2>/dev/null | wc -l | tr -d ' ')
set -o pipefail

# ── STEP 3: COUNT ASSERTION (fail-loud) ───────────────────────────────────────
log "STEP 3: count assertion — original=$original_count, past=$actual_past, today+null=$((today_count + null_ts_count))"
expected_sum=$((actual_past + today_count + null_ts_count))

if [[ "$expected_sum" -ne "$original_count" ]]; then
  err_msg="count mismatch: original=$original_count but past=$actual_past + today=$today_count + null_ts=$null_ts_count = $expected_sum"
  log "STEP 3: ABORT — $err_msg"
  log "STEP 3: live file NOT modified; backup preserved at $backup_path"
  # Write blocker alert
  mkdir -p "$(dirname "$ALERTS")"
  alert_line=$(printf '{"ts":"%sZ","blocker":true,"error":"%s","script":"rotate-signals.sh","backup":"%s"}' \
    "$(date -u '+%Y-%m-%dT%H:%M:%S')" "$err_msg" "$backup_path")
  echo "$alert_line" >> "$ALERTS"
  log "STEP 3: blocker alert written to $ALERTS"
  exit 1
fi

log "STEP 3: assertion PASSED — counts conserved"

# ── STEP 4: TRIM — atomic rewrite of live file ───────────────────────────────
log "STEP 4: trimming live file to today-only entries (atomic)..."
tmp_file="$(mktemp "${SIGNALS_FILE}.tmp.XXXXXX")"
# Keep today's entries + any null-ts entries (safety: don't discard unknowns)
jq -c 'select(.ts == null or (.ts[0:10] >= "'"$today"'"))' "$SIGNALS_FILE" > "$tmp_file"
new_count=$(wc -l < "$tmp_file" | tr -d ' ')
mv "$tmp_file" "$SIGNALS_FILE"
log "STEP 4: live file rewritten — $new_count lines remaining"

# ── STEP 5: COMPRESS + RETENTION ─────────────────────────────────────────────
log "STEP 5: compressing new archive shards..."
# Use a temp list file to avoid pipe-subshell (so gzip errors propagate under set -e)
shard_list="$(mktemp /tmp/rotate-signals-shards.XXXXXX)"
find "$ARCHIVE_DIR" -name "signals-*.jsonl" ! -name "*.gz" > "$shard_list" 2>/dev/null || true
while IFS= read -r shard; do
  [[ -z "$shard" ]] && continue
  gzip -f "$shard"
  log "STEP 5:   gzipped ${shard}.gz"
done < "$shard_list"
rm -f "$shard_list"

log "STEP 5: pruning archives older than ${RETENTION} days..."
old_gz_list="$(mktemp /tmp/rotate-signals-old-gz.XXXXXX)"
find "$ARCHIVE_DIR" -name "signals-*.jsonl.gz" -mtime "+${RETENTION}" > "$old_gz_list" 2>/dev/null || true
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  log "STEP 5:   pruning (retention) $f"
  rm -f "$f"
done < "$old_gz_list"
rm -f "$old_gz_list"

log "STEP 5: pruning backups older than 7 days..."
old_bak_list="$(mktemp /tmp/rotate-signals-old-bak.XXXXXX)"
find "$ARCHIVE_DIR" -name "signals.jsonl.bak-*" -mtime "+7" > "$old_bak_list" 2>/dev/null || true
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  log "STEP 5:   pruning (>7d) backup $f"
  rm -f "$f"
done < "$old_bak_list"
rm -f "$old_bak_list"

log "rotate-signals.sh: DONE — $actual_past entries archived, $new_count entries kept, backup at $backup_path"
exit 0
