#!/usr/bin/env bash
# dispatch-specialist-regression.sh — IMP-159 regression suite for
# dispatch-specialist-check.sh.
#
# Runs the hook DIRECTLY with synthetic Task/Agent PreToolUse JSON on an
# ISOLATED $HOME (mktemp) and a fresh /tmp state dir per test (unique
# session ids), so test runs never pollute the real
# ~/.claude/global-observation/dispatch-specialist.log or leave stray
# /tmp/dispatch-specialist-* touch files behind.
#
# Usage:  bash ~/.claude/hooks/tests/dispatch-specialist-regression.sh
# Exit:   0 = all assertions pass, 1 = failures (listed on stdout)
set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/dispatch-specialist-check.sh"
TESTHOME="$(mktemp -d)"
mkdir -p "$TESTHOME/.claude/global-observation" "$TESTHOME/.claude/agents"
# Seed a realistic agents/ dir so tests NOT exercising the runtime-read case
# still see a plausible specialist list.
for a in backend-agent cleanup-agent code-reviewer-agent control-agent \
         testing-agent ui-agent planning-agent version-control-agent; do
  : > "$TESTHOME/.claude/agents/$a.md"
done

cleanup() {
  rm -rf "$TESTHOME"
  rm -rf /tmp/dispatch-specialist-dsr-* 2>/dev/null || true
}
trap cleanup EXIT

PASS=0; FAIL=0; FAILURES=""

# json_cmd: builds Task/Agent PreToolUse JSON.
#   $1 = subagent_type ("" to omit the field entirely)
#   $2 = prompt text (may contain literal newlines)
#   $3 = session id
#   $4 = tool name (default "Task")
json_cmd() {
  python3 - "$1" "$2" "$3" "${4:-Task}" <<'PY'
import json, sys
subagent, prompt, session, tool = sys.argv[1:5]
tool_input = {"prompt": prompt, "description": "test dispatch"}
if subagent != "":
    tool_input["subagent_type"] = subagent
print(json.dumps({
    "tool_name": tool,
    "session_id": session,
    "tool_input": tool_input,
}))
PY
}

run_hook() {  # $1 = full stdin json; sets RC, OUT, ERR
  OUT=$(printf '%s' "$1" | HOME="$TESTHOME" bash "$HOOK" 2>/tmp/dsr-stderr-$$)
  RC=$?
  ERR=$(cat /tmp/dsr-stderr-$$ 2>/dev/null)
  rm -f /tmp/dsr-stderr-$$
}

assert_silent() {  # $1 = label, $2 = json
  run_hook "$2"
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [SILENT] $1 — rc=$RC out=<$OUT>\n"
  fi
}

assert_ask() {  # $1 = label, $2 = json
  run_hook "$2"
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '"permissionDecision": *"ask"'; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [ASK] $1 — rc=$RC out=<$OUT>\n"
  fi
}

assert_ask_contains() {  # $1 = label, $2 = json, $3 = substring the ask reason must contain
  run_hook "$2"
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '"permissionDecision": *"ask"' \
     && printf '%s' "$OUT" | grep -qF "$3"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [ASK+CONTAINS \"$3\"] $1 — rc=$RC out=<$OUT>\n"
  fi
}

assert_note() {  # $1 = label, $2 = json
  run_hook "$2"
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q '^NOTE:'; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [NOTE] $1 — rc=$RC out=<$OUT> err=<$ERR>\n"
  fi
}

echo "── Named specialists: silent, no ask, no log line ──"
assert_silent "backend-agent passes silently" \
  "$(json_cmd backend-agent 'implement the auth endpoint' dsr-1)"
assert_silent "Explore passes silently" \
  "$(json_cmd Explore 'find all callers of foo()' dsr-2)"

echo "── general-purpose without rationale → ask ──"
assert_ask "general-purpose, no rationale" \
  "$(json_cmd general-purpose 'fix the login bug' dsr-3)"
assert_ask "missing subagent_type entirely" \
  "$(json_cmd '' 'refactor the payment module' dsr-4)"
assert_ask "rationale too short (<15 chars)" \
  "$(json_cmd general-purpose $'do the thing\nAGENTENWAHL: kurz' dsr-5)"

echo "── general-purpose WITH rationale THAT NAMES A SPECIALIST → allow + NOTE ──"
# IMP-213: marker presence alone is no longer enough. Measured 2026-09-21:
# 57 of 60 general-purpose dispatches in the 2026-08-24..09-21 window passed
# on marker presence alone — the gate collected a formality, not a decision.
assert_note "AGENTENWAHL: marker naming a specialist" \
  "$(json_cmd general-purpose $'inventory the repo\nAGENTENWAHL: code-reviewer-agent käme am nächsten, ist aber read-only und deckt keine Repo-Inventur ab' dsr-6)"
assert_note "AGENT-RATIONALE: marker naming a specialist" \
  "$(json_cmd general-purpose $'build level assets\nAGENT-RATIONALE: ui-agent is the closest fit but covers web components, not game level assets' dsr-7)"
assert_note "Begründung Agentenwahl: (with umlaut), names a specialist" \
  "$(json_cmd general-purpose $'do X\nBegründung Agentenwahl: planning-agent passt nicht, die Aufgabe ist domänenübergreifend und nicht planend' dsr-8)"
assert_note "Begruendung Agentenwahl: (no umlaut), names a specialist" \
  "$(json_cmd general-purpose $'do Y\nBegruendung Agentenwahl: testing-agent schreibt Tests, hier wird aber nichts getestet' dsr-9)"

echo "── Substance check (IMP-213): rationale WITHOUT a specialist name → ask ──"
assert_ask_contains "boilerplate rationale, no name" \
  "$(json_cmd general-purpose $'do Z\nAGENTENWAHL: kein Spezialist deckt diese Aufgabe ab' dsr-6a)" \
  "nennt keinen Fachagenten beim Namen"
assert_note "built-in Explore counts as a nameable alternative" \
  "$(json_cmd general-purpose $'do W\nAGENTENWAHL: Explore wäre nah dran, darf aber nichts schreiben und hier wird geschrieben' dsr-6b)"

echo "── Escalation (IMP-213): 3rd GRANTED general-purpose per session → ask ──"
SESS_ESC="dsr-esc"
esc_json() { json_cmd general-purpose "$1" "$SESS_ESC"; }
run_hook "$(esc_json $'a\nAGENTENWAHL: backend-agent passt nicht, es gibt hier keine Server-Logik zu bauen')"
ESC1_OUT="$OUT"
run_hook "$(esc_json $'b\nAGENTENWAHL: ui-agent passt nicht, es entsteht hier keine Oberfläche sondern eine Inventur')"
ESC2_OUT="$OUT"
run_hook "$(esc_json $'c\nAGENTENWAHL: cleanup-agent passt nicht, es wird kein toter Code gesucht sondern Struktur')"
ESC3_OUT="$OUT"; ESC3_RC=$RC
if [ -z "$ESC1_OUT" ] && [ -z "$ESC2_OUT" ] \
   && printf '%s' "$ESC3_OUT" | grep -q '"permissionDecision": *"ask"' \
   && printf '%s' "$ESC3_OUT" | grep -q 'Auftrag in dieser Sitzung'; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [ESCALATION] 1=<$ESC1_OUT> 2=<$ESC2_OUT> 3=<$ESC3_OUT>\n"
fi

echo "── Refused attempts must NOT consume the quota ──"
# Found by this suite on the first build of IMP-213: counting attempts instead
# of grants let two refusals burn the whole quota before the first legitimate
# dispatch. The counter therefore tallies granted dispatches only.
SESS_Q="dsr-quota"
run_hook "$(json_cmd general-purpose 'no rationale at all' "$SESS_Q")"
run_hook "$(json_cmd general-purpose $'x\nAGENTENWAHL: eine Floskel ganz ohne jeden Namen darin' "$SESS_Q")"
run_hook "$(json_cmd general-purpose $'y\nAGENTENWAHL: backend-agent passt nicht, hier ist keine Server-Logik im Spiel' "$SESS_Q")"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [QUOTA-NOT-BURNED-BY-REFUSALS] rc=$RC out=<$OUT>\n"
fi

echo "── Escalation ask is still bypassable by an identical retry (no deadlock) ──"
SESS_ESC2="dsr-esc2"
for i in 1 2; do
  run_hook "$(json_cmd general-purpose "grant$i
AGENTENWAHL: ui-agent passt nicht, hier entsteht keine Oberfläche sondern eine Auswertung" "$SESS_ESC2")"
done
RETRY_J="$(json_cmd general-purpose $'third\nAGENTENWAHL: planning-agent passt nicht, es wird nichts geplant sondern gezählt' "$SESS_ESC2")"
run_hook "$RETRY_J"; ESC_FIRST="$OUT"
run_hook "$RETRY_J"; ESC_SECOND="$OUT"; ESC_SECOND_RC=$RC
if printf '%s' "$ESC_FIRST" | grep -q '"permissionDecision": *"ask"' \
   && [ "$ESC_SECOND_RC" -eq 0 ] && [ -z "$ESC_SECOND" ] \
   && grep -q '"decision":"allow-second-attempt"' "$TESTHOME/.claude/global-observation/dispatch-specialist.log" 2>/dev/null; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [ESCALATION-RETRY] first=<$ESC_FIRST> second_rc=$ESC_SECOND_RC second=<$ESC_SECOND>\n"
fi

echo "── Rationale snippet is logged (<=200 chars), so quality is auditable ──"
if grep -q '"rationale_snippet":"backend-agent passt nicht' "$TESTHOME/.claude/global-observation/dispatch-specialist.log" 2>/dev/null; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [SNIPPET-LOG] no rationale_snippet field found in log\n"
fi

echo "── Opt-out env var ──"
run_hook_optout() {
  OUT=$(printf '%s' "$1" | HOME="$TESTHOME" CLAUDE_DISPATCH_CHECK_OFF=1 bash "$HOOK" 2>/dev/null)
  RC=$?
}
run_hook_optout "$(json_cmd general-purpose 'anything at all' dsr-10)"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [OPT-OUT] rc=$RC out=<$OUT>\n"
fi
if grep -q '"decision":"allow-optout"' "$TESTHOME/.claude/global-observation/dispatch-specialist.log" 2>/dev/null; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [OPT-OUT LOG] no allow-optout entry logged\n"
fi

echo "── Second attempt: identical (subagent_type, prompt) pair, same session ──"
SESS_2ND="dsr-11"
PROMPT_2ND="fix the flaky checkout test"
J_2ND="$(json_cmd general-purpose "$PROMPT_2ND" "$SESS_2ND")"
run_hook "$J_2ND"
FIRST_RC=$RC; FIRST_OUT="$OUT"
run_hook "$J_2ND"
SECOND_RC=$RC; SECOND_OUT="$OUT"
if printf '%s' "$FIRST_OUT" | grep -q '"permissionDecision": *"ask"' \
   && [ "$SECOND_RC" -eq 0 ] && [ -z "$SECOND_OUT" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [SECOND-ATTEMPT] first=<$FIRST_OUT> second_rc=$SECOND_RC second_out=<$SECOND_OUT>\n"
fi

echo "── Unparseable stdin → fail open, exit 0 ──"
OUT=$(printf 'not json at all {{{' | HOME="$TESTHOME" bash "$HOOK" 2>/dev/null)
RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [UNPARSEABLE] rc=$RC out=<$OUT>\n"
fi

echo "── Agent list is read at RUNTIME (not hardcoded) ──"
TMPAGENTS="$(mktemp -d)"
: > "$TMPAGENTS/totally-unique-runtime-agent.md"
: > "$TMPAGENTS/another-runtime-specialist.md"
J_RUNTIME="$(json_cmd general-purpose 'some task with no rationale' dsr-12)"
OUT=$(printf '%s' "$J_RUNTIME" | HOME="$TESTHOME" CLAUDE_DISPATCH_AGENTS_DIR="$TMPAGENTS" bash "$HOOK" 2>/dev/null)
RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "totally-unique-runtime-agent" \
   && printf '%s' "$OUT" | grep -q "another-runtime-specialist"; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [RUNTIME AGENT LIST] out=<$OUT>\n"
fi
rm -rf "$TMPAGENTS"

echo "── Log line is valid JSON ──"
LOG="$TESTHOME/.claude/global-observation/dispatch-specialist.log"
if [ -s "$LOG" ] && tail -1 "$LOG" | jq -e . >/dev/null 2>&1; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [LOG VALID JSON] last line not parseable: $(tail -1 "$LOG" 2>/dev/null)\n"
fi

echo ""
echo "─────────────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '\nFailures:\n%b' "$FAILURES"
  exit 1
fi
exit 0
