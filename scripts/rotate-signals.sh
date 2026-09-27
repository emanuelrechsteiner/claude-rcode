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
#   0. GATE     — every record must be an object with a string .ts starting
#                 YYYY-MM-DD, else exit 1 before any mutation (review-2 #3)
#   2. ARCHIVE  — add past-date entries to per-date files in ARCHIVE_DIR (built
#                 in a dot-temp, then mv — no partial line on a kill, review-2 #5)
#   3. ASSERT   — verify past_count + today_count == original_count (fail-loud)
#   3c. MERGE   — merge each plain shard with its existing .gz (IMP-226: a late
#                 entry must never overwrite an archived day), verified atomic
#                 recompress (every merged line must parse as JSON); runs
#                 BEFORE the trim so a failure keeps the live file
#   4. TRIM     — write the continuity receipt for the trimmed temp, THEN
#                 rewrite the live file to today-only (atomic temp+mv)
#   5. RETAIN   — prune old .gz and .bak files
#
# IMP-221 — EMPTY SHARDS: a day with zero entries used to get no shard at all,
# and daily-docs' logbook-count.sh reads "no shard" as ABORT(5) "archive
# MISSING". After the assertion passes (and on the empty-file / no-past-entries
# no-op paths), every date in (anchor, yesterday] without a shard gets a valid,
# content-empty gz — ONLY if the continuity proof below holds. anchor = newest
# shard that existed BEFORE this run (the last trim boundary), else the oldest
# date archived by this run, raised to the receipt's floor. Older interior gaps
# are NEVER auto-filled; backfill them only after an independent check via
# --fill-empty-shard=YYYY-MM-DD (same writer function).
#
# CONTINUITY PROOF (review #4): an empty shard certifies "zero signals", so the
# live file must provably be the same, append-only file since the last run. A
# truncated (`: > signals.jsonl`) or deleted-and-recreated live file used to
# pass and turn a data loss into confident zero-signal days. Every successful
# run writes the receipt $ARCHIVE_DIR/<live basename>.continuity =
# "v1 <inode> <size> <cksum of those bytes> <floor|->" describing the live file
# as this run left it. A trimming run writes it BEFORE its mv (the rename keeps
# the temp's inode and mtime) and adds a 2nd line "pre <inode> <size> <cksum>"
# for the live file as it stood — so a failure, kill or sleep between receipt
# and mv never leaves a stale receipt (review-2 #1). The next run's proof, for
# line 1 or else the "pre" line: same inode, size >= recorded, same
# cksum over the recorded byte prefix, and (size unchanged) not modified since
# the receipt. First run without a receipt: the newest .bak is a byte prefix of
# the live file, or its trimmed form (same jq filter as STEP 4) a line prefix;
# no receipt and no backup = fresh archive, assumed and logged. Not proven →
# the fill is skipped for the whole run, everything else completes, alert,
# exit 3, and the receipt is re-armed with floor=today so the unproven dates
# (anchor, today] — today included — are never auto-filled later (they stay
# shard-less → consumers ABORT(5)); the alert names exactly that range.
# RESIDUAL (not closable from on-disk state): if the last run left the file
# EMPTY (normal after a 02:05 UTC trim) and it is then truncated AND appended
# to again before the next run, nothing distinguishes that from a quiet day.
# Inode reuse after delete+recreate (ext4) likewise evades the inode check.
#
# Usage:
#   bash ~/.claude/scripts/rotate-signals.sh [--dry-run]
#   bash ~/.claude/scripts/rotate-signals.sh --fill-empty-shard=YYYY-MM-DD [...]
#
# Env overrides (for testing — never touch real files in tests):
#   CLAUDE_SIGNALS_FILE      default: $HOME/.claude/global-observation/signals.jsonl
#   CLAUDE_ARCHIVE_DIR       default: $HOME/.claude/global-observation/archives
#   CLAUDE_ALERTS_FILE       default: $HOME/.claude/global-observation/alerts.jsonl
#   CLAUDE_SIGNALS_RETENTION_DAYS   default: 30
#   CLAUDE_ROTATE_TODAY      TEST-ONLY: pin "today" (YYYY-MM-DD, UTC) so the
#                            regression suite cannot flake across midnight.
#                            Never set it in the nightly job. Against the
#                            DEFAULT live file it is refused (exit 2) unless
#                            within +-1 day of the real UTC date (review-2 #7).
#   CLAUDE_ROTATE_PREFIX     default: signals — shard filename prefix
#                            (signals-YYYY-MM-DD.jsonl[.gz]). Generalized
#                            2026-08-22 so ANY newline-JSON log with a top-level
#                            "ts" string field can reuse this archive-then-trim engine
#                            without copy-pasting it — set CLAUDE_SIGNALS_FILE
#                            to the target log and CLAUDE_ROTATE_PREFIX to a
#                            distinct shard prefix (never "signals" for a
#                            non-signals file — shards would collide/co-mingle
#                            in the same ARCHIVE_DIR). Default reproduces the
#                            exact prior behavior byte-for-byte.
#
# Exit codes — every non-zero exit appends ONE line to $ALERTS:
#   {"ts","blocker","error","exit","script","stage","trimmed"[,"backup"]}
#   0 — clean run, clean dry-run, or nothing to do (a dry-run exits 1/3 like
#       a real run when its read-only checks fail — alert written — and never
#       writes a shard, receipt or the live file)
#   1 — content check refused, nothing mutated: non-JSON lines in the live
#       file; a record that is not an object or whose ts is missing, null,
#       empty or not YYYY-MM-DD-prefixed (first 3 line numbers named); count
#       assertion failed (backup kept); or --fill-empty-shard refused because
#       the live file still holds entries for that date
#   2 — script-level error: bad arguments or a CLAUDE_ROTATE_TODAY refused
#       against the default live file (blocker:false), missing dependency,
#       unwritable path, failed listing / write / merge / recompress, a merged
#       shard with non-JSON lines, or ANY unexpected command failure (EXIT-trap
#       catch-all). The alert names the stage and "trimmed"; before the STEP 4
#       mv the live file is untouched.
#   3 — continuity NOT proven (live file deleted, replaced, truncated or
#       rewritten since the last run): empty-shard fill skipped, the rest of
#       the run completed, receipt re-armed with floor=today; the alert names
#       the unproven range (anchor, today]. Dry-run: same verdict, nothing
#       written but the alert. Live file missing while a receipt exists:
#       nothing rotated or filled, receipt untouched.
#
# Idempotent: a second same-day run finds no past-date entries → no-op; the
# count assertion holds trivially (past=0, today=original_count).
# ─────────────────────────────────────────────────────────────────────────────
set -Eeuo pipefail

# ── Paths (env-overridable for testability) ───────────────────────────────────
DEFAULT_SIGNALS_FILE="$HOME/.claude/global-observation/signals.jsonl"
SIGNALS_FILE="${CLAUDE_SIGNALS_FILE:-$DEFAULT_SIGNALS_FILE}"
ARCHIVE_DIR="${CLAUDE_ARCHIVE_DIR:-$HOME/.claude/global-observation/archives}"
ALERTS="${CLAUDE_ALERTS_FILE:-$HOME/.claude/global-observation/alerts.jsonl}"
RETENTION="${CLAUDE_SIGNALS_RETENTION_DAYS:-30}"
PREFIX="${CLAUDE_ROTATE_PREFIX:-signals}"
LIVE_BASENAME="$(basename "$SIGNALS_FILE")"
RECEIPT="$ARCHIVE_DIR/${LIVE_BASENAME}.continuity"

# ── Failure plumbing: every exit is deliberate (finish/die) or caught ─────────
EXPECTED_EXIT=0; STAGE="preflight"; TRIMMED=0; backup_path=""
FAIL_LINE="?"; FAIL_CMD="?"
empty_tmp=""; past_dates_file=""; shard_list=""; merge_tmp_txt=""; merge_tmp_gz=""
tmp_file=""; receipt_tmp=""; old_gz_list=""; old_bak_list=""; step2_tmp=""
log() { echo "[rotate-${PREFIX}] $*"; }
# cleanup_temps — removes every temp; returns 1 if any rm failed (callers warn).
cleanup_temps() {
  local f rc=0
  for f in "$empty_tmp" "$past_dates_file" "$shard_list" "$merge_tmp_txt" \
           "$merge_tmp_gz" "$tmp_file" "$receipt_tmp" "$old_gz_list" "$old_bak_list" \
           "$step2_tmp"; do
    if [[ -n "$f" ]]; then rm -f -- "$f" || rc=1; fi
  done
  return "$rc"
}
# cleanup_or_warn — the exit paths' cleanup: a failed rm is reported, never fatal.
cleanup_or_warn() {
  cleanup_temps || echo "[rotate-${PREFIX}] WARNING: temp cleanup incomplete (see rm errors above)" >&2 || true
}
# write_alert <exit> <msg> <blocker:true|false> — never aborts the caller.
write_alert() {
  local line ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" || ts="date-unavailable"
  if command -v jq >/dev/null 2>&1; then
    line="$(jq -cn --arg ts "$ts" --arg e "$2" --argjson x "$1" --argjson b "$3" \
      --arg st "$STAGE" --argjson tr "$TRIMMED" --arg bk "$backup_path" \
      '{ts:$ts,blocker:$b,error:$e,exit:$x,script:"rotate-signals.sh",stage:$st,trimmed:($tr==1)}
       + (if $bk == "" then {} else {backup:$bk} end)')" || line=""
  else
    line="$(printf '{"ts":"%s","blocker":%s,"error":"%s","exit":%s,"script":"rotate-signals.sh","stage":"%s"}' \
      "$ts" "$3" "$(printf '%s' "$2" | tr -d '"\\')" "$1" "$STAGE")" || line=""
  fi
  if [[ -n "$line" ]] && mkdir -p "$(dirname "$ALERTS")" && printf '%s\n' "$line" >> "$ALERTS"; then
    log "alert written to $ALERTS" || true
  else
    echo "[rotate-${PREFIX}] ALERT WRITE FAILED ($ALERTS): $2" >&2 || true
  fi
}
# die <exit> <msg> [blocker=true] — the ONLY non-zero deliberate exit. Never
# call it inside $(...): the exit would only leave the subshell.
# EXPECTED_EXIT is set FIRST (review-2 #9): a failing rm/echo below must not
# re-enter on_exit and append a second, "unexpected failure" alert — and every
# step below is non-fatal, so the documented exit code always wins.
die() {
  EXPECTED_EXIT=1
  cleanup_or_warn
  echo "[rotate-${PREFIX}] EXIT $1 (stage=$STAGE, trimmed=$TRIMMED): $2" >&2 || true
  write_alert "$1" "$2" "${3:-true}" || true
  exit "$1"
}
finish() { EXPECTED_EXIT=1; cleanup_or_warn; exit 0; }
on_exit() {
  local rc=$?
  [[ "$EXPECTED_EXIT" -eq 1 ]] && return 0
  EXPECTED_EXIT=1
  trap - EXIT
  cleanup_or_warn
  echo "[rotate-${PREFIX}] EXIT 2: unexpected failure (status $rc) at line $FAIL_LINE: $FAIL_CMD" >&2 || true
  write_alert 2 "unexpected failure (status $rc) at line $FAIL_LINE: $FAIL_CMD" true || true
  exit 2
}
trap on_exit EXIT
# ERR (inherited via -E) only RECORDS — it also fires inside $(...), so no output.
trap 'FAIL_LINE=$LINENO; FAIL_CMD=$BASH_COMMAND' ERR

# ── Argument parsing ──────────────────────────────────────────────────────────
DRY_RUN=0
FILL_DATES=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --fill-empty-shard=*) FILL_DATES="$FILL_DATES ${arg#--fill-empty-shard=}" ;;
    *) die 2 "unknown argument: $arg" false ;;
  esac
done

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in jq gzip date mktemp mv cp rm wc sort find sed awk head tail tr cksum ls; do
  command -v "$cmd" &>/dev/null || die 2 "required command not found: $cmd"
done

# ── Dates (UTC) ───────────────────────────────────────────────────────────────
# add_days <YYYY-MM-DD> <n> — UTC calendar arithmetic via jq (already a dep).
add_days() {
  jq -rn --arg d "$1" --argjson n "$2" \
    '($d+"T00:00:00Z"|fromdateiso8601)+($n*86400)|strftime("%Y-%m-%d")'
}
# valid_date <s> — strict YYYY-MM-DD that survives a calendar round-trip.
valid_date() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ "$(add_days "$1" 0)" == "$1" ]]
}
real_today="$(date -u '+%Y-%m-%d')"
if [[ -n "${CLAUDE_ROTATE_TODAY:-}" ]]; then
  valid_date "$CLAUDE_ROTATE_TODAY" || die 2 "CLAUDE_ROTATE_TODAY='$CLAUDE_ROTATE_TODAY' is not YYYY-MM-DD" false
  # Review-2 #7: a pinned date on the REAL live file would archive/trim against
  # the wrong day. Allowed there only within +-1 day of the real UTC date.
  if [[ "$SIGNALS_FILE" == "$DEFAULT_SIGNALS_FILE" ]]; then
    pin_skew="$(jq -rn --arg a "$CLAUDE_ROTATE_TODAY" --arg b "$real_today" \
      '(($a+"T00:00:00Z"|fromdateiso8601)-($b+"T00:00:00Z"|fromdateiso8601))/86400
       | if . < 0 then -. else . end | floor')" \
      || die 2 "cannot compare CLAUDE_ROTATE_TODAY with the real UTC date"
    [[ "$pin_skew" -le 1 ]] || die 2 "CLAUDE_ROTATE_TODAY=$CLAUDE_ROTATE_TODAY is $pin_skew days from the real UTC date $real_today while the DEFAULT live file is targeted — refused (test-only override; set CLAUDE_SIGNALS_FILE to a scratch file)" false
  fi
  today="$CLAUDE_ROTATE_TODAY"
  log "TEST-ONLY: today pinned to $today via CLAUDE_ROTATE_TODAY"
else
  today="$real_today"
fi
# Backup stamp carries the SAME date the trim filter uses (continuity bootstrap).
ts_now="${today//-/}T$(date -u '+%H%M%S')Z"
yesterday="$(add_days "$today" -1)"

# ── IMP-221 empty-shard helpers (the ONLY writer of empty shards) ─────────────
shard_exists() {
  [[ -f "$ARCHIVE_DIR/${PREFIX}-$1.jsonl" || -f "$ARCHIVE_DIR/${PREFIX}-$1.jsonl.gz" ]]
}
# write_empty_shard <date> — atomic, verified, never overwrites an existing shard.
write_empty_shard() {
  local d="$1" dst="$ARCHIVE_DIR/${PREFIX}-$1.jsonl.gz" lines
  if shard_exists "$d"; then log "EMPTY-SHARD: $d already has a shard — untouched"; return 0; fi
  mkdir -p "$ARCHIVE_DIR" || die 2 "EMPTY-SHARD: cannot create $ARCHIVE_DIR"
  empty_tmp="$(mktemp "$ARCHIVE_DIR/.${PREFIX}-$d.empty.XXXXXX")" || die 2 "EMPTY-SHARD: mktemp failed in $ARCHIVE_DIR"
  gzip -c < /dev/null > "$empty_tmp" || die 2 "EMPTY-SHARD: gzip failed writing the empty shard for $d"
  gzip -t "$empty_tmp" || die 2 "EMPTY-SHARD: self-check gzip -t failed for $d"
  lines="$(gzip -dc < "$empty_tmp" | wc -l | tr -d ' ')" || die 2 "EMPTY-SHARD: cannot re-read the empty shard for $d"
  [[ "$lines" -eq 0 ]] || die 2 "EMPTY-SHARD: self-check failed for $d (lines=$lines)"
  mv "$empty_tmp" "$dst" || die 2 "EMPTY-SHARD: mv onto $dst failed"
  empty_tmp=""
  log "EMPTY-SHARD: wrote $dst (0 lines, $(wc -c < "$dst" | tr -d ' ') bytes, zero-signal day)"
}
# fill_empty_shards <anchor> — every date in (anchor, yesterday] without a shard.
fill_empty_shards() {
  local anchor="$1" d n=0 guard=0
  if [[ -z "$anchor" ]]; then
    log "EMPTY-SHARD: no anchor shard — continuity unprovable, nothing filled"; return 0
  fi
  d="$(add_days "$anchor" 1)"
  while [[ ! "$d" > "$yesterday" ]]; do
    guard=$((guard + 1))
    [[ "$guard" -gt 400 ]] && die 2 "EMPTY-SHARD: range from $anchor exceeds 400 days"
    if ! shard_exists "$d"; then
      if [[ "$DRY_RUN" -eq 1 ]]; then log "DRY-RUN: would write empty shard for $d"
      else write_empty_shard "$d"; fi
      n=$((n + 1))
    fi
    d="$(add_days "$d" 1)"
  done
  log "EMPTY-SHARD: $n zero-signal day(s) in ($anchor, $yesterday]"
}

# ── Explicit backfill mode (caller has verified zero activity independently) ──
if [[ -n "$FILL_DATES" ]]; then
  STAGE="fill-mode"
  [[ "$DRY_RUN" -eq 1 ]] && die 2 "--fill-empty-shard cannot be combined with --dry-run" false
  for d in $FILL_DATES; do
    valid_date "$d" || die 2 "FILL: invalid date '$d'" false
    [[ "$d" < "$today" ]] || die 2 "FILL: $d is not in the past (today=$today)" false
  done
  for d in $FILL_DATES; do
    if [[ -s "$SIGNALS_FILE" ]]; then
      live_n="$(jq -c --arg d "$d" 'select(.ts != null and .ts[0:10] == $d)' "$SIGNALS_FILE" | wc -l | tr -d ' ')" \
        || die 2 "FILL: cannot scan $SIGNALS_FILE for $d (jq failed)"
      [[ "$live_n" -eq 0 ]] || die 1 "FILL: REFUSED $d — live file holds $live_n entries for it" false
    fi
    write_empty_shard "$d"
  done
  finish
fi

# ── Continuity proof (review #4) — read-only; sets CONT_OK/CONT_REASON/CONT_FLOOR
# trim_filter <date> <file> — THE trim selection (STEP 4 and the bootstrap proof).
trim_filter() { jq -c --arg d "$1" 'select(.ts == null or (.ts[0:10] >= $d))' "$2"; }
file_inode() { ls -di "$1" | awk '{print $1}'; }
prefix_cksum() { # prefix_cksum <file> <bytes> — cksum CRC of the first <bytes> bytes
  if [[ "$2" -eq 0 ]]; then printf '' | cksum | awk '{print $1}'
  else head -c "$2" "$1" | cksum | awk '{print $1}'; fi
}
CONT_OK=0; CONT_REASON=""; CONT_FLOOR=""
# desc_matches <inode> <size> <crc> <cur_inode> <cur_size> — does the live file
# continue the described file append-only? 0 = yes; else DESC_REASON says why.
DESC_REASON=""
desc_matches() {
  local newer live_crc
  if [[ "$4" != "$1" ]]; then
    DESC_REASON="live file replaced since the last run (inode $1 -> $4): deleted/recreated or rewritten"; return 1
  fi
  if [[ "$5" -lt "$2" ]]; then
    DESC_REASON="live file shrank since the last run ($2 -> $5 bytes): truncated"; return 1
  fi
  live_crc="$(prefix_cksum "$SIGNALS_FILE" "$2")" || die 2 "continuity: cannot checksum $SIGNALS_FILE"
  if [[ "$live_crc" != "$3" ]]; then
    DESC_REASON="first $2 bytes of the live file changed since the last run: truncated and regrown, or rewritten"; return 1
  fi
  if [[ "$5" -eq "$2" ]]; then
    newer="$(find "$SIGNALS_FILE" -newer "$RECEIPT" -print)" || die 2 "continuity: find -newer failed on $SIGNALS_FILE"
    if [[ -n "$newer" ]]; then
      DESC_REASON="live file modified since the last run without growing ($5 bytes): truncated or rewritten"; return 1
    fi
  fi
  return 0
}
continuity_check() {
  local cur_inode cur_size line alt re r_inode r_size r_crc bak bak_date bak_size k_n k_crc live_crc
  cur_inode="$(file_inode "$SIGNALS_FILE")" || die 2 "continuity: cannot stat $SIGNALS_FILE"
  cur_size="$(wc -c < "$SIGNALS_FILE" | tr -d ' ')" || die 2 "continuity: cannot size $SIGNALS_FILE"
  if [[ -f "$RECEIPT" ]]; then
    line="$(sed -n 1p "$RECEIPT")" || die 2 "continuity: cannot read $RECEIPT"
    alt="$(sed -n 2p "$RECEIPT")" || die 2 "continuity: cannot read $RECEIPT"
    re='^v1 ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]{4}-[0-9]{2}-[0-9]{2}|-)$'
    if [[ ! "$line" =~ $re ]]; then CONT_REASON="receipt $RECEIPT is malformed"; return 0; fi
    r_inode="${BASH_REMATCH[1]}"; r_size="${BASH_REMATCH[2]}"; r_crc="${BASH_REMATCH[3]}"
    if [[ "${BASH_REMATCH[4]}" != "-" ]]; then CONT_FLOOR="${BASH_REMATCH[4]}"; fi
    if desc_matches "$r_inode" "$r_size" "$r_crc" "$cur_inode" "$cur_size"; then
      CONT_OK=1; CONT_REASON="receipt: same inode, ${r_size}-byte prefix intact, append-only"; return 0
    fi
    CONT_REASON="$DESC_REASON"
    [[ -z "$alt" ]] && return 0
    # Review-2 #1: a trim writes the receipt BEFORE its mv, describing the
    # trimmed temp (line 1) AND the live file as it stood (line 2, "pre").
    # Stopped between the two (mv failed, kill, sleep)? The live file is still
    # the pre-trim file — accept that description instead of a false exit 3.
    re='^pre ([0-9]+) ([0-9]+) ([0-9]+)$'
    if [[ ! "$alt" =~ $re ]]; then CONT_REASON="receipt $RECEIPT is malformed (line 2)"; return 0; fi
    if desc_matches "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "$cur_inode" "$cur_size"; then
      CONT_OK=1; CONT_REASON="receipt (pre-trim line): the last run stopped between its receipt and its trim; same inode, prefix intact, append-only"
    fi
    return 0
  fi
  bak=""
  if [[ -d "$ARCHIVE_DIR" ]]; then
    bak="$(find "$ARCHIVE_DIR" -maxdepth 1 -name "${LIVE_BASENAME}.bak-*")" \
      || die 2 "continuity: cannot list backups in $ARCHIVE_DIR"
    bak="$(printf '%s\n' "$bak" | LC_ALL=C sort | tail -1)"
  fi
  if [[ -z "$bak" ]]; then
    CONT_OK=1; CONT_REASON="bootstrap: no receipt and no backup (fresh archive) — continuity ASSUMED"; return 0
  fi
  re='\.bak-([0-9]{4})([0-9]{2})([0-9]{2})T[0-9]{6}Z$'
  if [[ ! "$bak" =~ $re ]]; then CONT_REASON="bootstrap: unrecognised backup name $bak"; return 0; fi
  bak_date="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
  bak_size="$(wc -c < "$bak" | tr -d ' ')" || die 2 "continuity: cannot size $bak"
  if [[ "$cur_size" -ge "$bak_size" ]]; then
    live_crc="$(prefix_cksum "$SIGNALS_FILE" "$bak_size")" || die 2 "continuity: cannot checksum $SIGNALS_FILE"
    k_crc="$(prefix_cksum "$bak" "$bak_size")" || die 2 "continuity: cannot checksum $bak"
    if [[ "$live_crc" == "$k_crc" ]]; then
      CONT_OK=1; CONT_REASON="bootstrap: newest backup is a byte prefix of the live file (not trimmed since)"; return 0
    fi
  fi
  if ! k_n="$(trim_filter "$bak_date" "$bak" | wc -l | tr -d ' ')"; then
    CONT_REASON="bootstrap: cannot parse newest backup $bak"; return 0
  fi
  if [[ "$k_n" -eq 0 ]]; then
    CONT_OK=1; CONT_REASON="bootstrap: last trim kept 0 lines ($bak) — nothing to compare, continuity ASSUMED"; return 0
  fi
  k_crc="$(trim_filter "$bak_date" "$bak" | cksum | awk '{print $1}')" || die 2 "continuity: cannot checksum trimmed $bak"
  live_crc="$(head -n "$k_n" "$SIGNALS_FILE" | cksum | awk '{print $1}')" || die 2 "continuity: cannot checksum $SIGNALS_FILE"
  if [[ "$live_crc" == "$k_crc" ]]; then
    CONT_OK=1; CONT_REASON="bootstrap: the $k_n lines the last trim kept ($bak) still head the live file"; return 0
  fi
  CONT_REASON="bootstrap: the $k_n lines the last trim kept ($bak) no longer head the live file: truncated or rewritten"
  return 0
}
# fill_if_continuous <anchor> — the fill, gated by the proof and raised to the floor.
fill_if_continuous() {
  local anchor="$1"
  if [[ "$CONT_OK" -ne 1 ]]; then
    log "EMPTY-SHARD: SKIPPED — continuity NOT proven: $CONT_REASON"; return 0
  fi
  if [[ -n "$anchor" && -n "$CONT_FLOOR" && "$CONT_FLOOR" > "$anchor" ]]; then
    log "EMPTY-SHARD: anchor $anchor raised to floor $CONT_FLOOR (earlier unproven gap)"; anchor="$CONT_FLOOR"
  fi
  fill_empty_shards "$anchor"
}
# write_receipt [<file-to-be-live>] — atomic receipt. No argument: describes the
# live file as this run leaves it. With the trimmed temp (STEP 4, written BEFORE
# the mv — rename keeps its inode and mtime): line 1 describes that temp, line 2
# ("pre") the live file as it stands now, so a stop between receipt and mv is
# still provable (review-2 #1).
write_receipt() {
  local target="${1:-$SIGNALS_FILE}" inode size crc floor="${CONT_FLOOR:--}" pre=""
  local p_inode p_size p_crc
  [[ "$CONT_OK" -eq 1 ]] || floor="$today"
  inode="$(file_inode "$target")" || die 2 "receipt: cannot stat $target"
  size="$(wc -c < "$target" | tr -d ' ')" || die 2 "receipt: cannot size $target"
  crc="$(prefix_cksum "$target" "$size")" || die 2 "receipt: cannot checksum $target"
  if [[ "$target" != "$SIGNALS_FILE" ]]; then
    p_inode="$(file_inode "$SIGNALS_FILE")" || die 2 "receipt: cannot stat $SIGNALS_FILE"
    p_size="$(wc -c < "$SIGNALS_FILE" | tr -d ' ')" || die 2 "receipt: cannot size $SIGNALS_FILE"
    p_crc="$(prefix_cksum "$SIGNALS_FILE" "$p_size")" || die 2 "receipt: cannot checksum $SIGNALS_FILE"
    pre="pre $p_inode $p_size $p_crc"
  fi
  mkdir -p "$ARCHIVE_DIR" || die 2 "receipt: cannot create $ARCHIVE_DIR"
  receipt_tmp="$(mktemp "$ARCHIVE_DIR/.${LIVE_BASENAME}.continuity.XXXXXX")" || die 2 "receipt: mktemp failed in $ARCHIVE_DIR"
  printf 'v1 %s %s %s %s\n' "$inode" "$size" "$crc" "$floor" > "$receipt_tmp" || die 2 "receipt: write failed"
  if [[ -n "$pre" ]]; then printf '%s\n' "$pre" >> "$receipt_tmp" || die 2 "receipt: write failed"; fi
  mv "$receipt_tmp" "$RECEIPT" || die 2 "receipt: mv onto $RECEIPT failed"
  receipt_tmp=""
  log "CONTINUITY: receipt written (inode=$inode size=$size floor=$floor${pre:+; $pre})"
}
# The dates an exit 3 leaves unproven: the re-armed floor is TODAY, so the
# range is (anchor, today] — today included (review-2 #2), not (anchor, yesterday].
# finish_run — exit 0, or 3 (alert) when the fill was skipped for lack of proof.
finish_run() {
  STAGE="continuity-verdict"
  [[ "$CONT_OK" -eq 1 ]] && finish
  die 3 "continuity of $SIGNALS_FILE NOT proven ($CONT_REASON) — empty-shard fill skipped; receipt re-armed with floor $today, so the dates ($anchor_for_alert, $today] are never auto-filled. Verify independently, then backfill true zero-signal days with --fill-empty-shard=YYYY-MM-DD"
}
# dry_run_verdict <anchor> — review-2 #6: a dry-run whose proof fails exits 3
# like the real run would (alert written; no shard, receipt or live-file write).
dry_run_verdict() {
  STAGE="continuity-verdict"
  [[ "$CONT_OK" -eq 1 ]] && { log "DRY-RUN: no files mutated — exiting cleanly"; finish; }
  die 3 "DRY-RUN: continuity of $SIGNALS_FILE NOT proven ($CONT_REASON) — a real run would skip the empty-shard fill and re-arm the receipt with floor $today, leaving the dates (${1:-none}, $today] unfilled. Nothing written."
}

# ── Anchor + missing/empty live file ─────────────────────────────────────────
pre_anchor=""
if [[ -d "$ARCHIVE_DIR" ]]; then
  shard_names="$(find "$ARCHIVE_DIR" -maxdepth 1 -name "${PREFIX}-????-??-??.jsonl*")" \
    || die 2 "cannot list shards in $ARCHIVE_DIR (find failed) — nothing mutated"
  pre_anchor="$(printf '%s\n' "$shard_names" \
    | sed -n "s|.*/${PREFIX}-\([0-9-]\{10\}\)\.jsonl\(\.gz\)\{0,1\}$|\1|p" \
    | LC_ALL=C awk -v t="$today" '$0 < t' | LC_ALL=C sort | tail -1)"
fi
anchor_for_alert="${pre_anchor:-none}"
if [[ ! -f "$SIGNALS_FILE" ]]; then
  if [[ -f "$RECEIPT" ]]; then
    CONT_REASON="live file $SIGNALS_FILE is missing although receipt $RECEIPT exists: it was deleted"
    log "EMPTY-SHARD: SKIPPED — $CONT_REASON"
    die 3 "continuity NOT proven: $CONT_REASON — nothing rotated, nothing filled"
  fi
  log "target file not found ($SIGNALS_FILE) — nothing to rotate; empty-shard fill SKIPPED (a missing file proves nothing about zero-signal days)"
  finish
fi
STAGE="continuity"
continuity_check
if [[ "$CONT_OK" -eq 1 ]]; then log "CONTINUITY: proven — $CONT_REASON"
else log "CONTINUITY: NOT proven — $CONT_REASON"; fi
if [[ ! -s "$SIGNALS_FILE" ]]; then
  log "target file is empty — nothing to rotate"
  if [[ "$DRY_RUN" -eq 1 ]]; then fill_if_continuous "$pre_anchor"; dry_run_verdict "$pre_anchor"; fi
  STAGE="fill"; fill_if_continuous "$pre_anchor"
  STAGE="receipt"; write_receipt
  finish_run
fi

# ── Announce mode ─────────────────────────────────────────────────────────────
STAGE="count"
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
# jq stderr is suppressed and pipefail relaxed ON PURPOSE: a parse error must
# not abort here — the valid_json_count assertion below detects it (exit 1).
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
  die 1 "file contains non-JSON lines: total=$original_count but valid-JSON=$valid_json_count ($(( original_count - valid_json_count )) bad lines) — live file NOT modified"
fi

# Review-2 #3: every record must be an object whose .ts starts with YYYY-MM-DD.
# An empty ts sorted as "past" but produced an empty date that STEP 2 skipped
# (entry lost, count check still passed); a short/unpadded ts made a junk
# shard; a null/missing ts stayed in the live file forever. Refuse all of them
# BEFORE any mutation (exit 1). Record N == line N: the check above proved
# one JSON value per line.
bad_ts_report="$(jq -r 'if (type != "object") or ((.ts | type) != "string")
      or ((.ts[0:10] | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) | not)
    then "BAD" else "ok" end' "$SIGNALS_FILE" \
  | awk '$0 == "BAD" { n++; if (n <= 3) l = l (l == "" ? "" : ",") NR } END { print n + 0, l }')" \
  || die 2 "cannot scan the ts values of $SIGNALS_FILE (jq/awk failed) — live file NOT modified"
bad_ts_n="${bad_ts_report%% *}"
if [[ "$bad_ts_n" -ne 0 ]]; then
  die 1 "$bad_ts_n record(s) with a missing, null, empty or malformed ts (first lines: ${bad_ts_report#* }) — ts must be a string starting YYYY-MM-DD; fix them by hand. Live file NOT modified"
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
      | LC_ALL=C sort | uniq -c | while read -r cnt date; do
        log "DRY-RUN:   → $ARCHIVE_DIR/${PREFIX}-$date.jsonl  ($cnt entries)"
      done
  fi
  # Empty-shard preview: the run-archived dates are not on disk yet, so the
  # preview anchor falls back to the oldest past date in the live file.
  # awk 'NR==1' (not head -1) drains the pipe: head exiting early SIGPIPEs sort
  # on a large file, and pipefail turned that into a false exit 2 (review-2 #8).
  dry_anchor="$pre_anchor"
  [[ -z "$dry_anchor" && "$past_count" -gt 0 ]] && dry_anchor=$(jq -r \
    'select(.ts != null and (.ts[0:10] < "'"$today"'")) | .ts[0:10]' "$SIGNALS_FILE" | LC_ALL=C sort | awk 'NR == 1')
  dry_dates=" $(jq -r 'select(.ts != null) | .ts[0:10]' "$SIGNALS_FILE" | LC_ALL=C sort -u | tr '\n' ' ')"
  shard_exists() { [[ "$dry_dates" == *" $1 "* || -f "$ARCHIVE_DIR/${PREFIX}-$1.jsonl" || -f "$ARCHIVE_DIR/${PREFIX}-$1.jsonl.gz" ]]; }
  fill_if_continuous "$dry_anchor"
  dry_run_verdict "$dry_anchor"
fi

# ── No past entries → idempotent no-op ───────────────────────────────────────
if [[ "$past_count" -eq 0 ]]; then
  log "no past-date entries found — nothing to rotate (idempotent no-op)"
  STAGE="fill"; fill_if_continuous "$pre_anchor"
  STAGE="receipt"; write_receipt
  finish_run
fi

# ── STEP 1: BACKUP (the guard that was missing in the original logic) ─────────
STAGE="step1-backup"
mkdir -p "$ARCHIVE_DIR" || die 2 "STEP 1: cannot create $ARCHIVE_DIR — live file untouched"
log "STEP 1: backing up to $ARCHIVE_DIR/${LIVE_BASENAME}.bak-${ts_now}"
cp "$SIGNALS_FILE" "$ARCHIVE_DIR/${LIVE_BASENAME}.bak-${ts_now}" \
  || die 2 "STEP 1: backup copy failed — live file untouched"
backup_path="$ARCHIVE_DIR/${LIVE_BASENAME}.bak-${ts_now}"
log "STEP 1: backup written ($(wc -l < "$backup_path" | tr -d ' ') lines)"

# ── STEP 2: ARCHIVE per-date shards ──────────────────────────────────────────
STAGE="step2-archive"
log "STEP 2: archiving past-date entries by date..."

# Extract unique past dates into a temp file (bash 3 compat — no mapfile)
past_dates_file="$(mktemp /tmp/rotate-signals-dates.XXXXXX)" || die 2 "STEP 2: mktemp failed — live file untouched"
jq -r 'select(.ts != null and (.ts[0:10] < "'"$today"'")) | .ts[0:10]' \
  "$SIGNALS_FILE" | LC_ALL=C sort -u > "$past_dates_file" \
  || die 2 "STEP 2: cannot list past dates — live file untouched"

while IFS= read -r entry_date; do
  [[ -z "$entry_date" ]] && continue
  shard="$ARCHIVE_DIR/${PREFIX}-${entry_date}.jsonl"
  # Review-2 #5: build the day's shard in a dot-temp (invisible to STEP 3c's
  # listing) and mv it into place, so a kill mid-write can never leave a
  # partial line in the plain shard. Byte-wise sort -u = idempotent dedup.
  step2_tmp="$(mktemp "$ARCHIVE_DIR/.${PREFIX}-${entry_date}.step2.XXXXXX")" \
    || die 2 "STEP 2: mktemp failed in $ARCHIVE_DIR — live file untouched"
  jq -c 'select(.ts != null and (.ts[0:10] == "'"$entry_date"'"))' "$SIGNALS_FILE" \
    > "$step2_tmp" || die 2 "STEP 2: cannot extract $entry_date entries — live file untouched"
  if [[ -f "$shard" ]]; then
    cat "$shard" >> "$step2_tmp" || die 2 "STEP 2: cannot read leftover $shard — live file untouched"
  fi
  LC_ALL=C sort -u "$step2_tmp" -o "$step2_tmp" || die 2 "STEP 2: sort -u failed for $shard — live file untouched"
  mv "$step2_tmp" "$shard" || die 2 "STEP 2: mv onto $shard failed — live file untouched"
  step2_tmp=""
  shard_count=$(wc -l < "$shard" | tr -d ' ')
  log "STEP 2:   $shard ($shard_count lines, after dedup)"
done < "$past_dates_file"
oldest_run_date="$(head -1 "$past_dates_file")"
rm -f "$past_dates_file"; past_dates_file=""

# Re-derive the actual past_count from the original file for the assertion.
# Must use -c so wc -l counts records, not pretty-printed tokens.
set +o pipefail
actual_past=$(jq -c 'select(.ts != null and (.ts[0:10] < "'"$today"'"))' \
  "$SIGNALS_FILE" 2>/dev/null | wc -l | tr -d ' ')
set -o pipefail

# ── STEP 3: COUNT ASSERTION (fail-loud) ───────────────────────────────────────
STAGE="step3-assert"
log "STEP 3: count assertion — original=$original_count, past=$actual_past, today+null=$((today_count + null_ts_count))"
expected_sum=$((actual_past + today_count + null_ts_count))

if [[ "$expected_sum" -ne "$original_count" ]]; then
  log "STEP 3: live file NOT modified; backup preserved at $backup_path"
  die 1 "count mismatch: original=$original_count but past=$actual_past + today=$today_count + null_ts=$null_ts_count = $expected_sum"
fi

log "STEP 3: assertion PASSED — counts conserved"

# ── STEP 3b: EMPTY SHARDS for zero-signal days (IMP-221) ─────────────────────
# Only after the assertion: a failed rotation must never claim "zero signals".
STAGE="step3b-fill"
fill_if_continuous "${pre_anchor:-$oldest_run_date}"
anchor_for_alert="${pre_anchor:-$oldest_run_date}"

# ── STEP 3c: MERGE + COMPRESS shards (IMP-226) — BEFORE the trim ─────────────
# A late entry for an already-archived date lands in a fresh plain .jsonl; the
# old `gzip -f` then replaced the existing gz with ONLY the late entries. Now
# every plain shard is merged with its existing gz (sort -u), recompressed to a
# temp, verified (gzip -t, line count == merged, merged >= old), then mv'd over.
# Runs before STEP 4 so any failure leaves the live file untouched: the next
# run re-archives from it, and a leftover plain shard is merged again (sort -u
# makes that idempotent).
STAGE="step3c-merge"
merge_fail() { # merge_fail <reason> — alert + exit 2; old gz untouched, plain kept
  log "STEP 3c: FATAL — $1 — old shard untouched, plain shard + live file kept"
  die 2 "IMP-226 shard merge failed: $1"
}
merge_compress_shard() { # merge_compress_shard <plain.jsonl>
  local plain="$1" dst="$1.gz" old_n=0 merged_n gz_n json_n=""
  if [[ -f "$dst" ]]; then
    gzip -t "$dst" || merge_fail "existing $dst fails gzip -t"
    old_n=$(gunzip -c "$dst" | wc -l | tr -d ' ') || merge_fail "cannot read $dst"
  fi
  merge_tmp_txt="$(mktemp "$ARCHIVE_DIR/.${PREFIX}-merge.XXXXXX")" || merge_fail "mktemp failed in $ARCHIVE_DIR"
  merge_tmp_gz="$(mktemp "$ARCHIVE_DIR/.${PREFIX}-merge-gz.XXXXXX")" || merge_fail "mktemp failed in $ARCHIVE_DIR"
  if [[ -f "$dst" ]]; then
    gunzip -c "$dst" > "$merge_tmp_txt" || merge_fail "gunzip -c $dst failed"
  fi
  cat "$plain" >> "$merge_tmp_txt" || merge_fail "cannot append $plain"
  LC_ALL=C sort -u "$merge_tmp_txt" -o "$merge_tmp_txt" || merge_fail "sort -u failed for $plain"
  merged_n=$(wc -l < "$merge_tmp_txt" | tr -d ' ')
  [[ "$merged_n" -ge "$old_n" ]] || merge_fail "merged $dst would shrink ($old_n -> $merged_n lines)"
  # Review-2 #5: every merged line must be one JSON value — a partial line (an
  # interrupted write in an older version, a hand edit) must never be archived.
  if ! json_n=$(jq -c . "$merge_tmp_txt" 2>/dev/null | wc -l | tr -d ' ') || [[ "$json_n" -ne "$merged_n" ]]; then
    merge_fail "merged $dst holds non-JSON lines (${json_n:-?} parseable of $merged_n) — inspect $plain"
  fi
  gzip -c < "$merge_tmp_txt" > "$merge_tmp_gz" || merge_fail "gzip failed for $plain"
  gzip -t "$merge_tmp_gz" || merge_fail "recompressed $dst fails gzip -t"
  gz_n=$(gunzip -c "$merge_tmp_gz" | wc -l | tr -d ' ') || merge_fail "cannot re-read recompressed $dst"
  [[ "$gz_n" -eq "$merged_n" ]] || merge_fail "recompressed $dst has $gz_n lines, expected $merged_n"
  mv "$merge_tmp_gz" "$dst" || merge_fail "mv onto $dst failed"
  merge_tmp_gz=""
  rm -f "$plain" "$merge_tmp_txt"
  merge_tmp_txt=""
  log "STEP 3c:   $dst ($old_n existing + merge -> $merged_n lines)"
}
log "STEP 3c: merging + compressing archive shards..."
# Temp list file avoids a pipe-subshell (so exit in merge_fail ends the script).
# A failed listing must abort BEFORE the trim (review #14), never read as "none".
shard_list="$(mktemp /tmp/rotate-signals-shards.XXXXXX)" || merge_fail "mktemp for the shard list failed"
find "$ARCHIVE_DIR" -name "${PREFIX}-*.jsonl" ! -name "*.gz" > "$shard_list" \
  || merge_fail "cannot list plain shards in $ARCHIVE_DIR (find failed)"
while IFS= read -r shard; do
  [[ -z "$shard" ]] && continue
  merge_compress_shard "$shard"
done < "$shard_list"
rm -f "$shard_list"; shard_list=""

# ── STEP 4: TRIM — continuity receipt, then atomic rewrite of the live file ──
STAGE="step4-trim"
log "STEP 4: trimming live file to today-only entries (atomic)..."
tmp_file="$(mktemp "${SIGNALS_FILE}.tmp.XXXXXX")" || die 2 "STEP 4: mktemp next to $SIGNALS_FILE failed — live file untouched"
# Keep today's entries (the filter's null-ts clause is unreachable here since
# the ts gate refuses null ts; it stays for the bootstrap proof over old backups)
trim_filter "$today" "$SIGNALS_FILE" > "$tmp_file" || die 2 "STEP 4: trim filter failed — live file untouched"
new_count=$(wc -l < "$tmp_file" | tr -d ' ')
# Receipt BEFORE the mv (review-2 #1): it describes the trimmed temp (the
# rename keeps inode + mtime) plus the pre-trim live file. A receipt failure
# now stops the run with the live file untouched and the old receipt valid;
# a stop after it is covered by the "pre" line. No window leaves a stale one.
STAGE="step4-receipt"
write_receipt "$tmp_file"
STAGE="step4-trim"
mv "$tmp_file" "$SIGNALS_FILE" || die 2 "STEP 4: mv of the trimmed file failed — live file untouched (receipt's pre-trim line still proves it)"
tmp_file=""; TRIMMED=1
log "STEP 4: live file rewritten — $new_count lines remaining"

# ── STEP 5: RETENTION (compression moved to STEP 3c, IMP-226) ────────────────
STAGE="step5-retention"
log "STEP 5: pruning archives older than ${RETENTION} days..."
old_gz_list="$(mktemp /tmp/rotate-signals-old-gz.XXXXXX)" || die 2 "STEP 5: mktemp failed (rotation itself completed)"
find "$ARCHIVE_DIR" -name "${PREFIX}-*.jsonl.gz" -mtime "+${RETENTION}" > "$old_gz_list" \
  || die 2 "STEP 5: cannot list archives for retention (rotation itself completed)"
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  log "STEP 5:   pruning (retention) $f"
  rm -f "$f" || die 2 "STEP 5: cannot prune $f (rotation itself completed)"
done < "$old_gz_list"
rm -f "$old_gz_list"; old_gz_list=""

log "STEP 5: pruning backups older than 7 days..."
old_bak_list="$(mktemp /tmp/rotate-signals-old-bak.XXXXXX)" || die 2 "STEP 5: mktemp failed (rotation itself completed)"
find "$ARCHIVE_DIR" -name "${LIVE_BASENAME}.bak-*" -mtime "+7" > "$old_bak_list" \
  || die 2 "STEP 5: cannot list backups for retention (rotation itself completed)"
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  log "STEP 5:   pruning (>7d) backup $f"
  rm -f "$f" || die 2 "STEP 5: cannot prune $f (rotation itself completed)"
done < "$old_bak_list"
rm -f "$old_bak_list"; old_bak_list=""

log "rotate-signals.sh: DONE — $actual_past entries archived, $new_count entries kept, backup at $backup_path"
STAGE="done"
finish_run
