#!/usr/bin/env bash
# Regression suite for scripts/compute-daily-metrics.sh — IMP-227
# ─────────────────────────────────────────────────────────────────────────────
# Companion to rotate-signals.sh's IMP-221 (empty-shard fill): since IMP-221 a
# zero-signal day gets an explicit, gzip-verified, 0-line archive shard instead
# of no shard at all. Before this fix, compute-daily-metrics.sh conflated
# "0 lines" with "corrupt" and aborted with a blocker alert on every such day —
# 7 such shards exist in the real archive as of 2026-09-27 (08-30, 08-31,
# 09-02, 09-11, 09-12, 09-14, 09-15).
#
# This suite works EXCLUSIVELY with scratch directories (CLAUDE_ARCHIVE_DIR /
# CLAUDE_METRICS_FILE / CLAUDE_ALERTS_FILE / CLAUDE_DISPATCH_LOG) — it never
# reads or writes anything under the real ~/.claude/global-observation/.
#
# Usage: bash scripts/tests/compute-daily-metrics-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET="$REPO_ROOT/scripts/compute-daily-metrics.sh"
[ -f "$TARGET" ] || { echo "compute-daily-metrics.sh not found: $TARGET" >&2; exit 1; }

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf '  [%s] %s\n' "$1" "$2"; }
check(){ # check <name> <expected> <got>
  if [ "$2" = "$3" ]; then ok; else bad "$1" "expected='$2' got='$3'"; fi
}
alert_count() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }
# grep -c prints "0" itself on no match (exit 1) — do not also echo a second 0.
row_count() { if [ -f "$1" ]; then grep -c "\"date\":\"$2\"" "$1" || true; else echo 0; fi; }

ROOT=$(mktemp -d)

# ── Pre-IMP-227 baseline script, PINNED to a fixed commit ────────────────────
# Used for (1) a negative control proving case (a) discriminates old vs. new
# behavior, and (2) the "unchanged output" comparison in case (d).
# WHY PINNED and not HEAD: once the IMP-227 fix is committed, HEAD *is* the
# fixed script — the negative control would then fail and the case-(d)
# comparison would compare the script with itself (proving nothing).
# b7f3c0d is the last commit before IMP-227 touched this script.
BASELINE_COMMIT="b7f3c0ddd045615c348ae862aae5de847e40648e"
BASELINE_SCRIPT="$ROOT/compute-daily-metrics-baseline.sh"
if git -C "$REPO_ROOT" show "$BASELINE_COMMIT:scripts/compute-daily-metrics.sh" > "$BASELINE_SCRIPT" 2>/dev/null \
   && [ -s "$BASELINE_SCRIPT" ]; then
  HAVE_BASELINE=1
  # Guard against a vacuous control: the baseline must differ from the target.
  check "baseline/differs-from-target" 1 "$(cmp -s "$BASELINE_SCRIPT" "$TARGET" && echo 0 || echo 1)"
else
  HAVE_BASELINE=0
  echo "  [warning] baseline $BASELINE_COMMIT not in this repo's history (e.g. a published copy) — baseline checks SKIPPED, counted below" >&2
fi

# setup_env <label> -> fresh scratch archive/metrics/alerts/dispatch paths,
# none of which pre-exist ($ARC is created empty; the others are created
# on demand by the script itself, exactly like the real paths).
setup_env() {
  local label="$1"
  ARC="$ROOT/archive-$label"
  MET="$ROOT/metrics-$label.jsonl"
  ALERT="$ROOT/alerts-$label.jsonl"
  DISP="$ROOT/dispatch-$label.jsonl"   # deliberately never created -> "no coverage"
  mkdir -p "$ARC"
}

run_script() { # run_script <script-path> <date> [extra-args...]
  local scr="$1"; shift
  CLAUDE_ARCHIVE_DIR="$ARC" CLAUDE_METRICS_FILE="$MET" CLAUDE_ALERTS_FILE="$ALERT" \
    CLAUDE_DISPATCH_LOG="$DISP" bash "$scr" "$@"
}

# ═══════════════════════════════════════════════════════════════════════════
# (a) Valid, gzip-verified, 0-line shard → row written, all-zero counts,
#     shard_state=empty_verified, exit 0, NO blocker alert.
# ═══════════════════════════════════════════════════════════════════════════
DATE_A="2026-08-30"
setup_env a
SHARD_A="$ARC/signals-$DATE_A.jsonl.gz"
printf '' | gzip -c > "$SHARD_A"
# Self-check the fixture really is what the task claims (read-only, mirrors
# the measurement done against the real archive shards).
gzip -t "$SHARD_A" 2>/dev/null && FIXTURE_A_GZOK=1 || FIXTURE_A_GZOK=0
FIXTURE_A_LINES=$(gunzip -c "$SHARD_A" 2>/dev/null | wc -l | tr -d ' ')
check "fixture/a-is-valid-gzip" 1 "$FIXTURE_A_GZOK"
check "fixture/a-is-0-lines" 0 "$FIXTURE_A_LINES"

run_script "$TARGET" "$DATE_A" >/dev/null 2>&1; RC_A=$?
check "empty/exit0" 0 "$RC_A"
check "empty/row-appended" 1 "$([ -f "$MET" ] && grep -c "\"date\":\"$DATE_A\"" "$MET" || echo 0)"
ROW_A=$(grep "\"date\":\"$DATE_A\"" "$MET" 2>/dev/null)
check "empty/shard_state" "empty_verified" "$(printf '%s' "$ROW_A" | jq -r '.shard_state // "MISSING"')"
check "empty/tool_invocations-zero" 0 "$(printf '%s' "$ROW_A" | jq -r '.tool_invocations')"
check "empty/tool_invocations_by_name-empty" "{}" "$(printf '%s' "$ROW_A" | jq -c '.tool_invocations_by_name')"
check "empty/errors-zero" 0 "$(printf '%s' "$ROW_A" | jq -r '.errors')"
check "empty/hook_blocks-zero" 0 "$(printf '%s' "$ROW_A" | jq -r '.hook_blocks')"
check "empty/sessions-zero" 0 "$(printf '%s' "$ROW_A" | jq -r '.sessions')"
check "empty/provenance-note-present" 1 \
  "$(printf '%s' "$ROW_A" | jq -r '(._provenance.shard_state_note // "") | test("IMP-227") | if . then 1 else 0 end')"
check "empty/no-blocker-alert" 0 "$(alert_count "$ALERT")"

# ── Negative control: the SAME fixture through the pinned pre-fix baseline
#    must ABORT — proving case (a) actually exercises the fixed behavior and
#    is not a vacuous pass. ───────────────────────────────────────────────────
if [ "$HAVE_BASELINE" -eq 1 ]; then
  setup_env a_neg
  cp "$SHARD_A" "$ARC/signals-$DATE_A.jsonl.gz"
  run_script "$BASELINE_SCRIPT" "$DATE_A" >/dev/null 2>&1; RC_A_NEG=$?
  check "negctrl/baseline-aborts-on-empty-shard" 1 "$RC_A_NEG"
  check "negctrl/baseline-writes-no-row" 0 "$(row_count "$MET" "$DATE_A")"
  check "negctrl/baseline-writes-blocker-alert" 1 "$(alert_count "$ALERT")"
else
  SKIP=$((SKIP+3)); echo "  [skipped] negative control: baseline not available"
fi

# ═══════════════════════════════════════════════════════════════════════════
# (b) Missing shard (neither .jsonl.gz nor .jsonl exists) → abort, exit 1,
#     blocker alert written, no row appended. Unchanged behavior.
# ═══════════════════════════════════════════════════════════════════════════
DATE_B="2026-09-03"
setup_env b
run_script "$TARGET" "$DATE_B" >/dev/null 2>&1; RC_B=$?
check "missing/exit1" 1 "$RC_B"
check "missing/no-row-appended" 0 "$([ -f "$MET" ] && grep -c "\"date\":\"$DATE_B\"" "$MET" || echo 0)"
check "missing/blocker-alert-written" 1 "$(alert_count "$ALERT")"
check "missing/alert-mentions-shard" 1 \
  "$([ -f "$ALERT" ] && grep -c "no archive shard" "$ALERT" || echo 0)"

# ═══════════════════════════════════════════════════════════════════════════
# (c) Corrupt shard (not valid gzip) → abort, exit 1, blocker alert written,
#     no row appended. New: explicit `gzip -t` check catches this before any
#     decompression is attempted.
# ═══════════════════════════════════════════════════════════════════════════
DATE_C="2026-09-04"
setup_env c
SHARD_C="$ARC/signals-$DATE_C.jsonl.gz"
printf 'this is not a gzip file\n' > "$SHARD_C"
gzip -t "$SHARD_C" 2>/dev/null && FIXTURE_C_GZOK=1 || FIXTURE_C_GZOK=0
check "fixture/c-is-invalid-gzip" 0 "$FIXTURE_C_GZOK"

run_script "$TARGET" "$DATE_C" >/dev/null 2>&1; RC_C=$?
check "corrupt/exit1" 1 "$RC_C"
check "corrupt/no-row-appended" 0 "$([ -f "$MET" ] && grep -c "\"date\":\"$DATE_C\"" "$MET" || echo 0)"
check "corrupt/blocker-alert-written" 1 "$(alert_count "$ALERT")"
check "corrupt/alert-mentions-corrupt" 1 \
  "$([ -f "$ALERT" ] && grep -c "corrupt" "$ALERT" || echo 0)"

# ═══════════════════════════════════════════════════════════════════════════
# (d) Normal, non-empty, all-valid-JSON shard → row is UNCHANGED vs. what the
#     pinned pre-fix baseline script produces for the identical fixture (aside from the
#     `ts` field, which legitimately differs run-to-run — stripped before
#     comparison). Proves the fix does not touch the pre-existing contract.
# ═══════════════════════════════════════════════════════════════════════════
DATE_D="2026-09-05"
setup_env d
SHARD_D="$ARC/signals-$DATE_D.jsonl.gz"
{
  printf '{"ts":"%s","tool":"Edit","session_id":"s1"}\n' "${DATE_D}T10:00:00Z"
  printf '{"ts":"%s","tool":"Write","session_id":"s1","error":"read-before-edit-block"}\n' "${DATE_D}T10:05:00Z"
  printf '{"ts":"%s","tool":"Edit","session_id":"s2"}\n' "${DATE_D}T11:00:00Z"
} | gzip -c > "$SHARD_D"

run_script "$TARGET" "$DATE_D" >/dev/null 2>&1; RC_D=$?
check "normal/exit0" 0 "$RC_D"
ROW_D_NEW=$(grep "\"date\":\"$DATE_D\"" "$MET" 2>/dev/null)
check "normal/row-appended" 1 "$([ -n "$ROW_D_NEW" ] && echo 1 || echo 0)"
check "normal/no-shard_state-field" "MISSING" "$(printf '%s' "$ROW_D_NEW" | jq -r '.shard_state // "MISSING"')"
check "normal/tool_invocations" 3 "$(printf '%s' "$ROW_D_NEW" | jq -r '.tool_invocations')"
check "normal/errors" 1 "$(printf '%s' "$ROW_D_NEW" | jq -r '.errors')"
check "normal/sessions" 2 "$(printf '%s' "$ROW_D_NEW" | jq -r '.sessions')"
check "normal/no-blocker-alert" 0 "$(alert_count "$ALERT")"

if [ "$HAVE_BASELINE" -eq 1 ]; then
  setup_env d_base
  cp "$SHARD_D" "$ARC/signals-$DATE_D.jsonl.gz"
  run_script "$BASELINE_SCRIPT" "$DATE_D" >/dev/null 2>&1; RC_D_BASE=$?
  check "normal/baseline-also-exit0" 0 "$RC_D_BASE"
  ROW_D_BASE=$(grep "\"date\":\"$DATE_D\"" "$MET" 2>/dev/null)
  check "normal/baseline-row-present" 1 "$([ -n "$ROW_D_BASE" ] && echo 1 || echo 0)"
  NEW_NORMALIZED=$(printf '%s' "$ROW_D_NEW"  | jq -cS 'del(.ts)')
  OLD_NORMALIZED=$(printf '%s' "$ROW_D_BASE" | jq -cS 'del(.ts)')
  check "normal/unchanged-vs-baseline" "$OLD_NORMALIZED" "$NEW_NORMALIZED"
else
  SKIP=$((SKIP+3)); echo "  [skipped] case (d) baseline comparison: baseline not available"
fi

# ═══════════════════════════════════════════════════════════════════════════
# (f) 0-byte PLAIN shard (e.g. rotation interrupted after `>>` created the
#     file) → NOT empty_verified: only a gzip shard can prove a zero-activity
#     day. Abort, exit 1, blocker alert naming the reason, no row.
# ═══════════════════════════════════════════════════════════════════════════
DATE_F="2026-09-06"
setup_env f
: > "$ARC/signals-$DATE_F.jsonl"
check "fixture/f-is-0-bytes" 0 "$(wc -c < "$ARC/signals-$DATE_F.jsonl" | tr -d ' ')"
run_script "$TARGET" "$DATE_F" >/dev/null 2>&1; RC_F=$?
check "plain-empty/exit1" 1 "$RC_F"
check "plain-empty/no-row-appended" 0 "$(row_count "$MET" "$DATE_F")"
check "plain-empty/blocker-alert-written" 1 "$(alert_count "$ALERT")"
check "plain-empty/alert-names-plain-0-bytes" 1 \
  "$([ -f "$ALERT" ] && grep -c "plain shard is 0 bytes" "$ALERT" || echo 0)"

# ═══════════════════════════════════════════════════════════════════════════
# (g) gz shard with ONE JSON record and NO trailing newline → counted as 1
#     line (wc -l would say 0), a normal row, NOT empty_verified.
# ═══════════════════════════════════════════════════════════════════════════
DATE_G="2026-09-07"
setup_env g
printf '{"ts":"%s","tool":"Edit","session_id":"s1"}' "${DATE_G}T09:00:00Z" \
  | gzip -c > "$ARC/signals-$DATE_G.jsonl.gz"
check "fixture/g-wc-l-is-0" 0 "$(gunzip -c "$ARC/signals-$DATE_G.jsonl.gz" | wc -l | tr -d ' ')"
run_script "$TARGET" "$DATE_G" >/dev/null 2>&1; RC_G=$?
check "no-newline/exit0" 0 "$RC_G"
ROW_G=$(grep "\"date\":\"$DATE_G\"" "$MET" 2>/dev/null)
check "no-newline/no-shard_state-field" "MISSING" "$(printf '%s' "$ROW_G" | jq -r '.shard_state // "MISSING"')"
check "no-newline/tool_invocations-1" 1 "$(printf '%s' "$ROW_G" | jq -r '.tool_invocations')"
check "no-newline/sessions-1" 1 "$(printf '%s' "$ROW_G" | jq -r '.sessions')"
check "no-newline/no-blocker-alert" 0 "$(alert_count "$ALERT")"

# ═══════════════════════════════════════════════════════════════════════════
# (h) gz shard whose decompressed content is only a newline → NOT empty (1
#     byte), not valid JSON either → abort as corrupt content, no row.
# ═══════════════════════════════════════════════════════════════════════════
DATE_H="2026-09-08"
setup_env h
printf '\n' | gzip -c > "$ARC/signals-$DATE_H.jsonl.gz"
run_script "$TARGET" "$DATE_H" >/dev/null 2>&1; RC_H=$?
check "blank-line/exit1" 1 "$RC_H"
check "blank-line/no-row-appended" 0 "$(row_count "$MET" "$DATE_H")"
check "blank-line/alert-non-JSON" 1 \
  "$([ -f "$ALERT" ] && grep -c "non-JSON" "$ALERT" || echo 0)"

# ═══════════════════════════════════════════════════════════════════════════
# (e) Idempotency: a second run for an already-recorded empty_verified date
#     does not append a duplicate row (unchanged idempotency contract).
#     NOTE: setup_env for DATE_A's env (label "a") was overwritten by the
#     negative-control and case-(d) blocks above — re-point ARC/MET/ALERT/DISP
#     at the original case-(a) paths before re-running.
# ═══════════════════════════════════════════════════════════════════════════
ARC="$ROOT/archive-a"; MET="$ROOT/metrics-a.jsonl"; ALERT="$ROOT/alerts-a.jsonl"; DISP="$ROOT/dispatch-a.jsonl"
run_script "$TARGET" "$DATE_A" >/dev/null 2>&1; RC_A2=$?
check "idempotent/exit0" 0 "$RC_A2"
check "idempotent/still-exactly-one-row" 1 "$(grep -c "\"date\":\"$DATE_A\"" "$MET" 2>/dev/null || echo 0)"

rm -rf "$ROOT"

printf '── compute-daily-metrics-regression: %d passed, %d failed, %d skipped ──\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
