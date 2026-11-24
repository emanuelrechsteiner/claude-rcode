#!/bin/bash
# knowledge-mirror-refresh.sh — SessionStart hook (matcher: startup), IMP-267.
# ─────────────────────────────────────────────────────────────────────────────
# The knowledge mirror ($CLAUDE_KNOWLEDGE_DIR/mirror/, built by
# scripts/knowledge-mirror.sh, ADR 0006) changes only when someone reruns it, so
# notes written since its last run are invisible to the lookup. When the README
# stamp "Last run: <ISO>" is older than CLAUDE_KNOWLEDGE_REFRESH_HOURS (default
# 24), this hook starts the mirror DETACHED and prints one context line.
#
# Fails open: a missing library, README or mirror script exits 0 silently.
# A stamp that cannot be parsed counts as stale (and the log says so with age "?").
# Opt-out: CLAUDE_KNOWLEDGE_REFRESH=0.
# Stdout is SessionStart context: one line, when a rebuild starts or escalates.
# Log (CLAUDE_KNOWLEDGE_REFRESH_LOG, default
# ~/.claude/global-observation/knowledge-refresh.log): one TAB-separated line per
# decision: <ts> <session_id> <age_h> <fresh|started|skipped-lock|failed-start|escalation>.
# Run output: $KDIR/eval/mirror-refresh.log (ends with "done rc=<n> <ts>").
# Failure streak: $KDIR/eval/mirror-refresh.failures ("<count> <last-rc>"). A run
# that ends rc!=0, or a stale lock left by a run with no "done" line, extends it;
# rc=0 or a fresh stamp resets it. At 3 consecutive failures the hook escalates
# (one stdout line, log "escalation") and starts no further run.
# ─────────────────────────────────────────────────────────────────────────────
set -u

LOCK_MAX_AGE_S=1800
FAILURE_ESCALATE_AT=3

INPUT=$(cat 2>/dev/null || true)
if [[ "${CLAUDE_KNOWLEDGE_REFRESH:-1}" == "0" ]]; then
    exit 0
fi

NOW=$(date -u +%s)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || SESSION_ID=""
SESSION_ID="${SESSION_ID:-unknown}"

# CLAUDE_KNOWLEDGE_DIR: environment first, else ~/.claude/env.local.sh (subshell, -u/-e off).
KDIR="${CLAUDE_KNOWLEDGE_DIR:-}"
if [[ -z "$KDIR" && -f "$HOME/.claude/env.local.sh" ]]; then
    # shellcheck disable=SC1091
    KDIR=$( set +u +e; . "$HOME/.claude/env.local.sh" >/dev/null 2>&1; printf '%s' "${CLAUDE_KNOWLEDGE_DIR:-}" )
fi
KDIR="${KDIR%/}"
if [[ -z "$KDIR" || ! -f "$KDIR/mirror/README.md" ]]; then
    exit 0
fi

MIRROR="${CLAUDE_KNOWLEDGE_MIRROR:-$HOME/.claude/scripts/knowledge-mirror.sh}"
if [[ ! -f "$MIRROR" ]]; then
    exit 0
fi

LOG_FILE="${CLAUDE_KNOWLEDGE_REFRESH_LOG:-$HOME/.claude/global-observation/knowledge-refresh.log}"
# Lock, log and failure state live in eval/: the mirror owns mirror/ and never reads or writes eval/.
LOCK="$KDIR/eval/mirror-refresh.lock"
EVAL_LOG="$KDIR/eval/mirror-refresh.log"
FAIL_FILE="$KDIR/eval/mirror-refresh.failures"

HOURS="${CLAUDE_KNOWLEDGE_REFRESH_HOURS:-24}"
if [[ ! "$HOURS" =~ ^[0-9]+$ ]]; then
    echo "knowledge-mirror-refresh: CLAUDE_KNOWLEDGE_REFRESH_HOURS='$HOURS' is not an integer; using 24" >&2
    HOURS=24
fi

# parse_stamp <ISO-Z> -> epoch on stdout; returns 1 when unparsable.
# Strict format first, so GNU date cannot read free text such as "yesterday".
parse_stamp() {
    local stamp="$1" epoch=""
    if [[ ! "$stamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        return 1
    fi
    epoch=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$stamp" +%s 2>/dev/null) \
        || epoch=$(date -u -d "$stamp" +%s 2>/dev/null) || return 1
    if [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    printf '%s' "$epoch"
}

# file_mtime <path> -> mtime epoch on stdout; returns 1 when unreadable.
file_mtime() {
    local mtime=""
    mtime=$(stat -c %Y "$1" 2>/dev/null) || mtime=$(stat -f %m "$1" 2>/dev/null) || return 1
    if [[ ! "$mtime" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    printf '%s' "$mtime"
}

# is_young <epoch> -> 0 when the epoch lies inside the lock window (never in the future).
is_young() {
    local age=$(( NOW - $1 ))
    (( age >= 0 && age < LOCK_MAX_AGE_S ))
}

# log_outcome <outcome> — append one line; an unwritable log warns, never fails.
log_outcome() {
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    if ! printf '%s\t%s\t%s\t%s\n' "$ts" "$SESSION_ID" "$AGE_H" "$1" >>"$LOG_FILE" 2>/dev/null; then
        echo "knowledge-mirror-refresh: cannot append to $LOG_FILE" >&2
    fi
}

# fail_start <reason> — no rebuild started; release our lock, report loudly, exit 0.
fail_start() {
    rm -f "$LOCK"
    echo "knowledge-mirror-refresh: no rebuild started: $1" >&2
    log_outcome failed-start
    exit 0
}

# read_failures -> FAILS and LAST_RC from the state file; no file means 0 and "-".
read_failures() {
    local line=""
    FAILS=0
    LAST_RC="-"
    [[ -f "$FAIL_FILE" ]] || return 0
    # read returns 1 at EOF when the last line has no newline; the line is still set.
    IFS= read -r line < "$FAIL_FILE" || true
    if [[ "$line" =~ ^([0-9]+)\ ([A-Za-z0-9-]+)$ ]]; then
        FAILS="${BASH_REMATCH[1]}"
        LAST_RC="${BASH_REMATCH[2]}"
    else
        echo "knowledge-mirror-refresh: malformed $FAIL_FILE; counting the streak from 0" >&2
    fi
}

# write_failures <count> <last-rc> — atomic replace; a failed write is reported, not silent.
write_failures() {
    local tmp="$FAIL_FILE.tmp.$$"
    if printf '%s %s\n' "$1" "$2" >"$tmp" && mv -f "$tmp" "$FAIL_FILE"; then
        return 0
    fi
    echo "knowledge-mirror-refresh: cannot write $FAIL_FILE" >&2
}

# record_result <rc> — runs in the detached subshell: rc 0 resets the streak, anything else extends it.
record_result() {
    if [[ "$1" == 0 ]]; then
        write_failures 0 0
        return 0
    fi
    read_failures
    write_failures $(( FAILS + 1 )) "$1"
}

# ── Read the stamp (first "Last run: <token>" match) ─────────────────────────
STAMP=""
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ Last\ run:\ ([^[:space:]]+) ]]; then
        STAMP="${BASH_REMATCH[1]}"
        break
    fi
done < "$KDIR/mirror/README.md"

# ── Age decision ──────────────────────────────────────────────────────────────
AGE_H="?"
AGE_S=0
STAMP_EPOCH=""
if [[ -n "$STAMP" ]]; then
    STAMP_EPOCH=$(parse_stamp "$STAMP") || STAMP_EPOCH=""
fi
if [[ -n "$STAMP_EPOCH" ]]; then
    AGE_S=$(( NOW - STAMP_EPOCH ))
    if (( AGE_S < 0 )); then
        AGE_S=0
    fi
    AGE_H=$(( AGE_S / 3600 ))
    if (( AGE_S <= HOURS * 3600 )); then
        # A fresh stamp means a rebuild succeeded since (ours or a manual one): end any streak.
        read_failures
        if (( FAILS > 0 )); then
            write_failures 0 0
        fi
        log_outcome fresh
        exit 0
    fi
fi

# ── Lock: a young lock means a run is in flight; a stale one is taken over atomically ──
if ! mkdir -p "$KDIR/eval" 2>/dev/null; then
    echo "knowledge-mirror-refresh: no rebuild started: cannot create $KDIR/eval" >&2
    log_outcome failed-start
    exit 0
fi
DEAD=0
if [[ -e "$LOCK" ]]; then
    LOCK_EPOCH=$(file_mtime "$LOCK") || LOCK_EPOCH=""
    if [[ -z "$LOCK_EPOCH" ]] || is_young "$LOCK_EPOCH"; then
        log_outcome skipped-lock
        exit 0
    fi
    # Only the session whose rename succeeds owns the stale lock; the others see ENOENT.
    TAKEN="$LOCK.stale.$$"
    if ! mv "$LOCK" "$TAKEN" 2>/dev/null; then
        log_outcome skipped-lock
        exit 0
    fi
    TAKEN_EPOCH=$(file_mtime "$TAKEN") || TAKEN_EPOCH=""
    if [[ -z "$TAKEN_EPOCH" ]] || is_young "$TAKEN_EPOCH"; then
        # We renamed a fresh lock another session just created: hand it back, never delete it.
        if ! mv -n "$TAKEN" "$LOCK" 2>/dev/null; then
            echo "knowledge-mirror-refresh: fresh lock kept at $TAKEN (lock path taken again)" >&2
        fi
        log_outcome skipped-lock
        exit 0
    fi
    rm -f "$TAKEN"
    # A stale lock with no "done" line in the last run's log means that run never finished.
    if ! grep -q '^done rc=' "$EVAL_LOG" 2>/dev/null; then
        DEAD=1
    fi
fi
if ! ( set -C; : > "$LOCK" ) 2>/dev/null; then
    if [[ -e "$LOCK" ]]; then
        log_outcome skipped-lock
        exit 0
    fi
    echo "knowledge-mirror-refresh: no rebuild started: cannot create lock $LOCK" >&2
    log_outcome failed-start
    exit 0
fi

# ── Failure streak: count a dead run, then escalate instead of restarting ─────
read_failures
if (( DEAD == 1 )); then
    FAILS=$(( FAILS + 1 ))
    LAST_RC="dead"
    write_failures "$FAILS" "$LAST_RC"
fi
if (( FAILS >= FAILURE_ESCALATE_AT )); then
    rm -f "$LOCK"
    log_outcome escalation
    printf '📚 ESCALATION: knowledge mirror rebuild failed %s times in a row (last rc=%s); not restarting automatically — run bash ~/.claude/scripts/knowledge-mirror.sh by hand and read %s\n' \
        "$FAILS" "$LAST_RC" "$EVAL_LOG"
    exit 0
fi

# ── Start the mirror detached; the subshell's stdout is /dev/null so the ─────
# ── SessionStart pipe closes at once. "done" is written before the lock goes.
if ! : >>"$EVAL_LOG" 2>/dev/null; then
    fail_start "cannot write $EVAL_LOG"
fi
(
    nohup bash "$MIRROR" >"$EVAL_LOG" 2>&1 </dev/null
    rc=$?
    printf 'done rc=%s %s\n' "$rc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$EVAL_LOG"
    record_result "$rc"
    rm -f "$LOCK"
) >/dev/null 2>&1 &
disown "$!" 2>/dev/null

log_outcome started
if [[ -n "$STAMP_EPOCH" ]]; then
    AGE_TEXT="${AGE_H}h old"
else
    AGE_TEXT="of unknown age (stamp unparsable)"
fi
printf '📚 Knowledge mirror was %s (last run %s); rebuild started in the background, log: %s\n' \
    "$AGE_TEXT" "${STAMP:-missing}" "$EVAL_LOG"
exit 0
