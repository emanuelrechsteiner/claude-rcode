#!/bin/bash
# routine-liveness-regression.sh — regression suite for
# hooks/routine-liveness-check.sh (IMP-191, 2026-09-09).
#
# Anlass: 39 status:"error" Zeilen in den drei Routine-Logs (daily-docs 18,
# nightly-observation 18, weekly-improve 3; 2026-08-23..09-09) hatten null
# Leser. Diese Suite prueft den neuen SessionStart-Hook AUSSCHLIESSLICH gegen
# ein Scratch-Verzeichnis (CLAUDE_ROUTINE_LOG_DIR) — sie liest/schreibt nie
# unter ~/.claude/global-observation/.
#
# Usage: bash hooks/tests/routine-liveness-regression.sh
# Exit: 0 = alle Faelle bestanden, 1 = mindestens einer fehlgeschlagen.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../routine-liveness-check.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     %s\n' "$1" "$2"; }

epoch_hours_ago() { date -u -v-"$1"H +%s; }
epoch_days_ago()  { date -u -v-"$1"d +%s; }

# fresh_dir -> creates + prints a scratch CLAUDE_ROUTINE_LOG_DIR
fresh_dir() { mktemp -d "${TMPDIR:-/tmp}/routine-liveness.XXXXXX"; }

run_hook() {  # run_hook <log_dir>
    CLAUDE_ROUTINE_LOG_DIR="$1" bash "$HOOK" </dev/null 2>&1
}

echo "── routine-liveness-check.sh regression (IMP-191) ──"

# ── Case 1: healthy — all three logs end in a fresh "ok". No output at all. ──
DIR1=$(fresh_dir)
printf '{"ts":%s,"status":"ok"}\n' "$(epoch_hours_ago 1)" > "$DIR1/daily-docs-log.jsonl"
printf '{"ts":%s,"status":"ok"}\n' "$(epoch_hours_ago 1)" > "$DIR1/nightly-obs-log.jsonl"
printf '{"ts":%s,"status":"ok"}\n' "$(epoch_hours_ago 1)" > "$DIR1/weekly-improve-log.jsonl"
out=$(run_hook "$DIR1")
if [[ -z "$out" ]]; then
    ok "healthy logs (fresh ok): completely silent"
else
    bad "healthy logs (fresh ok): completely silent" "unexpected output:
$out"
fi
rm -rf "$DIR1"

# ── Case 2: exactly 1 trailing error (below the >=2 threshold) — silent. ──
DIR2=$(fresh_dir)
{
    printf '{"ts":%s,"status":"ok"}\n' "$(epoch_hours_ago 5)"
    printf '{"ts":%s,"status":"error","note":"runner: claude exited 1 for daily-docs"}\n' "$(epoch_hours_ago 1)"
} > "$DIR2/daily-docs-log.jsonl"
out=$(run_hook "$DIR2")
if printf '%s' "$out" | grep -q "ROUTINE LIVENESS: 'daily-docs'.*consecutive"; then
    bad "1 trailing error stays below threshold (no alarm)" "unexpected alarm:
$out"
else
    ok "1 trailing error stays below threshold (no alarm)"
fi
rm -rf "$DIR2"

# ── Case 3: exactly 2 consecutive trailing errors -> alarm fires, names the
#    routine and the count. ──
DIR3=$(fresh_dir)
{
    printf '{"ts":%s,"status":"ok"}\n' "$(epoch_hours_ago 10)"
    printf '{"ts":%s,"status":"error","note":"runner: claude exited 1 for nightly-observation"}\n' "$(epoch_hours_ago 5)"
    printf '{"ts":%s,"status":"error","note":"runner: claude exited 1 for nightly-observation"}\n' "$(epoch_hours_ago 1)"
} > "$DIR3/nightly-obs-log.jsonl"
out=$(run_hook "$DIR3")
if printf '%s' "$out" | grep -q "ROUTINE LIVENESS: 'nightly-observation' — 2 consecutive failed runs"; then
    ok "2 consecutive trailing errors: alarm fires with count=2"
else
    bad "2 consecutive trailing errors: alarm fires with count=2" "no matching line in:
$out"
fi
if printf '%s' "$out" | grep -q "Erster Fehlzeitpunkt der Serie"; then
    ok "2 consecutive trailing errors: names the first-error timestamp of the series"
else
    bad "2 consecutive trailing errors: names the first-error timestamp" "no such phrase in:
$out"
fi
rm -rf "$DIR3"

# ── Case 4: 5 consecutive trailing errors -> count=5, reason text from the
#    most recent error is carried into the blocker line verbatim. ──
DIR4=$(fresh_dir)
{
    printf '{"ts":%s,"status":"ok"}\n' "$(epoch_days_ago 3)"
    for i in 5 4 3 2; do
        printf '{"ts":%s,"status":"error","note":"runner: claude exited 1 for daily-docs"}\n' "$(epoch_hours_ago "$i")"
    done
    printf '{"ts":%s,"status":"error","note":"runner: claude exited 42 for daily-docs"}\n' "$(epoch_hours_ago 1)"
} > "$DIR4/daily-docs-log.jsonl"
out=$(run_hook "$DIR4")
if printf '%s' "$out" | grep -q "ROUTINE LIVENESS: 'daily-docs' — 5 consecutive failed runs"; then
    ok "5 consecutive trailing errors: alarm fires with count=5"
else
    bad "5 consecutive trailing errors: alarm fires with count=5" "no matching line in:
$out"
fi
if printf '%s' "$out" | grep -q "runner: claude exited 42 for daily-docs"; then
    ok "5 consecutive trailing errors: carries the LATEST error's reason text"
else
    bad "5 consecutive trailing errors: carries the latest error's reason text" "reason text missing from:
$out"
fi
rm -rf "$DIR4"

# ── Case 5: log file missing entirely (fresh install) -> silent, no crash,
#    other routines still evaluated normally. ──
DIR5=$(fresh_dir)
printf '{"ts":%s,"status":"ok"}\n' "$(epoch_hours_ago 1)" > "$DIR5/nightly-obs-log.jsonl"
# daily-docs-log.jsonl and weekly-improve-log.jsonl intentionally absent.
out=$(run_hook "$DIR5")
if [[ -z "$out" ]]; then
    ok "missing log file(s): silent, no crash (fresh install)"
else
    bad "missing log file(s): silent, no crash" "unexpected output:
$out"
fi
rm -rf "$DIR5"

# ── Case 6: daily-cadence routine stale (last entry, status ok, >48h old) ->
#    staleness warning, NOT the consecutive-error alarm. ──
DIR6=$(fresh_dir)
printf '{"ts":%s,"status":"ok"}\n' "$(epoch_days_ago 5)" > "$DIR6/daily-docs-log.jsonl"
out=$(run_hook "$DIR6")
if printf '%s' "$out" | grep -q "hat seit .* Tag(en) gar nicht gefeuert" && printf '%s' "$out" | grep -q "48h"; then
    ok "daily-cadence routine stale (5d, status ok): staleness warning names 48h tolerance"
else
    bad "daily-cadence routine stale: staleness warning" "no matching line in:
$out"
fi
if printf '%s' "$out" | grep -q "consecutive failed runs"; then
    bad "stale-but-healthy routine does NOT also raise the error-streak alarm" "unexpected alarm in:
$out"
else
    ok "stale-but-healthy routine does NOT also raise the error-streak alarm"
fi
rm -rf "$DIR6"

# ── Case 7: weekly-improve stale at 10 days (> 8-day tolerance) -> fires. ──
DIR7=$(fresh_dir)
printf '{"ts":%s,"status":"ok"}\n' "$(epoch_days_ago 10)" > "$DIR7/weekly-improve-log.jsonl"
out=$(run_hook "$DIR7")
if printf '%s' "$out" | grep -q "'weekly-improve' hat seit .* Tag(en) gar nicht gefeuert" && printf '%s' "$out" | grep -q "8 Tage"; then
    ok "weekly-improve stale at 10 days: staleness warning fires (8-day tolerance)"
else
    bad "weekly-improve stale at 10 days: staleness warning fires" "no matching line in:
$out"
fi
rm -rf "$DIR7"

# ── Case 8: weekly-improve at 5 days (WITHIN the 8-day tolerance) -> must
#    NOT fire — guards against a daily-cadence threshold leaking onto the
#    weekly routine. ──
DIR8=$(fresh_dir)
printf '{"ts":%s,"status":"ok"}\n' "$(epoch_days_ago 5)" > "$DIR8/weekly-improve-log.jsonl"
out=$(run_hook "$DIR8")
if printf '%s' "$out" | grep -q "gar nicht gefeuert"; then
    bad "weekly-improve at 5 days (within tolerance): stays silent" "unexpected staleness warning:
$out"
else
    ok "weekly-improve at 5 days (within tolerance): stays silent"
fi
rm -rf "$DIR8"

# ── Case 9: mixed ts SHAPES within one file (epoch int AND ISO8601 string) —
#    exactly the real-world weekly-improve-log.jsonl pattern observed
#    2026-09-09 (ok-entries in ISO form, error-entries in epoch form). The
#    consecutive-error count must still be correct across the format mix. ──
DIR9=$(fresh_dir)
{
    printf '{"ts":"%s","task":"weekly-improve","status":"ok","findings":4}\n' "$(date -u -v-30d +"%Y-%m-%dT%H:%M:%SZ")"
    printf '{"ts":"%s","task":"weekly-improve","status":"ok","findings":6}\n' "$(date -u -v-20d +"%Y-%m-%dT%H:%M:%SZ")"
    printf '{"ts":%s,"status":"error","note":"runner: claude exited 1 for weekly-improve"}\n' "$(epoch_days_ago 10)"
    printf '{"ts":%s,"status":"error","note":"runner: claude exited 1 for weekly-improve"}\n' "$(epoch_days_ago 3)"
    printf '{"ts":%s,"status":"error","note":"runner: claude exited 1 for weekly-improve"}\n' "$(epoch_hours_ago 1)"
} > "$DIR9/weekly-improve-log.jsonl"
out=$(run_hook "$DIR9")
if printf '%s' "$out" | grep -q "ROUTINE LIVENESS: 'weekly-improve' — 3 consecutive failed runs"; then
    ok "mixed ts shapes (epoch + ISO8601) in one file: streak still counted correctly (3)"
else
    bad "mixed ts shapes in one file: streak counted correctly" "no matching line in:
$out"
fi
rm -rf "$DIR9"

# ── Case 10: unparseable/garbage line in the log must not crash the hook
#    and must not itself count as an error in the streak. ──
DIR10=$(fresh_dir)
{
    echo 'not even json'
    printf '{"ts":%s,"status":"error","note":"runner: claude exited 1 for daily-docs"}\n' "$(epoch_hours_ago 5)"
    printf '{"ts":%s,"status":"error","note":"runner: claude exited 1 for daily-docs"}\n' "$(epoch_hours_ago 1)"
} > "$DIR10/daily-docs-log.jsonl"
out=$(run_hook "$DIR10")
RC=$?
if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q "ROUTINE LIVENESS: 'daily-docs' — 2 consecutive failed runs"; then
    ok "garbage line in log: hook survives, still counts the real streak correctly"
else
    bad "garbage line in log: hook survives, still counts correctly" "rc=$RC out:
$out"
fi
rm -rf "$DIR10"

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
