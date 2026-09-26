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
#   CLAUDE_SEC_FINDINGS_HOOK_TIMEOUT_SECS   default: 2
#   CLAUDE_SEC_FINDINGS_HOOK_WINDOW_DAYS    default: 30
#   CLAUDE_SEC_FINDINGS_HOOK_CWD      default: $PWD (override lets tests fake "the current project")
#
# Exit: always 0.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

HOME_DIR="${HOME:-$(cd ~ 2>/dev/null && pwd)}"
SCRIPT="${CLAUDE_SEC_FINDINGS_SCRIPT:-$HOME_DIR/.claude/scripts/security-review-findings.sh}"
OUT="${CLAUDE_SEC_FINDINGS_OUT:-$HOME_DIR/.claude/global-observation/security-review-findings.jsonl}"
ACK="${CLAUDE_SEC_FINDINGS_ACK:-$HOME_DIR/.claude/global-observation/security-review-findings-ack.txt}"
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
    | ($o.ts // "") as $ts
    | select(($ts | length) > 0)
    | (try ($ts | sub("\\.[0-9]+Z$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) catch null) as $e
    | select($e != null and $e >= $cutoff)
    | [$o.ts, ($o.file // "?"), ($o.severity // "?"), ($o.summary // ""), ($o.session_id // "?")]
    | @tsv
' "$OUT" 2>/dev/null)"

[[ -n "$RESULT" ]] || exit 0

N=$(printf '%s\n' "$RESULT" | grep -c . )
[[ "$N" -gt 0 ]] || exit 0

# newest first (ts is ISO8601, sorts lexically)
NEWEST_LINE="$(printf '%s\n' "$RESULT" | sort -t $'\t' -k1,1r | head -1)"
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

echo "🔐 $N unreviewed security findings for $PROJECT_DISPLAY (newest $NEWEST_DATE: $NEWEST_FILE [$NEWEST_SEV] $SUMMARY_SHORT) — review: security-review-findings.sh --ack $NEWEST_SID"

exit 0
