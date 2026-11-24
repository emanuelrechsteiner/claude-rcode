#!/bin/bash
# routine-liveness-check.sh — SessionStart liveness reader for the three
# launchd routine run-logs (IMP-191, 2026-09-09).
# ─────────────────────────────────────────────────────────────────────────────
# Measured gap this closes: as of 2026-09-09, 39 status:"error" lines had
# accumulated across the three run-logs (daily-docs 18, nightly-observation
# 18, weekly-improve 3; window 2026-08-23..09-09) with ZERO readers — the
# quarterly audit was the only thing that ever looked at these files.
# session-end-check.sh's IMP-138/164 staleness alarm watches a DIFFERENT
# signal (the .last-run-ts watermark /meta-observe writes, at session END,
# when nobody is usually still looking). This hook reads the run-logs
# THEMSELVES, at SESSION START, where a human is actually present.
#
# This is a READER, not a gate — it never blocks (always exit 0). It prints
# a blocker line the moment >=2 CONSECUTIVE runs of ONE routine FAILED, and a
# separate staleness warning if a routine's log hasn't had ANY entry (of any
# status) in longer than its own cadence tolerates. The two checks are
# independent: a routine can be failing on every cycle without being stale
# (it still fires, it just fails — the daily-docs case observed 2026-09-09),
# or stale without failing (it simply stopped firing after a clean run).
#
# Two facts about the logs that the reader must respect (2026-11-06):
#   - Entries are ordered by their own `ts`, NEVER by file position. The
#     files are not chronological: dated backfill lines are interleaved with
#     runner lines, so the last line is not necessarily the newest.
#   - A failed run is status "error" (runner-written) or "fail" (a SKILL's own
#     ABORT). Every other status (ok, partial, backfill, unknown) ends a streak.
#
# Env overrides (testing only — production uses the fixed default):
#   CLAUDE_ROUTINE_LOG_DIR   default: $HOME/.claude/global-observation. Same
#                            variable scripts/routine-run.sh honors for its
#                            OWN error lines — both scripts point at the
#                            same directory by design, so a regression suite
#                            can point both at one scratch dir without
#                            inventing a second override convention.
#
# A missing log file is NOT an alarm (fresh install / never fired once yet —
# a different, install-time condition git-remote-check.sh's "silent unless
# there is something to say" pattern already covers by omission). Lines that
# fail to parse are dropped silently rather than surfaced as a false alarm —
# this hook only ever reports what it can positively confirm from the data
# (the fail-loud.md "graceful degradation" carve-out: nothing REQUIRED is
# being masked, this is an advisory reader that must never itself become a
# reason a session can't start).
#
# Exit: always 0.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

LOG_DIR="${CLAUDE_ROUTINE_LOG_DIR:-$HOME/.claude/global-observation}"

# Advisory hook — a missing jq must never break session start, but it must
# not go silent either: without jq the three logs are NOT checked, and the
# reader says so in one visible line instead of pretending all is well.
if ! command -v jq >/dev/null 2>&1; then
    echo "⚠️  ROUTINE LIVENESS: not checked — jq is missing (brew install jq)."
    exit 0
fi

NOW_EPOCH=$(date -u +%s)

# fmt_epoch EPOCH -> ISO8601 UTC string, or the raw value if not a plain int.
fmt_epoch() {
    local epoch="$1"
    if [[ "$epoch" =~ ^[0-9]+$ ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            date -u -r "$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "$epoch"
        else
            date -u -d "@$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "$epoch"
        fi
    else
        echo "$epoch"
    fi
}

# is_failed_status STATUS -> exit 0 when STATUS counts as a failed run.
# The exact set: "error" (runner) and "fail" (SKILL ABORT). Everything else
# ends a streak.
is_failed_status() {
    case "$1" in
        error|fail) return 0 ;;
        *) return 1 ;;
    esac
}

# check_routine NAME BASENAME STALE_THRESHOLD_SECS STALE_LABEL
check_routine() {
    local name="$1" base="$2" stale_secs="$3" stale_label="$4"
    local logfile="$LOG_DIR/${base}.jsonl"

    [[ -f "$logfile" ]] || return 0   # no log yet = fresh install, not this hook's alarm

    # One TSV row per parseable object line, NEWEST FIRST: epoch, status, reason.
    # Sorted by the line's own epoch; a tie goes to the later file position
    # (later append = newer), so the order is deterministic.
    # ts is observed as an epoch INTEGER (routine-run.sh's own log_error), a
    # numeric STRING, or an ISO8601 STRING (the SKILL lines), sometimes mixed
    # within the SAME file. Raw input (-R, sliced into lines with -s) plus an
    # inner `try fromjson catch null` per line isolates one malformed line to
    # itself; a plain whole-file parse would abort on one truncated write and
    # silently blind the hook to every later entry.
    local ordered jq_rc
    ordered=$(jq -R -s -r '
        split("\n") | to_entries
        | map(
            (.value | try fromjson catch null) as $o
            | select($o != null and ($o | type) == "object")
            | ($o.ts) as $ts
            | {
                idx: .key,
                epoch: (
                    if ($ts | type) == "number" then $ts
                    elif ($ts | type) == "string" and ($ts | test("^[0-9]+$")) then ($ts | tonumber)
                    elif ($ts | type) == "string" then (try ($ts | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) catch null)
                    else null end
                ),
                status: ($o.status // "unknown"),
                reason: (
                    [$o.note, $o.error, $o.reason]
                    | map(select(type == "string" and . != ""))
                    | (.[0] // "")
                )
            }
            | select(.epoch != null)
        )
        | sort_by([.epoch, .idx]) | reverse
        | .[]
        | [(.epoch | tostring), .status, (.reason | gsub("[\t\n]"; " "))]
        | @tsv
    ' "$logfile" 2>/dev/null)
    jq_rc=$?
    # A log that EXISTS but yields nothing is not "healthy": either jq could not
    # read the file, or no line parsed as a JSON object (garbage, or empty).
    # Both get one visible line per routine. A missing file stays silent above.
    if [[ "$jq_rc" -ne 0 ]]; then
        echo "⚠️  ROUTINE LIVENESS: '$name' log exists but jq could not read it (jq exit $jq_rc). Log: $logfile"
        return 0
    fi
    if [[ -z "$ordered" ]]; then
        echo "⚠️  ROUTINE LIVENESS: '$name' log exists but has no readable entries. Log: $logfile"
        return 0
    fi

    # Newest entry by time (first row). Plain parameter expansion, no pipes.
    local newest_line newest_epoch newest_rest newest_status
    newest_line="${ordered%%$'\n'*}"
    newest_epoch="${newest_line%%$'\t'*}"
    newest_rest="${newest_line#*$'\t'}"
    newest_status="${newest_rest%%$'\t'*}"

    # Consecutive failed-run streak counted from the newest entry backward —
    # a plain here-string loop (not a pipe), so `streak` and the other locals
    # survive past the loop in THIS shell, not a subshell.
    local streak=0 last_error_epoch="" last_error_reason="" first_error_epoch=""
    while IFS=$'\t' read -r epoch status reason; do
        is_failed_status "$status" || break
        streak=$((streak + 1))
        if [[ -z "$last_error_epoch" ]]; then
            last_error_epoch="$epoch"
            last_error_reason="$reason"
        fi
        first_error_epoch="$epoch"
    done <<< "$ordered"

    if [[ "$streak" -ge 2 ]]; then
        echo "🚨 ROUTINE LIVENESS: '$name' — $streak consecutive failed runs (IMP-191). Last error ($(fmt_epoch "$last_error_epoch")): ${last_error_reason:-<no reason in log>} · First failure time of the streak: $(fmt_epoch "$first_error_epoch")."
        echo "    Log: $logfile"
    fi

    # Staleness — newest entry of ANY status older than this routine's own
    # cadence tolerates (2x the run interval: 48h for the two daily-cadence
    # routines, 8 days for the weekly one). Independent of the streak check.
    if [[ "$newest_epoch" =~ ^[0-9]+$ ]]; then
        local age=$(( NOW_EPOCH - newest_epoch ))
        if [[ "$age" -gt "$stale_secs" ]]; then
            local age_days=$(( age / 86400 ))
            echo "⚠️  ROUTINE LIVENESS: '$name' has not fired at all in ${age_days} day(s) (last entry $(fmt_epoch "$newest_epoch"), status '$newest_status'; tolerance: $stale_label)."
            echo "    Log: $logfile"
        fi
    fi
}

check_routine "daily-docs"          "daily-docs-log"     172800 "48h"
check_routine "nightly-observation" "nightly-obs-log"    172800 "48h"
check_routine "weekly-improve"      "weekly-improve-log" 691200 "8 days"

# check_signal_flow (IMP-273): the nightly routine can report "ok" while the capture
# hook writes nowhere. Three ok runs in a row that rotated 0 signals get one visible
# line. Advisory: three quiet days without a session look the same.
check_signal_flow() {
    local logfile="$LOG_DIR/nightly-obs-log.jsonl" verdict
    [[ -f "$logfile" ]] || return 0
    verdict=$(jq -R -s -r '
        [split("\n")[] | (try fromjson catch null)
         | select(type == "object" and .status == "ok" and (.ts | type) == "number")]
        | sort_by(.ts) | .[-3:]
        | if length == 3 and all(.[]; (.entries_rotated // 0) == 0) then "zero" else "flowing" end
    ' "$logfile" 2>/dev/null) || return 0
    if [[ "$verdict" == "zero" ]]; then
        echo "⚠️  ROUTINE LIVENESS: nightly-observation reported ok three times in a row but rotated 0 signals each time (IMP-273). Either nothing was edited for three days, or the capture hook writes nowhere: check signals.jsonl and hooks/observation-capture.sh."
        echo "    Log: $logfile"
    fi
}
check_signal_flow

exit 0
