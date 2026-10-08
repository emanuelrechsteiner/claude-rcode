#!/bin/bash
# Regression suite for hooks/governing-path-guard.sh (IMP-239)
#
# Cause: the two-location rule (live install written only by claude-deploy) was
# prose only. Locks in: block of governed live paths (file tools + Bash forms),
# fail-closed parse failures, no false positives on reads / workshop / *.local.md /
# quoted data / deploy, the single-use content-bound ack, TESTMODE, fail-open.
# Uses a mktemp fixture as CLAUDE_LIVE_DIR; never touches the real ~/.claude.
#
# Usage:  bash hooks/tests/governing-path-guard-regression.sh   (tests the workshop copy)
# Exit:   0 = all green, 1 = at least one red

set -uo pipefail

HOOK="${CLAUDE_HOOK:-$(cd "$(dirname "$0")/.." && pwd)/governing-path-guard.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

WORK=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
L="$WORK/live"; SHOP="$WORK/workshop"
mkdir -p "$L/rules" "$L/hooks" "$L/scripts/lib" "$L/global-observation" "$SHOP/rules"
export CLAUDE_LIVE_DIR="$L" CLAUDE_GOVERNING_LOG="$WORK/guard.log" CLAUDE_GOVERNING_CONSUMED="$WORK/consumed"
GREEN=0; RED=0

run_hook() { local json="$1"; shift; ERR=$(printf '%s' "$json" | env "$@" bash "$HOOK" 2>&1 >/dev/null); RC=$?; }
file_json() { jq -nc --arg p "$1" --arg c "${2:-x}" '{tool_name:"Write",tool_input:{file_path:$p,content:$c},cwd:"/tmp"}'; }
bash_json() { jq -nc --arg c "$1" --arg d "${2:-/tmp}" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,session_id:"s1"}'; }
ok() { echo "  ok    $1"; ((GREEN++)); }
red() { echo "  RED   $1"; ((RED++)); }

# block <name> <json> <needle in reason> ; allow <name> <json>
block() {
    run_hook "$2" A=1
    if [[ "$RC" == 2 && "$ERR" == *"two-location rule"* && "$ERR" == *"$3"* ]]; then ok "$1"
    else red "$1 — want rc=2 with reason containing '$3', got rc=$RC: $ERR"; fi
}
allow() { run_hook "$2" A=1; [[ "$RC" == 0 ]] && ok "$1" || red "$1 — want rc=0, got rc=$RC: $ERR"; }
bblock() { block "$1" "$(bash_json "$2" "${4:-/tmp}")" "$3"; }
ballow() { allow "$1" "$(bash_json "$2" "${3:-/tmp}")"; }

echo "── File tools: block ──"
for rel in rules/foo.md agents/x.md skills/a/b/SKILL.md commands/c.md hooks/h.sh rcode/s/x.md \
    scheduled-tasks/t/SKILL.md CLAUDE.md settings.json settings.framework.json settings.local.json \
    scripts/lib/secret-patterns.sh cockpit/a.js output-styles/o.md templates/t.tpl; do
    block "live $rel" "$(file_json "$L/$rel")" "$(basename "$rel")"
done
block "dotdot normalization" "$(file_json "$L/rules/../hooks/x/../h.sh")" "h.sh"
block "case variant Rules/" "$(file_json "$L/Rules/X.md")" "X.md"
block "double leading slash" "$(file_json "/$L/rules/a.md")" "a.md"
block "directory root hooks" "$(file_json "$L/hooks")" "hooks"
block "relative path, cwd=live" "$(jq -nc '{tool_input:{file_path:"rules/r.md",content:"x"},cwd:env.CLAUDE_LIVE_DIR}')" "r.md"
run_hook "$(file_json '~/.claude/rules/foo.md')" CLAUDE_LIVE_DIR="$HOME/.claude"; [[ $RC == 2 ]] && ok "tilde expands" || red "tilde rc=$RC"
run_hook "$(file_json '$HOME/.claude/CLAUDE.md')" CLAUDE_LIVE_DIR="$HOME/.claude"; [[ $RC == 2 ]] && ok "\$HOME expands" || red "\$HOME rc=$RC"
ln -s "$L" "$WORK/livelink"
block "symlinked live dir" "$(file_json "$WORK/livelink/rules/s.md")" "s.md"
[[ "$ERR" == *"claude-deploy"* ]] && ok "message names claude-deploy" || red "no claude-deploy in message"

echo "── File tools: allow ──"
for p in "$L/rules/id.local.md" "$L/global-observation/x.log" "$L/projects/p/memory/m.md" "$L/plans/p.md" \
    "$SHOP/rules/foo.md" "$L/rules/../../workshop/rules/a.md"; do allow "allow ${p#$WORK/}" "$(file_json "$p")"; done

echo "── Bash: write forms blocked ──"
bblock "redirect >"        "echo hi > $L/rules/a.md" a.md
bblock "redirect >>"       "echo hi >> $L/CLAUDE.md" CLAUDE.md
bblock "tee"               "echo hi | tee $L/hooks/h.sh" h.sh
bblock "tee -a"            "echo hi | tee -a $L/settings.json" settings.json
bblock "sed -i"            "sed -i 's/a/b/' $L/agents/x.md" x.md
bblock "sed -i.bak"        "sed -i.bak 's/a/b/' $L/agents/x.md" x.md
bblock "cp to live file"   "cp $SHOP/rules/a.md $L/rules/a.md" a.md
bblock "cp into live dir"  "cp $SHOP/rules/a.md $L/rules/" rules
bblock "mv to live"        "mv $SHOP/h.sh $L/hooks/h.sh" h.sh
bblock "mv from live"      "mv $L/hooks/h.sh $SHOP/h.sh" h.sh
bblock "install -m"        "install -m 755 $SHOP/h.sh $L/hooks/h.sh" h.sh
bblock "cp -t"             "cp -t $L/hooks $SHOP/h.sh" hooks
bblock "after &&"          "cd /tmp && echo x > $L/rules/a.md" a.md
bblock "relative after cd" "cd $L && echo x > rules/a.md" a.md
bblock "cwd=live relative" "echo x > rules/a.md" a.md "$L"
bblock "inside bash -c"    "bash -c 'echo x > $L/rules/a.md'" a.md
bblock "bundled bash -lc"  "bash -lc 'echo x > $L/rules/a.md'" a.md
bblock "sh -ec"            "sh -ec \"cp x $L/rules/a.md\"" a.md
bblock "heredoc into bash" $'bash <<EOF\necho x > '"$L"$'/rules/a.md\nEOF' a.md
bblock "cp -r into live root"   "cp -r $SHOP/hooks $L/" hooks
bblock "cp onto dir root"       "cp x $L/hooks" hooks
echo "── Bash: reproduced bypasses 1-5 and parser items ──"
bblock "1 apostrophe in comment" $'# it\'s the live install\ncp x '"$L"$'/rules/a.md' a.md
bblock "2 fd redirect 2>/dev/null" "cp /w/a.md $L/rules/a.md 2>/dev/null" a.md
bblock "2b 2>&1"           "cp /w/a.md $L/rules/a.md 2>&1" a.md
bblock "3 for/do"          "for f in a; do cp \$f $L/rules/; done" rules
bblock "4 glued ); "       "V=\$(date); tee $L/rules/a.md" a.md
bblock "4b )&&"            "(cd /tmp)&& echo x > $L/rules/a.md" a.md
bblock "if/then"           "if true; then echo x > $L/rules/a.md; fi" a.md
bblock "env -i wrapper"    "env -i tee $L/rules/a.md" a.md
bblock "sudo -u wrapper"   "sudo -u root tee $L/rules/a.md" a.md
bblock "&> redirect"       "echo x &> $L/rules/a.md" a.md
bblock "parse-fail fail-closed (unbalanced quote)" "echo 'oops > $L/rules/a.md" "rules/"
grep -q "decision=parse-fail" "$CLAUDE_GOVERNING_LOG" && ok "parse-fail logged" || red "parse-fail not logged"
echo "── Bash: git forms ──"
bblock "git -C live checkout"  "git -C $L checkout -- rules/a.md" "checkout"
bblock "git -C live pull"      "git -C $L pull --ff-only" "pull"
bblock "git cwd=live reset"    "git reset --hard" "reset" "$L"
bblock "git -C live stash"     "git -C $L stash" "stash"

echo "── Bash: reads / data / deploy allowed ──"
for c in "cat $L/rules/a.md" "grep -rn foo $L/rules" "jq . $L/settings.json" "git -C $L log --oneline" \
    "git -C $L status" "git -C $L diff" "git -C $L show HEAD" "git -C $L rev-parse HEAD" "git -C $L fetch" \
    "echo \"redirect > $L/rules/a.md\"" "cat $L/rules/a.md 2>/dev/null" "echo hi > $SHOP/rules/a.md" \
    "cp $L/rules/a.md $SHOP/rules/a.md" "echo hi > $L/rules/x.local.md" "echo hi > $L/global-observation/x.log" \
    "echo hi > $L/projects/p/memory/m.md" "echo hi > $L/plans/p.md" "claude-deploy config" \
    "bash scripts/deploy-to-live.sh config" "bash $SHOP/scripts/deploy-to-live.sh all" "git status"; do
    ballow "allow: ${c:0:60}" "$c"
done
ballow "heredoc body to cat" $'cat <<EOF\necho > '"$L"$'/rules/a.md\nEOF'
ballow "git log, cwd=live" "git log" "$L"
ballow "comment mentions live path" "# cp x $L/rules/a.md"$'\n'"ls"

echo "── Ack token, replay, content binding, testmode, fail-open ──"
CMD="echo hi > $L/rules/ack.md"
SIG=$(printf '%s' "$CMD" | shasum -a 256 | cut -d' ' -f1)
run_hook "$(bash_json "CLAUDE_GOVERNING_WRITE_ACK=$SIG $CMD")" A=1; [[ $RC == 0 ]] && ok "inline ack allows once" || red "ack rc=$RC"
run_hook "$(bash_json "CLAUDE_GOVERNING_WRITE_ACK=$SIG $CMD")" A=1; [[ $RC == 2 && "$ERR" == *replay* ]] && ok "ack replay re-blocks" || red "replay rc=$RC $ERR"
run_hook "$(bash_json "CLAUDE_GOVERNING_WRITE_ACK=$(printf 'f%.0s' {1..64}) $CMD")" A=1; [[ $RC == 2 ]] && ok "wrong ack blocks" || red "wrong ack rc=$RC"
FP="$L/rules/env.md"; csha() { printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; }
fsig() { printf '%s' "$FP"$'\n'"$(csha "$1")" | shasum -a 256 | cut -d' ' -f1; }
run_hook "$(file_json "$FP" v1)" CLAUDE_GOVERNING_WRITE_ACK="$(fsig v1)"; [[ $RC == 0 ]] && ok "env ack, file tool" || red "env ack rc=$RC"
run_hook "$(file_json "$FP" v2)" CLAUDE_GOVERNING_WRITE_ACK="$(fsig v1)"; [[ $RC == 2 ]] && ok "same path, new content needs new ack" || red "content binding rc=$RC"
run_hook "$(file_json "$FP" v2)" CLAUDE_GOVERNING_WRITE_ACK="$(fsig v2)"; [[ $RC == 0 ]] && ok "second approved edit, own signature" || red "second ack rc=$RC"
grep -q "authorizer=user" "$CLAUDE_GOVERNING_LOG" && ok "log has authorizer=user" || red "no authorizer=user"
run_hook "$(file_json "$L/rules/t.md")" CLAUDE_GATE_TESTMODE=1; [[ $RC == 0 ]] && ok "TESTMODE exempts" || red "testmode rc=$RC"
grep -q "testmode-exempt" "$CLAUDE_GOVERNING_LOG" && ok "testmode logged" || red "testmode not logged"
run_hook "not json at all" A=1; [[ $RC == 0 && "$ERR" == *NOTE* ]] && ok "bad JSON fails open with NOTE" || red "bad JSON rc=$RC"
grep -q "decision=failopen" "$CLAUDE_GOVERNING_LOG" && ok "failopen logged" || red "failopen not logged"

echo ""
echo "GREEN=$GREEN RED=$RED of $((GREEN + RED))"
[[ "$RED" -eq 0 ]] || exit 1
