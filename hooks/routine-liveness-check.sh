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
# a blocker line the moment >=2 CONSECUTIVE runs of ONE routine ended in
# status:"error", and a separate staleness warning if a routine's log
# hasn't had ANY entry (of any status) in longer than its own cadence
# tolerates. The two checks are independent: a routine can be erroring on
# every cycle without being stale (it still fires, it just fails — the
# daily-docs case observed 2026-09-09), or stale without erroring (it simply
# stopped firing after a clean run).
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

# Advisory hook — a missing jq must never break session start.
command -v jq >/dev/null 2>&1 || exit 0

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

# check_routine NAME BASENAME STALE_THRESHOLD_SECS STALE_LABEL
check_routine() {
    local name="$1" base="$2" stale_secs="$3" stale_label="$4"
    local logfile="$LOG_DIR/${base}.jsonl"

    [[ -f "$logfile" ]] || return 0   # no log yet = fresh install, not this hook's alarm

    # Normalize every line's .ts — observed in the wild as an epoch INTEGER
    # (routine-run.sh's own log_error), a numeric STRING, or an ISO8601
    # STRING (each SKILL.md's own success/partial lines) — sometimes mixed
    # within the SAME file (weekly-improve-log.jsonl does exactly this in
    # production). Read as RAW input (`-R`, one line at a time) with an
    # inner `try fromjson catch null` per line — plain `jq -r '...'` on the
    # whole file aborts the ENTIRE parse (and yields NOTHING, silently) the
    # moment it meets ONE malformed line anywhere in the file, which would
    # have silently blinded this hook to every entry after a single
    # truncated write. Raw-input mode isolates the failure to that one line;
    # every other line is still evaluated. A line that parses but isn't a
    # JSON object (bare number/array/string) is skipped the same way.
    local tsv
    tsv=$(jq -R -r '
        (try fromjson catch null) as $o
        | select($o != null and ($o | type) == "object")
        | ($o.ts) as $ts
        | {
            epoch: (
                if ($ts | type) == "number" then $ts
                elif ($ts | type) == "string" and ($ts | test("^[0-9]+$")) then ($ts | tonumber)
                elif ($ts | type) == "string" then (try ($ts | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) catch null)
                else null end
            ),
            status: ($o.status // "unknown"),
            reason: ($o.note // $o.error // $o.reason // "")
        }
        | select(.epoch != null)
        | [(.epoch | tostring), .status, (.reason | gsub("[\t\n]"; " "))]
        | @tsv
    ' "$logfile" 2>/dev/null)
    [[ -n "$tsv" ]] || return 0   # empty/unparseable log — nothing positive to report

    # File order is append order (oldest first) — reverse to newest-first so
    # both checks below can walk from "most recent" without re-sorting twice.
    local reversed
    reversed=$(printf '%s\n' "$tsv" | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}')

    local newest_line newest_epoch newest_status
    newest_line=$(printf '%s\n' "$reversed" | head -1)
    newest_epoch=$(printf '%s' "$newest_line" | cut -f1)
    newest_status=$(printf '%s' "$newest_line" | cut -f2)

    # Consecutive "error" streak counted from the newest entry backward —
    # this is a plain here-string loop (not a pipe), so `streak` and the
    # other locals survive past the loop in THIS shell, not a subshell.
    local streak=0 last_error_epoch="" last_error_reason="" first_error_epoch=""
    while IFS=$'\t' read -r epoch status reason; do
        [[ "$status" == "error" ]] || break
        streak=$((streak + 1))
        if [[ -z "$last_error_epoch" ]]; then
            last_error_epoch="$epoch"
            last_error_reason="$reason"
        fi
        first_error_epoch="$epoch"
    done <<< "$reversed"

    if [[ "$streak" -ge 2 ]]; then
        echo "🚨 ROUTINE LIVENESS: '$name' — $streak consecutive failed runs (IMP-191). Letzter Fehler ($(fmt_epoch "$last_error_epoch")): ${last_error_reason:-<kein Grund im Log>} · Erster Fehlzeitpunkt der Serie: $(fmt_epoch "$first_error_epoch")."
        echo "    Log: $logfile"
    fi

    # Staleness — newest entry of ANY status older than this routine's own
    # cadence tolerates (2x the run interval: 48h for the two daily-cadence
    # routines, 8 days for the weekly one). Independent of the streak check.
    if [[ "$newest_epoch" =~ ^[0-9]+$ ]]; then
        local age=$(( NOW_EPOCH - newest_epoch ))
        if [[ "$age" -gt "$stale_secs" ]]; then
            local age_days=$(( age / 86400 ))
            echo "⚠️  ROUTINE LIVENESS: '$name' hat seit ${age_days} Tag(en) gar nicht gefeuert (letzter Eintrag $(fmt_epoch "$newest_epoch"), Status '$newest_status'; Toleranz: $stale_label)."
            echo "    Log: $logfile"
        fi
    fi
}

check_routine "daily-docs"          "daily-docs-log"     172800 "48h"
check_routine "nightly-observation" "nightly-obs-log"    172800 "48h"
check_routine "weekly-improve"      "weekly-improve-log" 691200 "8 Tage"

exit 0
