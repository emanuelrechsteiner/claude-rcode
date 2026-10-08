#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015
# Second regression suite for hooks/cockpit-secret-guard.sh: the inline override is an ask, logging and
# redaction, fail-closed on what the scanner cannot inspect, fail-open only on garbled JSON / missing scanner.
# The first suite (DENY / ALLOW spellings) is cockpit-secret-guard-regression.sh; both share the harness.
#
# Usage:  CLAUDE_HOOK=/path/to/cockpit-secret-guard.sh bash hooks/tests/cockpit-secret-guard-regression-modes.sh
# Exit:   0 = ALL PASS, 1 = at least one failure

# shellcheck source=lib/cockpit-secret-guard-harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/cockpit-secret-guard-harness.sh"

echo "== Override is an ask prompt, never an allow =="
: > "$CLAUDE_GUARD_LOG"
run_json "$(bash_json 'CLAUDE_GUARD_OVERRIDE=1 tmux capture-pane -p')"
decision=$(printf '%s' "$LAST_OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
event=$(printf '%s' "$LAST_OUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
reason=$(printf '%s' "$LAST_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
[[ "$RC" == 0 && "$decision" == ask ]] && ok "override -> exit 0 + permissionDecision ask" || bad "override ask" "rc=$RC out=$LAST_OUT"
[[ "$event" == PreToolUse && "$reason" == *"not approval"* ]] && ok "ask JSON shape + user-must-approve reason" || bad "ask shape" "$LAST_OUT"
grep -q "COCKPIT-GUARD-OVERRIDE-ASK" "$CLAUDE_GUARD_LOG" && grep -q "ask" "$CLAUDE_GUARD_LOG" && ok "override logged as ask" || bad "override log" "$(cat "$CLAUDE_GUARD_LOG")"
run_json "$(bash_json 'CLAUDE_GUARD_OVERRIDE=1 ls -la')"
[[ "$RC" == 0 && -z "$LAST_OUT" ]] && ok "override on harmless command stays silent allow" || bad "override harmless" "out=$LAST_OUT"
ov() { # name command expected(ask|deny|allow): token position x violation -> verdict
    run_json "$(bash_json "$2")"
    local got=allow
    [[ "$RC" == 2 ]] && got=deny
    [[ "$RC" == 0 && "$LAST_OUT" == *'"ask"'* ]] && got=ask
    [[ "$got" == "$3" ]] && ok "override: $1 -> $3" || bad "override: $1" "want $3 got $got (rc=$RC)"
}
OVT="CLAUDE_GUARD_OVERRIDE=1"
ov "leading token + violation"       "$OVT tmux capture-pane -p"      ask
ov "leading token, tab separated"    "$OVT"$'\t'"tmux capture-pane -p" ask
ov "leading token, doubled"          "$OVT $OVT tmux capture-pane -p" ask
ov "token after echo; + violation"   "echo x; $OVT tmux capture-pane -p" deny
ov "token after ; (leading true)"    "$OVT true; tmux capture-pane -p" ask
ov "token in middle + violation"     "tmux capture-pane $OVT -p"      deny
ov "token in double quotes"          "echo \"$OVT \"; tmux capture-pane -p" deny
ov "token in single quotes"          "echo '$OVT '; tmux capture-pane -p" deny
ov "export form + violation"         "export $OVT; tmux capture-pane -p" deny
ov "token after newline"             $'echo hi\n'"$OVT tmux capture-pane -p" deny
ov "leading newline then token"      $'\n'"$OVT tmux capture-pane -p" ask
ov "glued token = assignment, runs no tmux" "${OVT}tmux capture-pane -p" allow
ov "hidden second violation"         "$OVT ls; tmux save-buffer -"   ask
ov "leading token, harmless"         "$OVT ls -la"                    allow
ov "middle token, harmless"          "echo x; $OVT ls"                allow
ov "no token, harmless"              "ls -la"                         allow
ov "no token + violation"            "tmux capture-pane -p"           deny
ov "leading token + file violation"  "$OVT cat ~/.claude/cockpit/web-1.out" ask
tool_deny "Read has no inline override" '{"tool_name":"Read","tool_input":{"file_path":"~/.claude/cockpit/web-1.out","note":"CLAUDE_GUARD_OVERRIDE=1 "}}'

echo "== Logging and redaction =="
: > "$CLAUDE_GUARD_LOG"
SECRET_VAL="$(printf 's3cr3tV4lu3%.0s' 1 2 3 4)"
run_json "$(bash_json "tmux capture-pane -p; curl -H 'Authorization: Bearer $SECRET_VAL' --token=$SECRET_VAL x")"
grep -q "COCKPIT-GUARD-DENY" "$CLAUDE_GUARD_LOG" && ok "denial logged" || bad "denial logged" "no line"
grep -q "$SECRET_VAL" "$CLAUDE_GUARD_LOG" && bad "secret redacted in log" "value found" || ok "secret redacted in log"

echo "== Fail closed: commands the scanner cannot or may not inspect =="
NEST_N=200
nested=$(printf 'echo $( %.0s' $(seq $NEST_N))x$(printf ' )%.0s' $(seq $NEST_N))
deny "200-deep nested \$( )"        "$nested" "too complex to inspect"
deny "12-deep nested \$( ) + capture" "$(printf 'echo $( %.0s' {1..12})tmux capture-pane$(printf ' )%.0s' {1..12})" "too complex to inspect"
big=$(head -c 100000 /dev/zero | tr '\0' 'a')
deny "100 KB command"               "echo $big" "too long to inspect"
deny "just over the 64 KB cap"      "echo $(head -c 65600 /dev/zero | tr '\0' 'a')" "too long to inspect"
allow "just under the 64 KB cap"    "echo $(head -c 60000 /dev/zero | tr '\0' 'a')"
expect "DENY  lone surrogate (print crash)" 2 '{"tool_name":"Bash","tool_input":{"command":"tmux capture-pane \ud800"}}' "BLOCKED"
BROKEN="$WORK/broken"
mkdir -p "$BROKEN/lib"
cp "$HOOK" "$BROKEN/cockpit-secret-guard.sh"
echo 'raise RuntimeError("boom")' > "$BROKEN/lib/cockpit_secret_scan.py"
run_json "$(bash_json 'ls')" "$BROKEN/cockpit-secret-guard.sh"
[[ "$RC" == 2 && "$LAST_ERR" == *"too complex to inspect"* ]] && ok "crashing scanner on a parsed call fails closed" || bad "scanner crash" "rc=$RC err=${LAST_ERR:0:150}"

echo "== Fail-open: only for garbled hook JSON / missing scanner (loud + logged) =="
: > "$CLAUDE_GUARD_LOG"
expect "empty stdin" 0 ""
expect "empty object" 0 "{}"
expect "Bash without command" 0 '{"tool_name":"Bash","tool_input":{}}'
expect "garbled stdin warns" 0 "this is not json {" "WARNING"
grep -q "COCKPIT-GUARD-ERROR" "$CLAUDE_GUARD_LOG" && ok "garbled input logged" || bad "garbled input logged" "no line"
BIN="$WORK/bin"
mkdir -p "$BIN"
for t in jq dirname date mkdir cat; do ln -s "$(command -v "$t")" "$BIN/$t"; done
LAST_ERR=$(printf '%s' "$(bash_json 'tmux capture-pane -p')" | PATH="$BIN" /bin/bash "$HOOK" 2>&1 >/dev/null)
RC=$?
[[ "$RC" == 0 && "$LAST_ERR" == *"WARNING"* ]] && ok "no python3: fail-open with loud WARNING" || bad "no python3" "rc=$RC err=$LAST_ERR"

finish
