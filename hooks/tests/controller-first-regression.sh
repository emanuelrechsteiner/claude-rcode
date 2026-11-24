#!/usr/bin/env bash
# controller-first-regression.sh — regression suite for IMP-089/IMP-090
# ─────────────────────────────────────────────────────────────────────────────
# Exercises controller-first-mutation-gate.sh, controller-first-prompt-gate.sh,
# controller-first-subagent-flag.sh, and dispatch-capture.sh with
# synthetic hook JSON on an ISOLATED $HOME + unique per-test session ids, so
# runs never pollute ~/.claude/global-observation and never collide with real
# /tmp/controller-first-<session_id> state.
#
# Context diet (2026-11-10): the prompt gate's once-per-session reminder and its automated-turn skip
# are covered in section D2 (markers under the isolated TMPDIR).
# Retirement (2026-11-10, docs/adr/0011-controller-first-mutation-gate-retired.md): the mutation gate and the
# subagent flag hook are retired and unregistered; their sections keep the shelved scripts green as history.
# The prompt gate writes no state for the retired gate any more (sections D and D2 assert that); its own once-per-session marker stays.
# Usage:  bash ~/.claude/hooks/tests/controller-first-regression.sh
# Exit:   0 = all assertions pass, 1 = failures listed on stdout.
set -u
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTHOME="$(mktemp -d)"
mkdir -p "$TESTHOME/.claude/global-observation" "$TESTHOME/tmp"
RUN_ID="cfreg-$$-$RANDOM"

cleanup() {
  rm -rf "$TESTHOME"
  rm -rf /tmp/controller-first-"${RUN_ID}"-* 2>/dev/null || true
  rm -f /tmp/controller-first-ack-consumed-"${RUN_ID}"-* 2>/dev/null || true
}
trap cleanup EXIT

PASS=0; FAIL=0; FAILURES=""

sid() { echo "${RUN_ID}-$1"; }   # unique session id per test number

mark_substantial()    { mkdir -p "/tmp/controller-first-$1"; : > "/tmp/controller-first-$1/substantial"; }
mark_controller_ran() { mkdir -p "/tmp/controller-first-$1"; : > "/tmp/controller-first-$1/controller-ran"; }

# ── JSON builders (printf, no python — commands/paths in these tests need no escaping) ──
j_write() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"},"session_id":"%s"}' "$2" "$1"; }
j_edit()  { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"},"session_id":"%s"}' "$2" "$1"; }
j_bash()  { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"session_id":"%s"}' "$2" "$1"; }

run_gate() {  # mode, json -> exit code
  local mode="$1" json="$2"
  printf '%s' "$json" | HOME="$TESTHOME" CLAUDE_CONTROLLER_GATE_MODE="$mode" \
    bash "$HOOKS_DIR/controller-first-mutation-gate.sh" >/dev/null 2>/dev/null
  echo $?
}

run_gate_stderr() {  # mode, json -> stderr text
  local mode="$1" json="$2"
  printf '%s' "$json" | HOME="$TESTHOME" CLAUDE_CONTROLLER_GATE_MODE="$mode" \
    bash "$HOOKS_DIR/controller-first-mutation-gate.sh" 2>&1 >/dev/null
}

run_gate_testmode() {  # json -> exit code, with CLAUDE_GATE_TESTMODE=1
  local json="$1"
  printf '%s' "$json" | HOME="$TESTHOME" CLAUDE_CONTROLLER_GATE_MODE=enforce CLAUDE_GATE_TESTMODE=1 \
    bash "$HOOKS_DIR/controller-first-mutation-gate.sh" >/dev/null 2>/dev/null
  echo $?
}

assert_eq() {  # description, expected, actual
  if [ "$2" = "$3" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [$1] expected='$2' got='$3'\n"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# A) NOTE mode never blocks — in ANY state
# ═══════════════════════════════════════════════════════════════════════════
S1=$(sid 1); mark_substantial "$S1"
assert_eq "note/substantial/no-flag/Write" 0 "$(run_gate note "$(j_write "$S1" /Users/example/project/src/foo.ts)")"

S2=$(sid 2); mark_substantial "$S2"
assert_eq "note/substantial/no-flag/Bash-mutation" 0 "$(run_gate note "$(j_bash "$S2" "git commit -m x")")"

S3=$(sid 3)
assert_eq "note/no-state/Edit" 0 "$(run_gate note "$(j_edit "$S3" /Users/example/project/src/foo.ts)")"

# ═══════════════════════════════════════════════════════════════════════════
# B) ENFORCE mode
# ═══════════════════════════════════════════════════════════════════════════

# substantial + no controller-ran + non-exempt -> BLOCK
S4=$(sid 4); mark_substantial "$S4"
assert_eq "enforce/substantial/no-flag/Write/nonexempt" 2 "$(run_gate enforce "$(j_write "$S4" /Users/example/project/src/foo.ts)")"

S5=$(sid 5); mark_substantial "$S5"
assert_eq "enforce/substantial/no-flag/Edit/nonexempt" 2 "$(run_gate enforce "$(j_edit "$S5" /Users/example/project/src/foo.ts)")"

S6=$(sid 6); mark_substantial "$S6"
assert_eq "enforce/substantial/no-flag/Bash-mutation" 2 "$(run_gate enforce "$(j_bash "$S6" "git commit -m x")")"

# substantial + no controller-ran + READ-ONLY bash -> ALLOW (classifier gate — never reaches state check)
S7=$(sid 7); mark_substantial "$S7"
assert_eq "enforce/substantial/no-flag/Bash-readonly" 0 "$(run_gate enforce "$(j_bash "$S7" "git status")")"

# substantial + controller-ran -> ALLOW
S8=$(sid 8); mark_substantial "$S8"; mark_controller_ran "$S8"
assert_eq "enforce/substantial/controller-ran/Write" 0 "$(run_gate enforce "$(j_write "$S8" /Users/example/project/src/foo.ts)")"

# no substantial flag at all -> ALLOW (gate doesn't apply pre-substance)
S9=$(sid 9)
assert_eq "enforce/no-substantial-flag/Write" 0 "$(run_gate enforce "$(j_write "$S9" /Users/example/project/src/foo.ts)")"

# exempt paths -> ALLOW even substantial+no-flag
S10=$(sid 10); mark_substantial "$S10"
assert_eq "enforce/exempt-scratchpad" 0 "$(run_gate enforce "$(j_write "$S10" /private/tmp/claude-501/scratchpad/foo.md)")"

S11=$(sid 11); mark_substantial "$S11"
assert_eq "enforce/exempt-rcode" 0 "$(run_gate enforce "$(j_write "$S11" /repo/.rcode/state.json)")"

S12=$(sid 12); mark_substantial "$S12"
assert_eq "enforce/exempt-project-status" 0 "$(run_gate enforce "$(j_write "$S12" /repo/PROJECT-STATUS.md)")"

S13=$(sid 13); mark_substantial "$S13"
assert_eq "enforce/exempt-plans-dir" 0 "$(run_gate enforce "$(j_write "$S13" /Users/example/.claude/plans/proposal.md)")"

S13b=$(sid 13b); mark_substantial "$S13b"
assert_eq "enforce/exempt-agent-log" 0 "$(run_gate enforce "$(j_write "$S13b" /repo/.rcode/agent-log.md)")"

# CLAUDE_GATE_TESTMODE=1 -> ALLOW regardless of state/mode
S14=$(sid 14); mark_substantial "$S14"
assert_eq "enforce/testmode-exempt" 0 "$(run_gate_testmode "$(j_write "$S14" /Users/example/project/src/foo.ts)")"

# ═══════════════════════════════════════════════════════════════════════════
# C) ACK token: single-use, op-bound (Bash — the reliable delivery path)
# ═══════════════════════════════════════════════════════════════════════════
S15=$(sid 15); mark_substantial "$S15"
CMD15="git commit -m x"
BLOCKED_STDERR=$(run_gate_stderr enforce "$(j_bash "$S15" "$CMD15")")
SIG15=$(printf '%s' "$BLOCKED_STDERR" | grep -oE 'CLAUDE_CONTROLLER_ACK_ONCE=[A-Fa-f0-9]{64}' | head -1 | cut -d= -f2)
assert_eq "enforce/ack-sig-extracted-from-block-message" 1 "$([ -n "$SIG15" ] && echo 1 || echo 0)"

ACK_CMD15="CLAUDE_CONTROLLER_ACK_ONCE=$SIG15 $CMD15"
assert_eq "enforce/ack-valid-first-use" 0 "$(run_gate enforce "$(j_bash "$S15" "$ACK_CMD15")")"
assert_eq "enforce/ack-replay-blocked" 2 "$(run_gate enforce "$(j_bash "$S15" "$ACK_CMD15")")"

# mismatched token -> BLOCK
S16=$(sid 16); mark_substantial "$S16"
MISMATCH_CMD="CLAUDE_CONTROLLER_ACK_ONCE=0000000000000000000000000000000000000000000000000000000000000000 git commit -m x"
assert_eq "enforce/ack-mismatch" 2 "$(run_gate enforce "$(j_bash "$S16" "$MISMATCH_CMD")")"

# ═══════════════════════════════════════════════════════════════════════════
# D) controller-first-prompt-gate.sh — never blocks, writes no gate state, only nudges
# ═══════════════════════════════════════════════════════════════════════════
run_prompt_gate() {  # session_id, prompt -> stdout JSON (jq builds the payload, so quotes in a prompt stay valid JSON)
  jq -nc --arg p "$2" --arg s "$1" '{prompt: $p, session_id: $s}' \
    | HOME="$TESTHOME" TMPDIR="$TESTHOME/tmp" bash "$HOOKS_DIR/controller-first-prompt-gate.sh"
}

S17=$(sid 17)
OUT17=$(run_prompt_gate "$S17" "what does this file do")
assert_eq "prompt-gate/trivial-no-flag" 0 "$([ -f "/tmp/controller-first-$S17/substantial" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/trivial-no-context" 1 "$([ -z "$OUT17" ] && echo 1 || echo 0)"

S18=$(sid 18)
OUT18=$(run_prompt_gate "$S18" "baue eine neue funktion in src/foo.ts fuer login")
assert_eq "prompt-gate/substantial-writes-no-state-dir" 0 "$([ -e "/tmp/controller-first-$S18" ] && echo 1 || echo 0)"
HAS_CTX=$(printf '%s' "$OUT18" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
assert_eq "prompt-gate/substantial-has-context" 1 "$([ -n "$HAS_CTX" ] && echo 1 || echo 0)"

S19=$(sid 19); mark_controller_ran "$S19"
OUT19=$(run_prompt_gate "$S19" "baue eine neue funktion in src/foo.ts fuer logout")
assert_eq "prompt-gate/controller-ran-flag-is-not-read-any-more" 1 "$([ -n "$OUT19" ] && echo 1 || echo 0)"

# ═══════════════════════════════════════════════════════════════════════════
# D2) controller-first-prompt-gate.sh — once per session; silent on automated turns
#     (context diet, 2026-11-10). Markers live under the isolated TMPDIR.
# ═══════════════════════════════════════════════════════════════════════════
SP1=$(sid p1)
OUT_P1A=$(run_prompt_gate "$SP1" "baue eine neue funktion in src/foo.ts fuer login")
OUT_P1B=$(run_prompt_gate "$SP1" "baue eine neue funktion in src/foo.ts fuer logout")
assert_eq "prompt-gate/first-substantial-emits" 1 "$([ -n "$OUT_P1A" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/second-substantial-silent" 1 "$([ -z "$OUT_P1B" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/once-marker-written-under-tmpdir" 1 "$([ -e "$TESTHOME/tmp/claude-prompt-reminders/$SP1.controller-first-prompt-gate" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/second-substantial-writes-no-state-dir" 0 "$([ -e "/tmp/controller-first-$SP1" ] && echo 1 || echo 0)"

SP2=$(sid p2)
OUT_P2=$(run_prompt_gate "$SP2" "[Subagent hand-back] Background report: baue eine neue funktion in src/foo.ts fuer login")
assert_eq "prompt-gate/automated-turn-silent" 1 "$([ -z "$OUT_P2" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/automated-turn-sets-no-flag" 0 "$([ -f "/tmp/controller-first-$SP2/substantial" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/automated-turn-writes-no-marker" 0 "$([ -e "$TESTHOME/tmp/claude-prompt-reminders/$SP2.controller-first-prompt-gate" ] && echo 1 || echo 0)"
OUT_P2B=$(run_prompt_gate "$SP2" "baue eine neue funktion in src/foo.ts fuer logout")
assert_eq "prompt-gate/user-prompt-after-automated-turn-emits" 1 "$([ -n "$OUT_P2B" ] && echo 1 || echo 0)"

SP3=$(sid p3)
OUT_P3=$(run_prompt_gate "$SP3" "<system-reminder> baue eine neue funktion in src/foo.ts fuer login")
assert_eq "prompt-gate/system-reminder-prefix-silent" 1 "$([ -z "$OUT_P3" ] && echo 1 || echo 0)"

# the other automated forms (leading whitespace included): silent, no flag
AUTO_FORMS=(
  '<task-notification> done: baue eine neue funktion in src/foo.ts fuer login'
  '[SYSTEM NOTIFICATION - NOT USER INPUT] baue eine neue funktion in src/foo.ts fuer login'
  '   <agent-message from="abc123"> baue eine neue funktion in src/foo.ts fuer login'
)
for i in "${!AUTO_FORMS[@]}"; do
  SA=$(sid "auto$i")
  OUT_A=$(run_prompt_gate "$SA" "${AUTO_FORMS[$i]}")
  assert_eq "prompt-gate/automated-form-$i-silent" 1 "$([ -z "$OUT_A" ] && echo 1 || echo 0)"
  assert_eq "prompt-gate/automated-form-$i-sets-no-flag" 0 "$([ -f "/tmp/controller-first-$SA/substantial" ] && echo 1 || echo 0)"
done

# a marker quoted in the middle of a user prompt is user content: reminder emitted (and, as everywhere, no state dir)
SM=$(sid mid)
OUT_M=$(run_prompt_gate "$SM" 'Warum feuert der Hook bei <task-notification> nicht? baue eine neue funktion in src/foo.ts fuer login')
assert_eq "prompt-gate/mid-text-marker-reminder-emitted" 1 "$([ -n "$OUT_M" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/mid-text-marker-writes-no-state-dir" 0 "$([ -e "/tmp/controller-first-$SM" ] && echo 1 || echo 0)"

# session isolation: a second session gets its own first reminder
SI1=$(sid iso1); SI2=$(sid iso2)
OUT_I1=$(run_prompt_gate "$SI1" "baue eine neue funktion in src/foo.ts fuer login")
OUT_I2=$(run_prompt_gate "$SI2" "baue eine neue funktion in src/foo.ts fuer login")
assert_eq "prompt-gate/isolation-first-session-emits" 1 "$([ -n "$OUT_I1" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/isolation-second-session-emits-own-reminder" 1 "$([ -n "$OUT_I2" ] && echo 1 || echo 0)"

# the reminder text: ends with the once-per-session sentence, names /team-lead as a controller step,
# and cites neither the retired mutation gate nor an enforcement
CTX_P1=$(printf '%s' "$OUT_P1A" | jq -r '.hookSpecificOutput.additionalContext // empty')
case "$CTX_P1" in *"SOFT reminder, not a block, shown once per session."*) CTX_SOFT=1 ;; *) CTX_SOFT=0 ;; esac
assert_eq "prompt-gate/reminder-ends-with-once-per-session-sentence" 1 "$CTX_SOFT"
case "$CTX_P1" in *"checks the same state"*) CTX_OLD=1 ;; *) CTX_OLD=0 ;; esac
assert_eq "prompt-gate/reminder-does-not-cite-retired-gate-as-active" 0 "$CTX_OLD"
case "$CTX_P1" in *"/team-lead, a control-agent"*) CTX_TL=1 ;; *) CTX_TL=0 ;; esac
assert_eq "prompt-gate/reminder-names-team-lead-as-controller-step" 1 "$CTX_TL"
case "$CTX_P1" in *"Controller-First Enforcement"*|*"IMP-089"*) CTX_ENF=1 ;; *) CTX_ENF=0 ;; esac
assert_eq "prompt-gate/reminder-cites-no-enforcement" 0 "$CTX_ENF"

# missing session_id: no once-marker is written, so the reminder repeats
run_prompt_gate_nosid() {  # prompt -> stdout JSON
  jq -nc --arg p "$1" '{prompt: $p, session_id: ""}' \
    | HOME="$TESTHOME" TMPDIR="$TESTHOME/tmp" bash "$HOOKS_DIR/controller-first-prompt-gate.sh"
}
NM_BEFORE=$(ls "$TESTHOME/tmp/claude-prompt-reminders" 2>/dev/null | wc -l | tr -d ' ')
OUT_N1=$(run_prompt_gate_nosid "baue eine neue funktion in src/foo.ts fuer login")
OUT_N2=$(run_prompt_gate_nosid "baue eine neue funktion in src/bar.ts fuer logout")
assert_eq "prompt-gate/missing-session-id-first-emits" 1 "$([ -n "$OUT_N1" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/missing-session-id-second-emits-no-marker" 1 "$([ -n "$OUT_N2" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/missing-session-id-writes-no-marker" "$NM_BEFORE" "$(ls "$TESTHOME/tmp/claude-prompt-reminders" 2>/dev/null | wc -l | tr -d ' ')"

# unsafe session_id ("../" plus a name): the marker uses the sanitised id; no state dir is written
SU=$(sid "../x")
OUT_U=$(run_prompt_gate "$SU" "baue eine neue funktion in src/foo.ts fuer login")
assert_eq "prompt-gate/unsafe-session-id-reminder-emitted" 1 "$([ -n "$OUT_U" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/unsafe-session-id-writes-no-state-dir" 0 "$([ -e "/tmp/controller-first-$(sid x)" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/unsafe-session-id-marker-sanitised" 1 "$([ -e "$TESTHOME/tmp/claude-prompt-reminders/$(sid x).controller-first-prompt-gate" ] && echo 1 || echo 0)"

# ═══════════════════════════════════════════════════════════════════════════
# E) controller-first-subagent-flag.sh
# ═══════════════════════════════════════════════════════════════════════════
run_subagent_flag() {  # session_id, agent_type
  printf '{"session_id":"%s","agent_type":"%s","agent_id":"a1","stop_reason":"end_turn"}' "$1" "$2" \
    | HOME="$TESTHOME" bash "$HOOKS_DIR/controller-first-subagent-flag.sh"
}

S20=$(sid 20)
run_subagent_flag "$S20" "control-agent" >/dev/null 2>&1
assert_eq "subagent-flag/control-agent-sets-flag" 1 "$([ -f "/tmp/controller-first-$S20/controller-ran" ] && echo 1 || echo 0)"

S21=$(sid 21)
run_subagent_flag "$S21" "backend-agent" >/dev/null 2>&1
assert_eq "subagent-flag/other-agent-no-flag" 0 "$([ -f "/tmp/controller-first-$S21/controller-ran" ] && echo 1 || echo 0)"

# ═══════════════════════════════════════════════════════════════════════════
# F) dispatch-capture.sh — the delegation counter: always exit 0, one line
#    per dispatch, and NO prompt in the log.
#
#    Replaces, since 2026-08-04, the three cases against q2-probe-dispatch-dump.sh.
#    That script was retired under IMP-115 (now under hooks/archived/),
#    dispatch-capture.sh took over its job — the check was not carried along
#    during the removal, so this suite ran permanently red ever since
#    (exit 127, "command not found") and nobody looked anymore.
# ═══════════════════════════════════════════════════════════════════════════
DC_LOG="$TESTHOME/.claude/global-observation/dispatch-capture.jsonl"
run_dispatch() {  # json -> exit code; writes to $DC_LOG
  printf '%s' "$1" | HOME="$TESTHOME" CLAUDE_DISPATCH_LOG="$DC_LOG" \
    bash "$HOOKS_DIR/dispatch-capture.sh" >/dev/null 2>&1
  echo $?
}
dc_lines() { [ -f "$DC_LOG" ] && wc -l < "$DC_LOG" | tr -d ' ' || echo 0; }

# The prompt is untrusted content and has no business in the log
# (agents-as-users.md) — that is exactly why the predecessor was replaced.
DC_BEFORE=$(dc_lines)
RC_DC=$(run_dispatch '{"tool_name":"Task","tool_input":{"subagent_type":"backend-agent","model":"sonnet","prompt":"STRAW-SECRET"},"session_id":"probe-1"}')
DC_AFTER=$(dc_lines)
assert_eq "dispatch-capture/exit0"             0 "$RC_DC"
assert_eq "dispatch-capture/one-more-line"     1 "$([ "$DC_AFTER" -eq $((DC_BEFORE + 1)) ] && echo 1 || echo 0)"
assert_eq "dispatch-capture/subagent-captured" "backend-agent" "$(tail -1 "$DC_LOG" | jq -r '.subagent_type')"
assert_eq "dispatch-capture/model-captured"    "sonnet"        "$(tail -1 "$DC_LOG" | jq -r '.model')"
assert_eq "dispatch-capture/NO-prompt"         0 "$(grep -c 'STRAW-SECRET' "$DC_LOG" || true)"

# IMP-204 (2026-09-09): a dispatch WITHOUT a model parameter inherits the parent
# model at runtime — that is "ambient", not "no value". The raw JSON null made 51
# of 153 window rows unevaluable by model; the fix logs the literal string "inherit".
RC_DC=$(run_dispatch '{"tool_name":"Task","tool_input":{"subagent_type":"general-purpose"},"session_id":"probe-2"}')
assert_eq "dispatch-capture/imp204-exit0"        0 "$RC_DC"
assert_eq "dispatch-capture/imp204-model-inherit" "inherit" "$(tail -1 "$DC_LOG" | jq -r '.model')"
assert_eq "dispatch-capture/imp204-no-null"    0 "$(tail -1 "$DC_LOG" | jq -e '.model == null' >/dev/null 2>&1 && echo 1 || echo 0)"

# Unreadable input: the hook must never disrupt the dispatch (exit 0), but must
# still log the incident — a missing line and a broken line must
# stay distinguishable (fail-loud.md).
DC_BEFORE=$(dc_lines)
RC_DC=$(run_dispatch 'not-json-at-all{{{')
assert_eq "dispatch-capture/garbage-exit0"     0 "$RC_DC"
assert_eq "dispatch-capture/garbage-noted"     1 "$(tail -1 "$DC_LOG" | grep -c 'unparseable_input' || true)"
assert_eq "dispatch-capture/garbage-one-line"  1 "$([ "$(dc_lines)" -eq $((DC_BEFORE + 1)) ] && echo 1 || echo 0)"

# Empty input must also not disrupt the hook
assert_eq "dispatch-capture/empty-exit0"       0 "$(printf '' | HOME="$TESTHOME" CLAUDE_DISPATCH_LOG="$DC_LOG" bash "$HOOKS_DIR/dispatch-capture.sh" >/dev/null 2>&1; echo $?)"

echo "── controller-first-regression: $PASS passed, $FAIL failed ──"
if [ "$FAIL" -gt 0 ]; then
  printf "%b" "$FAILURES"
  exit 1
fi
exit 0
