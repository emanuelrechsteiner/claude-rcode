#!/bin/bash
# dispatch-capture.sh — the framework's subagent-dispatch meter
# ─────────────────────────────────────────────────────────────────────────────
# PreToolUse hook, matcher "Task|Agent". Records ONE compact line per subagent
# dispatch. This is the only deterministic source of delegation counts anywhere
# in global-observation/ — observation-capture.sh is registered with matcher
# "Edit|Write", so signals.jsonl structurally cannot see a dispatch, which is
# why daily-metrics.jsonl reported agent_invocations:null (honestly) for weeks.
#
# History (IMP-115, 2026-08-01): promoted from q2-probe-dispatch-dump.sh, a
# TEMPORARY probe (IMP-090 Schritt 0) that carried "expires 2026-07-22 —
# review/remove REGARDLESS" and was still writing 10 days past that date. Its
# question — "is a Task/Agent dispatch PreToolUse-matchable, and does
# subagent_type appear as a real tool_input field?" — is settled: 228 captured
# records, subagent_type present throughout. Deleting it on schedule would have
# deleted the framework's sole delegation meter, so it is promoted instead of
# retired, and the expiry banner is gone so the contradiction stops recurring.
#
# WHAT CHANGED vs. the probe: the probe dumped the ENTIRE raw PreToolUse JSON,
# including tool_input.prompt — ~4.7 KB per record, and prompt text is untrusted
# content that has no business sitting in an audit log (agents-as-users.md).
# This version extracts five fields and nothing else. The raw-shape questions
# that justified the unfiltered dump are answered, so the jq round-trip the
# probe deliberately avoided is now correct.
#
# Old data: q2-probe.jsonl is frozen as a historical artifact in the old bulky
# schema. It is NOT renamed or migrated — silently reinterpreting old records
# under a new schema is the kind of quiet rewrite fail-loud.md exists to stop.
#
# ALWAYS exits 0. This hook observes; it must never affect dispatch behaviour.
#
# model field (IMP-204, 2026-09-09): a Task/Agent call with NO explicit `model` param
# inherits the parent's model at dispatch time — it is not "no model", it is "unspecified,
# use ambient". Logging the raw missing value as JSON null made 51 of 153 dispatch-window
# lines unattributable by model (measured 2026-08-24..09-09). Logging the literal string
# "inherit" instead keeps agent_invocations analyzable by model without guessing WHICH
# model was actually inherited (that answer isn't in this hook's input and must not be
# invented — fail-loud.md).
set -u

INPUT=$(cat 2>/dev/null || printf '{}')
LOG="${CLAUDE_DISPATCH_LOG:-$HOME/.claude/global-observation/dispatch-capture.jsonl}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# Fail open: unparseable input is logged as such rather than silently dropped —
# a missing line and a malformed dispatch must stay distinguishable.
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
    printf '{"ts":"%s","event":"unparseable_input"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG" 2>/dev/null || true
    exit 0
fi

printf '%s' "$INPUT" | jq -c \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    {
      ts:                $ts,
      session_id:        (.session_id // null),
      tool:              (.tool_name // null),
      subagent_type:     (.tool_input.subagent_type // null),
      model:             (.tool_input.model // "inherit"),
      run_in_background: (.tool_input.run_in_background // null),
      isolation:         (.tool_input.isolation // null)
    }' >> "$LOG" 2>/dev/null || true

exit 0
