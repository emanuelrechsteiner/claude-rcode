#!/bin/bash
# Session-end reminder hook — non-blocking.
#
# Surfaces useful information at Stop time (uncommitted changes, R.Code
# agent-log gap) without forcing a hard block. The agent's own discipline —
# driven by code-quality / workflow-git / R.Code rules — handles the
# real-work commit case. Hard-blocking here creates false positives when:
#
#   1. Uncommitted changes are pre-existing drift the agent did not author.
#   2. The agent is intentionally waiting for human approval on a plan.
#   3. The session was read-only (onboarding, review, research).
#
# Always exits 0. Messages are informational.

# Read JSON input for transcript archival (Stop event includes transcript_path).
# Done early so we still have stdin even when we cd out of git roots later.
STOP_INPUT="$(cat 2>/dev/null || true)"

# ═══════════════════════════════════════════════════════════════════════════
# Reminder 0: Archive chat transcript (IndyDevDan pattern, 2025-07)
# ═══════════════════════════════════════════════════════════════════════════
# Copy this session's full transcript JSONL into ~/.claude/global-observation/
# chat-archives/ so meta-observer + future audits have the conversation, not
# just Edit/Write signals.
if [[ -n "$STOP_INPUT" ]] && command -v jq >/dev/null 2>&1; then
    TRANSCRIPT_PATH=$(printf '%s' "$STOP_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
    SESSION_ID=$(printf '%s' "$STOP_INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" && -n "$SESSION_ID" ]]; then
        ARCHIVE_DIR="$HOME/.claude/global-observation/chat-archives"
        mkdir -p "$ARCHIVE_DIR"
        TODAY=$(date -u +%Y-%m-%d)
        DEST="$ARCHIVE_DIR/${TODAY}-${SESSION_ID}.jsonl"
        # Only copy if size changed or doesn't exist (idempotent — Stop can fire
        # multiple times per session if conversation continues).
        if [[ ! -f "$DEST" ]] || [[ "$TRANSCRIPT_PATH" -nt "$DEST" ]]; then
            cp "$TRANSCRIPT_PATH" "$DEST" 2>/dev/null || true
        fi

        # Compress archives older than 30 days (one-time per session is fine;
        # gzip is idempotent because find -mtime excludes already-.gz files).
        find "$ARCHIVE_DIR" -name "*.jsonl" -mtime +30 -exec gzip -q {} \; 2>/dev/null || true
    fi
fi

# Find git root; bail silently if not in a repo.
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ $? -ne 0 ]]; then
    exit 0
fi

cd "$GIT_ROOT" || exit 0

# ═══════════════════════════════════════════════════════════════════════════
# Reminder 1: Uncommitted changes
# ═══════════════════════════════════════════════════════════════════════════
MODIFIED_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

if [[ $MODIFIED_COUNT -gt 0 ]]; then
    echo "ℹ️  $MODIFIED_COUNT file(s) with uncommitted changes or untracked status."
    echo "    If this session authored them, commit before ending."
    echo "    If they predate the session or await approval, that's fine."
fi

# ═══════════════════════════════════════════════════════════════════════════
# Reminder 2: R.Code agent log freshness
# ═══════════════════════════════════════════════════════════════════════════
if [[ -d .rcode ]] && [[ -f .rcode/agent-log.md ]]; then
    # Age of last modification, in seconds.
    if [[ "$(uname)" == "Darwin" ]]; then
        LOG_MTIME=$(stat -f %m .rcode/agent-log.md 2>/dev/null || echo 0)
    else
        LOG_MTIME=$(stat -c %Y .rcode/agent-log.md 2>/dev/null || echo 0)
    fi
    LOG_AGE=$(( $(date +%s) - LOG_MTIME ))

    # If the log hasn't been touched in the last 4 hours AND there are
    # uncommitted changes, surface a /handoff reminder. This is a heuristic
    # — it won't fire for quick read-only sessions, and won't fire when the
    # agent just appended to the log.
    if [[ $LOG_AGE -gt 14400 ]] && [[ $MODIFIED_COUNT -gt 0 ]]; then
        echo "ℹ️  R.Code: agent-log.md last updated $((LOG_AGE / 3600))h ago."
        echo "    Consider /handoff if this session did meaningful work."
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Reminder 3: Observation pipeline → /meta-observe prompt
# ═══════════════════════════════════════════════════════════════════════════
# Appends a per-session metric line and prompts for /meta-observe when
# activity thresholds are crossed. Replaces archived improvement-agent
# continuous observation with passive aggregation.

METRICS_FILE="$HOME/.claude/global-observation/session-metrics.jsonl"
SIGNALS_FILE="$HOME/.claude/global-observation/signals.jsonl"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TODAY=$(date -u +%Y-%m-%d)

# grep -c always prints a count on stdout (0 on no-match); only its EXIT code
# differs. The old `|| echo 0` appended a SECOND 0 on no-match, producing a
# two-line value ("0\n0") that corrupted the JSON record below. Capture the
# count, strip any newline, and validate it is a single numeric token.
SIGNALS_TODAY=0
if [[ -f "$SIGNALS_FILE" ]]; then
    SIGNALS_TODAY=$(grep -c "\"ts\":\"$TODAY" "$SIGNALS_FILE" 2>/dev/null | tr -d '\n')
    [[ "$SIGNALS_TODAY" =~ ^[0-9]+$ ]] || SIGNALS_TODAY=0
fi

COMMITS_RECENT=$(git log --since="4 hours ago" --oneline 2>/dev/null | wc -l | tr -d ' ')

# Append per-session aggregate (JSONL) — ONE physical line per record.
# Sanitize counts to bare integers (defends against any stray newline/whitespace
# slipping through), then build the object with jq so it is always single-line
# and correctly escaped. Fall back to a hand-built single line only if jq is
# absent — never interpolate a raw multi-line subshell result.
ST=${SIGNALS_TODAY//[!0-9]/}; ST=${ST:-0}
CR=${COMMITS_RECENT//[!0-9]/}; CR=${CR:-0}
MC=${MODIFIED_COUNT//[!0-9]/}; MC=${MC:-0}
if command -v jq >/dev/null 2>&1; then
    jq -nc \
        --arg ts "$TS" \
        --arg cwd "$(pwd)" \
        --argjson signals_today "$ST" \
        --argjson commits_4h "$CR" \
        --argjson modified "$MC" \
        '{ts:$ts,cwd:$cwd,signals_today:$signals_today,commits_4h:$commits_4h,modified:$modified}' \
        >> "$METRICS_FILE"
else
    CWD_ESC=$(printf '%s' "$(pwd)" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"ts":"%s","cwd":"%s","signals_today":%s,"commits_4h":%s,"modified":%s}\n' \
        "$TS" "$CWD_ESC" "$ST" "$CR" "$MC" >> "$METRICS_FILE"
fi

# Gate: if meaningful activity today → prompt /meta-observe
if [[ $SIGNALS_TODAY -ge 5 && $COMMITS_RECENT -gt 0 ]]; then
    echo "ℹ️  $SIGNALS_TODAY observation signals, $COMMITS_RECENT commits in last 4h."
    echo "    Run /meta-observe to extract patterns before context decays."
fi

# IMP-075: staleness ESCALATION on top of the per-session nudge above. The nudge
# fired ~158x during a 13-day stall (2026-06-20..07-03) without ever conveying AGE
# or BACKLOG — a 3-week gap looked identical to a 1-day gap. Reads the .last-run-ts
# watermark (which /meta-observe now updates on completion) + counts archived days.
OBS_DIR="$HOME/.claude/global-observation"
WATERMARK="$OBS_DIR/.last-run-ts"
if [[ -f "$WATERMARK" ]]; then
    LAST_RUN_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$(cat "$WATERMARK" 2>/dev/null)" +%s 2>/dev/null || echo 0)
    if [[ $LAST_RUN_EPOCH -gt 0 ]]; then
        DAYS_STALE=$(( ($(date +%s) - LAST_RUN_EPOCH) / 86400 ))
        BACKLOG_SHARDS=$(find "$OBS_DIR/archives" -name 'signals-*.jsonl.gz' -newer "$WATERMARK" 2>/dev/null | wc -l | tr -d ' ')
        if [[ $DAYS_STALE -ge 7 && $BACKLOG_SHARDS -ge 3 ]]; then
            echo "⚠️  OBSERVATION LOOP STALLED: last /meta-observe ran $DAYS_STALE days ago;"
            echo "    $BACKLOG_SHARDS unprocessed daily signal shards since. Run /meta-observe (IMP-075)."
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Reminder 4: Rewrite-heaviness warning (IMP-036)
# ═══════════════════════════════════════════════════════════════════════════
# Surfaces sessions where ≥10 edits with ≥80% Writes (full-rewrites) — typical
# of planning docs being treated as draft notebooks. See planning-doc-convention.md.
# Depends on observation-capture.sh emitting "tool" and "session_id" fields.
if [[ -f "$SIGNALS_FILE" && -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
    SESSION_LINES=$(grep -F "\"session_id\":\"$CLAUDE_CODE_SESSION_ID\"" "$SIGNALS_FILE" 2>/dev/null)
    if [[ -n "$SESSION_LINES" ]]; then
        SESSION_EDITS=$(echo "$SESSION_LINES" | grep -cE '"tool":"(Edit|Write|MultiEdit)"' || true)
        SESSION_REWRITES=$(echo "$SESSION_LINES" | grep -c '"tool":"Write"' || true)
        if [[ $SESSION_EDITS -ge 10 ]]; then
            REWRITE_PCT=$(( SESSION_REWRITES * 100 / SESSION_EDITS ))
            if [[ $REWRITE_PCT -ge 80 ]]; then
                echo "ℹ️  Rewrite-heavy session: $SESSION_REWRITES/$SESSION_EDITS edits ($REWRITE_PCT%) were full Writes."
                echo "    Per planning-doc-convention.md (IMP-036): rewriting >50% suggests the file is a draft, not a spec."
                echo "    Next time, copy to a *-draft-DATE.md, iterate there, then replace in one final commit."
            fi
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Reminder 5: Marathon-session warning (IMP-095)
# ═══════════════════════════════════════════════════════════════════════════
# A2/A1 evidence: session 8752218f ran ~38h wall-clock (2026-07-12T06:52:24Z
# to 2026-07-13T20:50:51Z) across 3 branches without a visible /clear, and
# drove that day's refactor=228 / fix=310 intent spikes. Wall-clock alone is
# a NOISY context-rot proxy — idle gaps burn no tokens (gap analysis found
# ~30.4h of the 38h were >60min gaps, i.e. overnight pauses) — so this is a
# SOFT surfacing warning per context-engineering.md, not a hard gate. Prefer
# an actual context-fill% signal where available; this is the wall-clock
# fallback for when none is.
SID_FOR_MARATHON="${SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
if [[ -f "$SIGNALS_FILE" && -n "$SID_FOR_MARATHON" ]] && command -v jq >/dev/null 2>&1; then
    SESSION_TS_SORTED=$(grep -F "\"session_id\":\"$SID_FOR_MARATHON\"" "$SIGNALS_FILE" 2>/dev/null \
        | jq -r '.ts // empty' 2>/dev/null | sort)
    if [[ -n "$SESSION_TS_SORTED" ]]; then
        FIRST_TS=$(echo "$SESSION_TS_SORTED" | head -1)
        LAST_TS=$(echo "$SESSION_TS_SORTED" | tail -1)
        FIRST_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$FIRST_TS" +%s 2>/dev/null || echo 0)
        LAST_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_TS" +%s 2>/dev/null || echo 0)
        if [[ $FIRST_EPOCH -gt 0 && $LAST_EPOCH -ge $FIRST_EPOCH ]]; then
            SESSION_HOURS=$(( (LAST_EPOCH - FIRST_EPOCH) / 3600 ))
            if [[ $SESSION_HOURS -ge 12 ]]; then
                echo "⚠️  Marathon session: ${SESSION_HOURS}h between first and last signal (session $SID_FOR_MARATHON)."
                echo "    Per context-engineering.md: long wall-clock spans risk context rot even across idle gaps."
                echo "    Consider /clear if the next task is independent; check /context fill% before continuing."
            fi
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Reminder 6: Gate-activity across subsystems (IMP-094)
# ═══════════════════════════════════════════════════════════════════════════
# signals.jsonl has carried exactly ONE error class over an 11-day window
# (read-before-edit-block, 106/106) because guard-unsafe.sh,
# excessive-agency-gate.sh, security-audit.sh, and web-fetch-safety-gate.sh
# each write to their OWN log file and never reach signals.jsonl — so
# /meta-observe (which reads only signals.jsonl) is structurally blind to
# their activity. This hook cannot register itself on Bash/mcp__* PreToolUse
# matchers (settings.json is out of scope here) and cannot edit the gate
# scripts themselves (out of this unit's exclusive file set), so a full
# consolidated pipeline is a separate follow-up. This surfaces today's known
# gate-log counts at session end so the monoculture gap is visible instead
# of silent. Caveat: security-audit.log timestamps are LOCAL time (see
# security-audit.sh `date "+%Y-%m-%d %H:%M:%S"`, no -u), while TODAY here is
# UTC — near a local midnight boundary the count can be off by one day; this
# is a soft nudge, not a precise metric.
AGENCY_LOG="$OBS_DIR/excessive-agency.log"
SECURITY_LOG="$OBS_DIR/security-audit.log"
WEBFETCH_LOG="$OBS_DIR/web-fetch-gate.log"

AGENCY_TODAY=0
if [[ -f "$AGENCY_LOG" ]]; then
    AGENCY_TODAY=$(grep -c "\"ts\":\"$TODAY" "$AGENCY_LOG" 2>/dev/null | tr -d '\n')
fi
[[ "$AGENCY_TODAY" =~ ^[0-9]+$ ]] || AGENCY_TODAY=0

SECURITY_TODAY=0
if [[ -f "$SECURITY_LOG" ]]; then
    SECURITY_TODAY=$(grep -c "^\[$TODAY" "$SECURITY_LOG" 2>/dev/null | tr -d '\n')
fi
[[ "$SECURITY_TODAY" =~ ^[0-9]+$ ]] || SECURITY_TODAY=0

WEBFETCH_TODAY=0
if [[ -f "$WEBFETCH_LOG" ]]; then
    WEBFETCH_TODAY=$(grep -c "\"ts\":\"$TODAY" "$WEBFETCH_LOG" 2>/dev/null | tr -d '\n')
fi
[[ "$WEBFETCH_TODAY" =~ ^[0-9]+$ ]] || WEBFETCH_TODAY=0

GATE_TOTAL=$(( AGENCY_TODAY + SECURITY_TODAY + WEBFETCH_TODAY ))
if [[ $GATE_TOTAL -gt 0 ]]; then
    echo "ℹ️  Gate activity today NOT in signals.jsonl (invisible to /meta-observe, IMP-094):"
    echo "    excessive-agency=$AGENCY_TODAY security-audit=$SECURITY_TODAY web-fetch=$WEBFETCH_TODAY"
fi

# Never block — the agent decides.
exit 0
