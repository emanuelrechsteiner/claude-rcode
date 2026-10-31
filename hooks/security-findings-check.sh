#!/bin/bash
# security-findings-check.sh — SessionStart reader for the security-review
# findings feed (IMP-207, 2026-09-09).
# ─────────────────────────────────────────────────────────────────────────────
# Companion to scripts/security-review-findings.sh (read its header first —
# this hook does NOT duplicate the extraction logic, it only (a) asks that
# script to do a bounded incremental scan and (b) prints ONE line naming
# unacked findings for the CURRENT project, if any.
#
# Registered AFTER routine-liveness-check.sh in settings.json's SessionStart
# chain (same "reader, not gate" contract: always exit 0, never blocks).
#
# Time budget: the extractor's own header explains why a cold-cache full scan
# can be slow (multi-MB transcripts, hundreds of sessions) and why that's
# fine — the STATE cache in scripts/security-review-findings.sh makes each
# session's re-scan progressively cheaper. This hook enforces the ~2s budget
# from the OUTSIDE via `timeout`/`gtimeout` (same detection pattern as
# scripts/phase-gate-check.sh — GNU `timeout` is not on macOS by default,
# `gtimeout` via Homebrew coreutils is the equivalent). If NEITHER binary is
# on PATH, this hook does NOT run the extractor at all (an unbounded scan at
# every session start would be exactly the kind of thing that makes a user
# disable a hook) — it falls back to reading whatever the OUT file already
# holds from a previous run. A cold install with neither timeout binary and
# no prior run will find nothing to report, which is correct: it has nothing
# positive to report, not a false "all clear".
#
# A missing OUT file (fresh install, extractor never run) is NOT an alarm —
# same "silent unless there is something to say" contract as
# git-remote-check.sh and routine-liveness-check.sh.
#
# Env overrides (testing only — production uses the fixed defaults, and MUST
# match the names scripts/security-review-findings.sh itself honors, since
# this hook reads the SAME files that script writes):
#   CLAUDE_SEC_FINDINGS_SCRIPT        default: ~/.claude/scripts/security-review-findings.sh
#   CLAUDE_SEC_FINDINGS_OUT           default: ~/.claude/global-observation/security-review-findings.jsonl
#   CLAUDE_SEC_FINDINGS_ACK           default: ~/.claude/global-observation/security-review-findings-ack.txt
#   CLAUDE_SEC_FINDINGS_UPSTREAM      default: ~/.claude/plans/upstream-findings.md
#   CLAUDE_SEC_FINDINGS_HOOK_TIMEOUT_SECS   default: 2
#   CLAUDE_SEC_FINDINGS_HOOK_WINDOW_DAYS    default: 30
#   CLAUDE_SEC_FINDINGS_HOOK_CWD      default: $PWD (override lets tests fake "the current project")
#
# P-IMP-264 (2026-10-31): a record with a non-null duplicate_of is skipped
# (logged in the feed, never counted). A vendor-owned record (vendor:true, see
# scripts/security-review-findings.sh header) is not counted as unacked; it is
# summarised as one token "(+N upstream, see plans/upstream-findings.md)".
#
# Upstream token — printed ONLY when the upstream list has gained rows since the
# token was last printed (review finding 4, 2026-10-31; the spec says vendor
# findings are neither silenced nor re-raised every session). The state is one
# integer in a marker file next to the ACK file:
#   <ACK dir>/security-review-findings-upstream-shown.txt
# holding the number of "- " rows in the upstream list when the token last
# printed. Token shown iff the current row count > the marker AND this project
# has vendor rows in the window; then the marker is rewritten. A list that
# shrank re-baselines the marker silently. A missing or unparseable marker means
# "nothing shown yet" (the token may then appear once more — never lost).
# The list is global, so a new upstream row shown from any project can surface
# the token in another project that has older vendor rows (accepted trade-off).
#
# Exit: always 0.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

HOME_DIR="${HOME:-$(cd ~ 2>/dev/null && pwd)}"
SCRIPT="${CLAUDE_SEC_FINDINGS_SCRIPT:-$HOME_DIR/.claude/scripts/security-review-findings.sh}"
OUT="${CLAUDE_SEC_FINDINGS_OUT:-$HOME_DIR/.claude/global-observation/security-review-findings.jsonl}"
ACK="${CLAUDE_SEC_FINDINGS_ACK:-$HOME_DIR/.claude/global-observation/security-review-findings-ack.txt}"
UPSTREAM="${CLAUDE_SEC_FINDINGS_UPSTREAM:-$HOME_DIR/.claude/plans/upstream-findings.md}"
SHOWN_MARK="$(dirname "$ACK")/security-review-findings-upstream-shown.txt"
BUDGET_SECS="${CLAUDE_SEC_FINDINGS_HOOK_TIMEOUT_SECS:-2}"
WINDOW_DAYS="${CLAUDE_SEC_FINDINGS_HOOK_WINDOW_DAYS:-30}"
CWD="${CLAUDE_SEC_FINDINGS_HOOK_CWD:-$PWD}"

# ── bounded-timeout detection (macOS lacks GNU `timeout` by default) ───────
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout"
fi

if [[ -n "$TIMEOUT_BIN" && -x "$SCRIPT" ]]; then
    "$TIMEOUT_BIN" "$BUDGET_SECS" bash "$SCRIPT" >/dev/null 2>&1 || true
fi
# No timeout binary (or no script) -> skip running the extractor entirely and
# fall through to reading whatever OUT already holds. Running an unbounded
# scan here is exactly the failure mode this budget exists to prevent.

[[ -f "$OUT" ]] || exit 0   # fresh install / extractor never run yet — silent

[[ -f "$ACK" ]] || : > "$ACK" 2>/dev/null || true

# project slug this session would be filed under, mirroring Claude Code's own
# ~/.claude/projects/<slug> convention (cwd with "/" and "_" -> "-").
CWD_SLUG="$(printf '%s' "$CWD" | tr '/_' '-')"
PROJECT_DISPLAY="$(basename "$CWD")"

NOW_EPOCH=$(date -u +%s)
CUTOFF_EPOCH=$(( NOW_EPOCH - WINDOW_DAYS * 86400 ))

ACK_JSON="$(jq -R -s -c 'split("\n") | map(select(length > 0))' "$ACK" 2>/dev/null || echo '[]')"

# Raw-input line-by-line parse (same defensive pattern as
# routine-liveness-check.sh): one malformed line must not blind this hook to
# every other line, and jq's whole-file parse mode would abort on the first
# bad line.
RESULT="$(jq -R -r --arg cwd_slug "$CWD_SLUG" --argjson ack "$ACK_JSON" --argjson cutoff "$CUTOFF_EPOCH" '
    (try fromjson catch null) as $o
    | select($o != null and ($o | type) == "object")
    | select((($o.project // "") as $p | ($cwd_slug | contains($p)) or ($p | contains($cwd_slug))))
    | select(($ack | index($o.session_id)) == null)
    | select(($o.duplicate_of // "") == "")
    | ($o.ts // "") as $ts
    | select(($ts | length) > 0)
    | (try ($ts | sub("\\.[0-9]+Z$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) catch null) as $e
    | select($e != null and $e >= $cutoff)
    | [$o.ts, ($o.file // "?"), ($o.severity // "?"), ($o.summary // ""), ($o.session_id // "?"),
       (if ($o.vendor // false) == true then "upstream" else "own" end)]
    | @tsv
' "$OUT" 2>/dev/null)"

[[ -n "$RESULT" ]] || exit 0

# P-IMP-264: field 6 is "own" (counted as unacked) or "upstream" (vendor-owned).
COUNTS="$(printf '%s\n' "$RESULT" | awk -F'\t' '$6 == "upstream" { m++; next } { n++ } END { print n + 0, m + 0 }')"
N="${COUNTS% *}"
M="${COUNTS#* }"

# ── upstream token: shown only when the upstream list gained rows (finding 4) ──
record_shown() {   # record_shown COUNT — rewrite the marker; a failure is reported, never silent
    printf '%s\n' "$1" > "$SHOWN_MARK" 2>/dev/null \
        || echo "[security-findings-check] WARN: cannot write $SHOWN_MARK (the upstream token may repeat)" >&2
}
UPSTREAM_COUNT=0
if [[ -f "$UPSTREAM" ]]; then
    UPSTREAM_COUNT="$(awk '/^- / { n++ } END { print n + 0 }' "$UPSTREAM")" \
        || { echo "[security-findings-check] WARN: cannot read $UPSTREAM" >&2; UPSTREAM_COUNT=0; }
fi
SHOWN_COUNT=0
if [[ -f "$SHOWN_MARK" ]]; then
    SHOWN_RAW="$(head -n 1 "$SHOWN_MARK" 2>/dev/null)"
    if [[ "$SHOWN_RAW" =~ ^[0-9]+$ ]]; then SHOWN_COUNT="$SHOWN_RAW"; fi
fi
GAINED=0
if [[ "$M" -gt 0 && "$UPSTREAM_COUNT" -gt "$SHOWN_COUNT" ]]; then GAINED=1; fi
if [[ "$UPSTREAM_COUNT" -lt "$SHOWN_COUNT" ]]; then record_shown "$UPSTREAM_COUNT"; fi

if [[ "$N" -eq 0 ]]; then
    if [[ "$GAINED" -eq 1 ]]; then
        record_shown "$UPSTREAM_COUNT"
        echo "🔐 (+$M upstream, see plans/upstream-findings.md) for $PROJECT_DISPLAY"
    fi
    exit 0
fi
UPSTREAM_TOKEN=""
if [[ "$GAINED" -eq 1 ]]; then
    UPSTREAM_TOKEN=" (+$M upstream, see plans/upstream-findings.md)"
    record_shown "$UPSTREAM_COUNT"
fi
OWN_ROWS="$(printf '%s\n' "$RESULT" | awk -F'\t' '$6 != "upstream"')"

# newest first (ts is ISO8601, sorts lexically)
NEWEST_LINE="$(printf '%s\n' "$OWN_ROWS" | sort -t $'\t' -k1,1r | head -1)"
NEWEST_TS="$(printf '%s' "$NEWEST_LINE" | cut -f1)"
NEWEST_FILE="$(printf '%s' "$NEWEST_LINE" | cut -f2)"
NEWEST_SEV="$(printf '%s' "$NEWEST_LINE" | cut -f3)"
NEWEST_SUMMARY="$(printf '%s' "$NEWEST_LINE" | cut -f4)"
NEWEST_SID="$(printf '%s' "$NEWEST_LINE" | cut -f5)"
NEWEST_DATE="${NEWEST_TS:0:10}"

SUMMARY_SHORT="$NEWEST_SUMMARY"
if [[ "${#SUMMARY_SHORT}" -gt 80 ]]; then
    SUMMARY_SHORT="${SUMMARY_SHORT:0:80}…"
fi

echo "🔐 $N unreviewed security findings for $PROJECT_DISPLAY (newest $NEWEST_DATE: $NEWEST_FILE [$NEWEST_SEV] $SUMMARY_SHORT)$UPSTREAM_TOKEN — review: security-review-findings.sh --ack $NEWEST_SID"

exit 0
