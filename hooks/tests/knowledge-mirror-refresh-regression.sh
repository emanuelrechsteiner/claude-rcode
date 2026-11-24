#!/bin/bash
# knowledge-mirror-refresh-regression.sh — regression suite for hooks/knowledge-mirror-refresh.sh (IMP-267)
# ─────────────────────────────────────────────────────────────────────────────
# Pins the SessionStart refresh decision on a FAKE library (the real mirror is
# never run; a stub stands in; fixtures in mktemp). Lock lives in eval/.
# BSD-only (date -j, touch -t): exits 2 loudly elsewhere.
# ─────────────────────────────────────────────────────────────────────────────
set -u

if ! date -u -j -f %s 0 +%s >/dev/null 2>&1; then
    printf 'FAIL: BSD date (date -j) required; this suite cannot run on this platform\n'
    exit 2
fi

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${CLAUDE_KMR_HOOK:-$HOOKS_DIR/knowledge-mirror-refresh.sh}"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/kmr-refresh-regression.XXXXXX")"
# shellcheck disable=SC2329  # invoked by the EXIT trap
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

export HOME="$SCRATCH/home"
mkdir -p "$HOME"
unset CLAUDE_KNOWLEDGE_DIR CLAUDE_KNOWLEDGE_REFRESH CLAUDE_KNOWLEDGE_REFRESH_HOURS KMR_STUB_RC

KDIR="$SCRATCH/lib"
LOCK="$KDIR/eval/mirror-refresh.lock"
EVAL_LOG="$KDIR/eval/mirror-refresh.log"
FAIL_FILE="$KDIR/eval/mirror-refresh.failures"
RLOG="$SCRATCH/global-observation/knowledge-refresh.log"
MARKER="$SCRATCH/stub-ran"
STUB="$SCRATCH/stub-mirror.sh"

# shellcheck disable=SC2016  # the stub body must keep $KMR_MARKER unexpanded
printf '#!/bin/bash\necho "$$" >> "$KMR_MARKER"\nsleep 1\nexit "${KMR_STUB_RC:-0}"\n' > "$STUB"
chmod +x "$STUB"

export CLAUDE_KNOWLEDGE_MIRROR="$STUB" KMR_MARKER="$MARKER"
export CLAUDE_KNOWLEDGE_REFRESH_LOG="$RLOG"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected: %s\n     got:      %s\n' "$1" "$2" "$3"; }
# ── helpers ──────────────────────────────────────────────────────────────
# wait_until <seconds> <command...> — poll until the command succeeds or the deadline passes.
wait_until() {
    local deadline=$(( $(date +%s) + $1 ))
    shift
    while (( $(date +%s) <= deadline )); do
        if "$@"; then return 0; fi
        sleep 0.1
    done
    return 1
}
# shellcheck disable=SC2329  # invoked indirectly through wait_until
lock_gone() { [[ ! -e "$LOCK" ]]; }
# shellcheck disable=SC2329  # invoked indirectly through wait_until
marker_present() { [[ -e "$MARKER" ]]; }
done_logged() { [[ -f "$EVAL_LOG" ]] && grep -q '^done rc=' "$EVAL_LOG"; }

# stamp_secs_ago <seconds> -> ISO8601 UTC stamp
stamp_secs_ago() { date -u -j -f %s "$(( $(date -u +%s) - $1 ))" +%Y-%m-%dT%H:%M:%SZ; }

# reset_case: wait out a detached run from the previous case, then wipe fixtures.
reset_case() {
    wait_until 5 lock_gone
    rm -rf "$KDIR" "$SCRATCH/global-observation" "$MARKER"
    mkdir -p "$KDIR/mirror" "$KDIR/eval"
    unset CLAUDE_KNOWLEDGE_REFRESH CLAUDE_KNOWLEDGE_REFRESH_HOURS
    export CLAUDE_KNOWLEDGE_DIR="$KDIR"
}

# write_readme <stamp-token> — README with the real stamp line shape.
write_readme() {
    printf '# Mirror\n\nscripts/knowledge-mirror.sh. Last run: %s (UTC).\n' "$1" > "$KDIR/mirror/README.md"
}

# run_hook <stdin-json> — sets HOOK_OUT, HOOK_RC, HOOK_SECS.
run_hook() {
    local t0 t1
    t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    HOOK_OUT=$(printf '%s' "$1" | bash "$HOOK" 2>"$SCRATCH/hook.err")
    HOOK_RC=$?
    t1=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    HOOK_SECS=$(perl -e 'printf "%.3f", $ARGV[1] - $ARGV[0]' "$t0" "$t1")
}

last_outcome() { if [[ -f "$RLOG" ]]; then tail -n 1 "$RLOG" | awk -F'\t' '{print $4}'; fi; }
last_field() { tail -n 1 "$RLOG" | cut -f"$1"; }
# ── Case 1: no KDIR -> silent ───────────────────────────────────────────────
echo "Case 1: no KDIR is silent"
reset_case
export CLAUDE_KNOWLEDGE_DIR=""
run_hook '{"session_id":"s1"}'
if [[ "$HOOK_RC" == 0 && -z "$HOOK_OUT" && ! -f "$RLOG" ]]; then ok "no KDIR: exit 0, silent, no log"; else bad "no KDIR silent" "rc 0, empty, no log" "rc $HOOK_RC out '$HOOK_OUT'"; fi
# ── Case 2: README missing -> silent ────────────────────────────────────────
echo "Case 2: missing README is silent"
reset_case
run_hook '{"session_id":"s2"}'
if [[ "$HOOK_RC" == 0 && -z "$HOOK_OUT" && ! -f "$RLOG" ]]; then ok "missing README: exit 0, silent, no log"; else bad "missing README silent" "rc 0, empty, no log" "rc $HOOK_RC out '$HOOK_OUT'"; fi
# ── Case 3: fresh stamp (1 h) -> silent, logged as fresh ────────────────────
echo "Case 3: fresh stamp is silent"
reset_case
write_readme "$(stamp_secs_ago 3600)"
run_hook '{"session_id":"s3"}'
if [[ "$HOOK_RC" == 0 && -z "$HOOK_OUT" && "$(last_outcome)" == fresh && ! -e "$MARKER" && ! -e "$LOCK" ]]; then
    ok "fresh (1 h): silent, outcome 'fresh', no run, no lock"
else
    bad "fresh" "silent, fresh, no run" "rc $HOOK_RC out '$HOOK_OUT' outcome $(last_outcome)"
fi
# ── Case 4: 23 h under default threshold (24 h) -> still fresh ──────────────
echo "Case 4: default 24 h threshold"
reset_case
write_readme "$(stamp_secs_ago $(( 23 * 3600 )))"
run_hook '{"session_id":"s4"}'
if [[ "$HOOK_RC" == 0 && -z "$HOOK_OUT" && "$(last_outcome)" == fresh ]]; then ok "23 h under default 24 h: fresh"; else bad "23 h fresh" "silent, fresh" "out '$HOOK_OUT' outcome $(last_outcome)"; fi
# ── Case 5: stale stamp (48 h) -> detached start, timed, lock under eval/ ───
echo "Case 5: stale stamp starts a detached rebuild"
reset_case
write_readme "$(stamp_secs_ago $(( 48 * 3600 )))"
run_hook '{"session_id":"sess-abc"}'
if [[ "$HOOK_RC" == 0 && -n "$HOOK_OUT" && "$HOOK_OUT" != *$'\n'* && "$HOOK_OUT" == *"was 48h old"* ]]; then
    ok "stale: exit 0, exactly one stdout line with the hours"
else
    bad "stale stdout" "rc 0, one line 'was 48h old'" "rc $HOOK_RC out '$HOOK_OUT'"
fi
if awk -v s="$HOOK_SECS" 'BEGIN { exit !(s < 1.0) }'; then ok "stale: hook returned in ${HOOK_SECS}s (< 1 s)"; else bad "stale timing" "< 1.0 s" "${HOOK_SECS} s"; fi
if [[ -e "$LOCK" && ! -e "$KDIR/mirror/.refresh.lock" ]]; then
    ok "stale: lock under eval/ while in flight; no lock under mirror/"
else
    bad "stale lock path" "lock in eval/, none in mirror/" "eval: $(find "$KDIR/eval" "$KDIR/mirror" -maxdepth 1 -name '*lock*' | tr '\n' ' ')"
fi
if wait_until 3 marker_present; then ok "stale: stub marker appeared within 3 s"; else bad "stale marker" "marker within 3 s" "no marker"; fi
if wait_until 5 lock_gone && done_logged && grep -q '^done rc=0 ' "$EVAL_LOG"; then
    ok "stale: lock released after the stub; eval log ends 'done rc=0'"
else
    bad "stale done" "lock gone, done rc=0" "eval: $(tail -n 1 "$EVAL_LOG" 2>/dev/null)"
fi
if [[ "$(last_outcome)" == started && "$(last_field 2)" == sess-abc && "$(last_field 3)" == 48 ]]; then
    ok "stale: log 'started' with session_id and age_h 48"
else
    bad "stale log" "sess-abc / 48 / started" "$(tail -n 1 "$RLOG")"
fi
# ── Case 6: stale + young lock -> no start ──────────────────────────────────
echo "Case 6: young lock blocks the start"
reset_case
write_readme "$(stamp_secs_ago $(( 48 * 3600 )))"
: > "$LOCK"
run_hook '{"session_id":"s6"}'
sleep 1.2
if [[ "$HOOK_RC" == 0 && -z "$HOOK_OUT" && "$(last_outcome)" == skipped-lock && ! -e "$MARKER" && -e "$LOCK" ]]; then
    ok "young lock: silent, outcome 'skipped-lock', no run, lock kept"
else
    bad "young lock" "silent, skipped-lock, no run, lock kept" "out '$HOOK_OUT' outcome $(last_outcome)"
fi
# ── Case 7: stale + lock older than 30 min -> stale lock removed, start ─────
echo "Case 7: lock older than 30 min is stale"
reset_case
write_readme "$(stamp_secs_ago $(( 48 * 3600 )))"
: > "$LOCK"
touch -t "$(date -j -f %s "$(( $(date -u +%s) - 2400 ))" +%Y%m%d%H%M)" "$LOCK"
run_hook '{"session_id":"s7"}'
if [[ "$HOOK_RC" == 0 && "$HOOK_OUT" == *"rebuild started"* ]] && wait_until 3 marker_present && wait_until 5 lock_gone && [[ "$(last_outcome)" == started ]]; then
    ok "old lock: removed, run started, released, outcome 'started'"
else
    bad "old lock" "started, marker, lock released" "out '$HOOK_OUT' outcome $(last_outcome)"
fi
# ── Case 8: unparsable stamp -> treated as stale ────────────────────────────
echo "Case 8: unparsable stamp is stale"
reset_case
write_readme "sometime"
run_hook '{"session_id":"s8"}'
if [[ "$HOOK_RC" == 0 && "$HOOK_OUT" == *"unknown age"* && "$HOOK_OUT" == *"last run sometime"* ]] \
    && wait_until 3 marker_present && wait_until 5 lock_gone \
    && [[ "$(last_field 3)" == "?" && "$(last_outcome)" == started ]]; then
    ok "unparsable: stale, 'unknown age' line, log age '?', run released"
else
    bad "unparsable" "unknown-age line, ?, started" "out '$HOOK_OUT' log $(tail -n 1 "$RLOG" 2>/dev/null)"
fi
# ── Case 9: README without a stamp line -> stale ────────────────────────────
echo "Case 9: README without a stamp is stale"
reset_case
printf '# Mirror\n\nno stamp here\n' > "$KDIR/mirror/README.md"
run_hook '{"session_id":"s9"}'
if [[ "$HOOK_RC" == 0 && "$HOOK_OUT" == *"last run missing"* ]]; then ok "no stamp: stale, message says missing"; else bad "no stamp" "missing-stamp line" "out '$HOOK_OUT'"; fi
wait_until 5 lock_gone
# ── Case 10: opt-out -> silent even when stale ──────────────────────────────
echo "Case 10: opt-out"
reset_case
write_readme "$(stamp_secs_ago $(( 48 * 3600 )))"
export CLAUDE_KNOWLEDGE_REFRESH=0
run_hook '{"session_id":"s10"}'
unset CLAUDE_KNOWLEDGE_REFRESH
if [[ "$HOOK_RC" == 0 && -z "$HOOK_OUT" && ! -e "$MARKER" && ! -f "$RLOG" ]]; then
    ok "opt-out: silent, no run, no log"
else
    bad "opt-out" "silent, no marker, no log" "rc $HOOK_RC out '$HOOK_OUT'"
fi
# ── Case 11: "{}" stdin -> exit 0, session logged as unknown ────────────────
echo "Case 11: empty JSON payload"
reset_case
write_readme "$(stamp_secs_ago $(( 48 * 3600 )))"
run_hook '{}'
wait_until 5 lock_gone
if [[ "$HOOK_RC" == 0 && "$HOOK_OUT" == *"rebuild started"* && "$(last_field 2)" == unknown ]]; then
    ok "{} stdin: exit 0, run started, session 'unknown'"
else
    bad "{} stdin" "rc 0, started, unknown" "rc $HOOK_RC out '$HOOK_OUT'"
fi
# ── Case 12: failing mirror -> rc recorded, lock still released ─────────────
echo "Case 12: failing mirror"
reset_case
write_readme "$(stamp_secs_ago $(( 48 * 3600 )))"
export KMR_STUB_RC=3
run_hook '{"session_id":"s12"}'
unset KMR_STUB_RC
if [[ "$HOOK_RC" == 0 ]] && wait_until 5 lock_gone && grep -q '^done rc=3 ' "$EVAL_LOG"; then
    ok "failing mirror: done rc=3 recorded, lock released"
else
    bad "failing mirror" "done rc=3 and lock gone" "eval: $(tail -n 1 "$EVAL_LOG" 2>/dev/null)"
fi
# ── Case 13: unwritable log -> hook still exits 0 (fresh path) ──────────────
echo "Case 13: unwritable log never fails the hook"
reset_case
write_readme "$(stamp_secs_ago 3600)"
printf 'not a directory' > "$SCRATCH/blocker"
export CLAUDE_KNOWLEDGE_REFRESH_LOG="$SCRATCH/blocker/knowledge-refresh.log"
run_hook '{"session_id":"s13"}'
export CLAUDE_KNOWLEDGE_REFRESH_LOG="$RLOG"
if [[ "$HOOK_RC" == 0 && -z "$HOOK_OUT" ]]; then ok "unwritable log: exit 0, silent stdout"; else bad "unwritable log" "rc 0, empty" "rc $HOOK_RC out '$HOOK_OUT'"; fi
# ── Case 14: mirror script missing -> silent ────────────────────────────────
echo "Case 14: missing mirror script is silent"
reset_case
write_readme "$(stamp_secs_ago $(( 48 * 3600 )))"
export CLAUDE_KNOWLEDGE_MIRROR="$SCRATCH/no-such-mirror.sh"
run_hook '{"session_id":"s14"}'
export CLAUDE_KNOWLEDGE_MIRROR="$STUB"
if [[ "$HOOK_RC" == 0 && -z "$HOOK_OUT" && ! -e "$LOCK" ]]; then ok "missing mirror: exit 0, silent, no lock"; else bad "missing mirror" "rc 0, empty, no lock" "rc $HOOK_RC out '$HOOK_OUT'"; fi
# ── Case 15: two hooks race on one stale lock -> exactly one start ──────────
echo "Case 15: two hooks race on one stale lock"
reset_case
write_readme "$(stamp_secs_ago $(( 48 * 3600 )))"
: > "$LOCK"
touch -t "$(date -j -f %s "$(( $(date -u +%s) - 2400 ))" +%Y%m%d%H%M)" "$LOCK"
printf '%s' '{"session_id":"race-a"}' | bash "$HOOK" >"$SCRATCH/race-a.out" 2>/dev/null &
printf '%s' '{"session_id":"race-b"}' | bash "$HOOK" >"$SCRATCH/race-b.out" 2>/dev/null &
wait
wait_until 5 lock_gone
starts=$(cat "$SCRATCH/race-a.out" "$SCRATCH/race-b.out" | grep -c 'rebuild started')
skips=$(grep -c 'skipped-lock' "$RLOG")
runs=0
if [[ -f "$MARKER" ]]; then runs=$(wc -l < "$MARKER" | tr -d ' '); fi
if [[ "$starts" == 1 && "$skips" == 1 && "$runs" == 1 ]]; then
    ok "race: one 'started', one 'skipped-lock', one stub run"
else
    bad "race" "1 started, 1 skipped-lock, 1 run" "started=$starts skipped=$skips runs=$runs"
fi

# ── Case 16: failure streak -> third failed run, then escalation, no start ──
echo "Case 16: failure streak escalates"
reset_case
write_readme "$(stamp_secs_ago $(( 48 * 3600 )))"
export KMR_STUB_RC=1
run_hook '{"session_id":"f1"}'; out1=$HOOK_OUT; wait_until 5 lock_gone
run_hook '{"session_id":"f2"}'; out2=$HOOK_OUT; wait_until 5 lock_gone
run_hook '{"session_id":"f3"}'; out3=$HOOK_OUT; wait_until 5 lock_gone
run_hook '{"session_id":"f4"}'; out4=$HOOK_OUT
unset KMR_STUB_RC
runs=$(wc -l < "$MARKER" | tr -d ' ')
if [[ "$out1$out2$out3" == *"rebuild started"*"rebuild started"*"rebuild started"* && "$out4" == *"ESCALATION"* \
    && "$out4" != *$'\n'* && "$runs" == 3 && "$(last_outcome)" == escalation && ! -e "$LOCK" && "$(cat "$FAIL_FILE")" == "3 1" ]]; then
    ok "streak: runs 1-3 start, 4th session escalates (no start), state '3 1'"
else
    bad "streak" "3 starts, ESCALATION, runs=3, state '3 1'" "runs=$runs state=$(cat "$FAIL_FILE" 2>/dev/null) out4='$out4'"
fi

# ── Case 17: success resets the streak ──────────────────────────────────────
echo "Case 17: a successful run resets the streak"
reset_case
write_readme "$(stamp_secs_ago $(( 48 * 3600 )))"
export KMR_STUB_RC=1
run_hook '{"session_id":"r1"}'; wait_until 5 lock_gone
export KMR_STUB_RC=0
run_hook '{"session_id":"r2"}'; wait_until 5 lock_gone
unset KMR_STUB_RC
if [[ "$(cat "$FAIL_FILE")" == "0 0" ]]; then ok "rc=0 run: streak reset to '0 0'"; else bad "reset" "0 0" "$(cat "$FAIL_FILE" 2>/dev/null)"; fi

# ── Case 18: a fresh stamp (manual rebuild) ends an escalated streak ────────
echo "Case 18: fresh stamp resets an escalated streak"
reset_case
printf '3 1\n' > "$FAIL_FILE"
write_readme "$(stamp_secs_ago 3600)"
run_hook '{"session_id":"m1"}'
if [[ "$HOOK_RC" == 0 && -z "$HOOK_OUT" && "$(cat "$FAIL_FILE")" == "0 0" ]]; then
    ok "fresh stamp: silent and streak reset to '0 0'"
else
    bad "fresh reset" "silent, '0 0'" "out '$HOOK_OUT' state $(cat "$FAIL_FILE" 2>/dev/null)"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo
echo "knowledge-mirror-refresh regression: $PASS passed, $FAIL failed"
if (( FAIL == 0 )); then
    echo "PASS"
    exit 0
fi
echo "FAIL"
exit 1
