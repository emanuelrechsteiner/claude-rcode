#!/usr/bin/env bash
# controller-first-regression.sh — regression suite for IMP-089/IMP-090
# ─────────────────────────────────────────────────────────────────────────────
# Exercises controller-first-mutation-gate.sh, controller-first-prompt-gate.sh,
# and controller-first-subagent-flag.sh with
# synthetic hook JSON on an ISOLATED $HOME + unique per-test session ids, so
# runs never pollute ~/.claude/global-observation and never collide with real
# /tmp/controller-first-<session_id> state.
#
# Usage:  bash ~/.claude/hooks/tests/controller-first-regression.sh
# Exit:   0 = all assertions pass, 1 = failures listed on stdout.
set -u
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTHOME="$(mktemp -d)"
mkdir -p "$TESTHOME/.claude/global-observation"
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
assert_eq "note/substantial/no-flag/Write" 0 "$(run_gate note "$(j_write "$S1" /Users/x/project/src/foo.ts)")"

S2=$(sid 2); mark_substantial "$S2"
assert_eq "note/substantial/no-flag/Bash-mutation" 0 "$(run_gate note "$(j_bash "$S2" "git commit -m x")")"

S3=$(sid 3)
assert_eq "note/no-state/Edit" 0 "$(run_gate note "$(j_edit "$S3" /Users/x/project/src/foo.ts)")"

# ═══════════════════════════════════════════════════════════════════════════
# B) ENFORCE mode
# ═══════════════════════════════════════════════════════════════════════════

# substantial + no controller-ran + non-exempt -> BLOCK
S4=$(sid 4); mark_substantial "$S4"
assert_eq "enforce/substantial/no-flag/Write/nonexempt" 2 "$(run_gate enforce "$(j_write "$S4" /Users/x/project/src/foo.ts)")"

S5=$(sid 5); mark_substantial "$S5"
assert_eq "enforce/substantial/no-flag/Edit/nonexempt" 2 "$(run_gate enforce "$(j_edit "$S5" /Users/x/project/src/foo.ts)")"

S6=$(sid 6); mark_substantial "$S6"
assert_eq "enforce/substantial/no-flag/Bash-mutation" 2 "$(run_gate enforce "$(j_bash "$S6" "git commit -m x")")"

# substantial + no controller-ran + READ-ONLY bash -> ALLOW (classifier gate — never reaches state check)
S7=$(sid 7); mark_substantial "$S7"
assert_eq "enforce/substantial/no-flag/Bash-readonly" 0 "$(run_gate enforce "$(j_bash "$S7" "git status")")"

# substantial + controller-ran -> ALLOW
S8=$(sid 8); mark_substantial "$S8"; mark_controller_ran "$S8"
assert_eq "enforce/substantial/controller-ran/Write" 0 "$(run_gate enforce "$(j_write "$S8" /Users/x/project/src/foo.ts)")"

# no substantial flag at all -> ALLOW (gate doesn't apply pre-substance)
S9=$(sid 9)
assert_eq "enforce/no-substantial-flag/Write" 0 "$(run_gate enforce "$(j_write "$S9" /Users/x/project/src/foo.ts)")"

# exempt paths -> ALLOW even substantial+no-flag
S10=$(sid 10); mark_substantial "$S10"
assert_eq "enforce/exempt-scratchpad" 0 "$(run_gate enforce "$(j_write "$S10" /private/tmp/claude-501/scratchpad/foo.md)")"

S11=$(sid 11); mark_substantial "$S11"
assert_eq "enforce/exempt-rcode" 0 "$(run_gate enforce "$(j_write "$S11" /repo/.rcode/state.json)")"

S12=$(sid 12); mark_substantial "$S12"
assert_eq "enforce/exempt-project-status" 0 "$(run_gate enforce "$(j_write "$S12" /repo/PROJECT-STATUS.md)")"

S13=$(sid 13); mark_substantial "$S13"
assert_eq "enforce/exempt-plans-dir" 0 "$(run_gate enforce "$(j_write "$S13" /Users/x/.claude/plans/proposal.md)")"

S13b=$(sid 13b); mark_substantial "$S13b"
assert_eq "enforce/exempt-agent-log" 0 "$(run_gate enforce "$(j_write "$S13b" /repo/.rcode/agent-log.md)")"

# CLAUDE_GATE_TESTMODE=1 -> ALLOW regardless of state/mode
S14=$(sid 14); mark_substantial "$S14"
assert_eq "enforce/testmode-exempt" 0 "$(run_gate_testmode "$(j_write "$S14" /Users/x/project/src/foo.ts)")"

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
# D) controller-first-prompt-gate.sh — never blocks, only sets flags / nudges
# ═══════════════════════════════════════════════════════════════════════════
run_prompt_gate() {  # session_id, prompt -> stdout JSON
  printf '{"prompt":"%s","session_id":"%s"}' "$2" "$1" \
    | HOME="$TESTHOME" bash "$HOOKS_DIR/controller-first-prompt-gate.sh"
}

S17=$(sid 17)
OUT17=$(run_prompt_gate "$S17" "what does this file do")
assert_eq "prompt-gate/trivial-no-flag" 0 "$([ -f "/tmp/controller-first-$S17/substantial" ] && echo 1 || echo 0)"
assert_eq "prompt-gate/trivial-no-context" 1 "$([ -z "$OUT17" ] && echo 1 || echo 0)"

S18=$(sid 18)
OUT18=$(run_prompt_gate "$S18" "baue eine neue funktion in src/foo.ts fuer login")
assert_eq "prompt-gate/substantial-sets-flag" 1 "$([ -f "/tmp/controller-first-$S18/substantial" ] && echo 1 || echo 0)"
HAS_CTX=$(printf '%s' "$OUT18" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
assert_eq "prompt-gate/substantial-has-context" 1 "$([ -n "$HAS_CTX" ] && echo 1 || echo 0)"

S19=$(sid 19); mark_controller_ran "$S19"
OUT19=$(run_prompt_gate "$S19" "baue eine neue funktion in src/foo.ts fuer logout")
assert_eq "prompt-gate/substantial-but-controller-ran-silent" 1 "$([ -z "$OUT19" ] && echo 1 || echo 0)"

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

echo "── controller-first-regression: $PASS passed, $FAIL failed ──"
if [ "$FAIL" -gt 0 ]; then
  printf "%b" "$FAILURES"
  exit 1
fi
exit 0
