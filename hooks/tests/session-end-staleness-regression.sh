#!/bin/bash
# session-end-staleness-regression.sh — regression suite for the IMP-138 fix
# to the OBSERVATION LOOP STALLED escalation in hooks/session-end-check.sh.
#
# Anlass (IMP-138): the alarm gated on `DAYS_STALE >= 7 && BACKLOG_SHARDS >= 3`.
# BACKLOG_SHARDS is produced by the SAME nightly routine whose death the alarm
# is meant to catch — if that routine dies early, the shard count freezes (often
# at 0 or low) and the AND-gate silently never fires again. Real incident: 20
# days of silence. Fix: DAYS_STALE >= 7 alone is now sufficient; BACKLOG_SHARDS
# is demoted to an enrichment field, and a "newest shard is N days old" line
# names the frozen producer instead of leaving the reader to guess.
#
# Runs entirely inside an isolated fake $HOME + a scratch git repo — never
# touches the real ~/.claude/global-observation. Per the Bauhof/Haus split,
# this suite always tests the WORKING COPY at hooks/session-end-check.sh in
# this repo, not the installed ~/.claude copy (override with CLAUDE_HOOK).
#
# Usage: bash hooks/tests/session-end-staleness-regression.sh
# Exit: 0 = all cases pass, 1 = at least one failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../session-end-check.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     %s\n' "$1" "$2"; }

# days-ago → ISO8601 UTC timestamp string, matching the watermark format the
# hook parses ("%Y-%m-%dT%H:%M:%SZ").
iso_days_ago() { date -u -v-"$1"d +"%Y-%m-%dT%H:%M:%SZ"; }

# Set a file's mtime to N days in the past (BSD touch -t, macOS).
touch_days_ago() {
    local f="$1" days="$2"
    local stamp
    stamp=$(date -v-"${days}"d +"%Y%m%d%H%M.%S")
    touch -t "$stamp" "$f"
}

# Runs the hook inside a fresh fake HOME + scratch git repo. Sets up
# $OBS_DIR/.last-run-ts per $1 (days-ago watermark, or "" to skip). $2 is a
# space-separated list of "shard-age-in-days" values to create in archives/
# ("" = no archives dir at all). Prints the hook's stdout.
run_case() {
    local watermark_days="$1" shard_ages="$2"
    local FAKE_HOME
    FAKE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/session-end-staleness.XXXXXX")
    local OBS_DIR="$FAKE_HOME/.claude/global-observation"
    mkdir -p "$OBS_DIR"

    if [[ -n "$watermark_days" ]]; then
        iso_days_ago "$watermark_days" > "$OBS_DIR/.last-run-ts"
        # The hook's BACKLOG_SHARDS uses `find -newer $WATERMARK`, which compares
        # against the watermark FILE's mtime, not the ISO date parsed from its
        # contents. In production those coincide (the watermark is written at the
        # moment /meta-observe finishes). Match that here, or -newer comparisons
        # in this harness would silently compare against "just now".
        touch_days_ago "$OBS_DIR/.last-run-ts" "$watermark_days"
    fi

    if [[ -n "$shard_ages" ]]; then
        mkdir -p "$OBS_DIR/archives"
        local i=0
        for age in $shard_ages; do
            i=$((i+1))
            local shard="$OBS_DIR/archives/signals-case-${i}.jsonl.gz"
            : > "$shard"
            touch_days_ago "$shard" "$age"
        done
    fi

    # Scratch git repo — the hook exits 0 silently outside one.
    local REPO="$FAKE_HOME/repo"
    mkdir -p "$REPO"
    (cd "$REPO" && git init -q && git config user.email t@t.test && git config user.name t)

    local out
    out=$(cd "$REPO" && HOME="$FAKE_HOME" bash "$HOOK" </dev/null 2>&1)
    printf '%s' "$out"
    rm -rf "$FAKE_HOME"
}

echo "── session-end-check.sh staleness-escalation regression (IMP-138) ──"

# ── Case 1: fresh — watermark is now, no archives. No alarm expected. ──
out=$(run_case 0 "")
if printf '%s' "$out" | grep -q "OBSERVATION LOOP STALLED"; then
    bad "fresh run (0 days stale) does not alarm" "STALLED line present:
$out"
else
    ok "fresh run (0 days stale) does not alarm"
fi

# ── Case 2: 26 days stale + frozen shards (existing shards, none new since
#    the watermark) — the pre-fix code's own worked example of a real stall.
#    Alarm MUST fire, and the newest-shard-age line must be present.
out=$(run_case 26 "20 22")
if printf '%s' "$out" | grep -q "OBSERVATION LOOP STALLED"; then
    ok "26 days stale + frozen shards: alarm fires"
else
    bad "26 days stale + frozen shards: alarm fires" "no STALLED line in:
$out"
fi
if printf '%s' "$out" | grep -qE "newest shard is 20 day"; then
    ok "26 days stale + frozen shards: names the newest-shard age (20d)"
else
    bad "26 days stale + frozen shards: names the newest-shard age (20d)" "no 'newest shard is 20 day' line in:
$out"
fi

# ── Case 3: 8 days stale + 0 shards — the case that was PREVIOUSLY DEAD.
#    Old gate: DAYS_STALE>=7(8✓) && BACKLOG_SHARDS>=3(0✗) → never fired.
#    New gate: DAYS_STALE>=7 alone → must fire.
out=$(run_case 8 "")
if printf '%s' "$out" | grep -q "OBSERVATION LOOP STALLED"; then
    ok "8 days stale + 0 shards: alarm fires (was the dead case pre-IMP-138)"
else
    bad "8 days stale + 0 shards: alarm fires (was the dead case pre-IMP-138)" "no STALLED line in:
$out"
fi
if printf '%s' "$out" | grep -q "no shards found in"; then
    ok "8 days stale + 0 shards: reports 'no shards found' (fail-loud, not silent 0)"
else
    bad "8 days stale + 0 shards: reports 'no shards found'" "no such line in:
$out"
fi

# ── Case 4: 6 days stale (below threshold) — must NOT alarm, guards against
#    an accidental off-by-one from the >= 7 boundary.
out=$(run_case 6 "")
if printf '%s' "$out" | grep -q "OBSERVATION LOOP STALLED"; then
    bad "6 days stale (below threshold) does not alarm" "STALLED line present:
$out"
else
    ok "6 days stale (below threshold) does not alarm"
fi

# ── Case 5: 10 days stale + a healthy backlog (5 shards, all recent) —
#    the alarm still fires (as before) AND the enrichment line still reports
#    the correct backlog count, i.e. BACKLOG_SHARDS is demoted, not removed.
out=$(run_case 10 "1 2 3 4 5")
if printf '%s' "$out" | grep -q "OBSERVATION LOOP STALLED"; then
    ok "10 days stale + healthy backlog: alarm fires"
else
    bad "10 days stale + healthy backlog: alarm fires" "no STALLED line in:
$out"
fi
if printf '%s' "$out" | grep -qE "5 unprocessed daily signal shards"; then
    ok "10 days stale + healthy backlog: BACKLOG_SHARDS count still reported (5)"
else
    bad "10 days stale + healthy backlog: BACKLOG_SHARDS count still reported (5)" "no '5 unprocessed' line in:
$out"
fi

echo ""
echo "── session-end-check.sh alarm-repetition escalation (IMP-164) ──"

# Shared FAKE_HOME across MULTIPLE hook invocations, simulating consecutive
# session-ends where the SAME underlying condition (observation loop stale)
# keeps firing. The repeat-counter state persists at
# $FAKE_HOME/.claude/global-observation/.alarm-repeat-obs-loop-stalled.txt
# specifically because — unlike the Case 1-5 helper above — this FAKE_HOME is
# reused across calls instead of created fresh per case.
FAKE_HOME_R=$(mktemp -d "${TMPDIR:-/tmp}/session-end-repeat.XXXXXX")
OBS_DIR_R="$FAKE_HOME_R/.claude/global-observation"
mkdir -p "$OBS_DIR_R"
REPO_R="$FAKE_HOME_R/repo"
mkdir -p "$REPO_R"
(cd "$REPO_R" && git init -q && git config user.email t@t.test && git config user.name t)

run_repeat_case() {  # $1 = watermark_days_ago ("" = delete watermark / resolved)
    local wd="$1"
    if [[ -z "$wd" ]]; then
        rm -f "$OBS_DIR_R/.last-run-ts"
    else
        iso_days_ago "$wd" > "$OBS_DIR_R/.last-run-ts"
        touch_days_ago "$OBS_DIR_R/.last-run-ts" "$wd"
    fi
    (cd "$REPO_R" && HOME="$FAKE_HOME_R" bash "$HOOK" </dev/null 2>&1)
}

# ── Run 1: 8 days stale (1st occurrence) — plain Hinweis, no ESKALATION form. ──
out=$(run_repeat_case 8)
if printf '%s' "$out" | grep -q "OBSERVATION LOOP STALLED" && ! printf '%s' "$out" | grep -q "ESKALATION"; then
    ok "1st occurrence: informational form, no escalation"
else
    bad "1st occurrence: informational form, no escalation" "$out"
fi

# ── Run 2: still stale (9d) — 2nd consecutive occurrence, still informational. ──
out=$(run_repeat_case 9)
if printf '%s' "$out" | grep -q "OBSERVATION LOOP STALLED" && ! printf '%s' "$out" | grep -q "ESKALATION"; then
    ok "2nd consecutive occurrence: still informational (escalation starts at 3rd)"
else
    bad "2nd consecutive occurrence: still informational" "$out"
fi

# ── Run 3: still stale (10d) — 3rd consecutive occurrence -> ESCALATION form. ──
out=$(run_repeat_case 10)
if printf '%s' "$out" | grep -q "ESKALATION"; then
    ok "3rd consecutive (identical-class) occurrence: escalates form"
else
    bad "3rd consecutive occurrence: escalates form" "$out"
fi

# ── Run 4: still stale (11d) — 4th: escalation persists, no ledger hint yet. ──
out=$(run_repeat_case 11)
if printf '%s' "$out" | grep -q "ESKALATION" && ! printf '%s' "$out" | grep -qi "Ledger-Eintrag"; then
    ok "4th consecutive occurrence: escalation without ledger hint yet"
else
    bad "4th consecutive occurrence: escalation without ledger hint yet" "$out"
fi

# ── Run 5: still stale (12d) — 5th: escalation + ledger-entry-due hint. ──
out=$(run_repeat_case 12)
if printf '%s' "$out" | grep -q "ESKALATION" && printf '%s' "$out" | grep -qi "Ledger-Eintrag"; then
    ok "5th consecutive occurrence: escalation + ledger-entry-due hint"
else
    bad "5th consecutive occurrence: escalation + ledger-entry-due hint" "$out"
fi

# ── Run 6: condition resolved (watermark removed -> no alarm) -> resets. ──
out=$(run_repeat_case "")
if ! printf '%s' "$out" | grep -q "OBSERVATION LOOP STALLED"; then
    ok "resolved run: no alarm at all"
else
    bad "resolved run: no alarm at all" "$out"
fi

# ── Run 7: stale again (8d) — counter must have reset: informational again,
#    NOT escalation. This is the "changed message resets the counter" case. ──
out=$(run_repeat_case 8)
if printf '%s' "$out" | grep -q "OBSERVATION LOOP STALLED" && ! printf '%s' "$out" | grep -q "ESKALATION"; then
    ok "re-occurrence after resolution: counter reset, informational again"
else
    bad "re-occurrence after resolution: counter reset, informational again" "$out"
fi

rm -rf "$FAKE_HOME_R"

echo ""
echo "── session-end-check.sh IMP-192: cause-coupling + ledger write-back ──"

# Fresh FAKE_HOME/OBS_DIR for this block, independent of the repeat block
# above (a clean alarm-repeat counter is needed to drive REPEAT_N precisely
# from 1 to 6). Uses the REAL scripts/ledger-append-proposed.sh from THIS
# repo (Bauhof) — redirected to a SCRATCH ledger via CLAUDE_LEDGER_FILE, so
# this suite never touches the real ~/.claude/global-observation/
# improvement-ledger.json, per the "no real logs/ledger" constraint.
FAKE_HOME_C=$(mktemp -d "${TMPDIR:-/tmp}/session-end-imp192.XXXXXX")
OBS_DIR_C="$FAKE_HOME_C/.claude/global-observation"
mkdir -p "$OBS_DIR_C"
REPO_C="$FAKE_HOME_C/repo"
mkdir -p "$REPO_C"
(cd "$REPO_C" && git init -q && git config user.email t@t.test && git config user.name t)

LEDGER_SCRIPT="$SCRIPT_DIR/../../scripts/ledger-append-proposed.sh"
[[ -f "$LEDGER_SCRIPT" ]] || { echo "ERROR: ledger-append-proposed.sh not found: $LEDGER_SCRIPT" >&2; exit 1; }
SCRATCH_LEDGER="$FAKE_HOME_C/scratch-ledger.json"
echo '{}' > "$SCRATCH_LEDGER"

run_case_c() {  # $1 = watermark_days_ago, $2 = nightly-obs-log last status ("" = no file this call)
    local wd="$1" nightly_status="$2"
    iso_days_ago "$wd" > "$OBS_DIR_C/.last-run-ts"
    touch_days_ago "$OBS_DIR_C/.last-run-ts" "$wd"
    if [[ -n "$nightly_status" ]]; then
        printf '{"ts":%s,"status":"%s","note":"runner: claude exited 1 for nightly-observation"}\n' \
            "$(date -u -v-1H +%s)" "$nightly_status" > "$OBS_DIR_C/nightly-obs-log.jsonl"
    fi
    (cd "$REPO_C" && HOME="$FAKE_HOME_C" CLAUDE_LEDGER_FILE="$SCRATCH_LEDGER" \
        CLAUDE_LEDGER_APPEND_SCRIPT="$LEDGER_SCRIPT" bash "$HOOK" </dev/null 2>&1)
}

# ── C1 (1st occurrence, 8d stale): nightly-obs-log's own last run is
#    status:"error" -> the alarm must name that as the CAUSE, not just
#    repeat the DAYS_STALE/BACKLOG_SHARDS symptom. ──
out=$(run_case_c 8 "error")
if printf '%s' "$out" | grep -q "Ursache statt nur Symptom" && printf '%s' "$out" | grep -q "nightly-observation-Lauf selbst endete mit status:\"error\""; then
    ok "IMP-192 coupling: nightly-obs-log error is named as the likely cause"
else
    bad "IMP-192 coupling: nightly-obs-log error is named as the likely cause" "$out"
fi
if printf '%s' "$out" | grep -q "runner: claude exited 1 for nightly-observation"; then
    ok "IMP-192 coupling: the routine's own error reason text is carried into the line"
else
    bad "IMP-192 coupling: the routine's own error reason text is carried into the line" "$out"
fi

# ── C2..C4: drive REPEAT_N to 4 (2nd..4th occurrence) — no ledger write yet. ──
out=$(run_case_c 9 "ok")
out=$(run_case_c 10 "ok")
out=$(run_case_c 11 "ok")
if printf '%s' "$out" | grep -q "Ledger-Eintrag geschrieben"; then
    bad "IMP-192 ledger: no write before the 5th occurrence" "unexpected write at 4th occurrence:
$out"
else
    ok "IMP-192 ledger: no write before the 5th occurrence"
fi

# ── C5 (5th occurrence): the ledger write fires EXACTLY here — status
#    "proposed" entry actually lands in the scratch ledger. ──
out=$(run_case_c 12 "ok")
if printf '%s' "$out" | grep -q "Ledger-Eintrag geschrieben"; then
    ok "IMP-192 ledger: write fires at the 5th consecutive occurrence"
else
    bad "IMP-192 ledger: write fires at the 5th consecutive occurrence" "$out"
fi
PROPOSED_COUNT_AFTER_5=$(jq '[.. | objects | select(.status? == "proposed")] | length' "$SCRATCH_LEDGER" 2>/dev/null)
if [[ "$PROPOSED_COUNT_AFTER_5" == "1" ]]; then
    ok "IMP-192 ledger: scratch ledger now holds exactly 1 status:proposed entry"
else
    bad "IMP-192 ledger: scratch ledger now holds exactly 1 status:proposed entry" "count=$PROPOSED_COUNT_AFTER_5"
fi

# ── C6 (6th occurrence): must NOT write a second entry — the month-keyed
#    marker file must suppress re-invocation entirely. ──
out=$(run_case_c 13 "ok")
if printf '%s' "$out" | grep -q "Ledger-Eintrag geschrieben"; then
    bad "IMP-192 ledger: no second write at the 6th occurrence" "unexpected second write:
$out"
else
    ok "IMP-192 ledger: no second write at the 6th occurrence"
fi
PROPOSED_COUNT_AFTER_6=$(jq '[.. | objects | select(.status? == "proposed")] | length' "$SCRATCH_LEDGER" 2>/dev/null)
if [[ "$PROPOSED_COUNT_AFTER_6" == "1" ]]; then
    ok "IMP-192 ledger: scratch ledger still holds exactly 1 entry after the 6th occurrence (no duplicate)"
else
    bad "IMP-192 ledger: scratch ledger still holds exactly 1 entry after the 6th occurrence" "count=$PROPOSED_COUNT_AFTER_6"
fi

rm -rf "$FAKE_HOME_C"

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
